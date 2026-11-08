"""HMAC-SHA256 signed action tokens for ntfy webhook authentication.

Tokens are short-lived, timestamp-bound signatures used to authorize direct
action requests (presence confirmation, Izin, Sakit, Alpa) dispatched through
ntfy.sh HTTP action buttons.

Token format:
    <base64url(json_envelope)>.<base64url(hmac_sha256)>

The envelope carries the caller payload plus issued-at and expiration claims,
so verification both authenticates the secret and enforces expiry without any
server-side state.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import json
import time
from typing import Any

SEPARATOR = "."


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def create_action_token(
    payload: dict[str, Any],
    secret: str,
    expires_in_seconds: int,
) -> str:
    """Sign ``payload`` with ``secret`` and stamp an expiration timestamp.

    Args:
        payload: Arbitrary JSON-serifiable action payload, e.g.
            ``{"action": "confirm_presence", "schedule_id": 101}``.
        secret: HMAC shared secret (``ACTION_SECRET_KEY``).
        expires_in_seconds: Token lifetime in seconds. Negative values produce
            immediately-expired tokens, useful for testing.
    """
    now = time.time()
    envelope = {
        "payload": payload,
        "iat": now,
        "exp": now + expires_in_seconds,
    }
    payload_bytes = json.dumps(envelope, separators=(",", ":")).encode("utf-8")
    payload_b64 = _b64url_encode(payload_bytes)
    signature = hmac.new(
        secret.encode("utf-8"), payload_b64.encode("ascii"), hashlib.sha256
    ).digest()
    signature_b64 = _b64url_encode(signature)
    return f"{payload_b64}{SEPARATOR}{signature_b64}"


def verify_action_token(token: str, secret: str) -> dict[str, Any] | None:
    """Verify and decode an action token.

    Returns the original payload dict when the signature is valid and the
    token has not expired, otherwise ``None``.
    """
    try:
        payload_b64, signature_b64 = token.split(SEPARATOR)
    except ValueError:
        return None

    expected_signature = hmac.new(
        secret.encode("utf-8"), payload_b64.encode("ascii"), hashlib.sha256
    ).digest()
    try:
        provided_signature = _b64url_decode(signature_b64)
    except (ValueError, binascii.Error):
        return None

    if not hmac.compare_digest(expected_signature, provided_signature):
        return None

    try:
        envelope = json.loads(_b64url_decode(payload_b64))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None

    exp = envelope.get("exp")
    if exp is None or time.time() > float(exp):
        return None

    payload = envelope.get("payload")
    if not isinstance(payload, dict):
        return None
    return payload
