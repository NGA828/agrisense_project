"""Celery tasks for the sensors app."""

from celery import shared_task


@shared_task
def monitor_irrigation_task():
    """Scan active soil-moisture sensors and alert owners when irrigation is due.

    Throttled per device (``IRRIGATION_ALERT_THROTTLE_HOURS``). Returns a dict of
    alerted device ids -> recommendation.
    """
    from .services import monitor_and_alert_irrigation
    return monitor_and_alert_irrigation(save=True)
