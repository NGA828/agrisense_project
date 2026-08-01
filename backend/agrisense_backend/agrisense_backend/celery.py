"""
Celery application for AgriSense AI.

Background work lives in ``<app>/tasks.py`` and is auto-discovered here:

* ``announcements.tasks.fan_out_announcement_task`` — broadcast fan-out
* ``products.tasks.release_stale_reservations_task`` — free abandoned stock holds
* ``users.tasks.expire_premiums_task`` — drop expired dealer premium boosts
* ``payments.tasks.reconcile_payments_task`` — cross-check provider payments
* ``weather.tasks.cleanup_weather_task`` — prune old weather rows

In development / test (no ``CELERY_BROKER_URL``) tasks run eagerly
(``CELERY_TASK_ALWAYS_EAGER``), so ``.delay()`` executes synchronously and no
broker is required. In production the broker (Redis) is set and tasks run on a
worker (see docker-compose ``worker`` service).
"""

import os

from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agrisense_backend.settings')

app = Celery('agrisense')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()
