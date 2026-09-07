"""Mobile-money collection adapters. No implicit simulation or fake success.

Sandbox and live are different environments, not just different credentials.
A timeout after request-to-pay is an UNKNOWN outcome: verify the SAME reference
instead of releasing stock or issuing a second charge.
"""
import base64
import hashlib
import json
import logging
import re
import uuid
from decimal import Decimal, InvalidOperation
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger('agrisense.payments')

PREMIUM_PRICE_PER_MONTH = Decimal(str(settings.PREMIUM_PRICE_PER_MONTH))


class PaymentError(Exception):
    """A definite rejection or configuration error, safe to show to the payer."""

    def __init__(self, message, code='payment_rejected'):
        super().__init__(message)
        self.code = code


class PaymentStatusUnknown(PaymentError):
    """The provider may have accepted the charge. Never retry with a new ID."""


class PaymentVerificationMismatch(PaymentStatusUnknown):
    """A response does not match the expected collection. Needs investigation."""


def normalize_phone(phone, *, sandbox=False):
    value = str(phone or '').strip()
    if not re.fullmatch(r'\+?[0-9 ()-]{8,22}', value):
        raise PaymentError('Enter a valid mobile money number.', 'invalid_phone')
    digits = re.sub(r'[^0-9]', '', value)
    if digits.startswith('00'):
        digits = digits[2:]
    # MTN's documented sandbox MSISDNs are not Cameroon numbers.
    if sandbox and re.fullmatch(r'4673312345[0-4]', digits):
        return digits
    if re.fullmatch(r'6[0-9]{8}', digits):
        digits = '237' + digits
    if not re.fullmatch(r'2376[0-9]{8}', digits):
        raise PaymentError('Use a Cameroon mobile number: +237 followed by 9 digits '
                           'starting with 6.', 'invalid_phone')
    return digits


class BaseGateway:
    provider = 'base'
    environment = ''
    is_test = False

    def validate_phone(self, phone):
        return normalize_phone(phone)

    def request_payment(self, *, amount, phone_number, description, transaction_id,
                        provider_reference):
        raise NotImplementedError

    def verify_transaction(self, transaction_id, *, provider_reference, amount, phone_number):
        raise NotImplementedError


class SandboxGateway(BaseGateway):
    """Explicit local simulation only. Deterministic: every payment succeeds.

    Simulated checkout must be reliable for demos and training, so the old
    even/odd phone-digit coin flip is gone. To exercise the failure path
    (declined payment, stock release, no dealer order), pay from a number
    whose last four digits are 0000, e.g. +237 670 00 00 00.
    """

    provider = 'sandbox'
    environment = 'simulated'
    is_test = True
    DECLINE_SUFFIX = '0000'

    def request_payment(self, *, amount, phone_number, description, transaction_id,
                        provider_reference):
        phone = self.validate_phone(phone_number)
        declined = phone.endswith(self.DECLINE_SUFFIX)
        return {'status': 'failed' if declined else 'completed',
                'provider': self.provider, 'provider_reference': str(provider_reference),
                'is_test': True}

    def verify_transaction(self, transaction_id, **kwargs):
        return 'pending'


class MTNMoMoGateway(BaseGateway):
    provider = 'MTN_MOMO'

    def __init__(self, environment=None):
        self.primary_key = settings.MTN_MOMO_PRIMARY_KEY
        self.api_user = settings.MTN_MOMO_API_USER
        self.api_key = settings.MTN_MOMO_API_KEY
        configured = settings.MTN_MOMO_ENVIRONMENT.lower()
        # Backward-compatible input alias; NEVER send the literal 'live' to MTN.
        configured = 'mtncameroon' if configured == 'live' else configured
        self.environment = environment or configured
        if self.environment not in ('sandbox', 'mtncameroon'):
            raise PaymentError('Set MTN_MOMO_ENVIRONMENT to sandbox or mtncameroon.',
                               'payment_not_configured')
        if environment and environment != configured:
            raise PaymentStatusUnknown(
                'This payment belongs to a different MTN environment. Ask the '
                'administrator to reconcile it before changing environments.',
                'payment_environment_mismatch')
        if not all((self.primary_key, self.api_user, self.api_key)):
            raise PaymentError('MTN payments are not configured. The administrator must '
                               'set the Collection subscription key, API user and API key.',
                               'payment_not_configured')
        self.is_test = self.environment == 'sandbox'
        self.currency = 'EUR' if self.is_test else 'XAF'
        self.host = settings.MTN_MOMO_BASE_URL or (
            'https://sandbox.momodeveloper.mtn.com' if self.is_test
            else 'https://proxy.momoapi.mtn.com')
        self.host = self.host.rstrip('/')
        parsed = urlparse(self.host)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username:
            raise PaymentError('MTN_MOMO_BASE_URL must be the provider HTTPS API URL.',
                               'payment_not_configured')
        self.callback_url = settings.MTN_MOMO_CALLBACK_URL
        if self.callback_url:
            callback = urlparse(self.callback_url)
            if callback.scheme != 'https' or not callback.hostname or callback.username:
                raise PaymentError('MTN_MOMO_CALLBACK_URL must be a public HTTPS URL.',
                                   'payment_not_configured')

    def validate_phone(self, phone):
        return normalize_phone(phone, sandbox=self.is_test)

    def _request(self, method, path, *, headers=None, body=None, collection=False):
        # MTN's token endpoint expects an empty body, not grant_type JSON/form.
        payload = json.dumps(body).encode() if body is not None else (
            b'' if method == 'POST' else None)
        request = Request(self.host + path, data=payload, method=method,
                          headers={'Accept': 'application/json', **(headers or {})})
        try:
            with urlopen(request, timeout=settings.PAYMENT_PROVIDER_TIMEOUT_SECONDS) as response:
                raw = response.read().decode('utf-8')
                data = json.loads(raw) if raw else {}
                if not isinstance(data, dict):
                    raise ValueError('Invalid envelope')
                return response.status, data
        except HTTPError as exc:
            # Do not expose raw provider bodies (may contain credentials/PII).
            if collection and exc.code == 409:
                # Same UUID was already accepted. Verify it; don't charge again.
                return 202, {}
            if exc.code in (408, 429) or exc.code >= 500:
                raise PaymentStatusUnknown(
                    'MTN is temporarily unavailable. We will check this payment; '
                    'do not start another payment.', 'provider_unavailable') from exc
            hints = {
                400: 'MTN rejected the request. Check the payment settings and number.',
                401: 'MTN authentication failed. Ask the administrator to check the Collection credentials.',
                403: 'MTN has not authorised this merchant. Contact the administrator.',
                404: 'MTN has not found this payment yet. Check its status again shortly.',
            }
            raise PaymentError(hints.get(exc.code, 'MTN rejected this request.'),
                               f'provider_http_{exc.code}') from exc
        except (URLError, TimeoutError, OSError, ValueError) as exc:
            raise PaymentStatusUnknown(
                'Payment confirmation is not available yet. Check the same payment '
                'again; do not pay a second time.', 'provider_timeout') from exc

    def _token(self):
        fingerprint = hashlib.sha256(
            f'{self.host}|{self.environment}|{self.api_user}|{self.api_key}|{self.primary_key}'.encode()
        ).hexdigest()
        key = 'mtn:token:' + fingerprint
        try:
            token = cache.get(key)
        except Exception:
            # Authentication caching is an optimisation, not evidence of a
            # collection. Do not strand a processing attempt before contacting MTN.
            logger.warning('MTN token cache unavailable; requesting authentication directly.')
            token = None
        if isinstance(token, str) and token:
            return token
        credentials = base64.b64encode(f'{self.api_user}:{self.api_key}'.encode()).decode()
        _, data = self._request('POST', '/collection/token/', headers={
            'Authorization': f'Basic {credentials}',
            'Ocp-Apim-Subscription-Key': self.primary_key,
        })
        token = data.get('access_token')
        if not isinstance(token, str) or not token:
            raise PaymentError('MTN authentication did not return a token.', 'provider_authentication')
        try:
            ttl = max(1, min(3600, int(data.get('expires_in', 300))) - 30)
        except (TypeError, ValueError):
            ttl = 270
        try:
            cache.set(key, token, timeout=max(1, ttl))
        except Exception:
            # The valid token is still usable; no repeated authentication or
            # collection request is needed. Never log the token/cache URL.
            logger.warning('MTN token could not be cached; continuing with authenticated token.')
        return token

    def _headers(self):
        return {'Authorization': f'Bearer {self._token()}',
                'Ocp-Apim-Subscription-Key': self.primary_key,
                'X-Target-Environment': self.environment}

    def request_payment(self, *, amount, phone_number, description, transaction_id,
                        provider_reference):
        phone = self.validate_phone(phone_number)
        reference_uuid = uuid.UUID(str(provider_reference))
        if reference_uuid.version != 4:
            # Preserve old IDs for status lookup, but never submit a fresh MTN
            # collection with an invalid UUIDv5 or silently rotate a possibly
            # already-submitted legacy reference (which could double charge).
            raise PaymentStatusUnknown(
                'This legacy payment reference needs verification by support before retrying. '
                'No new collection was submitted.', 'legacy_payment_reference')
        reference = str(reference_uuid)
        try:
            headers = {**self._headers(), 'X-Reference-Id': reference,
                       'Content-Type': 'application/json'}
        except PaymentStatusUnknown as exc:
            # No collection request has been sent yet; a token timeout cannot
            # have charged the payer, so a new attempt is safe in this case.
            raise PaymentError('MTN authentication is temporarily unavailable. No '
                               'payment request was sent; please retry.',
                               'provider_authentication_unavailable') from exc
        if self.callback_url and not self.is_test:
            headers['X-Callback-Url'] = self.callback_url
        status, _ = self._request('POST', '/collection/v1_0/requesttopay',
                                 headers=headers, collection=True, body={
            'amount': str(amount), 'currency': self.currency,
            'externalId': transaction_id,
            'payer': {'partyIdType': 'MSISDN', 'partyId': phone},
            'payerMessage': 'AgriSense order payment',
            'payeeNote': transaction_id[:100],
        })
        if status != 202:
            raise PaymentStatusUnknown('MTN has not confirmed acceptance. Check payment status.',
                                       'provider_unexpected_response')
        return {'status': 'processing', 'provider': self.provider,
                'provider_reference': reference, 'is_test': self.is_test}

    def verify_transaction(self, transaction_id, *, provider_reference, amount, phone_number):
        reference = str(uuid.UUID(str(provider_reference)))
        _, data = self._request('GET', f'/collection/v1_0/requesttopay/{reference}',
                                headers=self._headers())
        state = str(data.get('status', '')).upper()
        if state == 'SUCCESSFUL':
            try:
                received_amount = Decimal(str(data.get('amount')))
                correct = (received_amount.is_finite() and received_amount == Decimal(str(amount))
                           and data.get('currency') == self.currency
                           and data.get('externalId') == transaction_id
                           and (data.get('payer') or {}).get('partyId') == self.validate_phone(phone_number))
            except (InvalidOperation, TypeError, ValueError, AttributeError):
                correct = False
            if not correct:
                raise PaymentVerificationMismatch(
                    'MTN returned details that do not match this payment. The '
                    'administrator must investigate; do not pay again.',
                    'payment_verification_mismatch')
            return 'completed'
        if state == 'FAILED':
            return 'failed'
        return 'processing'


def get_gateway(payment_method, *, environment=None):
    method = str(payment_method or '').upper()
    if method not in ('MTN_MOMO', 'ORANGE_MONEY'):
        raise PaymentError('Card payments are not available. Choose an enabled mobile-money method.',
                           'payment_method_unavailable')
    simulator_requested = environment == 'simulated' or (
        not environment and settings.PAYMENT_SIMULATOR_ENABLED)
    if simulator_requested:
        # DEBUG-only by default; PAYMENT_SIMULATOR_ALLOW_NON_DEBUG=true is the
        # explicit, auditable opt-in for demo/staging deployments.
        simulator_allowed = (settings.DEBUG
                             or getattr(settings, 'PAYMENT_SIMULATOR_ALLOW_NON_DEBUG', False))
        if not settings.PAYMENT_SIMULATOR_ENABLED or not simulator_allowed:
            raise PaymentError('Local payment simulation is disabled.', 'payment_not_configured')
        return SandboxGateway()
    if method == 'MTN_MOMO' and settings.MTN_MOMO_ENABLED:
        return MTNMoMoGateway(environment=environment)
    if method == 'ORANGE_MONEY':
        raise PaymentError('Orange Money is not integrated yet. Choose an enabled payment method.',
                           'payment_method_unavailable')
    raise PaymentError('MTN payments are not enabled. Ask the administrator to configure the gateway.',
                       'payment_not_configured')


def payment_methods():
    """Public readiness metadata, never credentials or live provider calls."""
    methods = []
    for method, label in (('MTN_MOMO', 'MTN Mobile Money'), ('ORANGE_MONEY', 'Orange Money')):
        try:
            gateway = get_gateway(method)
            methods.append({'id': method, 'label': label, 'available': True,
                            'is_test': gateway.is_test, 'environment': gateway.environment,
                            'message': 'Approve the payment on your phone.'})
        except PaymentError as exc:
            methods.append({'id': method, 'label': label, 'available': False,
                            'is_test': False, 'message': str(exc)})
    return methods
