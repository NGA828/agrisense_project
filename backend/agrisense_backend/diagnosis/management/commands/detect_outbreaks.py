"""Detect growing disease clusters and alert nearby farmers.

Run via cron / Celery beat:
    python manage.py detect_outbreaks
"""

from django.core.management.base import BaseCommand

from diagnosis.services import detect_outbreak_alerts


class Command(BaseCommand):
    help = 'Detect growing disease clusters and notify nearby farmers.'

    def handle(self, *args, **kwargs):
        alerts = detect_outbreak_alerts(save=True)
        self.stdout.write(self.style.SUCCESS(
            f'Outbreak detection: created {len(alerts)} alert(s).'))
        for a in alerts:
            self.stdout.write(
                f'  {a["disease"]} ({a["crop"]}) @ '
                f'({a["lat"]:.1f},{a["lon"]:.1f}) '
                f'x{a["cluster_size"]} (prev {a["previous_size"]}) '
                f'-> notified {a["notified"]} farmer(s)')
