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

    # ── Groq engine ──────────────────────────────────────────────────────
    def _groq_catalog(self, client):
        """GET /models validates the key, connectivity and the live catalog."""
        request = urllib.request.Request(
            client.base_url + '/models',
            headers={'Accept': 'application/json',
                     'Authorization': f'Bearer {client.api_key}',
                     'User-Agent': 'AgriSense/1.0'})
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                data = json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as exc:
            if exc.code == 401:
                raise RuntimeError(
                    'The Groq API key was rejected. Check GROQ_API_KEY at '
                    'https://console.groq.com/keys.') from exc
            if exc.code == 429:
                raise RuntimeError(
                    'Groq rate limit reached while listing models. Free-tier '
                    'limits reset over time; retry shortly.') from exc
            raise RuntimeError(f'Groq returned HTTP {exc.code}.') from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise RuntimeError(f'Could not reach the Groq API: {exc}') from exc
        models = {m.get('id'): m for m in (data or {}).get('data', [])
                  if isinstance(m, dict) and m.get('id')}
        if not models:
            raise RuntimeError('Groq returned an empty model catalog.')
        return models

    @staticmethod
    def _groq_evaluate(model_id, catalog):
        model = catalog.get(model_id)
        if model is None:
            return {'model': model_id, 'ok': False, 'listed': False, 'free': True,
                    'problems': ['not present in the Groq model catalog']}
        modalities = set(model.get('modalities') or [])
        # Older catalog entries omit `modalities`; absence is not proof a
        # vision request will fail, so it is reported as unknown, not failed.
        vision = 'image' in modalities if modalities else None
        problems = []
        if vision is False:
            problems.append('does not accept image input')
        if model.get('active') is False:
            problems.append('is marked inactive by Groq')
        return {'model': model_id, 'ok': not problems, 'listed': True, 'free': True,
                'vision': vision, 'active': model.get('active'),
                'context_window': (model.get('context_window') or {}).get('window')
                if isinstance(model.get('context_window'), dict) else None,
                'problems': problems}

    def _handle_groq(self, options):
        from ai_engine.groq_client import GroqVisionClient

        as_json = options['json']
        client = GroqVisionClient()
        if client.configuration_error:
            raise CommandError(client.configuration_error)
        try:
            catalog = self._groq_catalog(client)
        except RuntimeError as exc:
            raise CommandError(str(exc)) from exc

        if options['model']:
            targets = [options['model']]
        elif options['list_free'] or options['list_all']:
            # Groq does not publish per-model pricing in the catalog: every
            # listed model is callable on the free tier with per-key quotas.
            targets = sorted(catalog)
            results = [self._groq_evaluate(model_id, catalog) for model_id in targets]
            vision = [r for r in results if r['vision'] is not False]
            if as_json:
                self.stdout.write(json.dumps(results, indent=2))
            else:
                self.stdout.write(
                    f'Groq models ({len(vision)} available, vision unknown for '
                    f'{sum(1 for r in results if r["vision"] is None)}):\n')
                for result in results:
                    marker = ('image' if result['vision'] else
                              'text?' if result['vision'] is None else 'text')
                    flag = 'OK  ' if result['ok'] else 'FAIL'
                    self.stdout.write(f'  {flag}  {result["model"]}  [{marker}]')
                    for problem in result['problems']:
                        self.stdout.write(self.style.ERROR(f'        - {problem}'))
                self.stdout.write(self.style.NOTICE(
                    'All Groq models are callable on the free tier; daily quotas '
                    'are per key and per model (console.groq.com/settings/limits).'))
            return

        targets = ([client.model, *client.fallback_models]
                   if not options['model'] else targets)
        results = [self._groq_evaluate(model_id, catalog) for model_id in targets]
        for result in results:
            result['inference_tested'] = False
            result['engine'] = 'groq'
        if as_json:
            self.stdout.write(json.dumps(results, indent=2))
            return
        self.stdout.write('Checking configured Groq models:\n')
        for index, result in enumerate(results):
            self.stdout.write('primary:' if index == 0 else f'fallback{index}:')
            if result['ok']:
                note = ('vision confirmed' if result['vision']
                        else 'vision not advertised by catalog; test a scan')
                self.stdout.write(self.style.SUCCESS(
                    f'  OK    {result["model"]}\n        free tier, {note}'))
            else:
                self.stdout.write(self.style.ERROR(f'  FAIL  {result["model"]}'))
                for problem in result['problems']:
                    self.stdout.write(self.style.ERROR(f'        - {problem}'))
        if options['check_auth']:
            self.stdout.write('Groq authentication succeeded. No scan was submitted.')
        if not any(r['ok'] for r in results):
            raise CommandError(
                'No configured Groq model is usable. Re-run with --list-free to '
                'see the live catalog and update GROQ_MODEL.')
        self.stdout.write(self.style.SUCCESS(
            'Groq configuration is usable. Free-tier quota is per key/model; this '
            'does not guarantee remaining quota, latency, or accuracy.'))

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
        if settings.AI_ENGINE in ('groq', 'groq-vision'):
            return self._handle_groq(options)
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
        guarded = (not options['model'] and not getattr(settings, 'OPENROUTER_ALLOW_PAID_MODELS', False))
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
