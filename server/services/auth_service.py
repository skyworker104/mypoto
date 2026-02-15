"""Authentication & pairing business logic.

Manages PIN state (in-memory for simplicity), pairing flow,
and token refresh.
"""

import time
from dataclasses import dataclass, field

from sqlmodel import Session, select

from server.config import settings
from server.models.device import Device
from server.models.user import Family, User
from server.utils.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    generate_pin,
    hash_password,
    hash_token,
)


@dataclass
class PinState:
    pin: str = ""
    created_at: float = 0.0
    attempts: int = 0
    lockout_until: float = 0.0


# Module-level singleton for PIN state (only one pairing at a time)
_pin_state = PinState()


def init_pairing() -> dict:
    """Generate a new PIN for pairing. Returns info for the client."""
    now = time.time()

    # Check lockout
    if _pin_state.lockout_until > now:
        remaining = int(_pin_state.lockout_until - now)
        return {
            "pin_displayed": False,
            "expires_in": 0,
            "message": f"Too many attempts. Try again in {remaining}s",
        }

    _pin_state.pin = generate_pin()
    _pin_state.created_at = now
    _pin_state.attempts = 0

    return {
        "pin_displayed": True,
        "expires_in": settings.pin_expire_seconds,
        "message": "서버 화면에 표시된 PIN을 입력하세요",
        "_pin": _pin_state.pin,  # For server display (not sent to client)
    }


def get_current_pin() -> str | None:
    """Get the current active PIN (for server display)."""
    now = time.time()
    if _pin_state.pin and (now - _pin_state.created_at) < settings.pin_expire_seconds:
        return _pin_state.pin
    return None


def verify_pin_and_pair(
    pin: str,
    device_name: str,
    device_type: str,
    device_model: str | None,
    app_version: str | None,
    session: Session,
) -> dict:
    """Verify PIN and create device + user if needed.

    Returns pairing result dict or raises ValueError.
    """
    now = time.time()

    # Check lockout
    if _pin_state.lockout_until > now:
        remaining = int(_pin_state.lockout_until - now)
        raise ValueError(f"locked_out:0:Too many attempts. Wait {remaining}s")

    # Check PIN exists and not expired
    if not _pin_state.pin:
        raise ValueError("no_pin:0:No active PIN. Request a new one from the server")

    if (now - _pin_state.created_at) >= settings.pin_expire_seconds:
        _pin_state.pin = ""
        raise ValueError("pin_expired:0:PIN has expired. Request a new one")

    # Verify PIN
    if pin != _pin_state.pin:
        _pin_state.attempts += 1
        remaining = settings.pin_max_attempts - _pin_state.attempts

        if _pin_state.attempts >= settings.pin_max_attempts:
            _pin_state.lockout_until = now + settings.pin_lockout_seconds
            _pin_state.pin = ""
            raise ValueError(f"invalid_pin:0:Too many attempts. Locked for {settings.pin_lockout_seconds}s")

        raise ValueError(f"invalid_pin:{remaining}:Incorrect PIN")

    # PIN is correct - clear it
    _pin_state.pin = ""
    _pin_state.attempts = 0

    # Find or create family
    family = session.exec(select(Family)).first()
    if not family:
        family = Family()
        session.add(family)
        session.flush()

    # Determine role: first user is admin
    existing_users = session.exec(select(User).where(User.family_id == family.id)).all()
    is_first_user = len(existing_users) == 0
    role = "admin" if is_first_user else "member"

    # Create user (will be set up later with nickname/password)
    user = User(
        family_id=family.id,
        nickname=device_name,  # Temporary nickname
        password_hash="",  # Will be set during user setup
        role=role,
    )
    session.add(user)
    session.flush()

    # Create tokens
    access_token = create_access_token(user.id, "", family.id, role)
    refresh_token = create_refresh_token(user.id, "")

    # Create device
    device = Device(
        user_id=user.id,
        device_name=device_name,
        device_type=device_type,
        device_model=device_model,
        app_version=app_version,
        token_hash=hash_token(refresh_token),
    )
    session.add(device)
    session.flush()

    # Update tokens with device_id
    access_token = create_access_token(user.id, device.id, family.id, role)
    refresh_token = create_refresh_token(user.id, device.id)
    device.token_hash = hash_token(refresh_token)

    session.commit()

    return {
        "device_id": device.id,
        "user_id": user.id,
        "access_token": access_token,
        "refresh_token": refresh_token,
        "server_name": settings.server_name,
        "is_new_user": is_first_user,
    }


def local_auto_pair(session: Session) -> dict:
    """Auto-pair for localhost access (no PIN required).

    Reuses existing local-web device or creates one.
    """
    family = session.exec(select(Family)).first()
    if not family:
        family = Family()
        session.add(family)
        session.flush()

    user = session.exec(
        select(User).where(User.family_id == family.id)
    ).first()
    if not user:
        user = User(
            family_id=family.id,
            nickname="서버 관리자",
            password_hash="",
            role="admin",
        )
        session.add(user)
        session.flush()

    device = session.exec(
        select(Device).where(
            Device.user_id == user.id,
            Device.device_name == "Local Web",
        )
    ).first()
    if not device:
        device = Device(
            user_id=user.id,
            device_name="Local Web",
            device_type="web",
        )
        session.add(device)
        session.flush()

    access_token = create_access_token(user.id, device.id, family.id, user.role)
    refresh_tok = create_refresh_token(user.id, device.id)
    device.token_hash = hash_token(refresh_tok)
    device.status = "paired"
    session.commit()

    return {
        "device_id": device.id,
        "user_id": user.id,
        "access_token": access_token,
        "refresh_token": refresh_tok,
        "server_name": settings.server_name,
        "is_new_user": False,
    }


def refresh_access_token(refresh_token_str: str, device_id: str, session: Session) -> str:
    """Validate refresh token and issue new access token."""
    try:
        payload = decode_token(refresh_token_str)
    except Exception:
        raise ValueError("Invalid or expired refresh token")

    if payload.get("type") != "refresh":
        raise ValueError("Invalid token type")

    # Verify device exists and token matches
    device = session.get(Device, device_id)
    if not device or device.status != "paired":
        raise ValueError("Device not found or revoked")

    if device.token_hash != hash_token(refresh_token_str):
        raise ValueError("Token mismatch")

    # Get user for role info
    user = session.get(User, device.user_id)
    if not user:
        raise ValueError("User not found")

    return create_access_token(user.id, device.id, user.family_id, user.role)


def logout_device(device_id: str, session: Session) -> None:
    """Invalidate a device's refresh token."""
    device = session.get(Device, device_id)
    if device:
        device.token_hash = None
        session.add(device)
        session.commit()
