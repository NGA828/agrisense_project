from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


class HealthCheckTests(APITestCase):
    @override_settings(OPENROUTER_API_KEY='test-openrouter-key')
    def test_configured_openrouter_returns_ready(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Critical deps are up; optional ones (push/payments) may be degraded.
        self.assertIn(resp.data['status'], ('ok', 'degraded'))
        self.assertEqual(resp.data['checks']['database']['status'], 'ok')
        self.assertEqual(resp.data['checks']['cache']['status'], 'ok')
        ai = resp.data['checks']['ai_engine']
        self.assertEqual(ai['status'], 'ok')
        self.assertEqual(ai['engine'], 'openrouter-vision')
        self.assertTrue(ai['trained_model'])
        self.assertTrue(ai['remote'])

    def test_health_is_public_and_reports_missing_openrouter_key(self):
        resp = self.client.get(reverse('health_check'))
        # No authentication challenge: readiness correctly fails because the
        # default OpenRouter engine has no key in the test environment.
        self.assertEqual(resp.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(resp.data['checks']['ai_engine']['status'], 'error')

    @override_settings(
        AI_ENGINE='rules',
        AI_REQUIRE_TRAINED_MODEL=False,
    )
    def test_explicit_demo_rule_engine_is_degraded(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['checks']['ai_engine']['status'], 'degraded')
        self.assertFalse(resp.data['checks']['ai_engine']['trained_model'])

    @override_settings(
        AI_ENGINE='tensorflow',
        AI_MODEL_PATH='',
        AI_CLASS_MAP_PATH='',
        AI_ALLOW_RULE_FALLBACK=False,
    )
    def test_requested_but_missing_local_model_fails_readiness(self):
        resp = self.client.get(reverse('health_check'))
        self.assertEqual(resp.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(resp.data['checks']['ai_engine']['status'], 'error')
        self.assertFalse(resp.data['checks']['ai_engine']['trained_model'])


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
        self.assertIn('agrisense.W010', ids)  # OpenRouter key unset
