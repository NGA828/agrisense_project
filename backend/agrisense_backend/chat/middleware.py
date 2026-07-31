"""WebSocket JWT authentication middleware for Channels.

The Flutter app connects to ``ws://host/ws/chat/{room_id}/?token=<access>``.
The token is validated with SimpleJWT and ``scope['user']`` is populated, so
consumers can enforce room membership and can never trust a client-supplied
sender identity.
"""

from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import AccessToken


@database_sync_to_async
def get_user_from_token(token):
    from users.models import User
    try:
        access = AccessToken(token)
        user_id = access['user_id']
        user = User.objects.get(id=user_id)
        if not user.is_active:
            return AnonymousUser()
        return user
    except Exception:
        return AnonymousUser()


class JwtAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        if scope['type'] == 'websocket':
            query = parse_qs(scope.get('query_string', b'').decode())
            token = (query.get('token') or [None])[0]
            if token:
                scope['user'] = await get_user_from_token(token)
        return await super().__call__(scope, receive, send)
