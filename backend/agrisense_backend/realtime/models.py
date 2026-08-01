"""
Device push tokens + realtime delivery state.

``PushDevice`` stores the mobile push tokens (FCM / APNs) a user registered
through the app. A ``PushProvider`` adapter (see ``push_provider.py``) delivers
true push notifications to these devices even when the app is closed. The
in-app realtime layer is delivered over WebSockets (see ``consumers.py``).
"""

from django.conf import settings
from django.db import models


class PushDevice(models.Model):
    PROVIDER_CHOICES = (
        ('fcm', 'Firebase Cloud Messaging (Android)'),
        ('apns', 'Apple Push Notification Service (iOS)'),
    )
    PLATFORM_CHOICES = (
        ('android', 'Android'),
        ('ios', 'iOS'),
        ('web', 'Web'),
    )

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='push_devices',
    )
    token = models.CharField(max_length=512)
    provider = models.CharField(max_length=10, choices=PROVIDER_CHOICES, default='fcm')
    platform = models.CharField(max_length=10, choices=PLATFORM_CHOICES, default='android')
    is_active = models.BooleanField(default=True)
    last_seen = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.user.username} [{self.provider}] {self.token[:16]}…'

    class Meta:
        db_table = 'push_device'
        unique_together = ['user', 'token']
        indexes = [
            models.Index(fields=['user', 'is_active'], name='idx_push_user_active'),
        ]
