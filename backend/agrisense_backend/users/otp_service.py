"""OTP generation, delivery and verification (phone-based identity checks).

Used for registration and password-reset verification. Codes are generated
cryptographically, stored as a hash, delivered via the SMS provider, and are
single-use with a short TTL and limited attempts (brute-force guard).
"""

import hashlib
import secrets

from django.conf import settings
from django.utils import timezone

from .models import OTPRequest

OTP_LENGTH = int(getattr(settings, 'OTP_LENGTH', 6))
OTP_TTL_SECONDS = int(getattr(settings, 'OTP_TTL_SECONDS', 300))
OTP_MAX_ATTEMPTS = int(getattr(settings, 'OTP_MAX_ATTEMPTS', 5))


def _hash_code(code):
    return hashlib.sha256(f'{code}::{settings.SECRET_KEY}'.encode()).hexdigest()


def _normalize_phone(phone):
    return ''.join(ch for ch in (phone or '') if ch.isdigit()) or (phone or '')


def _make_code():
    # Secure random numeric code of OTP_LENGTH digits.
    return ''.join(str(secrets.randbelow(10)) for _ in range(OTP_LENGTH))


def send_otp(phone_number, purpose='register'):
    """Generate, store and deliver an OTP for a phone number.

    Returns the plaintext code ONLY when DEBUG is on (so the demo is usable
    without an SMS gateway); otherwise returns None.
    """
    from .sms_provider import get_sms_provider

    phone = _normalize_phone(phone_number)
    code = _make_code()
    OTPRequest.objects.create(
        phone_number=phone,
        purpose=purpose,
        code_hash=_hash_code(code),
        expires_at=timezone.now() + timezone.timedelta(seconds=OTP_TTL_SECONDS),
    )
    message = (f'AgriSense AI verification code: {code}. '
               f'It expires in {OTP_TTL_SECONDS // 60} minutes. Do not share it.')
    try:
        get_sms_provider().send(phone_number=phone, message=message)
    except Exception:
        # Delivery is best-effort in dev; in production a provider failure
        # should be retried/alerted, but must not crash the caller.
        pass
    if settings.DEBUG:
        return code
    return None


def verify_otp(phone_number, purpose, code):
    """Verify an OTP code for a phone + purpose.

    Returns (ok, error_message). Consumes the code on success (single-use).
    Guards: expiry, attempt limit, and only the latest unused request is checked.
    """
    phone = _normalize_phone(phone_number)
    code = str(code or '').strip()

    request = (
        OTPRequest.objects
        .filter(phone_number=phone, purpose=purpose, is_used=False)
        .order_by('-created_at')
        .first()
    )
    if request is None:
        return False, 'No active verification code. Request a new one.'

    if request.expires_at < timezone.now():
        return False, 'Verification code has expired. Request a new one.'

    if request.attempts >= OTP_MAX_ATTEMPTS:
        return False, 'Too many attempts. Request a new code.'

    # Constant-time-ish compare of hashes.
    if secrets.compare_digest(request.code_hash, _hash_code(code)):
        request.is_used = True
        request.save(update_fields=['is_used'])
        return True, ''

    request.attempts += 1
    request.save(update_fields=['attempts'])
    return False, 'Incorrect code. Try again.'
