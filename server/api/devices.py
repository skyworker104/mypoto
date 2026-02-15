"""Device management API endpoints."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from server.api.deps import get_current_user
from server.database import get_session
from server.models.device import Device
from server.models.user import User
from server.schemas.family import DeviceResponse, DeviceUpdateRequest

router = APIRouter(tags=["devices"])


@router.get("/devices", response_model=list[DeviceResponse])
def list_devices(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """List all devices for the current user."""
    devices = session.exec(
        select(Device).where(Device.user_id == user.id, Device.status == "paired")
    ).all()

    return [
        DeviceResponse(
            id=d.id,
            device_name=d.device_name,
            device_type=d.device_type,
            device_model=d.device_model,
            status=d.status,
            last_seen=d.last_seen.isoformat() if d.last_seen else None,
        )
        for d in devices
    ]


@router.patch("/devices/{device_id}", response_model=DeviceResponse)
def update_device(
    device_id: str,
    request: DeviceUpdateRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Update a device's name."""
    device = session.get(Device, device_id)
    if not device or device.user_id != user.id:
        raise HTTPException(status_code=404, detail="Device not found")

    device.device_name = request.device_name
    session.add(device)
    session.commit()
    session.refresh(device)

    return DeviceResponse(
        id=device.id,
        device_name=device.device_name,
        device_type=device.device_type,
        device_model=device.device_model,
        status=device.status,
        last_seen=device.last_seen.isoformat() if device.last_seen else None,
    )


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_device(
    device_id: str,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Revoke (unpair) a device."""
    device = session.get(Device, device_id)
    if not device or device.user_id != user.id:
        raise HTTPException(status_code=404, detail="Device not found")

    device.status = "revoked"
    device.token_hash = None
    session.add(device)
    session.commit()
