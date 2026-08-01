from rest_framework import serializers

from .models import SensorDevice, SensorReading


class SensorDeviceSerializer(serializers.ModelSerializer):
    owner_name = serializers.CharField(source='owner.first_name', read_only=True)

    class Meta:
        model = SensorDevice
        fields = ['id', 'device_id', 'name', 'sensor_type', 'latitude', 'longitude',
                  'crop', 'is_active', 'last_irrigation_alert_at',
                  'owner', 'owner_name', 'created_at']
        read_only_fields = ['id', 'owner', 'owner_name', 'last_irrigation_alert_at',
                            'created_at']


class SensorReadingSerializer(serializers.ModelSerializer):
    class Meta:
        model = SensorReading
        fields = ['id', 'device', 'value', 'unit', 'recorded_at', 'received_at']
        read_only_fields = ['id', 'received_at']


class SensorReadingIngestSerializer(serializers.Serializer):
    """Ingest payload for one or many readings for a device.

    Body: {device_id, sensor_type, readings: [{value, unit?, recorded_at?}]}
    Accepts a single reading too: {device_id, sensor_type, value, unit?}.
    """
    device_id = serializers.CharField(max_length=100)
    sensor_type = serializers.ChoiceField(choices=SensorDevice.SENSOR_TYPE_CHOICES)
    value = serializers.FloatField(required=False)
    unit = serializers.CharField(required=False, max_length=20, default='')
    readings = serializers.ListField(required=False, child=serializers.DictField())
