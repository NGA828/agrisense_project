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

ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS') or (['localhost', '127.0.0.1'] if DEBUG else ['*'])


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
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
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
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

MEDIA_URL = 'media/'
MEDIA_ROOT = BASE_DIR / 'media'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# DRF Throttle rates (environment overridable for load tests)
THROTTLE_AUTH_RATE = os.getenv('THROTTLE_AUTH_RATE', '10/min')
THROTTLE_AI_RATE = os.getenv('THROTTLE_AI_RATE', '30/min')
THROTTLE_ANON_RATE = os.getenv('THROTTLE_ANON_RATE', '60/min')
THROTTLE_USER_RATE = os.getenv('THROTTLE_USER_RATE', '120/min')

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
    },
    'DEFAULT_FILTER_BACKENDS': (
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ),
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

# Media files configuration
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# File upload settings
FILE_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']

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
