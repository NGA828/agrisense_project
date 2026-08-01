"""
Realtime push-bus WebSocket consumer.

The Flutter app opens a single persistent connection to
``ws://host/ws/push/?token=<access>`` after login. The consumer:

* authenticates the token (via the shared JWT middleware),
* joins the user's private group (``user_{id}``) and the broadcast group
  (``all_online``),
* forwards server-pushed events (``notification``, ``order_status``,
  ``stock_update``, ``announcement``) to the client,
* answers client ``ping`` messages with ``pong`` (keepalive).

The authenticated user is the only identity trusted; clients cannot subscribe to
other users' groups.
"""

import json

from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth.models import AnonymousUser

from .services import USER_GROUP, ALL_ONLINE_GROUP


class PushConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        user = self.scope.get('user', AnonymousUser())
        if isinstance(user, AnonymousUser) or not user.is_authenticated:
            await self.close(code=4001)  # unauthenticated
            return
        self.user = user
        self.group_name = USER_GROUP.format(user_id=user.id)

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        # Farmers browse the marketplace and care about stock changes; everyone
        # cares about broadcasts. Joining all_online lets us fan out cheaply.
        await self.channel_layer.group_add(ALL_ONLINE_GROUP, self.channel_name)
        await self.accept()

        await self.send(text_data=json.dumps({
            'type': 'connected',
            'message': 'realtime connected',
            'user_id': user.id,
            'role': user.role,
        }))

    async def disconnect(self, close_code):
        if hasattr(self, 'group_name'):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        try:
            await self.channel_layer.group_discard(ALL_ONLINE_GROUP, self.channel_name)
        except Exception:
            pass

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return
        msg_type = data.get('type')
        if msg_type == 'ping':
            await self.send(text_data=json.dumps({'type': 'pong'}))
        # Other client messages (e.g. chat typing) go through their own consumer.

    # Server-initiated event handler (Channels maps event['type']='push.event'
    # to this method).
    async def push_event(self, event):
        await self.send(text_data=json.dumps({
            'type': event.get('event_type', 'event'),
            'payload': event.get('payload', {}),
        }))
