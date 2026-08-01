"""Celery tasks for the diagnosis app."""

from celery import shared_task


@shared_task
def detect_outbreak_alerts_task():
    """Detect growing disease clusters and notify nearby farmers.

    Returns a list of newly created alerts (for tests / logging).
    """
    from .services import detect_outbreak_alerts
    return detect_outbreak_alerts(save=True)
