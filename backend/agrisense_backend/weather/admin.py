from django.contrib import admin
from .models import WeatherData


@admin.register(WeatherData)
class WeatherDataAdmin(admin.ModelAdmin):
    list_display = ['id', 'location_name', 'temperature', 'humidity', 'condition', 'fetched_at']
    list_filter = ['condition']
    search_fields = ['location_name']
