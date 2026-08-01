"""Celery tasks for the announcements app."""

from celery import shared_task


@shared_task
def fan_out_announcement_task(announcement_id):
    """Materialise a broadcast into per-user notifications + push.

    Runs asynchronously in production so a large broadcast does not block the
    admin's HTTP request. In dev/test (eager mode) it executes synchronously.
    """
    from .models import Announcement, fan_out_announcement

    try:
        announcement = Announcement.objects.get(id=announcement_id)
    except Announcement.DoesNotExist:
        return None
    if not announcement.is_active:
        return 0
    return fan_out_announcement(announcement)
