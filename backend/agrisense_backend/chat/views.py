from rest_framework import viewsets, status, permissions, serializers as drf_serializers
from rest_framework.response import Response
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser

from .models import ChatRoom, Message
from .serializers import ChatRoomSerializer, MessageSerializer


class ChatRoomViewSet(viewsets.ModelViewSet):
    queryset = ChatRoom.objects.all()
    serializer_class = ChatRoomSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser, JSONParser]

    def get_queryset(self):
        user = self.request.user
        return (ChatRoom.objects.filter(farmer=user) | ChatRoom.objects.filter(dealer=user)).order_by('-updated_at')

    def create(self, request, *args, **kwargs):
        """Start a conversation (get-or-create semantics).

        Farmer ↔ dealer pairings are unique; starting an existing conversation
        returns the existing room.
        """
        from users.models import User

        user = request.user
        other_id = request.data.get('dealer') if user.role == 'farmer' else request.data.get('farmer')
        if not other_id:
            raise drf_serializers.ValidationError(
                {'error': 'Provide a dealer id (as farmer) or a farmer id (as dealer).'})

        try:
            other = User.objects.get(id=other_id)
        except User.DoesNotExist:
            raise drf_serializers.ValidationError({'error': 'User not found.'})

        if user.role == 'farmer' and other.role != 'dealer':
            raise drf_serializers.ValidationError({'error': 'Farmers can only chat with dealers.'})
        if user.role == 'dealer' and other.role != 'farmer':
            raise drf_serializers.ValidationError({'error': 'Dealers can only chat with farmers.'})
        if user.role not in ('farmer', 'dealer'):
            raise drf_serializers.ValidationError({'error': 'Only farmers and dealers can chat.'})

        room, created = ChatRoom.objects.get_or_create(
            farmer=user if user.role == 'farmer' else other,
            dealer=user if user.role == 'dealer' else other,
        )
        serializer = self.get_serializer(room)
        return Response(serializer.data, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    @action(detail=True, methods=['get'])
    def messages(self, request, pk=None):
        """List messages (marks incoming messages as read)."""
        room = self.get_object()
        room.messages.filter(is_read=False).exclude(sender=request.user).update(is_read=True)
        messages = room.messages.order_by('created_at')
        serializer = MessageSerializer(messages, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def send_message(self, request, pk=None):
        """Send a text and/or image message. REST fallback for the WebSocket."""
        room = self.get_object()
        content = str(request.data.get('content') or request.data.get('message') or '').strip()
        image = request.FILES.get('image', None)

        if not content and not image:
            return Response({'error': 'Content or image required'}, status=status.HTTP_400_BAD_REQUEST)

        message = Message.objects.create(
            chat_room=room,
            sender=request.user,
            message=content,
            image=image,
        )
        serializer = MessageSerializer(message)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def mark_read(self, request, pk=None):
        room = self.get_object()
        room.messages.filter(is_read=False).exclude(sender=request.user).update(is_read=True)
        return Response({'status': 'ok'})

    @action(detail=False, methods=['get'])
    def unread_counts(self, request):
        """Per-room unread counts for the authenticated user."""
        rooms = self.get_queryset()
        data = {room.id: room.messages.filter(is_read=False).exclude(sender=request.user).count()
                for room in rooms}
        return Response(data)
