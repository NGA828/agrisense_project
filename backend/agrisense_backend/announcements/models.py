from django.conf import settings
from django.db import models


class Announcement(models.Model):
    TARGET_CHOICES = (
        ('all', 'All Users'),
        ('farmers', 'Farmers Only'),
        ('dealers', 'Dealers Only'),
    )

    title = models.CharField(max_length=200)
    content = models.TextField()
    target_audience = models.CharField(max_length=20, choices=TARGET_CHOICES, default='all')
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='announcements')
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.title

    class Meta:
        db_table = 'announcement'
        ordering = ['-created_at']


class Notification(models.Model):
    """Per-user in-app notification (order placed, payment received, etc.).

    These are the app-level equivalent of push notifications: the mobile app
    polls ``/api/notifications/`` for new items and surfaces a badge + list.
    An FCM/APNs adapter can later fan these out as true push notifications.
    """

    TYPE_CHOICES = (
        ('order', 'New order placed'),
        ('order_status', 'Order status update'),
        ('payment', 'Payment update'),
        ('premium', 'Premium subscription'),
        ('system', 'System alert'),
        ('chat', 'New chat message'),
    )

    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='notifications')
    title = models.CharField(max_length=200)
    message = models.TextField()
    type = models.CharField(max_length=20, choices=TYPE_CHOICES, default='system')
    reference_id = models.CharField(max_length=50, blank=True, default='', help_text='e.g. order id')
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'notification'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['recipient', 'is_read', '-created_at'], name='idx_notif_recipient'),
        ]

    def __str__(self):
        return f'{self.title} → {self.recipient.username}'


def fan_out_announcement(announcement):
    """Materialise a broadcast into per-user notifications + push them.

    Creates a ``Notification`` row for every active user in the announcement's
    target audience, so the broadcast shows in each user's in-app list and
    unread badge, and delivers it over WS + push. (At larger scale this should
    move to a background task — see the Phase C roadmap.)
    """
    from users.models import User
    qs = User.objects.filter(is_active=True)
    if announcement.target_audience == 'farmers':
        qs = qs.filter(role='farmer')
    elif announcement.target_audience == 'dealers':
        qs = qs.filter(role='dealer')

    created = 0
    for user in qs.iterator():
        if notify_user(user, announcement.title, announcement.content,
                       type='system', reference_id=f'announcement:{announcement.id}'):
            created += 1
    return created


def notify_user(user, title, message, type='system', reference_id=''):
    """Create an in-app notification for a user and deliver it in realtime.

    In addition to persisting the ``Notification`` row, this pushes the
    notification over the user's WebSocket push bus (live apps update
    instantly) and, if push is configured, to their registered FCM/APNs
    devices. No-op if the user is inactive.
    """
    if not user or not user.is_active:
        return None
    notification = Notification.objects.create(
        recipient=user,
        title=title,
        message=message,
        type=type,
        reference_id=str(reference_id or ''),
    )
    try:
        from realtime.services import send_to_user, send_push_notification
        send_to_user(user.id, 'notification', {
            'id': notification.id,
            'title': title,
            'message': message,
            'type': type,
            'reference_id': str(reference_id or ''),
        })
        send_push_notification(user, title, message,
                               data={'type': type, 'reference_id': str(reference_id or '')})
    except Exception:
        # Realtime/push are best-effort; never break the business operation.
        pass
    return notification
