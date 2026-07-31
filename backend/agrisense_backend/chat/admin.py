from django.contrib import admin
from .models import ChatRoom, Message


@admin.register(ChatRoom)
class ChatRoomAdmin(admin.ModelAdmin):
    list_display = ['id', 'farmer', 'dealer', 'created_at']
    search_fields = ['farmer__email', 'dealer__email']


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ['id', 'chat_room', 'sender', 'message', 'is_read', 'created_at']
    list_filter = ['is_read']
