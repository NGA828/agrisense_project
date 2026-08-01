import pymysql

# Make PyMySQL act as MySQLdb so Django's MySQL backend works without mysqlclient
pymysql.install_as_MySQLdb()

# Expose the Celery app so `celery` CLI finds it via `agrisense_backend.celery.app`
# and so `app.autodiscover_tasks()` runs on Django startup.
from .celery import app as celery_app  # noqa: E402,F401
