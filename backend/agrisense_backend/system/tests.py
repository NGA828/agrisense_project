from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


class HealthCheckTests(APITestCase):
    def test_health_returns_ok(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'ok')
        self.assertEqual(resp.data['checks']['database']['status'], 'ok')
        self.assertEqual(resp.data['checks']['ai_engine']['status'], 'ok')

    def test_health_is_public(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
