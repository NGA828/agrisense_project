"""Verify that the configured OpenRouter model can actually serve diagnoses.

The AgriSense diagnosis client has three hard requirements, and a model that
misses any one of them fails at runtime — usually as an opaque HTTP 404/400 the
farmer sees as "diagnosis unavailable":

1. **Image input** — the request sends a base64 JPEG data URL.
2. **Structured outputs** — the disease allow-list is enforced with
   ``response_format: json_schema`` + ``provider.require_parameters``. A model
   without ``structured_outputs`` is filtered out by ``require_parameters`` and
   the request fails to route.
3. **A live provider endpoint** — a model can be listed in the catalog with
   ``"endpoints": []`` (deprecated / not currently served). Requests 404.

This command checks all three against the live OpenRouter catalog for the
configured primary model and every fallback, and can list working alternatives.

Usage::

    python manage.py check_ai_model                # check configured models
    python manage.py check_ai_model --list-free    # show usable free models
    python manage.py check_ai_model --list-all     # include paid models
    python manage.py check_ai_model --model X      # check a specific model
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

CATALOG_URL = 'https://openrouter.ai/api/v1/models'
TIMEOUT = 30


class Command(BaseCommand):
    help = 'Check advertised vision-model capabilities without running inference.'

    def add_arguments(self, parser):
        parser.add_argument('--check-auth', action='store_true',
                            help='Validate the OpenRouter key without running inference.')
        parser.add_argument('--model', help='Check this model id instead of settings.')
        parser.add_argument('--list-free', action='store_true',
                            help='List free models meeting all requirements.')
        parser.add_argument('--list-all', action='store_true',
                            help='List all models meeting all requirements.')
        parser.add_argument('--json', action='store_true',
                            help='Emit machine-readable JSON.')

    # ── catalog access ───────────────────────────────────────────────────
    def _fetch(self, url):
        request = urllib.request.Request(
            url, headers={'Accept': 'application/json', 'User-Agent': 'AgriSense/1.0'})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                return json.loads(response.read().decode('utf-8'))
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise RuntimeError(f'Could not reach the OpenRouter catalog: {exc}') from exc

    def _catalog(self):
        return {m['id']: m for m in self._fetch(CATALOG_URL).get('data', [])}

    def _endpoints(self, model_id):
        """Live provider endpoints. Empty list => nothing serves this model."""
        data = self._fetch(f'{CATALOG_URL}/{model_id}/endpoints').get('data', {})
        return data.get('endpoints', []) or []

    # ── evaluation ───────────────────────────────────────────────────────
    @staticmethod
    def _is_free(model):
        pricing = model.get('pricing') or {}
        try:
            return float(pricing['prompt']) == 0 and float(pricing['completion']) == 0
        except (KeyError, TypeError, ValueError):
            return False

    @staticmethod
    def _requirements(model):
        params = set(model.get('supported_parameters') or [])
        modalities = set(
            (model.get('architecture') or {}).get('input_modalities') or [])
        return {
            'vision': 'image' in modalities,
            'structured_outputs': 'structured_outputs' in params,
        }

    def _evaluate(self, model_id, catalog):
        if model_id == 'openrouter/free':
            # The router has no provider endpoint of its own. Inspect the
            # current eligible pool, not stale, hard-coded free-model slugs.
            usable = []
            for candidate_id, _ in self._usable(catalog, True):
                if candidate_id == model_id or not candidate_id.endswith(':free'):
                    continue
                candidate = self._evaluate(candidate_id, catalog)
                if candidate['ok']:
                    usable.append(candidate_id)
                    break
            return {'model': model_id, 'ok': bool(usable), 'free': True,
                    'vision': bool(usable), 'structured_outputs': bool(usable),
                    'providers': usable,
                    'problems': [] if usable else ['No live free vision/structured-output endpoint found.']}
        model = catalog.get(model_id)
        if model is None:
            return {'model': model_id, 'ok': False, 'listed': False,
                    'problems': ['not present in the OpenRouter catalog']}

        checks = self._requirements(model)
        problems = []
        if not checks['vision']:
            problems.append('does not accept image input')
        if not checks['structured_outputs']:
            problems.append(
                'does not support structured_outputs (required by '
                'provider.require_parameters; the request will not route)')

        try:
            endpoints = self._endpoints(model_id)
        except RuntimeError as exc:
            endpoints = []
            problems.append(str(exc))
        else:
            if not endpoints:
                problems.append('no provider currently serves this model')

        uptimes = [e.get('uptime_last_1d') for e in endpoints
                   if e.get('uptime_last_1d') is not None]
        return {
            'model': model_id,
            'listed': True,
            'free': self._is_free(model),
            'vision': checks['vision'],
            'structured_outputs': checks['structured_outputs'],
            'providers': [e.get('provider_name') for e in endpoints],
            'uptime_1d': round(max(uptimes), 2) if uptimes else None,
            'context_length': model.get('context_length'),
            'ok': not problems,
            'problems': problems,
        }

    def _usable(self, catalog, free_only):
        rows = []
        for model_id, model in catalog.items():
            checks = self._requirements(model)
            if not (checks['vision'] and checks['structured_outputs']):
                continue
            if free_only and (not self._is_free(model) or not (
                    model_id == 'openrouter/free' or model_id.endswith(':free'))):
                continue
            rows.append((model_id, model))
        return rows

    # ── output ───────────────────────────────────────────────────────────
    def _report(self, result):
        name = result['model']
        if result['ok']:
            uptime = result.get('uptime_1d')
            detail = f", {uptime}% uptime/24h" if uptime is not None else ''
            providers = ', '.join(p for p in result.get('providers') or [] if p)
            self.stdout.write(self.style.SUCCESS(
                f'  OK    {name}\n'
                f'        {"free" if result.get("free") else "paid"}, '
                f'vision + structured outputs, '
                f'served by {providers or "unknown"}{detail}'))
        else:
            self.stdout.write(self.style.ERROR(f'  FAIL  {name}'))
            for problem in result['problems']:
                self.stdout.write(self.style.ERROR(f'        - {problem}'))

    def handle(self, *args, **options):
        as_json = options['json']
        if settings.AI_ENGINE in ('ollama', 'ollama-vision') and not (
                options['list_free'] or options['list_all'] or options['model']):
            from ai_engine.ollama_client import OllamaVisionClient
            import requests

            client = OllamaVisionClient()
            if client.configuration_error:
                raise CommandError(client.configuration_error)
            try:
                response = requests.post(f'{client.base_url}/api/show',
                                         json={'model': client.model}, timeout=10)
                response.raise_for_status()
                info = response.json()
            except (requests.RequestException, ValueError) as exc:
                raise CommandError('Ollama is unreachable or the vision model is not installed.') from exc
            if not isinstance(info, dict) or 'vision' not in (info.get('capabilities') or []):
                raise CommandError('The installed Ollama model does not advertise vision support.')
            if as_json:
                self.stdout.write(json.dumps([{'model': client.model, 'engine': 'ollama',
                    'ok': True, 'vision': True, 'provider_daily_limit': None,
                    'inference_tested': False}], indent=2))
            else:
                self.stdout.write(self.style.SUCCESS(
                    f'{client.model}: installed, vision enabled, no hosted API daily quota. '
                    'No inference was run; benchmark latency on your hardware.'))
            return
        if options['check_auth']:
            from ai_engine.openrouter_client import OpenRouterVisionClient
            client = OpenRouterVisionClient()
            if client.configuration_error:
                raise CommandError(client.configuration_error)
            request = urllib.request.Request(client.base_url + '/key', headers=client._headers())
            try:
                with urllib.request.urlopen(request, timeout=10) as response:
                    auth = json.loads(response.read())
                if not isinstance(auth, dict) or not isinstance(auth.get('data'), dict) or auth.get('error'):
                    raise ValueError('Invalid authentication response')
            except (urllib.error.URLError, TimeoutError, ValueError) as exc:
                raise CommandError('OpenRouter key check failed. Check credentials and connectivity privately.') from exc
            if not as_json:
                self.stdout.write('OpenRouter authentication succeeded. No scan was submitted.')

        try:
            catalog = self._catalog()
        except RuntimeError as exc:
            raise CommandError(str(exc)) from exc

        if options['list_free'] or options['list_all']:
            free_only = not options['list_all']
            rows = self._usable(catalog, free_only)
            results = [self._evaluate(model_id, catalog)
                       for model_id, _model in sorted(rows)]
            usable = [r for r in results if r['ok']]
            broken = [r for r in results if not r['ok']]
            if as_json:
                self.stdout.write(json.dumps(results, indent=2))
            else:
                self.stdout.write(
                    f'Models with image input + structured outputs '
                    f'({"free only" if free_only else "all"}): '
                    f'{len(usable)} usable, {len(broken)} unavailable\n')
                for result in usable + broken:
                    self._report(result)
            return

        if options['model']:
            targets = [options['model']]
        else:
            targets = [getattr(settings, 'OPENROUTER_MODEL', '')]
            targets += list(getattr(settings, 'OPENROUTER_FALLBACK_MODELS', ()) or ())
        targets = list(dict.fromkeys(t for t in targets if t))
        if not targets:
            raise CommandError('No model configured.')
        guarded = (not options['model'] and not settings.OPENROUTER_ALLOW_PAID_MODELS)
        invalid_ids = [t for t in targets if t != 'openrouter/free' and not t.endswith(':free')]
        results = [self._evaluate(model_id, catalog) for model_id in targets]
        for result in results:
            if guarded and result['model'] in invalid_ids:
                result['ok'] = False
                result['problems'].append('Model ID is blocked by the free-only configuration guard.')
            if options['check_auth']:
                result['authentication_checked'] = True
            result['inference_tested'] = False
        if as_json:
            self.stdout.write(json.dumps(results, indent=2))
        else:
            self.stdout.write('Checking configured OpenRouter models:\n')
            for index, result in enumerate(results):
                self.stdout.write('primary:' if index == 0 else f'fallback{index}:')
                self._report(result)
        if guarded and invalid_ids:
            raise CommandError('The configured model list includes IDs blocked by the free-only guard.')
        if not any(r['ok'] for r in results):
            raise CommandError('No configured model is usable. Run check_ai_model --list-free.')
        if not as_json:
            if not results[0]['ok']:
                self.stdout.write(self.style.WARNING('Primary unavailable; a fallback can serve the request.'))
            self.stdout.write(self.style.SUCCESS(
                'Catalog configuration is usable. This does not guarantee free quota, '
                'latency, accuracy, or future availability.'))
