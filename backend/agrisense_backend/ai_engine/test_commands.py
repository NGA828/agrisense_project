import io
import json
from unittest.mock import MagicMock, Mock, patch

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase, override_settings

from .management.commands.check_ai_model import Command


def model(*, free=True, vision=True):
    return {'architecture': {'input_modalities': ['text', 'image'] if vision else ['text']},
            'supported_parameters': ['structured_outputs'],
            'pricing': {'prompt': '0' if free else '0.01', 'completion': '0' if free else '0.01'}}


@override_settings(AI_ENGINE='openrouter', OPENROUTER_MODEL='openrouter/free',
                   OPENROUTER_FALLBACK_MODELS=['openrouter/free'],
                   OPENROUTER_ALLOW_PAID_MODELS=False, OPENROUTER_API_KEY='private-test-key')
class CheckAIModelCommandTests(SimpleTestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.catalog = {'vendor/vision:free': model(), 'vendor/paid': model(free=False),
                        'vendor/text:free': model(vision=False)}
        self.catalog_patch = patch.object(Command, '_catalog', return_value=self.catalog)
        self.catalog_patch.start()
        self.addCleanup(self.catalog_patch.stop)
        self.endpoint_patch = patch.object(Command, '_endpoints', return_value=[{'provider_name': 'test'}])
        self.endpoints = self.endpoint_patch.start()
        self.addCleanup(self.endpoint_patch.stop)

    def test_free_router_checks_live_pool_not_its_own_nonexistent_endpoint(self):
        call_command('check_ai_model', '--json', stdout=self.output)
        results = json.loads(self.output.getvalue())
        self.assertEqual(len(results), 1, 'Duplicate fallback must be removed')
        self.assertTrue(results[0]['ok'])
        self.assertFalse(results[0]['inference_tested'])
        self.endpoints.assert_called_once_with('vendor/vision:free')

    def test_empty_endpoint_pool_fails_instead_of_recommending_dead_free_model(self):
        self.endpoints.return_value = []
        with self.assertRaises(CommandError):
            call_command('check_ai_model', '--json', stdout=self.output)
        self.assertFalse(json.loads(self.output.getvalue())[0]['ok'])

    def test_list_free_json_is_parseable_and_excludes_paid_text_only_models(self):
        call_command('check_ai_model', '--list-free', '--json', stdout=self.output)
        self.assertEqual([r['model'] for r in json.loads(self.output.getvalue())], ['vendor/vision:free'])

    @override_settings(OPENROUTER_FALLBACK_MODELS=['vendor/paid'])
    def test_configured_paid_fallback_is_a_configuration_error(self):
        with self.assertRaises(CommandError):
            call_command('check_ai_model', '--json', stdout=self.output)
        self.assertIn('free-only', self.output.getvalue())

    def test_auth_check_only_reads_key_and_keeps_json_and_credentials_private(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"data":{"is_free_tier":true}}'
        with patch('urllib.request.urlopen', return_value=response) as request:
            call_command('check_ai_model', '--check-auth', '--json', stdout=self.output)
        self.assertTrue(json.loads(self.output.getvalue())[0]['authentication_checked'])
        self.assertTrue(request.call_args.args[0].full_url.endswith('/key'))
        self.assertEqual(request.call_args.args[0].get_method(), 'GET')
        self.assertNotIn('private-test-key', self.output.getvalue())

    def test_error_in_auth_http_200_is_not_reported_as_success(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"error":{"message":"invalid key"}}'
        with patch('urllib.request.urlopen', return_value=response), self.assertRaises(CommandError):
            call_command('check_ai_model', '--check-auth', stdout=self.output)
        self.assertNotIn('succeeded', self.output.getvalue())

    @override_settings(AI_ENGINE='ollama', OLLAMA_MODEL='gemma3:4b', OLLAMA_BASE_URL='http://ollama:11434')
    def test_ollama_check_inspects_installed_vision_model_without_inference(self):
        response = Mock()
        response.json.return_value = {'capabilities': ['completion', 'vision']}
        with patch('requests.post', return_value=response) as request:
            call_command('check_ai_model', '--json', stdout=self.output)
        request.assert_called_once_with('http://ollama:11434/api/show', json={'model': 'gemma3:4b'}, timeout=10)
        info = json.loads(self.output.getvalue())[0]
        self.assertTrue(info['ok'])
        self.assertIsNone(info['provider_daily_limit'])
        self.assertFalse(info['inference_tested'])
        self.endpoints.assert_not_called()

    @override_settings(AI_ENGINE='ollama', OLLAMA_MODEL='gemma3:4b')
    def test_ollama_text_only_or_malformed_info_fails_readiness(self):
        for info in ({'capabilities': ['completion']}, None):
            with self.subTest(info=info):
                response = Mock()
                response.json.return_value = info
                with patch('requests.post', return_value=response), self.assertRaises(CommandError):
                    call_command('check_ai_model', stdout=self.output)
