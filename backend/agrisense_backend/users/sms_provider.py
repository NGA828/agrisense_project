"""
SMS provider abstraction for OTP delivery.

The default ``NoopSMSProvider`` logs the code (development/demo — the code is
returned to the caller only in debug). A real provider (Twilio, Africa's
Talking, etc.) can be plugged in behind the same interface so switching vendors
is a configuration change, not a code change.
"""

import logging
import os

from django.conf import settings

logger = logging.getLogger('agrisense.otp')


class SMSProvider:
    provider_name = 'base'

    def send(self, *, phone_number, message):
        raise NotImplementedError


class NoopSMSProvider(SMSProvider):
    """Logs the OTP message. In DEBUG the code is surfaced in the response so
    the demo flow works end-to-end without an SMS gateway."""

    provider_name = 'noop'

    def send(self, *, phone_number, message):
        logger.info('[SMS noop] to=%s: %s', phone_number, message)
        return {'status': 'sent', 'provider': 'noop'}


class AfricaSTalkingSMSProvider(SMSProvider):
    """Africa's Talking SMS gateway (common in the region).

    Set:
        SMS_PROVIDER=africastalking
        AT_API_KEY=...
        AT_USERNAME=...
        AT_SENDER_ID=... (optional)
    """

    provider_name = 'africastalking'

    def send(self, *, phone_number, message):
        import requests  # noqa
        api_key = os.getenv('AT_API_KEY', '')
        username = os.getenv('AT_USERNAME', '')
        if not api_key or not username:
            raise RuntimeError('Africa\'s Talking not configured (AT_API_KEY/AT_USERNAME)')
        resp = requests.post(
            'https://api.sandbox.africastalking.com/version1/messaging',
            headers={'apiKey': api_key, 'Content-Type': 'application/x-www-form-urlencoded'},
            data={
                'username': username,
                'to': phone_number,
                'message': message,
                'from': os.getenv('AT_SENDER_ID', ''),
            },
            timeout=10,
        )
        resp.raise_for_status()
        return {'status': 'sent', 'provider': 'africastalking'}


class TwilioSMSProvider(SMSProvider):
    """Twilio SMS gateway.

    Set:
        SMS_PROVIDER=twilio
        TWILIO_ACCOUNT_SID=...
        TWILIO_AUTH_TOKEN=...
        TWILIO_FROM_NUMBER=...
    """

    provider_name = 'twilio'

    def send(self, *, phone_number, message):
        from twilio.rest import Client  # optional dependency
        client = Client(os.getenv('TWILIO_ACCOUNT_SID'), os.getenv('TWILIO_AUTH_TOKEN'))
        client.messages.create(
            to=phone_number, from_=os.getenv('TWILIO_FROM_NUMBER'), body=message,
        )
        return {'status': 'sent', 'provider': 'twilio'}


def get_sms_provider():
    """Return the configured SMS provider (cached per process)."""
    provider = getattr(settings, 'SMS_PROVIDER', 'noop')
    if provider == 'africastalking':
        return AfricaSTalkingSMSProvider()
    if provider == 'twilio':
        return TwilioSMSProvider()
    return NoopSMSProvider()
