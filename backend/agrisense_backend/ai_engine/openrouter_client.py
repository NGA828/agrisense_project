"""Minimal, fail-closed OpenRouter vision client for crop diagnosis.

Only visual classification is delegated to the remote model. The caller gives
this client an allow-list of reviewed disease records; the JSON schema prevents
the model from returning any disease outside that list. Treatment instructions
are never requested from or accepted from OpenRouter.
"""

from __future__ import annotations

import base64
import io
import json
from dataclasses import dataclass
from typing import Any, Callable

from django.conf import settings


class OpenRouterClientError(RuntimeError):
    """Base error raised by the OpenRouter transport/parser."""


class OpenRouterUnavailableError(OpenRouterClientError):
    """Configuration, network, authentication, quota, or provider failure."""


class OpenRouterResponseError(OpenRouterClientError):
    """The provider returned a malformed or unsafe classification."""


@dataclass(frozen=True)
class OpenRouterClassification:
    outcome: str
    disease_name: str
    confidence: float
    evidence: tuple[str, ...]
    model: str


class OpenRouterVisionClient:
    """Call a vision-capable OpenRouter model with a strict output schema."""

    def __init__(self, post: Callable[..., Any] | None = None):
        self.api_key = str(getattr(settings, 'OPENROUTER_API_KEY', '') or '').strip()
        self.model = str(getattr(
            settings, 'OPENROUTER_MODEL',
            'google/gemma-4-26b-a4b-it:free') or '').strip()
        # Server-side failover list (see OPENROUTER_FALLBACK_MODELS). Free
        # endpoints are the first thing providers throttle under load, so a
        # single-model configuration turns a provider hiccup into a failed
        # diagnosis for the farmer.
        self.fallback_models = tuple(
            str(name).strip()
            for name in (getattr(settings, 'OPENROUTER_FALLBACK_MODELS', ()) or ())
            if str(name).strip() and str(name).strip() != self.model
        )
        self.base_url = str(getattr(
            settings, 'OPENROUTER_BASE_URL',
            'https://openrouter.ai/api/v1') or '').rstrip('/')
        self.timeout = float(getattr(settings, 'OPENROUTER_TIMEOUT_SECONDS', 60.0))
        self.max_dimension = int(getattr(
            settings, 'OPENROUTER_IMAGE_MAX_DIMENSION', 1280))
        self.jpeg_quality = int(getattr(settings, 'OPENROUTER_IMAGE_QUALITY', 88))
        self.app_url = str(getattr(settings, 'OPENROUTER_APP_URL', '') or '').strip()
        self.app_title = str(getattr(
            settings, 'OPENROUTER_APP_TITLE', 'AgriSense AI') or '').strip()
        # Hard spend guard. When true (the default), only model ids ending in
        # ':free' may be used, and the request additionally pins `max_price` to
        # zero so OpenRouter itself refuses to bill. A deployment that wants
        # paid models must opt in explicitly by setting
        # OPENROUTER_ALLOW_PAID_MODELS=true.
        self.free_only = bool(getattr(settings, 'OPENROUTER_FREE_ONLY', True))
        if post is None:
            import requests
            post = requests.post
        self._post = post

    @property
    def available(self) -> bool:
        return bool(self.api_key and self.model and self.base_url)

    @property
    def configuration_error(self) -> str:
        if not self.api_key:
            return 'OPENROUTER_API_KEY is not configured.'
        if not self.model:
            return 'OPENROUTER_MODEL is not configured.'
        if not self.base_url:
            return 'OPENROUTER_BASE_URL is not configured.'
        if self.timeout <= 0:
            return 'OPENROUTER_TIMEOUT_SECONDS must be greater than zero.'
        if self.max_dimension < 224:
            return 'OPENROUTER_IMAGE_MAX_DIMENSION must be at least 224.'
        if not 40 <= self.jpeg_quality <= 100:
            return 'OPENROUTER_IMAGE_QUALITY must be between 40 and 100.'
        if self.free_only:
            paid = [name for name in (self.model, *self.fallback_models)
                    if not name.endswith(':free')]
            if paid:
                return (
                    f'OPENROUTER_FREE_ONLY is enabled but these models are not '
                    f'free: {", ".join(paid)}. Use a model id ending in ":free" '
                    f'(run `manage.py check_ai_model --list-free`), or set '
                    f'OPENROUTER_ALLOW_PAID_MODELS=true to permit billing.')
        return ''

    def _encode_image(self, image_file) -> str:
        """Resize, remove EXIF metadata, and create a private base64 data URL."""
        if self.configuration_error:
            raise OpenRouterUnavailableError(self.configuration_error)
        try:
            from PIL import Image, ImageOps

            image_file.seek(0)
            image = ImageOps.exif_transpose(Image.open(image_file)).convert('RGB')
            image.thumbnail(
                (self.max_dimension, self.max_dimension),
                Image.Resampling.LANCZOS,
            )
            output = io.BytesIO()
            image.save(
                output,
                format='JPEG',
                quality=self.jpeg_quality,
                optimize=True,
            )
            encoded = base64.b64encode(output.getvalue()).decode('ascii')
            return f'data:image/jpeg;base64,{encoded}'
        except OpenRouterClientError:
            raise
        except Exception as exc:
            raise OpenRouterResponseError(
                f'Could not prepare the image for cloud inference: {exc}') from exc
        finally:
            try:
                image_file.seek(0)
            except Exception:
                pass

    @staticmethod
    def _hint_for_status(status_code: int) -> str:
        """Map well-known OpenRouter status codes to actionable hints.

        The raw provider message is deliberately not forwarded (it can contain
        upstream diagnostics); these curated hints cover the failure modes an
        AgriSense administrator can actually act on.
        """
        if status_code == 401:
            return ('The API key was rejected. Check OPENROUTER_API_KEY at '
                    'https://openrouter.ai/settings/keys.')
        if status_code == 402:
            return ('The account is out of free-tier credit/quota for now. '
                    'Free models allow ~50 requests/day (1000/day after a '
                    'one-time $10 top-up); wait for the reset or top up.')
        if status_code == 429:
            return ('Rate limited: free tiers allow ~20 requests/minute and '
                    '~50/day. Wait a moment (or a day) and retry; consider a '
                    'one-time $10 top-up for 1000 requests/day.')
        if status_code in (400, 404):
            return ('The configured model (or every fallback) no longer has a '
                    'live provider — free models are retired regularly. Run '
                    '`python manage.py check_ai_model --list-free` and update '
                    'OPENROUTER_MODEL.')
        if status_code in (408, 504):
            return 'The vision provider timed out. Retry with a smaller image.'
        if status_code >= 500:
            return 'OpenRouter or the upstream provider is having an outage.'
        return 'Unexpected OpenRouter response.'

    @staticmethod
    def _candidate_payload(candidates: list[dict[str, Any]]) -> list[dict[str, str]]:
        reviewed = []
        for candidate in candidates:
            name = str(candidate.get('disease_name') or '').strip()
            if not name:
                continue
            reviewed.append({
                'disease_name': name,
                'pathogen': str(candidate.get('pathogen') or '')[:180],
                'reviewed_symptoms': str(candidate.get('symptoms') or '')[:700],
            })
        if not reviewed:
            raise OpenRouterResponseError(
                'No reviewed diseases are available for the selected crop.')
        return reviewed

    @staticmethod
    def _response_schema(disease_names: list[str]) -> dict[str, Any]:
        allowed_names = ['Healthy', 'Inconclusive', 'NotACrop', 'CropMismatch', *disease_names]
        return {
            'type': 'object',
            'properties': {
                'outcome': {
                    'type': 'string',
                    'enum': ['healthy', 'disease', 'inconclusive', 'not_a_crop', 'crop_mismatch'],
                },
                'disease_name': {
                    'type': 'string',
                    'enum': allowed_names,
                    'description': (
                        'Healthy for a healthy plant, NotACrop if not a crop image, '
                        'CropMismatch if the crop in the image does not match the selected crop, '
                        'Inconclusive when uncertain, or exactly one reviewed disease_name.'),
                },
                'confidence': {
                    'type': 'number',
                    'minimum': 0,
                    'maximum': 100,
                    'description': 'Conservative visual match confidence from 0 to 100.',
                },
                'evidence': {
                    'type': 'array',
                    'items': {'type': 'string'},
                    'maxItems': 5,
                    'description': 'Short visible signs in the supplied image only.',
                },
            },
            'required': ['outcome', 'disease_name', 'confidence', 'evidence'],
            'additionalProperties': False,
        }

    def _request_payload(
        self,
        image_data_url: str,
        crop_type: str,
        candidates: list[dict[str, Any]],
    ) -> dict[str, Any]:
        reviewed = self._candidate_payload(candidates)
        disease_names = [item['disease_name'] for item in reviewed]
        candidate_json = json.dumps(reviewed, ensure_ascii=False)
        prompt = (
            f'Analyze this image as a cautious crop-screening assistant. The farmer '
            f'selected crop is {crop_type!r}. CRITICAL: First verify the image shows the SELECTED '
            f'crop type. If the image contains a DIFFERENT crop (e.g., user selected Tomato but '
            f'image shows Maize), return CropMismatch with outcome crop_mismatch immediately. '
            f'You may classify valid {crop_type} images ONLY as Healthy, NotACrop, Inconclusive, '
            f'or one disease in the reviewed list below. Do not invent a disease, treatment, '
            f'pesticide, dosage, cause, or symptom. Use only visible evidence from this image. '
            f'If the image is clearly NOT a crop (e.g., a person, animal, building, or other '
            f'non-agricultural subject), return NotACrop with outcome not_a_crop. '
            f'If the image is unclear, blurry, shows no useful plant area, or does not '
            f'closely match a reviewed disease, return Inconclusive. Use conservative '
            f'confidence; uncertainty must not be hidden.\n\n'
            f'Reviewed diseases for {crop_type}:\n{candidate_json}'
        )
        payload: dict[str, Any] = {
            'model': self.model,
            'messages': [
                {
                    'role': 'system',
                    'content': (
                        'You perform restricted visual screening, not definitive '
                        'agronomic diagnosis. Follow the JSON schema exactly.'),
                },
                {
                    'role': 'user',
                    'content': [
                        {'type': 'text', 'text': prompt},
                        {
                            'type': 'image_url',
                            'image_url': {'url': image_data_url, 'detail': 'high'},
                        },
                    ],
                },
            ],
            'temperature': 0,
            # Reasoning-capable models spend hidden reasoning tokens from the
            # same completion budget. With a small cap the model can exhaust
            # the budget thinking and return an EMPTY JSON body, which surfaces
            # to the farmer as "the photo could not be analyzed". The final
            # schema object itself is tiny, so a generous cap costs nothing on
            # free endpoints and only prevents truncation.
            'max_tokens': int(getattr(
                settings, 'OPENROUTER_MAX_TOKENS', 2000)),
            'response_format': {
                'type': 'json_schema',
                'json_schema': {
                    'name': 'agrisense_crop_diagnosis',
                    'strict': True,
                    'schema': self._response_schema(disease_names),
                },
            },
            # Route only to endpoints that can honor structured output.
            'provider': {'require_parameters': True},
        }
        if self.free_only:
            # Belt-and-braces: even if a ':free' slug were ever silently
            # remapped to a billable endpoint, OpenRouter rejects the request
            # rather than charging the account.
            payload['provider']['max_price'] = {'prompt': 0, 'completion': 0}
        if self.fallback_models:
            # OpenRouter tries these in order when the primary model errors,
            # is rate-limited, or is down — one HTTP request, no extra upload.
            payload['models'] = [self.model, *self.fallback_models]
        return payload

    def _headers(self) -> dict[str, str]:
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json',
        }
        if self.app_url:
            headers['HTTP-Referer'] = self.app_url
        if self.app_title:
            headers['X-OpenRouter-Title'] = self.app_title
        return headers

    @staticmethod
    def _message_content(data: dict[str, Any]) -> Any:
        try:
            content = data['choices'][0]['message']['content']
        except (KeyError, IndexError, TypeError) as exc:
            raise OpenRouterResponseError(
                'OpenRouter response did not contain an assistant message.') from exc
        if isinstance(content, list):
            text_parts = [
                str(part.get('text', ''))
                for part in content
                if isinstance(part, dict) and part.get('type') in ('text', 'output_text')
            ]
            content = ''.join(text_parts)
        return content

    @staticmethod
    def _parse_content(content: Any) -> dict[str, Any]:
        if isinstance(content, dict):
            return content
        if not isinstance(content, str) or not content.strip():
            raise OpenRouterResponseError(
                'OpenRouter returned empty diagnosis content. The model likely '
                'spent its output budget on hidden reasoning (raise '
                'OPENROUTER_MAX_TOKENS) or cannot serve vision requests.')
        text = content.strip()
        # Defensive compatibility for providers that wrap JSON despite strict mode.
        if text.startswith('```'):
            lines = text.splitlines()
            if lines and lines[0].startswith('```'):
                lines = lines[1:]
            if lines and lines[-1].strip() == '```':
                lines = lines[:-1]
            text = '\n'.join(lines).strip()
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError as exc:
            raise OpenRouterResponseError(
                'OpenRouter returned invalid structured diagnosis JSON.') from exc
        if not isinstance(parsed, dict):
            raise OpenRouterResponseError(
                'OpenRouter diagnosis response must be a JSON object.')
        return parsed

    @staticmethod
    def _validate_result(
        result: dict[str, Any],
        allowed_disease_names: list[str],
        response_model: str,
    ) -> OpenRouterClassification:
        expected_fields = {'outcome', 'disease_name', 'confidence', 'evidence'}
        if set(result) != expected_fields:
            raise OpenRouterResponseError(
                'OpenRouter returned fields outside the restricted diagnosis schema.')
        outcome = str(result.get('outcome') or '').strip().lower()
        disease_name = str(result.get('disease_name') or '').strip()
        if outcome not in {'healthy', 'disease', 'inconclusive', 'not_a_crop', 'crop_mismatch'}:
            raise OpenRouterResponseError('OpenRouter returned an invalid outcome.')

        try:
            raw_confidence = result['confidence']
            if isinstance(raw_confidence, bool):
                raise TypeError
            confidence = float(raw_confidence)
        except (KeyError, TypeError, ValueError) as exc:
            raise OpenRouterResponseError(
                'OpenRouter returned an invalid confidence value.') from exc
        if not 0 <= confidence <= 100:
            raise OpenRouterResponseError(
                'OpenRouter confidence must be between 0 and 100.')

        evidence = result.get('evidence')
        if (not isinstance(evidence, list)
                or len(evidence) > 5
                or any(not isinstance(item, str) for item in evidence)):
            raise OpenRouterResponseError(
                'OpenRouter returned invalid visual evidence.')
        clean_evidence = tuple(item.strip()[:300] for item in evidence if item.strip())

        allowed = {name.casefold(): name for name in allowed_disease_names}
        if outcome == 'healthy':
            if disease_name.casefold() != 'healthy':
                raise OpenRouterResponseError(
                    'Healthy outcome must use the Healthy label.')
            disease_name = 'Healthy'
        elif outcome == 'inconclusive':
            if disease_name.casefold() != 'inconclusive':
                raise OpenRouterResponseError(
                    'Inconclusive outcome must use the Inconclusive label.')
            disease_name = 'Inconclusive'
        elif outcome == 'not_a_crop':
            if disease_name.casefold() != 'notacrop':
                raise OpenRouterResponseError(
                    'NotACrop outcome must use the NotACrop label.')
            disease_name = 'NotACrop'
        elif outcome == 'crop_mismatch':
            if disease_name.casefold() != 'cropmismatch':
                raise OpenRouterResponseError(
                    'CropMismatch outcome must use the CropMismatch label.')
            disease_name = 'CropMismatch'
        else:
            canonical = allowed.get(disease_name.casefold())
            if canonical is None:
                # This is the key server-side guard even if a provider ignores
                # the request JSON schema.
                raise OpenRouterResponseError(
                    'OpenRouter selected a disease outside the reviewed allow-list.')
            disease_name = canonical

        return OpenRouterClassification(
            outcome=outcome,
            disease_name=disease_name,
            confidence=round(confidence, 2),
            evidence=clean_evidence,
            model=response_model,
        )

    def classify(
        self,
        image_file,
        crop_type: str,
        candidates: list[dict[str, Any]],
    ) -> OpenRouterClassification:
        if self.configuration_error:
            raise OpenRouterUnavailableError(self.configuration_error)

        reviewed = self._candidate_payload(candidates)
        allowed_names = [item['disease_name'] for item in reviewed]
        payload = self._request_payload(
            self._encode_image(image_file), crop_type, candidates)
        try:
            response = self._post(
                f'{self.base_url}/chat/completions',
                headers=self._headers(),
                json=payload,
                timeout=self.timeout,
            )
        except Exception as exc:
            # Never include request headers or image data in this error.
            raise OpenRouterUnavailableError(
                f'OpenRouter request failed: {type(exc).__name__}.') from exc

        status_code = int(getattr(response, 'status_code', 0) or 0)
        try:
            data = response.json()
        except Exception as exc:
            raise OpenRouterUnavailableError(
                f'OpenRouter returned HTTP {status_code} without JSON.') from exc
        if not isinstance(data, dict):
            raise OpenRouterUnavailableError('OpenRouter returned an invalid envelope.')
        if status_code < 200 or status_code >= 300 or data.get('error'):
            # Provider messages are intentionally not propagated: they are not
            # needed by the client and could contain upstream diagnostic data.
            # The status code alone is mapped to an actionable reason so an
            # administrator can tell "model retired" from "out of free quota"
            # without guessing.
            raise OpenRouterUnavailableError(
                f'OpenRouter returned HTTP {status_code}. '
                f'{self._hint_for_status(status_code)}')

        content = self._message_content(data)
        result = self._parse_content(content)
        response_model = str(data.get('model') or self.model)[:100]
        return self._validate_result(result, allowed_names, response_model)
