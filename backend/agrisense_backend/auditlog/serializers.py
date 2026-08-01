from rest_framework import serializers

from .models import AuditLog


class AuditLogSerializer(serializers.ModelSerializer):
    actor_name = serializers.CharField(source='actor.get_full_name', read_only=True, default='System')
    actor_username = serializers.CharField(source='actor.username', read_only=True, default='system')

    class Meta:
        model = AuditLog
        fields = ['id', 'actor', 'actor_name', 'actor_username', 'category', 'action',
                  'target_type', 'target_id', 'description', 'metadata',
                  'request_id', 'ip_address', 'created_at']
        read_only_fields = fields
