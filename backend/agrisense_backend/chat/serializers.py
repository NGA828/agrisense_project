from rest_framework import serializers
from .models import ChatRoom, Message


class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.CharField(source='sender.get_full_name', read_only=True)

    class Meta:
        model = Message
        fields = ['id', 'chat_room', 'sender', 'sender_name', 'message', 'image', 'is_read', 'created_at']
        read_only_fields = ['id', 'sender', 'created_at']


class ChatRoomSerializer(serializers.ModelSerializer):
    other_user_name = serializers.SerializerMethodField()
    other_user_role = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()

    class Meta:
        model = ChatRoom
        fields = ['id', 'farmer', 'dealer', 'other_user_name', 'other_user_role',
                  'last_message', 'unread_count', 'created_at', 'updated_at']

    def get_other_user_name(self, obj):
        request = self.context.get('request')
        if request and request.user:
            if request.user == obj.farmer:
                return obj.dealer.get_full_name()
            return obj.farmer.get_full_name()
        return ''

    def get_other_user_role(self, obj):
        request = self.context.get('request')
        if request and request.user:
            if request.user == obj.farmer:
                return obj.dealer.role
            return obj.farmer.role
        return ''

    def get_last_message(self, obj):
        msg = obj.messages.order_by('-created_at').first()
        return msg.message if msg else ''

    def get_unread_count(self, obj):
        request = self.context.get('request')
        if request and request.user:
            return obj.messages.filter(is_read=False).exclude(sender=request.user).count()
        return 0
