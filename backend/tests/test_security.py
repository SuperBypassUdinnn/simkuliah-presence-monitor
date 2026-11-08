"""Purpose: Unit tests for HMAC action token generation and verification.
Data & Logic Flow: Exercises token creation, signature verification, and expiration handling.
Key Components: test_token_creation_and_verification, test_token_expiration
"""

from app.core.security import create_action_token, verify_action_token


def test_token_creation_and_verification():
    payload = {"action": "confirm_presence", "schedule_id": 101, "meeting_no": 4}
    secret = "test-secret-key-32-chars-long-123456"
    token = create_action_token(payload, secret=secret, expires_in_seconds=300)

    verified = verify_action_token(token, secret=secret)
    assert verified is not None
    assert verified["action"] == "confirm_presence"
    assert verified["schedule_id"] == 101


def test_token_expiration():
    payload = {"action": "confirm_presence"}
    secret = "test-secret-key-32-chars-long-123456"
    token = create_action_token(payload, secret=secret, expires_in_seconds=-10)
    assert verify_action_token(token, secret=secret) is None
