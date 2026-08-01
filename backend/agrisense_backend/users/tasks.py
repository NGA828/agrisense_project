"""Celery tasks for the users app."""

from datetime import timedelta

from celery import shared_task


@shared_task
def expire_premiums_task():
    """Expire dealer premium subscriptions whose window has passed.

    Dropping ``is_premium`` removes the search-visibility boost (the ranking
    query respects the expiry). Notifies the dealer and posts a realtime event.
    Returns the number of dealers expired.
    """
    from django.utils import timezone

    from .models import User

    now = timezone.now()
    expired_qs = User.objects.filter(
        role='dealer', is_premium=True, premium_expiry__isnull=False,
        premium_expiry__lte=now,
    )
    count = expired_qs.count()
    for user in expired_qs.iterator():
        user.is_premium = False
        user.save(update_fields=['is_premium'])
        from announcements.models import notify_user
        notify_user(
            user,
            'Premium expired',
            'Your premium dealer subscription has ended. Upgrade anytime to '
            'rank higher in farmer searches again.',
            type='premium',
        )

    # Safety: dealers flagged premium with no expiry get a default window.
    dangling = User.objects.filter(role='dealer', is_premium=True, premium_expiry__isnull=True)
    for user in dangling.iterator():
        user.premium_expiry = now + timedelta(days=30)
        user.save(update_fields=['premium_expiry'])
    return count
