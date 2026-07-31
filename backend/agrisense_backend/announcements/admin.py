from django.contrib import admin
from .models import Announcement, Notification


@admin.register(Announcement)
class AnnouncementAdmin(admin.ModelAdmin):
    list_display = ['title', 'target_audience', 'is_active', 'created_by', 'created_at']
    list_filter = ['target_audience', 'is_active', 'created_at']
    search_fields = ['title', 'content']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ['id', 'recipient', 'title', 'type', 'is_read', 'created_at']
    list_filter = ['type', 'is_read']
    search_fields = ['recipient__username', 'title', 'message']
    readonly_fields = ['created_at']
