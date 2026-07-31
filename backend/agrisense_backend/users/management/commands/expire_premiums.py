from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from users.models import User


class Command(BaseCommand):
    help = 'Expire premium subscriptions whose window has passed (run daily via cron).'

    def handle(self, *args, **kwargs):
        now = timezone.now()
        expired = User.objects.filter(
            role='dealer', is_premium=True, premium_expiry__isnull=False,
            premium_expiry__lte=now,
        )
        count = expired.count()
        expired.update(is_premium=False)
        self.stdout.write(self.style.SUCCESS(f'Expired premium for {count} dealer(s)'))

        # Safety: dealers flagged premium with no expiry get a default window.
        dangling = User.objects.filter(role='dealer', is_premium=True, premium_expiry__isnull=True)
        for user in dangling:
            user.premium_expiry = now + timedelta(days=30)
            user.save(update_fields=['premium_expiry'])
        if dangling.count():
            self.stdout.write(f'Fixed {dangling.count()} premium dealer(s) with missing expiry')
