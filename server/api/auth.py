"""Authentication & pairing API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlmodel import Session

from server.database import get_session
from server.api.deps import get_current_user
from server.models.user import User
from server.schemas.auth import (
    PairInitResponse,
    PairRequest,
    PairResponse,
    RefreshRequest,
    RefreshResponse,
    UserSetupRequest,
    UserSetupResponse,
    UserProfileResponse,
    UserUpdateRequest,
)
from server.services.auth_service import (
    init_pairing,
    verify_pin_and_pair,
    refresh_access_token,
    local_auto_pair,
)
from server.utils.security import decode_token, hash_password

router = APIRouter(tags=["auth"])


@router.post("/pair/init", response_model=PairInitResponse)
def pair_init():
    """Generate a PIN for pairing. PIN is displayed on the server screen."""
    result = init_pairing()
    return PairInitResponse(
        pin_displayed=result["pin_displayed"],
        expires_in=result["expires_in"],
        message=result["message"],
    )


@router.post("/pair", response_model=PairResponse)
def pair(request: PairRequest, session: Session = Depends(get_session)):
    """Verify PIN and register device. Returns JWT tokens."""
    try:
        result = verify_pin_and_pair(
            pin=request.pin,
            device_name=request.device_name,
            device_type=request.device_type,
            device_model=request.device_model,
            app_version=request.app_version,
            session=session,
        )
    except ValueError as e:
        parts = str(e).split(":", 2)
        error_code = parts[0] if len(parts) > 0 else "error"
        remaining = int(parts[1]) if len(parts) > 1 else 0
        message = parts[2] if len(parts) > 2 else str(e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "error": error_code,
                "remaining_attempts": remaining,
                "message": message,
            },
        )
    return PairResponse(**result)


@router.post("/auth/local", response_model=PairResponse)
def local_auth(request_obj: Request, session: Session = Depends(get_session)):
    """Auto-authenticate from localhost without PIN."""
    client_ip = request_obj.client.host if request_obj.client else ""
    if client_ip not in ("127.0.0.1", "::1", "localhost"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Local access only",
        )
    result = local_auto_pair(session)
    return PairResponse(**result)


@router.post("/auth/refresh", response_model=RefreshResponse)
def refresh_token(request: RefreshRequest, session: Session = Depends(get_session)):
    """Refresh an access token using a refresh token."""
    try:
        new_token = refresh_access_token(request.refresh_token, request.device_id, session)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )
    return RefreshResponse(access_token=new_token)


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Logout: invalidate the current device's refresh token."""
    # Extract device_id from the current token (via dependency chain)
    # For simplicity, we invalidate all user devices here
    # A more precise approach would extract device_id from the JWT
    from sqlmodel import select
    from server.models.device import Device

    devices = session.exec(
        select(Device).where(Device.user_id == user.id, Device.status == "paired")
    ).all()
    for device in devices:
        device.token_hash = None
        session.add(device)
    session.commit()


@router.post("/users/setup", response_model=UserSetupResponse)
def user_setup(
    request: UserSetupRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Set up user profile after initial pairing (nickname + password)."""
    user.nickname = request.nickname
    user.password_hash = hash_password(request.password)
    session.add(user)
    session.commit()
    session.refresh(user)
    return UserSetupResponse(
        user_id=user.id,
        nickname=user.nickname,
        role=user.role,
    )


@router.get("/users/me", response_model=UserProfileResponse)
def get_my_profile(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get current user's profile."""
    from server.models.user import Family

    family = session.get(Family, user.family_id)
    return UserProfileResponse(
        id=user.id,
        nickname=user.nickname,
        role=user.role,
        avatar_url=user.avatar_url,
        family_id=user.family_id,
        family_name=family.name if family else "",
    )


@router.patch("/users/me", response_model=UserProfileResponse)
def update_my_profile(
    request: UserUpdateRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Update current user's profile."""
    if request.nickname is not None:
        user.nickname = request.nickname
    if request.avatar_url is not None:
        user.avatar_url = request.avatar_url
    session.add(user)
    session.commit()
    session.refresh(user)

    from server.models.user import Family

    family = session.get(Family, user.family_id)
    return UserProfileResponse(
        id=user.id,
        nickname=user.nickname,
        role=user.role,
        avatar_url=user.avatar_url,
        family_id=user.family_id,
        family_name=family.name if family else "",
    )
