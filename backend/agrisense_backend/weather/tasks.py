"""Celery tasks for the weather app."""

from celery import shared_task


@shared_task
def cleanup_weather_task(retention_days=None):
    """Prune old weather rows (unbounded DB growth guard).

    Keeps only the most recent ``retention_days`` of samples per coordinate.
    """
    from datetime import timedelta

    from django.conf import settings
    from django.utils import timezone

    from .models import WeatherData

    days = retention_days or getattr(settings, 'WEATHER_RETENTION_DAYS', 30)
    cutoff = timezone.now() - timedelta(days=days)
    deleted, _ = WeatherData.objects.filter(fetched_at__lt=cutoff).delete()
    return deleted
