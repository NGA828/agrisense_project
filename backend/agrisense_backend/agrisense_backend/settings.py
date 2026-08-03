"""
Django settings for agrisense_backend project.

For more information on this file, see
https://docs.djangoproject.com/en/4.2/topics/settings/

For the full list of settings and their values, see
https://docs.djangoproject.com/en/4.2/ref/settings/
"""
# Use PyMySQL as a drop-in replacement for mysqlclient (no C extension needed)
import pymysql
pymysql.install_as_MySQLdb()

import os
import socket
from pathlib import Path
from datetime import timedelta

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent


# Load environment variables from .env (development convenience; does not
# override real process environment variables).
try:
    from dotenv import load_dotenv
    load_dotenv(BASE_DIR / '.env')
except ImportError:  # python-dotenv is optional in dev
    pass


def _env_bool(name, default=False):
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in ('1', 'true', 'yes', 'on')


def _env_list(name, default=None):
    value = os.getenv(name)
    if not value:
        return default or []
    return [item.strip() for item in value.split(',') if item.strip()]


# SECURITY WARNING: keep the secret key used in production secret!
SECRET_KEY = os.getenv('DJANGO_SECRET_KEY', 'm(l2!fbpl&%gy9yx47k=a)2h@ie@%fm%t603=0u$ww@(kvz2gp')

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = _env_bool('DEBUG', True)

ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS') or ['localhost', '127.0.0.1']
if DEBUG:
    try:
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
        if local_ip not in ALLOWED_HOSTS:
            ALLOWED_HOSTS.append(local_ip)
    except Exception:
        pass


# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    
    # Third party
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'channels',
    'django_filters',

    # Local apps
    'users',
    'diagnosis',
    'products',
    'chat',
    'payments',
    'weather',
    'ai_engine',
    'announcements',
    'system',
    'ledger',
    'realtime',
    'auditlog',
    'sensors',
    'ussd',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'agrisense_backend.middleware.RequestIDMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.locale.LocaleMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'agrisense_backend.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'agrisense_backend.wsgi.application'

# Database - MySQL/MariaDB 10.6+ (default). For local smoke tests without a
# MySQL server, run with:
#   DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3
# All values can be overridden via environment variables (see .env.example).
_DB_ENGINE = os.getenv('DB_ENGINE', 'django.db.backends.mysql')
_DB_OPTIONS = {
    'init_command': "SET sql_mode='STRICT_TRANS_TABLES'",
    'charset': 'utf8mb4',
} if _DB_ENGINE.endswith('mysql') else {}

DATABASES = {
    'default': {
        'ENGINE': _DB_ENGINE,
        'NAME': os.getenv('DB_NAME', 'agrisense_db'),
        'USER': os.getenv('DB_USER', 'agrisense_user'),
        'PASSWORD': os.getenv('DB_PASSWORD', 'password123'),
        'HOST': os.getenv('DB_HOST', 'localhost'),
        'PORT': os.getenv('DB_PORT', '3306'),
        'OPTIONS': _DB_OPTIONS,
    }
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

LANGUAGE_CODE = 'en-us'
LANGUAGES = [
    ('en', 'English'),
    ('fr', 'Français'),
]
LOCALE_PATHS = [BASE_DIR / 'locale']
TIME_ZONE = 'UTC'
USE_I18N = True
USE_L10N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

# Media files configuration
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# DRF Throttle rates (environment overridable for load tests)
THROTTLE_AUTH_RATE = os.getenv('THROTTLE_AUTH_RATE', '10/min')
THROTTLE_AI_RATE = os.getenv('THROTTLE_AI_RATE', '30/min')
THROTTLE_ANON_RATE = os.getenv('THROTTLE_ANON_RATE', '60/min')
THROTTLE_USER_RATE = os.getenv('THROTTLE_USER_RATE', '120/min')
THROTTLE_WEATHER_RATE = os.getenv('THROTTLE_WEATHER_RATE', '30/min')
THROTTLE_USSD_RATE = os.getenv('THROTTLE_USSD_RATE', '20/min')

# REST Framework Configuration
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 20,
    'DEFAULT_THROTTLE_CLASSES': (
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
        'rest_framework.throttling.ScopedRateThrottle',
    ),
    'DEFAULT_THROTTLE_RATES': {
        'anon': THROTTLE_ANON_RATE,
        'user': THROTTLE_USER_RATE,
        'auth': THROTTLE_AUTH_RATE,
        'ai': THROTTLE_AI_RATE,
        'weather': THROTTLE_WEATHER_RATE,
        'ussd': THROTTLE_USSD_RATE,
    },
    'DEFAULT_FILTER_BACKENDS': (
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ),
    # Return relative media paths (e.g. "profile_photos/abc.png") instead of
    # absolute URLs built from the request's Host header. Clients (Flutter)
    # resolve them against their own configured API base URL, so images keep
    # working from emulators, physical devices and behind reverse proxies
    # whose Host header differs from the client-reachable host.
    'UPLOADED_FILES_USE_URL': False,
}

# JWT Settings
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=int(os.getenv('JWT_ACCESS_MINUTES', '30'))),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=int(os.getenv('JWT_REFRESH_DAYS', '7'))),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
}

# CORS Settings (for Flutter) - restrict via CORS_ALLOWED_ORIGINS in production.
# In development the Flutter web / mobile debuggers use arbitrary origins.
if _env_bool('CORS_ALLOW_ALL', DEBUG):
    CORS_ALLOW_ALL_ORIGINS = True
else:
    CORS_ALLOW_ALL_ORIGINS = False
    CORS_ALLOWED_ORIGINS = _env_list(
        'CORS_ALLOWED_ORIGINS',
        ['http://localhost', 'http://127.0.0.1'],
    )
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
]

# Custom User Model
AUTH_USER_MODEL = 'users.User'

# ASGI for WebSockets (Chat)
ASGI_APPLICATION = 'agrisense_backend.asgi.application'

# Channel Layers.
# Development: in-memory. Production: redis (set CHANNEL_LAYER_BACKEND=redis
# and CHANNEL_LAYER_REDIS_URL).
if os.getenv('CHANNEL_LAYER_BACKEND', 'memory') == 'redis':
    CHANNEL_LAYERS = {
        'default': {
            'BACKEND': 'channels_redis.core.RedisChannelLayer',
            'CONFIG': {
                'hosts': [os.getenv('CHANNEL_LAYER_REDIS_URL', 'redis://127.0.0.1:6379/0')],
            },
        },
    }
else:
    CHANNEL_LAYERS = {
        'default': {
            'BACKEND': 'channels.layers.InMemoryChannelLayer',
        },
    }

# File upload settings
FILE_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']

# ── Order / payment / settlement configuration (Phase A — money-flow) ──
# How long a freshly placed (unpaid) order keeps its stock reserved before the
# reconciler command releases it. The farmer can retry payment within this
# window; after it lapses the order is auto-cancelled and stock is freed.
ORDER_RESERVATION_MINUTES = int(os.getenv('ORDER_RESERVATION_MINUTES', '30'))

# Platform commission on a fulfilled marketplace order (0.0 = none). Applied
# at settlement (order delivered): the dealer is credited (total - commission)
# and the platform fee account is credited the commission.
PLATFORM_COMMISSION_RATE = float(os.getenv('PLATFORM_COMMISSION_RATE', '0.0'))

# Shared secret used to HMAC-sign payment webhook callbacks from real mobile
# money providers. In production this must be a long random value known to the
# provider and never shipped in source.
PAYMENT_WEBHOOK_SECRET = os.getenv('PAYMENT_WEBHOOK_SECRET', 'dev-webhook-secret')

# ── Realtime / push (Phase B) ───────────────────────────────────────────
# Push provider: 'noop' (default) | 'fcm'. Real pushes require FCM credentials.
PUSH_PROVIDER = os.getenv('PUSH_PROVIDER', 'noop')
FCM_CREDENTIALS_PATH = os.getenv('FCM_CREDENTIALS_PATH', '')

# ── Weather (Phase C) ───────────────────────────────────────────────────
OPENWEATHER_API_KEY = os.getenv('OPENWEATHER_API_KEY', '')
# How long a weather response is cached (seconds) — avoids hammering the
# external provider and unbounded DB writes on repeated requests.
WEATHER_CACHE_TTL = int(os.getenv('WEATHER_CACHE_TTL', '900'))
# Prune weather rows older than this many days (see weather.tasks + command).
WEATHER_RETENTION_DAYS = int(os.getenv('WEATHER_RETENTION_DAYS', '30'))

# ── Caching (Phase C) ───────────────────────────────────────────────────
# redis in production, locmem in dev/test so no broker/server is required.
CACHE_BACKEND = os.getenv('CACHE_BACKEND', 'locmem')
if CACHE_BACKEND == 'redis':
    CACHES = {
        'default': {
            'BACKEND': 'django_redis.cache.RedisCache',
            'LOCATION': os.getenv('REDIS_CACHE_URL', 'redis://127.0.0.1:6379/2'),
            'OPTIONS': {'CLIENT_CLASS': 'django_redis.client.DefaultClient'},
            'KEY_PREFIX': 'agrisense',
            'TIMEOUT': 300,
        }
    }
else:
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
            'LOCATION': 'agrisense-default',
        }
    }

# ── Celery (Phase C) ────────────────────────────────────────────────────
# Broker defaults to the Redis used for the channel layer when that is Redis;
# otherwise tasks run eagerly (dev/tests, no broker required).
CELERY_BROKER_URL = os.getenv('CELERY_BROKER_URL', '')
CELERY_RESULT_BACKEND = os.getenv('CELERY_RESULT_BACKEND', '')
CELERY_TASK_ALWAYS_EAGER = not bool(CELERY_BROKER_URL)
CELERY_TASK_EAGER_PROPAGATES = True
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE
CELERY_BEAT_SCHEDULE = {
    'release-stale-reservations': {
        'task': 'products.tasks.release_stale_reservations_task',
        'schedule': 300.0,  # every 5 minutes
    },
    'expire-premiums': {
        'task': 'users.tasks.expire_premiums_task',
        'schedule': 86400.0,  # daily
    },
    'reconcile-payments': {
        'task': 'payments.tasks.reconcile_payments_task',
        'schedule': 900.0,  # every 15 minutes
    },
    'cleanup-weather': {
        'task': 'weather.tasks.cleanup_weather_task',
        'schedule': 86400.0,  # daily
    },
    'monitor-irrigation': {
        'task': 'sensors.tasks.monitor_irrigation_task',
        'schedule': 1800.0,  # every 30 minutes
    },
    'detect-outbreaks': {
        'task': 'diagnosis.tasks.detect_outbreak_alerts_task',
        'schedule': 3600.0,  # hourly
    },
}

# ── Plant-pathology inference ────────────────────────────────────────────
# OpenRouter vision is primary. The remote model may only select diseases from
# the admin-reviewed Disease rows supplied in its strict response schema;
# treatments are always resolved locally. TensorFlow remains an offline option.
AI_ENGINE = os.getenv('AI_ENGINE', 'openrouter').strip().lower()
OPENROUTER_API_KEY = os.getenv('OPENROUTER_API_KEY', '').strip()
OPENROUTER_MODEL = os.getenv(
    'OPENROUTER_MODEL', 'nex-agi/nex-n2-pro:free').strip()
OPENROUTER_BASE_URL = os.getenv(
    'OPENROUTER_BASE_URL', 'https://openrouter.ai/api/v1').strip()
OPENROUTER_TIMEOUT_SECONDS = float(
    os.getenv('OPENROUTER_TIMEOUT_SECONDS', '60'))
OPENROUTER_IMAGE_MAX_DIMENSION = int(
    os.getenv('OPENROUTER_IMAGE_MAX_DIMENSION', '1280'))
OPENROUTER_IMAGE_QUALITY = int(os.getenv('OPENROUTER_IMAGE_QUALITY', '88'))
OPENROUTER_CONFIDENCE_THRESHOLD = float(
    os.getenv('OPENROUTER_CONFIDENCE_THRESHOLD', '70'))
# A general vision model's self-reported certainty is not calibrated pathology
# confidence, so never display more than this cap.
OPENROUTER_MAX_CONFIDENCE = float(
    os.getenv('OPENROUTER_MAX_CONFIDENCE', '95'))
OPENROUTER_APP_URL = os.getenv('OPENROUTER_APP_URL', '').strip()
OPENROUTER_APP_TITLE = os.getenv('OPENROUTER_APP_TITLE', 'AgriSense AI').strip()

# Optional local TensorFlow engine settings.
AI_MODEL_PATH = os.getenv('AI_MODEL_PATH', '').strip()
AI_CLASS_MAP_PATH = os.getenv('AI_CLASS_MAP_PATH', '').strip()
AI_MODEL_VERSION = os.getenv('AI_MODEL_VERSION', '').strip()
AI_MODEL_INPUT_SIZE = os.getenv('AI_MODEL_INPUT_SIZE', '224x224').strip()
AI_MAX_IMAGE_PIXELS = int(os.getenv('AI_MAX_IMAGE_PIXELS', '25000000'))
AI_MODEL_NORMALIZATION = os.getenv('AI_MODEL_NORMALIZATION', 'zero_one').strip().lower()
AI_MODEL_OUTPUT_NAME = os.getenv('AI_MODEL_OUTPUT_NAME', '').strip()
AI_MODEL_CONFIDENCE_THRESHOLD = float(
    os.getenv('AI_MODEL_CONFIDENCE_THRESHOLD', '65.0'))
AI_MODEL_TEMPERATURE = float(os.getenv('AI_MODEL_TEMPERATURE', '1.0'))
AI_STRICT_CLASS_COUNT = _env_bool('AI_STRICT_CLASS_COUNT', True)
# Require a real model by default. A developer who intentionally wants the
# labelled heuristic must set AI_ENGINE=rules and AI_REQUIRE_TRAINED_MODEL=false.
AI_REQUIRE_TRAINED_MODEL = _env_bool('AI_REQUIRE_TRAINED_MODEL', True)
# Never silently disguise a missing/broken model as trained AI. Enable this
# only for demos that intentionally accept the heuristic fallback.
AI_ALLOW_RULE_FALLBACK = _env_bool('AI_ALLOW_RULE_FALLBACK', False)

# Calibration + honesty thresholds used by the demo rule-based engine.
AI_TEMPERATURE = float(os.getenv('AI_TEMPERATURE', '1.6'))
AI_LOW_CONFIDENCE_THRESHOLD = float(os.getenv('AI_LOW_CONFIDENCE_THRESHOLD', '80.0'))

# ── Precision irrigation (Phase F, innovation #2) ───────────────────────
# How often a given sensor is re-alerted for irrigation (hours).
IRRIGATION_ALERT_THROTTLE_HOURS = int(os.getenv('IRRIGATION_ALERT_THROTTLE_HOURS', '6'))

# ── Predictive outbreak alerting (Phase F, innovation #4) ───────────────
OUTBREAK_RECENT_DAYS = int(os.getenv('OUTBREAK_RECENT_DAYS', '7'))
OUTBREAK_MIN_CLUSTER_SIZE = int(os.getenv('OUTBREAK_MIN_CLUSTER_SIZE', '3'))
OUTBREAK_GROWTH_FACTOR = float(os.getenv('OUTBREAK_GROWTH_FACTOR', '2.0'))
OUTBREAK_COOLDOWN_HOURS = int(os.getenv('OUTBREAK_COOLDOWN_HOURS', '24'))
OUTBREAK_NOTIFY_RADIUS_DEG = float(os.getenv('OUTBREAK_NOTIFY_RADIUS_DEG', '0.8'))

# ── OTP / SMS (Phase D) ─────────────────────────────────────────────────# Phone-based verification for registration & password reset.
SMS_PROVIDER = os.getenv('SMS_PROVIDER', 'noop')  # noop | africastalking | twilio
OTP_LENGTH = int(os.getenv('OTP_LENGTH', '6'))
OTP_TTL_SECONDS = int(os.getenv('OTP_TTL_SECONDS', '300'))
OTP_MAX_ATTEMPTS = int(os.getenv('OTP_MAX_ATTEMPTS', '5'))
# When True, registration / password reset require a verified OTP first.
OTP_REQUIRED_FOR_REGISTRATION = _env_bool('OTP_REQUIRED_FOR_REGISTRATION', False)
OTP_REQUIRED_FOR_PASSWORD_RESET = _env_bool('OTP_REQUIRED_FOR_PASSWORD_RESET', False)

# ── Logging (Phase C) ───────────────────────────────────────────────────
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'json': {
            '()': 'agrisense_backend.logging.JsonFormatter',
        },
        'verbose': {
            'format': '{levelname} {asctime} {name} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'json' if _env_bool('JSON_LOGS', not DEBUG) else 'verbose',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': os.getenv('LOG_LEVEL', 'INFO'),
    },
    'loggers': {
        'django.request': {'level': 'WARNING', 'handlers': ['console'], 'propagate': False},
        'django.security': {'level': 'WARNING', 'handlers': ['console'], 'propagate': False},
        'agrisense': {'level': 'INFO', 'handlers': ['console'], 'propagate': False},
    },
}

# ── Sentry (optional error tracking) ────────────────────────────────────
SENTRY_DSN = os.getenv('SENTRY_DSN', '')
if SENTRY_DSN:
    try:
        import sentry_sdk
        from sentry_sdk.integrations.django import DjangoIntegration

        sentry_sdk.init(
            dsn=SENTRY_DSN,
            integrations=[DjangoIntegration()],
            traces_sample_rate=float(os.getenv('SENTRY_TRACES_SAMPLE_RATE', '0.1')),
            environment=os.getenv('SENTRY_ENVIRONMENT', 'production'),
        )
    except Exception:
        pass  # Sentry is optional; never block startup on it.

# Production security defaults (turned OFF in DEBUG so local dev keeps working)
if not DEBUG:
    SECURE_SSL_REDIRECT = _env_bool('SECURE_SSL_REDIRECT', True)
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = int(os.getenv('SECURE_HSTS_SECONDS', '31536000'))
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = True
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
    X_FRAME_OPTIONS = 'DENY'
