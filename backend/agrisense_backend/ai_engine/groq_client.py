"""Groq free-tier vision client using the same guarded classification contract.

Groq (https://console.groq.com/keys) serves open vision models on the free
tier with generous per-key daily quotas and very fast inference. The API is
OpenAI-compatible, so this adapter reuses the OpenRouter client's image
preparation, prompt contract and fail-closed response validation. Only visual
classification is delegated; treatment content is never requested from or
accepted from Groq.

Unlike OpenRouter, Groq has no server-side ``models`` failover array, so the
configured fallback models are tried in order client-side (one request per
model, only on transport/model-level errors). Rate limits are tracked per
model per key, so a rate-limited primary can still fall back.
"""

from __future__ import annotations

import json
import math
from urllib.parse import urlparse

from django.conf import settings

from .openrouter_client import (
    OpenRouterVisionClient, OpenRouterUnavailableError, OpenRouterResponseError,
)

DEFAULT_GROQ_MODEL = 'meta-llama/llama-4-scout-17b-16e-instruct'

# HTTP statuses on which trying the next configured model can still succeed.
# 401 is account-wide (the key is bad for every model), so it never fails over.
_FAILOVER_STATUSES = frozenset({400, 404, 408, 413, 429, 500, 502, 503, 504, 529})


class GroqVisionClient(OpenRouterVisionClient):
    """Call a vision-capable Groq model with a strict output contract."""

    def __init__(self, post=None):
        super().__init__(post=post)
        self.api_key = str(getattr(settings, 'GROQ_API_KEY', '') or '').strip()
        self.model = str(getattr(
            settings, 'GROQ_MODEL', DEFAULT_GROQ_MODEL) or '').strip()
        self.fallback_models = tuple(dict.fromkeys(
            str(name).strip()
            for name in (getattr(settings, 'GROQ_FALLBACK_MODELS', ()) or ())
            if str(name).strip() and str(name).strip() != self.model
        ))
        self.base_url = str(getattr(
            settings, 'GROQ_BASE_URL', 'https://api.groq.com/openai/v1')
            or '').rstrip('/')
        self.timeout = float(getattr(settings, 'GROQ_TIMEOUT_SECONDS', 25.0))
        self.max_tokens = int(getattr(settings, 'GROQ_MAX_TOKENS', 1024))
        self.max_dimension = int(getattr(
            settings, 'GROQ_IMAGE_MAX_DIMENSION',
            getattr(settings, 'OPENROUTER_IMAGE_MAX_DIMENSION', 1024)))
        self.jpeg_quality = int(getattr(
            settings, 'GROQ_IMAGE_QUALITY',
            getattr(settings, 'OPENROUTER_IMAGE_QUALITY', 82)))
        # The shared contract advertises OpenRouter-specific routing headers;
        # Groq must never receive them.
        self.app_url = ''
        self.app_title = ''
        self.free_only = False

    # ── configuration ───────────────────────────────────────────────────
    @property
    def available(self) -> bool:
        return not self.configuration_error

    @property
    def configuration_error(self) -> str:
        if not self.api_key:
            return ('GROQ_API_KEY is not configured. Create a free key at '
                    'https://console.groq.com/keys and set it privately in the '
                    'backend environment.')
        if not self.model:
            return 'GROQ_MODEL is not configured.'
        url = urlparse(self.base_url)
        if url.scheme != 'https' or not url.hostname or url.username:
            return ('GROQ_BASE_URL must be the provider HTTPS API URL '
                    '(https://api.groq.com/openai/v1).')
        if url.hostname.endswith('openrouter.ai'):
            return 'GROQ_BASE_URL points at OpenRouter; use the Groq API URL.'
        if not math.isfinite(self.timeout) or self.timeout <= 0:
            return 'GROQ_TIMEOUT_SECONDS must be greater than zero.'
        if self.max_dimension < 224:
            return 'GROQ_IMAGE_MAX_DIMENSION must be at least 224.'
        if not 40 <= self.jpeg_quality <= 100:
            return 'GROQ_IMAGE_QUALITY must be between 40 and 100.'
        if self.max_tokens < 128:
            return 'GROQ_MAX_TOKENS must be at least 128.'
        return ''

    # ── request shaping ─────────────────────────────────────────────────
    @staticmethod
    def _hint_for_status(status_code: int) -> str:
        if status_code == 401:
            return ('The Groq API key was rejected. Check GROQ_API_KEY at '
                    'https://console.groq.com/keys.')
        if status_code == 429:
            return ('Rate limited by the Groq free tier (per model, per key). '
                    'Free limits reset over time; check '
                    'https://console.groq.com/settings/limits.')
        if status_code in (400, 404):
            return ('The configured model is unavailable or cannot serve image '
                    'input. Run `python manage.py check_ai_model` and update '
                    'GROQ_MODEL.')
        if status_code == 413:
            return ('The image payload is too large for Groq. Lower '
                    'GROQ_IMAGE_MAX_DIMENSION or GROQ_IMAGE_QUALITY.')
        if status_code in (408, 504):
            return 'Groq timed out. Retry, or lower GROQ_IMAGE_MAX_DIMENSION.'
        if status_code >= 500:
            return 'Groq is having an outage. A fallback model may still work.'
        return 'Unexpected Groq response.'

    def _groq_payload(self, image_data_url: str, contract: dict) -> dict:
        """Adapt the shared contract to Groq's OpenAI-compatible schema.

        Groq does not implement OpenRouter routing controls, reasoning hints
        or ``json_schema`` response formats on every vision model, so the
        schema is enforced three ways instead: JSON mode (``json_object``),
        the schema embedded in the prompt, and server-side validation of the
        parsed response (``_validate_result``) — the last one is authoritative.
        """
        system_message = contract['messages'][0]
        user_text = contract['messages'][1]['content'][0]['text']
        schema = contract['response_format']['json_schema']['schema']
        json_instruction = (
            '\n\nRespond with ONLY a valid JSON object (no markdown, no '
            'commentary) that satisfies exactly this JSON schema. Use only '
            'these keys and nothing else:\n' + json.dumps(
                schema, ensure_ascii=False)
        )
        return {
            'model': self.model,
            'messages': [
                {'role': 'system', 'content': system_message['content']},
                {
                    'role': 'user',
                    'content': [
                        {'type': 'text', 'text': user_text + json_instruction},
                        # Groq accepts a private base64 data URL. The shared
                        # contract's 'detail' hint is OpenAI-specific.
                        {'type': 'image_url',
                         'image_url': {'url': image_data_url}},
                    ],
                },
            ],
            'temperature': 0,
            'max_completion_tokens': self.max_tokens,
            'response_format': {'type': 'json_object'},
            'stream': False,
        }

    # ── transport ───────────────────────────────────────────────────────
    def _post_one(self, model: str, payload: dict):
        """Send one completion request. Returns the parsed envelope dict."""
        payload = {**payload, 'model': model}
        try:
            response = self._post(
                f'{self.base_url}/chat/completions',
                headers={'Authorization': f'Bearer {self.api_key}',
                         'Content-Type': 'application/json'},
                json=payload,
                timeout=(min(5, self.timeout), self.timeout),
            )
        except Exception as exc:
            # Never include request headers or image data in the error.
            raise OpenRouterUnavailableError(
                f'Groq request failed: {type(exc).__name__}.',
                code='ai_timeout' if 'Timeout' in type(exc).__name__
                else 'ai_model_unavailable') from exc
        try:
            data = response.json()
        except Exception as exc:
            raise OpenRouterUnavailableError(
                f'Groq returned HTTP {int(getattr(response, "status_code", 0) or 0)} '
                'without JSON.') from exc
        if not isinstance(data, dict):
            raise OpenRouterUnavailableError('Groq returned an invalid envelope.')
        status_code = int(getattr(response, 'status_code', 0) or 0)
        if status_code < 200 or status_code >= 300 or data.get('error'):
            error = data.get('error')
            if isinstance(error, dict):
                try:
                    status_code = int(error.get('code', status_code) or status_code)
                except (TypeError, ValueError):
                    pass
            retry_after = None
            if status_code == 429:
                try:
                    retry_after = max(1, min(86400, int(
                        str(getattr(response, 'headers', {}).get('retry-after', '60')))))
                except (TypeError, ValueError):
                    retry_after = 60
            raise _GroqHTTPError(
                status_code, self._hint_for_status(status_code), retry_after)
        return data

    def classify(self, image_file, crop_type, candidates):
        if self.configuration_error:
            raise OpenRouterUnavailableError(self.configuration_error)

        data_url = self._encode_image(image_file)
        contract = self._request_payload(data_url, crop_type, candidates)
        payload = self._groq_payload(data_url, contract)
        allowed_names = [item['disease_name'] for item in candidates]

        last_error = None
        for index, model in enumerate((self.model, *self.fallback_models)):
            try:
                data = self._post_one(model, payload)
            except _GroqHTTPError as exc:
                last_error = exc
                # A rejected key is wrong for every model: do not hammer the
                # provider with retries that cannot succeed.
                if exc.status_code == 401 or exc.status_code not in _FAILOVER_STATUSES:
                    break
                continue
            try:
                choices = data.get('choices') or []
                finish_reason = str(
                    (choices[0] or {}).get('finish_reason') or '').lower()
                content = self._message_content(data)
                result = self._parse_content(content)
            except OpenRouterResponseError as exc:
                if finish_reason == 'length':
                    raise OpenRouterResponseError(
                        'Groq response was truncated by the token budget '
                        '(raise GROQ_MAX_TOKENS).') from exc
                raise
            except (KeyError, IndexError, TypeError, AttributeError) as exc:
                raise OpenRouterResponseError(
                    'Groq response did not contain a diagnosis message.') from exc
            return self._validate_result(
                result, allowed_names, str(data.get('model') or model)[:100])

        if last_error is not None:
            code = 'ai_rate_limited' if last_error.status_code == 429 else 'ai_model_unavailable'
            raise OpenRouterUnavailableError(
                f'Groq returned HTTP {last_error.status_code}. {last_error.hint}',
                code=code, retry_after=last_error.retry_after)
        raise OpenRouterUnavailableError('Groq request did not run.')


class _GroqHTTPError(Exception):
    """Internal carrier for a Groq HTTP status between failover attempts."""

    def __init__(self, status_code, hint, retry_after=None):
        super().__init__(hint)
        self.status_code = status_code
        self.hint = hint
        self.retry_after = retry_after
