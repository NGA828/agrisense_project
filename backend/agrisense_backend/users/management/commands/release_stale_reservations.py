"""Release stale order stock reservations.

Orders placed but never paid hold their product stock for
``settings.ORDER_RESERVATION_MINUTES``. When that window lapses the stock must
be returned to the marketplace, otherwise a failed/abandoned checkout locks
inventory out forever.

Run via cron / Celery beat, e.g. every 5 minutes:
    python manage.py release_stale_reservations
"""

from django.core.management.base import BaseCommand

from products.tasks import release_stale_reservations_task


class Command(BaseCommand):
    help = 'Cancel pending orders whose stock reservation window has lapsed.'

    def handle(self, *args, **kwargs):
        # Run eagerly in-process so the CLI works without a broker (same logic
        # as the Celery beat task).
        released = release_stale_reservations_task.apply().result
        self.stdout.write(self.style.SUCCESS(
            f'Released {released} stale reservation(s).'))
