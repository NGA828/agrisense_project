"""
Realtime delivery helpers.

Two complementary channels:
* **In-app (WebSocket push bus)** — an online client is joined to ``user_{id}``
  and (for farmers browsing the marketplace) ``all_online``. These helpers push
  lightweight events over the Channels channel layer so a *live* app updates
  instantly (notifications, order-status, stock availability).
* **True push (FCM/APNs)** — ``send_push_notification`` delivers to the user's
  registered device tokens so they receive it even when the app is closed.

All helpers are safe to call from sync Django code (they use ``async_to_sync``)
and never raise: delivery failures are swallowed so business logic is unaffected.
"""

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .push_provider import get_push_provider, PushError

# Channel-group names.
USER_GROUP = 'user_{user_id}'
ALL_ONLINE_GROUP = 'all_online'


def _group_send(group, event):
    layer = get_channel_layer()
    if layer is None:
        return
    try:
        async_to_sync(layer.group_send)(group, event)
    except Exception:
        pass


async def asend_to_user(user_id, event_type, **payload):
    """Async variant of :func:`send_to_user` (safe inside a running loop)."""
    layer = get_channel_layer()
    if layer is None:
        return
    try:
        await layer.group_send(USER_GROUP.format(user_id=user_id), {
            'type': 'push.event',
            'event_type': event_type,
            'payload': payload,
        })
    except Exception:
        pass


async def asend_to_all(event_type, **payload):
    """Async variant of :func:`send_to_all`."""
    layer = get_channel_layer()
    if layer is None:
        return
    try:
        await layer.group_send(ALL_ONLINE_GROUP, {
            'type': 'push.event',
            'event_type': event_type,
            'payload': payload,
        })
    except Exception:
        pass


def send_to_user(user_id, event_type, **payload):
    """Push an in-app event to one user's WS group (best-effort)."""
    _group_send(USER_GROUP.format(user_id=user_id), {
        'type': 'push.event',
        'event_type': event_type,
        'payload': payload,
    })


def send_to_all(event_type, **payload):
    """Broadcast an in-app event to everyone currently online (best-effort)."""
    _group_send(ALL_ONLINE_GROUP, {
        'type': 'push.event',
        'event_type': event_type,
        'payload': payload,
    })


def send_push_notification(user, title, message, data=None):
    """Deliver a true push to a user's registered devices (best-effort)."""
    from .models import PushDevice
    devices = PushDevice.objects.filter(user=user, is_active=True)
    if not devices.exists():
        return
    provider = get_push_provider()
    try:
        provider.send_batch(devices, title, message, data=data)
    except Exception:
        pass
