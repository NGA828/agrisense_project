from rest_framework import serializers

from .models import PushDevice


class PushDeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = PushDevice
        fields = ['id', 'token', 'provider', 'platform', 'is_active', 'created_at']
        read_only_fields = ['id', 'is_active', 'created_at']
