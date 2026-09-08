"""Private, self-hosted vision using the same guarded classification contract.

Ollama must already be running with a downloaded vision model. This adapter
never downloads weights, silently changes providers, or uses Ollama Cloud.
"""
import math
from urllib.parse import urlparse

from django.conf import settings

from .openrouter_client import (
    OpenRouterVisionClient, OpenRouterUnavailableError, OpenRouterResponseError,
)


class OllamaVisionClient(OpenRouterVisionClient):
    def __init__(self, post=None):
        super().__init__(post=post)
        self.model = settings.OLLAMA_MODEL
        self.base_url = settings.OLLAMA_BASE_URL
        self.timeout = settings.OLLAMA_TIMEOUT_SECONDS

    @property
    def available(self):
        return not self.configuration_error

    @property
    def configuration_error(self):
        url = urlparse(self.base_url)
        if url.scheme not in ('http', 'https') or not url.hostname:
            return 'OLLAMA_BASE_URL must be the private Ollama server URL.'
        if url.hostname in ('ollama.com', 'www.ollama.com') or ':cloud' in self.model:
            return 'Use a locally downloaded vision model, not Ollama Cloud.'
        if not self.model:
            return 'OLLAMA_MODEL is not configured.'
        if not math.isfinite(self.timeout) or self.timeout <= 0:
            return 'OLLAMA_TIMEOUT_SECONDS must be positive.'
        if self.max_dimension < 224 or not 40 <= self.jpeg_quality <= 100:
            return 'Invalid image resizing settings.'
        return ''

    def classify(self, image_file, crop_type, candidates):
        if self.configuration_error:
            raise OpenRouterUnavailableError(self.configuration_error)
        data_url = self._encode_image(image_file)
        contract = self._request_payload(data_url, crop_type, candidates)
        reviewed = self._candidate_payload(candidates)
        payload = {
            'model': self.model,
            'stream': False,
            'keep_alive': '30m',
            'format': self.response_schema(
                [item['disease_name'] for item in reviewed]),
            'options': {'temperature': 0, 'num_predict': 1024},
            'messages': [
                contract['messages'][0],
                {
                    'role': 'user',
                    'content': contract['messages'][1]['content'][0]['text'],
                    'images': [data_url.split(',', 1)[1]],
                },
            ],
        }
        try:
            response = self._post(
                f'{self.base_url}/api/chat', json=payload,
                timeout=(min(5, self.timeout), self.timeout),
            )
            if response.status_code != 200:
                raise OpenRouterUnavailableError(
                    f'Ollama returned HTTP {response.status_code}. '
                    'Check that the configured vision model is installed and running.')
            data = response.json()
        except OpenRouterUnavailableError:
            raise
        except Exception as exc:
            raise OpenRouterUnavailableError(
                f'Private vision service unavailable ({type(exc).__name__}).',
                code='ai_timeout' if 'Timeout' in type(exc).__name__ else 'ai_model_unavailable',
            ) from exc
        if not isinstance(data, dict) or not isinstance(data.get('message'), dict):
            raise OpenRouterResponseError('Ollama returned an invalid response envelope.')
        result = self._parse_content(data['message'].get('content'))
        return self._validate_result(
            result, [item['disease_name'] for item in candidates],
            str(data.get('model') or self.model)[:100],
        )
