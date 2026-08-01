"""
ASGI config for agrisense_backend project.

It exposes the ASGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/4.2/howto/deployment/asgi/
"""

import os

from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agrisense_backend.settings')

django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402

from chat.middleware import JwtAuthMiddleware  # noqa: E402
from chat.routing import websocket_urlpatterns as chat_ws  # noqa: E402
from realtime.routing import websocket_urlpatterns as realtime_ws  # noqa: E402

# The push bus and chat share the JWT auth middleware so every WebSocket is
# authenticated; consumers never trust client-supplied identity.
websocket_urlpatterns = chat_ws + realtime_ws

application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": JwtAuthMiddleware(
        URLRouter(websocket_urlpatterns)
    ),
})
