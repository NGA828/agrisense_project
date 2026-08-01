import logging

import requests
from django.conf import settings
from django.core.cache import cache
from rest_framework import status, permissions
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from .models import WeatherData

logger = logging.getLogger('agrisense.weather')

# Farming advice based on weather conditions
FARMING_ADVICE = {
    'Clear': 'Good day for spraying pesticides. Apply early morning or late afternoon.',
    'Cloudy': 'Moderate conditions for field work. Good time for planting seedlings.',
    'Rain': 'Avoid spraying chemicals. Check field drainage. Protect seedlings.',
    'Thunderstorm': 'Stay indoors. Ensure drainage systems are clear. Protect livestock.',
    'Drizzle': 'Light rain - good for newly planted crops. Avoid heavy field work.',
    'Mist': 'High humidity - monitor for fungal diseases. Apply preventive fungicide.',
}


def get_farming_advice(condition, humidity, rain_chance):
    advice = []

    if condition in FARMING_ADVICE:
        advice.append(FARMING_ADVICE[condition])

    if humidity > 80:
        advice.append('High humidity detected. Watch for fungal diseases like late blight.')
    elif humidity < 30:
        advice.append('Low humidity. Ensure adequate irrigation for your crops.')

    if rain_chance and rain_chance > 50:
        advice.append('Rain expected. Complete any spraying before rain arrives.')
        advice.append('Ensure field drainage is working properly.')

    if not advice:
        advice.append('Good conditions for general farm work and crop maintenance.')

    return ' | '.join(advice)


def _cache_key(lat, lon):
    return f'weather:{round(lat, 4)}:{round(lon, 4)}'


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
@throttle_classes([ScopedRateThrottle])
def get_weather(request):
    """Live weather + farming advice for a coordinate (authenticated).

    Hardened (Phase C):
    * requires authentication and is rate-limited (``weather`` throttle scope),
    * responses are cached for ``WEATHER_CACHE_TTL`` seconds keyed by coordinate,
      so repeat requests neither hit OpenWeatherMap nor grow the DB unboundedly,
    * a graceful offline fallback is retained when no API key / on failure.
    """
    lat = float(request.data.get('latitude', 3.8480))  # Default: Yaoundé
    lon = float(request.data.get('longitude', 11.5021))
    location_name = request.data.get('location', 'Yaoundé, Cameroon')

    # Serve from cache when fresh.
    key = _cache_key(lat, lon)
    cached = cache.get(key)
    if cached is not None:
        cached = dict(cached)
        cached['cached'] = True
        return Response(cached)

    api_key = getattr(settings, 'OPENWEATHER_API_KEY', '')
    result = None
    if api_key:
        result = _fetch_live(api_key, lat, lon, location_name)

    if result is None:
        result = _default_payload(lat, lon, location_name)

    # Cache the assembled payload (TTL caps repeat external calls + DB writes).
    cache.set(key, result, timeout=getattr(settings, 'WEATHER_CACHE_TTL', 900))
    return Response(result)


def _fetch_live(api_key, lat, lon, location_name):
    try:
        current_url = (f'https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}'
                       f'&appid={api_key}&units=metric')
        current = requests.get(current_url, timeout=10)
        if current.status_code != 200:
            return None
        data = current.json()
        condition = data['weather'][0]['main']
        humidity = data['main']['humidity']
        temp = data['main']['temp']
        feels_like = data['main']['feels_like']
        wind_speed = data['wind']['speed'] * 3.6  # m/s to km/h

        forecast_data = []
        forecast_url = (f'https://api.openweathermap.org/data/2.5/forecast?lat={lat}&lon={lon}'
                        f'&appid={api_key}&units=metric')
        forecast_resp = requests.get(forecast_url, timeout=10)
        if forecast_resp.status_code == 200:
            for item in forecast_resp.json().get('list', [])[:7]:
                forecast_data.append({
                    'dt': item['dt'],
                    'temp': item['main']['temp'],
                    'temp_min': item['main']['temp_min'],
                    'temp_max': item['main']['temp_max'],
                    'condition': item['weather'][0]['main'],
                    'humidity': item['main']['humidity'],
                    'rain_chance': item.get('pop', 0) * 100,
                })

        advice = get_farming_advice(condition, humidity, data.get('pop', 0) * 100)

        result = {
            'temperature': temp,
            'feels_like': feels_like,
            'humidity': humidity,
            'wind_speed': wind_speed,
            'condition': condition,
            'description': data['weather'][0].get('description', ''),
            'location': location_name,
            'latitude': lat,
            'longitude': lon,
            'forecast': forecast_data,
            'farming_advice': advice,
            'source': 'openweathermap',
        }

        # Persist a sample for analytics. A later cleanup task prunes old rows.
        try:
            WeatherData.objects.create(
                location_name=location_name, latitude=lat, longitude=lon,
                temperature=temp, feels_like=feels_like, humidity=humidity,
                wind_speed=wind_speed, condition=condition,
                rain_probability=data.get('pop', 0) * 100,
                description=data['weather'][0].get('description', ''),
                farming_advice=advice,
            )
        except Exception:
            logger.exception('Failed to persist weather sample')
        return result
    except Exception:
        logger.exception('OpenWeatherMap request failed')
        return None


def _default_payload(lat, lon, location_name):
    """Graceful offline/fallback payload (used when no key or on failure)."""
    advice = get_farming_advice('Partly Cloudy', 72, 45)
    return {
        'temperature': 28,
        'feels_like': 31,
        'humidity': 72,
        'wind_speed': 10,
        'condition': 'Partly Cloudy',
        'description': 'scattered clouds',
        'location': location_name,
        'latitude': lat,
        'longitude': lon,
        'forecast': [
            {'temp': 27, 'temp_min': 21, 'temp_max': 27, 'condition': 'Rain', 'humidity': 75, 'rain_chance': 60},
            {'temp': 26, 'temp_min': 20, 'temp_max': 26, 'condition': 'Thunderstorm', 'humidity': 80, 'rain_chance': 80},
            {'temp': 27, 'temp_min': 21, 'temp_max': 27, 'condition': 'Rain', 'humidity': 73, 'rain_chance': 55},
            {'temp': 28, 'temp_min': 21, 'temp_max': 28, 'condition': 'Cloudy', 'humidity': 68, 'rain_chance': 30},
            {'temp': 29, 'temp_min': 22, 'temp_max': 29, 'condition': 'Clear', 'humidity': 60, 'rain_chance': 10},
            {'temp': 28, 'temp_min': 21, 'temp_max': 28, 'condition': 'Cloudy', 'humidity': 65, 'rain_chance': 25},
            {'temp': 27, 'temp_min': 20, 'temp_max': 27, 'condition': 'Rain', 'humidity': 74, 'rain_chance': 50},
        ],
        'farming_advice': advice,
        'source': 'default',
    }
