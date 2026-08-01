from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


class HealthCheckTests(APITestCase):
    def test_health_returns_ok(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Critical deps are up; optional ones (push/payments) may be degraded.
        self.assertIn(resp.data['status'], ('ok', 'degraded'))
        self.assertEqual(resp.data['checks']['database']['status'], 'ok')
        self.assertEqual(resp.data['checks']['cache']['status'], 'ok')
        self.assertEqual(resp.data['checks']['ai_engine']['status'], 'ok')

    def test_health_is_public(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)


class SecurityChecksTests(TestCase):
    """Custom production-security checks fire warnings on insecure defaults."""

    def test_insecure_defaults_raise_warnings(self):
        from django.core.checks import run_checks
        messages = run_checks()
        ids = {m.id for m in messages}
        # In default config these warnings fire (DEBUG is forced off by the test
        # runner, so W001 is not asserted here).
        self.assertIn('agrisense.W002', ids)  # insecure SECRET_KEY
        self.assertIn('agrisense.W007', ids)  # dev webhook secret
        self.assertIn('agrisense.W005', ids)  # weather key unset
