from rest_framework import status, permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from .models import PushDevice
from .serializers import PushDeviceSerializer


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def register_push_token(request):
    """Register (or refresh) a device push token for the current user.

    Body: {token, provider: 'fcm'|'apns', platform: 'android'|'ios'|'web'}
    Registering an existing token simply reactivates it.
    """
    token = str(request.data.get('token') or '').strip()
    if not token or len(token) < 8:
        return Response({'error': 'token is required (min length 8)'},
                        status=status.HTTP_400_BAD_REQUEST)

    provider = str(request.data.get('provider') or 'fcm').lower()
    if provider not in ('fcm', 'apns'):
        return Response({'error': "provider must be 'fcm' or 'apns'"},
                        status=status.HTTP_400_BAD_REQUEST)
    platform = str(request.data.get('platform') or 'android').lower()
    if platform not in ('android', 'ios', 'web'):
        return Response({'error': "platform must be 'android', 'ios' or 'web'"},
                        status=status.HTTP_400_BAD_REQUEST)

    device, _ = PushDevice.objects.update_or_create(
        user=request.user, token=token,
        defaults={'provider': provider, 'platform': platform, 'is_active': True},
    )
    serializer = PushDeviceSerializer(device)
    return Response(serializer.data, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def unregister_push_token(request):
    """Deactivate a push token (e.g. user logged out)."""
    token = str(request.data.get('token') or '').strip()
    if not token:
        return Response({'error': 'token is required'}, status=status.HTTP_400_BAD_REQUEST)
    PushDevice.objects.filter(user=request.user, token=token).update(is_active=False)
    return Response({'status': 'ok'})
