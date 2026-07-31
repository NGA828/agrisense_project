from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action
from .models import ChatRoom, Message
from .serializers import ChatRoomSerializer, MessageSerializer


class ChatRoomViewSet(viewsets.ModelViewSet):
    queryset = ChatRoom.objects.all()
    serializer_class = ChatRoomSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return ChatRoom.objects.filter(farmer=user) | ChatRoom.objects.filter(dealer=user)

    def perform_create(self, serializer):
        user = self.request.user
        if user.role == 'farmer':
            dealer_id = self.request.data.get('dealer')
            from users.models import User
            dealer = User.objects.get(id=dealer_id, role='dealer') if dealer_id else None
            serializer.save(farmer=user, dealer=dealer)
        elif user.role == 'dealer':
            farmer_id = self.request.data.get('farmer')
            from users.models import User
            farmer = User.objects.get(id=farmer_id, role='farmer') if farmer_id else None
            serializer.save(farmer=farmer, dealer=user)

    @action(detail=True, methods=['get'])
    def messages(self, request, pk=None):
        room = self.get_object()
        messages = room.messages.order_by('created_at')
        serializer = MessageSerializer(messages, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def send_message(self, request, pk=None):
        room = self.get_object()
        content = request.data.get('content', '')
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
