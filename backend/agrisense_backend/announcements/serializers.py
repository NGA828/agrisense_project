from rest_framework import serializers
from .models import Announcement, Notification


class AnnouncementSerializer(serializers.ModelSerializer):
    created_by_name = serializers.CharField(source='created_by.first_name', read_only=True)

    class Meta:
        model = Announcement
        fields = ['id', 'title', 'content', 'target_audience', 'created_by',
                  'created_by_name', 'is_active', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_by', 'created_at', 'updated_at']


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ['id', 'title', 'message', 'type', 'reference_id', 'is_read', 'created_at']
        read_only_fields = ['id', 'title', 'message', 'type', 'reference_id', 'created_at']
