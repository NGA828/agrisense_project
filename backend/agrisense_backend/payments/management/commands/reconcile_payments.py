"""Cron alternative when a Celery worker/beat is not installed."""
from django.core.management.base import BaseCommand
from payments.tasks import reconcile_payments_task
from products.tasks import release_stale_reservations_task


class Command(BaseCommand):
    help = 'Verify pending collections and release only safe, unsubmitted expired reservations.'

    def handle(self, *args, **options):
        reconciled = reconcile_payments_task(max_age_minutes=0)
        expired = release_stale_reservations_task()
        self.stdout.write(f'Reconciled {reconciled} payment(s); expired {expired} reservation(s).')
