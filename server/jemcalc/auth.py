"""A small, fail-closed authentication boundary for the private pilot."""

import secrets
from typing import Annotated

from fastapi import Header, HTTPException

from .config import get_settings


def token_is_valid(token: str) -> bool:
    expected = get_settings().pilot_token
    return bool(expected) and isinstance(token, str) and secrets.compare_digest(
        token.encode("utf-8"), expected.encode("utf-8")
    )


async def require_pilot_token(
    authorization: Annotated[str | None, Header()] = None,
) -> None:
    if not get_settings().pilot_token:
        raise HTTPException(503, "Pilot authentication is not configured")
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token_is_valid(token):
        raise HTTPException(401, "Invalid pilot token", headers={"WWW-Authenticate": "Bearer"})
