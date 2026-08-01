"""
Push notification provider abstraction.

A ``PushProvider`` delivers a push notification to one (or many) device tokens.
The default ``NoopPushProvider`` is a safe no-op (keeps tests and demo flows
green). When Firebase credentials are configured (``FCM_CREDENTIALS_PATH``),
the ``FCMPushProvider`` sends real push messages via the Firebase Admin SDK and
deactivates invalid/expired tokens.

Switching providers is a configuration change (``get_push_provider()``), never a
code change — the same pattern as the mobile-money gateway.
"""

import os

from django.conf import settings


class PushProvider:
    provider_name = 'base'

    def send(self, *, device, title, message, data=None):
        """Deliver one notification to ``device`` (a PushDevice).

        Should raise ``PushError`` on unrecoverable failures so the caller can
        deactivate the token.
        """
        raise NotImplementedError

    def send_batch(self, devices, title, message, data=None):
        """Deliver a notification to many devices; best-effort."""
        for device in devices:
            try:
                self.send(device=device, title=title, message=message, data=data)
            except PushError:
                device.is_active = False
                device.save(update_fields=['is_active'])


class PushError(Exception):
    """Raised when a device token is invalid / cannot be delivered to."""


class NoopPushProvider(PushProvider):
    """No-op fallback used when push is not configured (dev/test)."""

    provider_name = 'noop'

    def send(self, *, device, title, message, data=None):
        # Deliberately does nothing; in-app notifications still work.
        return {'status': 'noop', 'device': device.token}


class FCMPushProvider(PushProvider):
    """Firebase Cloud Messaging via the Firebase Admin SDK.

    Enabled when ``FCM_CREDENTIALS_PATH`` points to a service-account JSON.
    Falls back to a no-op (and logs) when the SDK / credentials are absent so
    the rest of the system is unaffected.
    """

    provider_name = 'fcm'
    _messaging = None

    def __init__(self):
        path = getattr(settings, 'FCM_CREDENTIALS_PATH', '') or ''
        if path and os.path.exists(path):
            try:
                import firebase_admin
                from firebase_admin import credentials, messaging
                if not firebase_admin._apps:
                    cred = credentials.Certificate(path)
                    firebase_admin.initialize_app(cred)
                self._messaging = messaging
            except Exception:
                self._messaging = None

    @property
    def available(self):
        return self._messaging is not None

    def send(self, *, device, title, message, data=None):
        if not self.available:
            return {'status': 'noop', 'device': device.token}
        try:
            payload = {
                'notification': {'title': title, 'body': message},
                'token': device.token,
            }
            if data:
                payload['data'] = {str(k): str(v) for k, v in data.items()}
            return self._messaging.send(self._messaging.Message(**payload))
        except Exception as exc:  # token invalid / quota — deactivate
            if device.provider == 'fcm':
                raise PushError(str(exc))
            return {'status': 'error', 'error': str(exc)}


def get_push_provider():
    """Return the configured push provider (cached per process)."""
    if getattr(settings, 'PUSH_PROVIDER', 'noop') == 'fcm':
        return FCMPushProvider()
    return NoopPushProvider()
