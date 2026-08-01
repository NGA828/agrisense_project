"""
Precision irrigation & crop advisory (Phase F — innovation #2).

Combines live soil-moisture readings from ``sensors.SensorReading`` with the
latest local weather (rain probability) to produce an actionable irrigation
recommendation per crop. Soil moisture is compared against crop-specific
thresholds, then the weather forecast adjusts the recommendation: if rain is
expected soon, irrigation is delayed even when the soil is dry.

Also provides the background-monitor logic (used by the Celery task) that pushes
an irrigation alert to the owner only when it is genuinely time to irrigate and
not too soon after the last alert.
"""

from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from .models import SensorReading

# Soil-moisture thresholds (% volumetric) per crop. `dry` is the point below
# which the crop needs water; `adequate` is the upper comfort bound.
CROP_IRRIGATION_THRESHOLDS = {
    'Tomato': {'dry': 40, 'adequate': 60, 'label': 'Tomato'},
    'Maize': {'dry': 45, 'adequate': 65, 'label': 'Maize'},
    'Cassava': {'dry': 35, 'adequate': 55, 'label': 'Cassava'},
    'Pepper': {'dry': 40, 'adequate': 60, 'label': 'Pepper'},
    'Cocoa': {'dry': 45, 'adequate': 65, 'label': 'Cocoa'},
}
DEFAULT_THRESHOLDS = {'dry': 35, 'adequate': 60, 'label': 'General'}


def _thresholds(crop):
    if not crop:
        return DEFAULT_THRESHOLDS
    return CROP_IRRIGATION_THRESHOLDS.get(crop, DEFAULT_THRESHOLDS)


def _nearest_rain_probability(lat, lon):
    """Best-effort rain probability from the most recent weather sample.

    Falls back to 0 when no weather data is available (never blocks the
    irrigation logic).
    """
    try:
        from weather.models import WeatherData
        sample = (
            WeatherData.objects
            .order_by('-fetched_at')
            .first()
        )
        if sample is None:
            return 0
        # Prefer a sample close to the sensor; otherwise use the most recent.
        if lat is not None and lon is not None:
            nearby = (
                WeatherData.objects
                .filter(latitude__range=(lat - 2.0, lat + 2.0),
                        longitude__range=(lon - 2.0, lon + 2.0))
                .order_by('-fetched_at')
                .first()
            )
            if nearby is not None:
                return int(nearby.rain_probability or 0)
        return int(sample.rain_probability or 0)
    except Exception:
        return 0


def _recent_reading(device):
    """Latest reading + a rough trend over the last few readings."""
    latest = device.readings.order_by('-recorded_at').first()
    trend = 0.0
    if latest is not None:
        recent = list(
            device.readings.order_by('-recorded_at')[:4].values_list('value', flat=True))
        if len(recent) >= 2:
            # Sign: positive means moisture is rising, negative means drying.
            trend = round(recent[0] - recent[-1], 1)
    return latest, trend


def compute_irrigation_advice(device, crop=None):
    """Compute an irrigation recommendation for a soil-moisture sensor.

    Returns a dict:
        recommendation: 'irrigate_now' | 'delay_rain' | 'monitor' | 'adequate' | 'no_data'
        advice:         human-readable guidance
        moisture, threshold, rain_probability, trend, crop
    """
    if device.sensor_type != 'soil_moisture':
        return {
            'recommendation': 'not_applicable',
            'advice': 'Irrigation advice requires a soil-moisture sensor.',
            'moisture': None, 'threshold': None, 'rain_probability': None,
            'trend': None, 'crop': crop,
        }

    latest, trend = _recent_reading(device)
    if latest is None:
        return {
            'recommendation': 'no_data',
            'advice': 'No soil-moisture reading yet. Once readings arrive, '
                      'irrigation advice will appear here.',
            'moisture': None, 'threshold': None, 'rain_probability': None,
            'trend': None, 'crop': crop,
        }

    moisture = latest.value
    thresholds = _thresholds(crop)
    rain = _nearest_rain_probability(device.latitude, device.longitude)

    dry, adequate = thresholds['dry'], thresholds['adequate']
    crop_label = thresholds['label']

    if moisture < dry:
        if rain >= 60:
            recommendation = 'delay_rain'
            advice = (f'{crop_label} soil is dry ({moisture:.0f}%) but '
                      f'{rain}% rain is expected — delay irrigation and let the '
                      'rain do the work.')
        else:
            recommendation = 'irrigate_now'
            advice = (f'{crop_label} soil is dry ({moisture:.0f}%) and no rain '
                      'is expected soon — irrigate now to protect the crop.')
    elif moisture < adequate:
        recommendation = 'monitor'
        advice = (f'{crop_label} soil moisture is moderate ({moisture:.0f}%). '
                  f'Monitor; irrigate if it drops below {dry}%.')
    else:
        recommendation = 'adequate'
        advice = (f'{crop_label} soil moisture is adequate ({moisture:.0f}%). '
                  'No irrigation needed.')

    # Surface a drying trend as an extra hint.
    if trend is not None and trend < -2.0 and recommendation in ('monitor', 'adequate'):
        advice += ' Moisture is falling quickly — check again soon.'

    return {
        'recommendation': recommendation,
        'advice': advice,
        'moisture': round(moisture, 1),
        'threshold': {'dry': dry, 'adequate': adequate},
        'rain_probability': rain,
        'trend': trend,
        'crop': crop_label,
    }


def monitor_and_alert_irrigation(save=True):
    """Scan active soil-moisture sensors and push an alert where irrigation is due.

    Throttles repeated alerts per device (``IRRIGATION_ALERT_THROTTLE_HOURS``).
    Returns a dict {device_id: recommendation} for sensors alerted.
    """
    from .models import SensorDevice
    from announcements.models import notify_user
    from realtime.services import send_to_user, send_push_notification

    throttle_hours = int(getattr(settings, 'IRRIGATION_ALERT_THROTTLE_HOURS', '6'))
    now = timezone.now()
    alerted = {}

    devices = SensorDevice.objects.filter(
        sensor_type='soil_moisture', is_active=True,
    ).select_related('owner')

    for device in devices:
        # Skip if we alerted this device too recently.
        if device.last_irrigation_alert_at is not None:
            if (now - device.last_irrigation_alert_at) < timedelta(hours=throttle_hours):
                continue

        result = compute_irrigation_advice(device, crop=device.crop)
        if result['recommendation'] != 'irrigate_now':
            continue

        title = 'Water your crops 💧'
        message = (f'{result["crop"]} soil on "{device.name or device.device_id}" '
                   f'is dry ({result["moisture"]:.0f}%) and no rain is expected — '
                   'irrigate now.')
        notify_user(device.owner, title, message, type='system',
                    reference_id=f'sensor:{device.id}')
        send_to_user(device.owner_id, 'irrigation_alert', device_id=device.id,
                     advice=result['advice'], moisture=result['moisture'])
        send_push_notification(device.owner, title, message,
                               data={'type': 'irrigation', 'device_id': device.id})

        if save:
            device.last_irrigation_alert_at = now
            device.save(update_fields=['last_irrigation_alert_at'])
        alerted[device.device_id] = result['recommendation']

    return alerted
