"""Run the irrigation monitor and alert owners whose soil is dry.

Run via cron / Celery beat:
    python manage.py monitor_irrigation
"""

from django.core.management.base import BaseCommand

from sensors.services import monitor_and_alert_irrigation


class Command(BaseCommand):
    help = 'Alert sensor owners when soil moisture is low and no rain is expected.'

    def handle(self, *args, **kwargs):
        alerted = monitor_and_alert_irrigation(save=True)
        self.stdout.write(self.style.SUCCESS(
            f'Irrigation monitor: alerted {len(alerted)} sensor(s): {list(alerted)}'))
