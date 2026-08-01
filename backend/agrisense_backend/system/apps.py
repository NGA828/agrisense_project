from django.apps import AppConfig


class SystemConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'system'

    def ready(self):
        # Register the production-security system checks.
        import system.checks  # noqa: F401
