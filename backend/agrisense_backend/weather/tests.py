from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from .views import get_farming_advice


def make_user(username='farmer1'):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name='Farmer', last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role='farmer',
    )


class FarmingAdviceTests(TestCase):
    def test_rain_advice(self):
        advice = get_farming_advice('Rain', 85, 90)
        self.assertIn('Avoid spraying chemicals', advice)
        self.assertIn('High humidity', advice)

    def test_clear_advice(self):
        advice = get_farming_advice('Clear', 20, 5)
        self.assertIn('Good day for spraying', advice)
        self.assertIn('Low humidity', advice)

    def test_generic_advice(self):
        advice = get_farming_advice('Fog', 50, 10)
        self.assertIn('Good conditions for general farm work', advice)


class WeatherEndpointTests(APITestCase):
    def setUp(self):
        self.user = make_user()

    def test_requires_authentication(self):
        """Phase C hardening: weather is now authenticated + rate-limited."""
        resp = self.client.post(reverse('get_weather'), {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_authenticated_returns_fallback(self):
        self.client.force_authenticate(user=self.user)
        resp = self.client.post(reverse('get_weather'),
                                {'latitude': 3.8480, 'longitude': 11.5021},
                                format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['source'], 'default')

    def test_response_is_cached(self):
        self.client.force_authenticate(user=self.user)
        resp1 = self.client.post(reverse('get_weather'),
                                 {'latitude': 3.8480, 'longitude': 11.5021},
                                 format='json')
        resp2 = self.client.post(reverse('get_weather'),
                                 {'latitude': 3.8480, 'longitude': 11.5021},
                                 format='json')
        self.assertEqual(resp1.status_code, status.HTTP_200_OK)
        self.assertEqual(resp2.status_code, status.HTTP_200_OK)
        self.assertTrue(resp2.data.get('cached', False))


class WeatherCleanupTaskTests(TestCase):
    def test_cleanup_prunes_old_rows(self):
        from datetime import timedelta
        from django.utils import timezone
        from .models import WeatherData
        from .tasks import cleanup_weather_task

        old = WeatherData.objects.create(
            location_name='Old', latitude=1, longitude=1, temperature=20,
            humidity=50, wind_speed=5, condition='Clear',
        )
        old.fetched_at = timezone.now() - timedelta(days=90)
        old.save(update_fields=['fetched_at'])

        new = WeatherData.objects.create(
            location_name='New', latitude=2, longitude=2, temperature=21,
            humidity=50, wind_speed=5, condition='Clear',
        )
        deleted = cleanup_weather_task.apply(kwargs={'retention_days': 30}).result
        self.assertEqual(deleted, 1)
        self.assertFalse(WeatherData.objects.filter(pk=old.pk).exists())
        self.assertTrue(WeatherData.objects.filter(pk=new.pk).exists())
