"""IoT sensor ingestion for precision agriculture (Phase F).

Dealers/farmers can register field sensors (soil moisture, temperature, humidity,
rainfall) that push readings periodically. The advice engine (and future
irrigation automation) can consume these readings. Kept lightweight and append-only:
readings are never edited, only queried with retention pruning.
"""

from django.conf import settings
from django.db import models


class SensorDevice(models.Model):
    """A physical field sensor registered to a user's account."""
    SENSOR_TYPE_CHOICES = (
        ('soil_moisture', 'Soil moisture'),
        ('soil_temperature', 'Soil temperature'),
        ('air_temperature', 'Air temperature'),
        ('air_humidity', 'Air humidity'),
        ('rainfall', 'Rainfall'),
    )

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='sensor_devices',
    )
    device_id = models.CharField(max_length=100, unique=True, help_text='Vendor device identifier')
    name = models.CharField(max_length=100, blank=True, default='')
    sensor_type = models.CharField(max_length=30, choices=SENSOR_TYPE_CHOICES, default='soil_moisture')
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    # Optional crop for irrigation advice (used by the advisory service).
    crop = models.CharField(max_length=50, blank=True, default='',
                            help_text='Crop grown at this sensor (for irrigation thresholds)')
    is_active = models.BooleanField(default=True)
    # Last time an automatic irrigation alert was pushed (alert throttle).
    last_irrigation_alert_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.name or self.device_id} ({self.sensor_type})'

    class Meta:
        db_table = 'sensor_device'
        indexes = [
            models.Index(fields=['owner', 'sensor_type'], name='idx_sensor_owner_type'),
        ]


class SensorReading(models.Model):
    """A single measurement pushed by a sensor device."""
    device = models.ForeignKey(
        SensorDevice, on_delete=models.CASCADE, related_name='readings')
    value = models.FloatField(help_text='Measurement in the device unit')
    unit = models.CharField(max_length=20, blank=True, default='')
    recorded_at = models.DateTimeField(db_index=True)
    received_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'sensor_reading'
        ordering = ['-recorded_at']
        indexes = [
            models.Index(fields=['device', '-recorded_at'], name='idx_reading_device_time'),
        ]
