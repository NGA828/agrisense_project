"""Production-security system checks (auto-discovered by Django).

Django auto-imports ``<app>.checks`` for every app in INSTALLED_APPS, which
registers the check functions defined in ``agrisense_backend.checks``. Keeping
the implementations in the project package and re-importing here lets them run
on every ``manage.py check`` / ``check --deploy``.
"""

from agrisense_backend.checks import *  # noqa: F401,F403  (registers checks)
