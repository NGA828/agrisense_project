from datetime import timedelta

from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from sensors.models import SensorDevice, SensorReading
from sensors.services import compute_irrigation_advice, monitor_and_alert_irrigation


def make_user(username='farmer1'):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name='F', last_name='T', email=f'{username}@t.com',
        phone_number='+237600000000', role='farmer',
    )


def make_sensor(owner, device_id='SENS-1', moisture=None, crop='Tomato', **kw):
    device = SensorDevice.objects.create(
        owner=owner, device_id=device_id, sensor_type='soil_moisture',
        latitude=3.848, longitude=11.5021, crop=crop, **kw)
    if moisture is not None:
        SensorReading.objects.create(device=device, value=moisture,
                                     recorded_at=timezone.now())
    return device


class IrrigationAdviceTests(APITestCase):
    def test_dry_soil_no_rain_irrigate_now(self):
        # No weather data -> rain probability 0.
        device = make_sensor(make_user(), moisture=20)
        result = compute_irrigation_advice(device, crop='Tomato')
        self.assertEqual(result['recommendation'], 'irrigate_now')
        self.assertIn('irrigate', result['advice'].lower())

    def test_dry_soil_with_rain_delays(self):
        from weather.models import WeatherData
        WeatherData.objects.create(location_name='Y', latitude=3.8, longitude=11.5,
                                   temperature=28, humidity=80, wind_speed=5,
                                   condition='Rain', rain_probability=80)
        device = make_sensor(make_user(), moisture=20)
        result = compute_irrigation_advice(device, crop='Tomato')
        self.assertEqual(result['recommendation'], 'delay_rain')

    def test_adequate_soil(self):
        device = make_sensor(make_user(), moisture=70)
        result = compute_irrigation_advice(device, crop='Tomato')
        self.assertEqual(result['recommendation'], 'adequate')

    def test_no_data_when_no_reading(self):
        device = make_sensor(make_user())  # no reading
        result = compute_irrigation_advice(device, crop='Tomato')
        self.assertEqual(result['recommendation'], 'no_data')

    def test_irrigation_endpoint(self):
        user = make_user()
        device = make_sensor(user, moisture=20)
        self.client.force_authenticate(user=user)
        resp = self.client.get(reverse('sensor-irrigation-advice', args=[device.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['recommendation'], 'irrigate_now')

    def test_monitor_alert_throttle(self):
        user = make_user()
        device = make_sensor(user, moisture=15)
        # First run alerts.
        alerted = monitor_and_alert_irrigation(save=True)
        self.assertIn(device.device_id, alerted)
        self.assertEqual(user.notifications.count(), 1)
        # Second immediate run is throttled.
        alerted2 = monitor_and_alert_irrigation(save=True)
        self.assertNotIn(device.device_id, alerted2)
        self.assertEqual(user.notifications.count(), 1)
        # After the throttle window it alerts again.
        device.last_irrigation_alert_at = timezone.now() - timedelta(hours=7)
        device.save(update_fields=['last_irrigation_alert_at'])
        alerted3 = monitor_and_alert_irrigation(save=True)
        self.assertIn(device.device_id, alerted3)
        self.assertEqual(user.notifications.count(), 2)
