"""
Custom Django system checks for production security (Phase C).

These run alongside Django's built-in checks on every ``manage.py check`` (and
``manage.py check --deploy``). They surface misconfigurations as warnings
(pass-level) so development and tests are unaffected, but CI and operators can
treat warnings as failures for a production gate.

Registering: Django auto-imports ``checks`` from each installed app and from the
project package, so defining functions with ``@register`` is enough.
"""

from django.conf import settings
from django.core.checks import Warning, register

# Known insecure development defaults that must never ship to production.
_INSECURE_SECRETS = {
    'm(l2!fbpl&%gy9yx47k=a)2h@ie@%fm%t603=0u$ww@(kvz2gp',
    'dev-secret-key-change-me',
}


@register()
def check_debug_and_secret(app_configs, **kwargs):
    """Warn when DEBUG is on or SECRET_KEY is a known dev default."""
    errors = []
    if settings.DEBUG:
        errors.append(Warning(
            'DEBUG is enabled.',
            hint='Set DEBUG=False in production.',
            id='agrisense.W001',
        ))
    if settings.SECRET_KEY in _INSECURE_SECRETS:
        errors.append(Warning(
            'DJANGO_SECRET_KEY is a known insecure default.',
            hint='Set a long random DJANGO_SECRET_KEY in production.',
            id='agrisense.W002',
        ))
    return errors


@register()
def check_cors(app_configs, **kwargs):
    """Warn when CORS allows all origins or credentials are unrestricted."""
    errors = []
    if getattr(settings, 'CORS_ALLOW_ALL_ORIGINS', False):
        errors.append(Warning(
            'CORS_ALLOW_ALL_ORIGINS is enabled.',
            hint='Restrict CORS_ALLOWED_ORIGINS to known clients in production.',
            id='agrisense.W003',
        ))
    return errors


@register()
def check_allowed_hosts(app_configs, **kwargs):
    """Warn when ALLOWED_HOSTS is the wildcard."""
    hosts = getattr(settings, 'ALLOWED_HOSTS', [])
    if hosts == ['*']:
        errors = [Warning(
            'ALLOWED_HOSTS is set to the wildcard "*".',
            hint='Set an explicit allow-list of hostnames in production.',
            id='agrisense.W004',
        )]
    else:
        errors = []
    return errors


@register()
def check_weather_config(app_configs, **kwargs):
    """Remind operators to set weather + push + webhook secrets in production."""
    errors = []
    if not getattr(settings, 'OPENWEATHER_API_KEY', ''):
        errors.append(Warning(
            'OPENWEATHER_API_KEY is not set; weather falls back to canned data.',
            hint='Set OPENWEATHER_API_KEY for live forecasts.',
            id='agrisense.W005',
        ))
    if settings.PUSH_PROVIDER == 'noop':
        errors.append(Warning(
            'PUSH_PROVIDER is "noop"; notifications are in-app only.',
            hint='Set PUSH_PROVIDER=fcm + FCM_CREDENTIALS_PATH for real push.',
            id='agrisense.W006',
        ))
    if settings.PAYMENT_WEBHOOK_SECRET == 'dev-webhook-secret':
        errors.append(Warning(
            'PAYMENT_WEBHOOK_SECRET is the dev default.',
            hint='Set a strong PAYMENT_WEBHOOK_SECRET in production.',
            id='agrisense.W007',
        ))
    if getattr(settings, 'AI_ENGINE', 'rules') in ('rules', 'rule-based', 'heuristic'):
        errors.append(Warning(
            'AI_ENGINE uses the demo rule-based heuristic; no trained plant-pathology model is active.',
            hint='Configure AI_ENGINE=tensorflow, AI_MODEL_PATH and AI_CLASS_MAP_PATH for real inference.',
            id='agrisense.W008',
        ))
    elif (getattr(settings, 'AI_ENGINE', '') in ('tensorflow', 'keras', 'tf')
          and not getattr(settings, 'AI_MODEL_PATH', '')):
        errors.append(Warning(
            'AI_ENGINE requests TensorFlow but AI_MODEL_PATH is empty.',
            hint='Mount a trained model artifact and set AI_MODEL_PATH.',
            id='agrisense.W009',
        ))
    return errors
