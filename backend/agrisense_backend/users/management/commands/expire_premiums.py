from django.core.management.base import BaseCommand

from users.tasks import expire_premiums_task


class Command(BaseCommand):
    help = 'Expire premium subscriptions whose window has passed (run daily via cron).'

    def handle(self, *args, **kwargs):
        # Run eagerly in-process (no broker needed); same logic as the beat task.
        count = expire_premiums_task.apply().result
        self.stdout.write(self.style.SUCCESS(f'Expired premium for {count} dealer(s)'))
