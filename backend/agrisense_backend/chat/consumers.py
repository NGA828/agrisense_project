import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.contrib.auth.models import AnonymousUser

from .models import ChatRoom, Message


class ChatConsumer(AsyncWebsocketConsumer):
    """Real-time chat over WebSocket.

    Security:
    * connection requires a valid JWT (``?token=...``) - see chat/middleware.py
    * only room participants may connect (close code 4003 otherwise)
    * the sender is ALWAYS the authenticated user, never the payload
    """

    async def connect(self):
        user = self.scope.get('user', AnonymousUser())
        if isinstance(user, AnonymousUser) or not user.is_authenticated:
            await self.close(code=4001)  # unauthenticated
            return

        self.room_id = self.scope['url_route']['kwargs']['room_id']
        self.room_group_name = f'chat_{self.room_id}'

        if not await self.is_participant(self.room_id, user.id):
            await self.close(code=4003)  # forbidden
            return

        self.user = user
        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()

        # Deliver any pending unread message count for the client.
        unread = await self.unread_count(self.room_id, user.id)
        await self.send(text_data=json.dumps({
            'type': 'room_joined',
            'room_id': int(self.room_id),
            'unread_count': unread,
        }))

    async def disconnect(self, close_code):
        if hasattr(self, 'room_group_name'):
            await self.channel_layer.group_discard(self.room_group_name, self.channel_name)

    async def receive(self, text_data):
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return

        message = (data.get('message') or '').strip()
        if not message:
            return

        saved = await self.save_message(self.room_id, self.user.id, message)
        if saved is None:
            return

        # Broadcast to the room group (including sender for echo/ordering).
        await self.channel_layer.group_send(
            self.room_group_name,
            {
                'type': 'chat_message',
                'id': saved['id'],
                'message': message,
                'sender_id': saved['sender_id'],
                'sender_name': saved['sender_name'],
                'image_url': saved.get('image_url'),
                'created_at': saved['created_at'],
            }
        )

    async def chat_message(self, event):
        await self.send(text_data=json.dumps({
            'type': 'chat_message',
            'id': event['id'],
            'message': event['message'],
            'sender_id': event['sender_id'],
            'sender_name': event['sender_name'],
            'image_url': event.get('image_url'),
            'created_at': event['created_at'],
        }))

    # ── DB helpers ────────────────────────────────────────────────────
    @database_sync_to_async
    def is_participant(self, room_id, user_id):
        try:
            room = ChatRoom.objects.get(id=room_id)
        except ChatRoom.DoesNotExist:
            return False
        return room.farmer_id == user_id or room.dealer_id == user_id

    @database_sync_to_async
    def unread_count(self, room_id, user_id):
        try:
            room = ChatRoom.objects.get(id=room_id)
        except ChatRoom.DoesNotExist:
            return 0
        return room.messages.filter(is_read=False).exclude(sender_id=user_id).count()

    @database_sync_to_async
    def save_message(self, room_id, sender_id, message):
        try:
            room = ChatRoom.objects.get(id=room_id)
            from users.models import User
            sender = User.objects.get(id=sender_id)
            msg = Message.objects.create(chat_room=room, sender=sender, message=message)

            recipient = room.dealer if room.farmer_id == sender_id else room.farmer
            from announcements.models import notify_user
            notify_user(
                recipient,
                'New message 💬',
                f'{sender.first_name or sender.username}: {message[:40]}',
                type='chat',
                reference_id=room.id,
            )

            return {
                'id': msg.id,
                'sender_id': msg.sender_id,
                'sender_name': msg.sender.get_full_name() or msg.sender.username,
                'image_url': msg.image.url if msg.image else None,
                'created_at': msg.created_at.isoformat(),
            }
        except Exception:
            return None
