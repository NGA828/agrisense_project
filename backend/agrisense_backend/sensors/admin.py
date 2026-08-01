from django.contrib import admin

from .models import SensorDevice, SensorReading


@admin.register(SensorDevice)
class SensorDeviceAdmin(admin.ModelAdmin):
    list_display = ('device_id', 'name', 'sensor_type', 'owner', 'is_active')
    list_filter = ('sensor_type', 'is_active')
    search_fields = ('device_id', 'name', 'owner__username')


@admin.register(SensorReading)
class SensorReadingAdmin(admin.ModelAdmin):
    list_display = ('device', 'value', 'unit', 'recorded_at')
    date_hierarchy = 'recorded_at'
    search_fields = ('device__device_id',)
