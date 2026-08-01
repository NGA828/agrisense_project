"""Prune old weather rows.

Run via cron / Celery beat:
    python manage.py cleanup_weather [--days 30]
"""

from django.core.management.base import BaseCommand

from weather.tasks import cleanup_weather_task


class Command(BaseCommand):
    help = 'Delete weather samples older than the retention window.'

    def add_arguments(self, parser):
        parser.add_argument('--days', type=int, default=None,
                            help='Retention window in days (default: WEATHER_RETENTION_DAYS).')

    def handle(self, *args, **options):
        # Run eagerly in-process so the CLI works without a broker.
        deleted = cleanup_weather_task.apply(kwargs={'retention_days': options['days']}).result
        self.stdout.write(self.style.SUCCESS(f'Pruned {deleted} old weather row(s).'))
