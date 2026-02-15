"""Family & invite API endpoints."""

import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from server.api.deps import get_current_user, require_admin
from server.config import settings
from server.database import get_session
from server.models.device import Device
from server.models.invite import Invite
from server.models.user import Family, User
from server.schemas.family import (
    DeviceResponse,
    FamilyMemberResponse,
    FamilyResponse,
    InviteCreateRequest,
    InviteCreateResponse,
    InviteJoinRequest,
    InviteJoinResponse,
)
from server.utils.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    hash_token,
)

router = APIRouter(tags=["family"])


@router.get("/family", response_model=FamilyResponse)
def get_family(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Get family info with all members."""
    family = session.get(Family, user.family_id)
    if not family:
        raise HTTPException(status_code=404, detail="Family not found")

    members = session.exec(
        select(User).where(User.family_id == family.id)
    ).all()

    member_responses = []
    for m in members:
        device_count = len(
            session.exec(
                select(Device).where(Device.user_id == m.id, Device.status == "paired")
            ).all()
        )
        member_responses.append(
            FamilyMemberResponse(
                user_id=m.id,
                nickname=m.nickname,
                role=m.role,
                avatar_url=m.avatar_url,
                device_count=device_count,
            )
        )

    return FamilyResponse(
        id=family.id,
        name=family.name,
        members=member_responses,
    )


@router.post("/family/invite", response_model=InviteCreateResponse)
def create_invite(
    request: InviteCreateRequest,
    user: User = Depends(require_admin),
    session: Session = Depends(get_session),
):
    """Create an invite code for a new family member. Admin only."""
    invite_code = str(secrets.randbelow(90000000) + 10000000)  # 8-digit
    invite_token = f"inv_{secrets.token_urlsafe(24)}"
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=request.expires_in)

    invite = Invite(
        family_id=user.family_id,
        created_by=user.id,
        invite_code=invite_code,
        invite_token=invite_token,
        role=request.role,
        nickname_hint=request.nickname_hint,
        expires_at=expires_at,
    )
    session.add(invite)
    session.commit()

    host = f"{settings.host}:{settings.port}"
    invite_url = f"photonest://invite?token={invite_token}&host={host}"

    return InviteCreateResponse(
        invite_code=invite_code,
        invite_token=invite_token,
        invite_url=invite_url,
        qr_data=invite_url,
        expires_at=expires_at.isoformat(),
    )


@router.post("/family/join", response_model=InviteJoinResponse)
def join_family(
    request: InviteJoinRequest,
    session: Session = Depends(get_session),
):
    """Join a family using an invite code. No auth required."""
    invite = session.exec(
        select(Invite).where(
            Invite.invite_code == request.invite_code,
            Invite.used_at == None,  # noqa: E711
        )
    ).first()

    if not invite:
        raise HTTPException(status_code=404, detail="Invalid invite code")

    # Compare as naive UTC if needed (SQLite stores without tz info)
    expires = invite.expires_at
    if expires.tzinfo is not None:
        expires = expires.replace(tzinfo=None)
    if datetime.utcnow() > expires:
        raise HTTPException(status_code=410, detail="Invite has expired")

    family = session.get(Family, invite.family_id)
    if not family:
        raise HTTPException(status_code=404, detail="Family not found")

    # Create user
    user = User(
        family_id=invite.family_id,
        nickname=request.nickname,
        password_hash=hash_password(request.password),
        role=invite.role,
    )
    session.add(user)
    session.flush()

    # Create device
    device = Device(
        user_id=user.id,
        device_name=request.device_name,
        device_type=request.device_type,
        device_model=request.device_model,
    )
    session.add(device)
    session.flush()

    # Create tokens
    access_token = create_access_token(user.id, device.id, invite.family_id, invite.role)
    refresh_token = create_refresh_token(user.id, device.id)
    device.token_hash = hash_token(refresh_token)

    # Mark invite as used
    invite.used_at = datetime.now(timezone.utc)
    invite.used_by = user.id

    session.commit()

    return InviteJoinResponse(
        user_id=user.id,
        device_id=device.id,
        access_token=access_token,
        refresh_token=refresh_token,
        family_name=family.name,
    )


@router.delete("/family/members/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_member(
    member_id: str,
    user: User = Depends(require_admin),
    session: Session = Depends(get_session),
):
    """Remove a family member. Admin only. Cannot remove yourself."""
    if member_id == user.id:
        raise HTTPException(status_code=400, detail="Cannot remove yourself")

    member = session.get(User, member_id)
    if not member or member.family_id != user.family_id:
        raise HTTPException(status_code=404, detail="Member not found")

    # Delete all devices first (FK constraint)
    devices = session.exec(
        select(Device).where(Device.user_id == member_id)
    ).all()
    for device in devices:
        session.delete(device)

    # Delete user
    session.delete(member)
    session.commit()
