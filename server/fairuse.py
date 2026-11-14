"""Fair use of the teacher's free monthly credit."""
from __future__ import annotations

import os

from fastapi import HTTPException

# ---------------------------------------------------------------- fair use --
# The teacher runs on the owner's free monthly cloud credit, so:
#  1. only the Hifz Academy app may call it (light check: app header);
#  2. each phone gets a daily allowance;
#  3. the owner's family (who enter the family code in the app) always come first:
#     everyone else together shares a monthly allowance, so the family's share is kept.
# Counts live in a Modal Dict when running on Modal (they survive the container
# sleeping), or in memory otherwise.
import datetime
import hashlib

APP_HEADER = "hifz-academy-app-v1"
FAMILY_HASHES = {"9a310d70b470072e0f529991fd9858a730a702168fde6e712d565b6135764c27"}  # sha256 of the family code
DAILY_LIMIT = int(os.environ.get("HIFZ_DAILY_LIMIT", "20"))
FAMILY_DAILY_LIMIT = int(os.environ.get("HIFZ_FAMILY_DAILY_LIMIT", "300"))
SHARED_MONTHLY_LIMIT = int(os.environ.get("HIFZ_SHARED_MONTHLY_LIMIT", "1500"))

_mem: dict[str, int] = {}
_dict = None
if os.environ.get("MODAL_TASK_ID"):
    try:
        import modal

        _dict = modal.Dict.from_name("hifz-teacher-usage", create_if_missing=True)
    except Exception:
        _dict = None


async def _get(key: str) -> int:
    if _dict is not None:
        try:
            return int(await _dict.get.aio(key, 0))
        except Exception:
            pass
    return _mem.get(key, 0)


async def _put(key: str, value: int) -> None:
    _mem[key] = value
    if _dict is not None:
        try:
            await _dict.put.aio(key, value)
        except Exception:
            pass


def is_family(code: str | None) -> bool:
    return bool(code) and hashlib.sha256(code.strip().upper().encode()).hexdigest() in FAMILY_HASHES


async def admit(app_header: str | None, device: str | None, family_code: str | None) -> dict:
    """Raises 401/429 when the request isn't allowed; returns the usage after counting it."""
    if app_header != APP_HEADER:
        raise HTTPException(401, {"reason": "app_only"})
    device = (device or "")[:64]
    if len(device) < 8:
        raise HTTPException(400, {"reason": "no_device"})
    now = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=5, minutes=30)  # India time
    day, month = now.strftime("%Y-%m-%d"), now.strftime("%Y-%m")
    family = is_family(family_code)
    dkey = f"d:{day}:{device}"
    used_today = await _get(dkey)
    limit = FAMILY_DAILY_LIMIT if family else DAILY_LIMIT
    if used_today >= limit:
        raise HTTPException(429, {"reason": "daily_limit", "limit": limit})
    if not family:
        mkey = f"m:{month}:shared"
        used_month = await _get(mkey)
        if used_month >= SHARED_MONTHLY_LIMIT:
            raise HTTPException(429, {"reason": "shared_limit"})
        await _put(mkey, used_month + 1)
    await _put(dkey, used_today + 1)
    return {"family": family, "used_today": used_today + 1, "daily_limit": limit}
