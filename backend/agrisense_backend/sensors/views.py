"""IoT sensor endpoints: device registration, reading ingestion, queries."""

from datetime import timedelta

from django.utils import timezone
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action

from .models import SensorDevice, SensorReading
from .serializers import (SensorDeviceSerializer, SensorReadingSerializer,
                          SensorReadingIngestSerializer)


class SensorDeviceViewSet(viewsets.ModelViewSet):
    queryset = SensorDevice.objects.all()
    serializer_class = SensorDeviceSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        if self.request.user.role == 'admin':
            return SensorDevice.objects.all()
        return SensorDevice.objects.filter(owner=self.request.user)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(owner=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def ingest(self, request, pk=None):
        """Push one or many readings for this device (vendor/sensor clients)."""
        device = self.get_object()
        serializer = SensorReadingIngestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        data = serializer.validated_data
        created = 0
        now = timezone.now()

        if data.get('readings'):
            for item in data['readings']:
                SensorReading.objects.create(
                    device=device,
                    value=float(item.get('value')),
                    unit=item.get('unit') or data.get('unit') or '',
                    recorded_at=item.get('recorded_at') or now,
                )
                created += 1
        elif data.get('value') is not None:
            SensorReading.objects.create(
                device=device,
                value=data['value'],
                unit=data.get('unit') or '',
                recorded_at=now,
            )
            created = 1
        else:
            return Response({'error': 'Provide a value or a readings list.'},
                            status=status.HTTP_400_BAD_REQUEST)

        return Response({'status': 'ok', 'ingested': created}, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['get'])
    def latest(self, request, pk=None):
        """Latest reading per metric + simple advisory hint."""
        device = self.get_object()
        latest = device.readings.order_by('-recorded_at').first()
        reading = SensorReadingSerializer(latest).data if latest else None

        # Lightweight irrigation advisory based on the latest reading.
        advice = None
        if device.sensor_type == 'soil_moisture' and latest:
            if latest.value < 30:
                advice = 'Soil is dry — consider irrigation.'
            elif latest.value < 60:
                advice = 'Soil moisture is moderate.'
            else:
                advice = 'Soil moisture is adequate.'

        return Response({'device': device.device_id, 'latest': reading, 'advice': advice})

    @action(detail=True, methods=['get'])
    def irrigation_advice(self, request, pk=None):
        """Precision irrigation advice for a soil-moisture sensor.

        Combines live moisture + trend with the local weather (rain probability)
        and crop-specific thresholds. Optionally override the crop:
            GET /api/sensors/{id}/irrigation_advice/?crop=Tomato
        """
        device = self.get_object()
        crop = request.query_params.get('crop') or device.crop or None
        from .services import compute_irrigation_advice
        return Response({
            'device': device.device_id,
            'sensor_type': device.sensor_type,
            **compute_irrigation_advice(device, crop=crop),
        })
