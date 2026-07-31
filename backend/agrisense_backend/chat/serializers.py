from rest_framework import serializers
from .models import ChatRoom, Message


class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.CharField(source='sender.get_full_name', read_only=True)
    sender_role = serializers.CharField(source='sender.role', read_only=True)
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = ['id', 'chat_room', 'sender', 'sender_name', 'sender_role',
                  'message', 'image', 'image_url', 'is_read', 'created_at']
        read_only_fields = ['id', 'sender', 'created_at', 'is_read']

    def get_image_url(self, obj):
        if obj.image:
            request = self.context.get('request')
            url = obj.image.url
            return request.build_absolute_uri(url) if request else url
        return None


class ChatRoomSerializer(serializers.ModelSerializer):
    other_user_id = serializers.SerializerMethodField()
    other_user_name = serializers.SerializerMethodField()
    other_user_role = serializers.SerializerMethodField()
    other_user_phone = serializers.SerializerMethodField()
    other_is_verified = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    last_message_time = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()

    class Meta:
        model = ChatRoom
        fields = ['id', 'farmer', 'dealer', 'other_user_id', 'other_user_name',
                  'other_user_role', 'other_user_phone', 'other_is_verified',
                  'last_message', 'last_message_time', 'unread_count',
                  'created_at', 'updated_at']

    def _other(self, obj, request):
        if request and request.user:
            if request.user.id == obj.farmer_id:
                return obj.dealer
            return obj.farmer
        return None

    def get_other_user_id(self, obj):
        other = self._other(obj, self.context.get('request'))
        return other.id if other else None

    def get_other_user_name(self, obj):
        other = self._other(obj, self.context.get('request'))
        if not other:
            return ''
        name = f'{other.first_name} {other.last_name}'.strip()
        return name or other.username

    def get_other_user_role(self, obj):
        other = self._other(obj, self.context.get('request'))
        return other.role if other else ''

    def get_other_user_phone(self, obj):
        other = self._other(obj, self.context.get('request'))
        return other.phone_number if other else ''

    def get_other_is_verified(self, obj):
        other = self._other(obj, self.context.get('request'))
        return other.is_verified if other else False

    def get_last_message(self, obj):
        msg = obj.messages.order_by('-created_at').first()
        if not msg:
            return ''
        return f'{msg.sender.get_full_name() or msg.sender.username}: {msg.message}' if msg.message \
            else '[Image]'

    def get_last_message_time(self, obj):
        msg = obj.messages.order_by('-created_at').first()
        return msg.created_at.isoformat() if msg else ''

    def get_unread_count(self, obj):
        request = self.context.get('request')
        if request and request.user:
            return obj.messages.filter(is_read=False).exclude(sender=request.user).count()
        return 0
