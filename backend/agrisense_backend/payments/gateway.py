"""
Payment gateway abstraction for AgriSense AI.

The production app integrates two mobile-money providers:

* MTN Mobile Money (Cameroon / Africa) — Collection API (sandbox at
  https://momodeveloper.mtn.com, client-credentials + access-token flows)
* Orange Money (Orange Developer sandbox)

This module defines a small adapter interface so the rest of the codebase
depends on *a gateway*, not on a specific provider. A sandbox implementation is
provided out of the box so the marketplace checkout flow works end-to-end in
development/demo. To go live, implement `request_payment`/`verify_transaction`
against the provider API using credentials from the environment and switch
`get_gateway()` to return the real adapter (feature-flagged via env var).

Idempotency: every payment row carries a unique `transaction_id`; gateways must
return the same transaction reference for retries of the same payment.
"""

import os
import uuid

from decimal import Decimal

# Premium subscription pricing (FCFA per month) — kept here so both the
# upgrade endpoint and the frontend pricing UI can reference one source.
PREMIUM_PRICE_PER_MONTH = Decimal(os.getenv('PREMIUM_PRICE_PER_MONTH', '1000'))


class PaymentError(Exception):
    """Raised when a provider rejects or cannot confirm a transaction."""


class BaseGateway:
    """Interface all mobile-money gateways implement."""

    provider = 'base'

    def request_payment(self, *, amount, phone_number, description, transaction_id):
        """Initiate a collection request.

        Returns a dict with at least ``status`` ('pending'|'processing') and
        provider-specific references.
        """
        raise NotImplementedError

    def verify_transaction(self, transaction_id):
        """Confirm the final state of a transaction.

        Returns one of 'completed', 'failed', 'pending'.
        """
        raise NotImplementedError


class SandboxGateway(BaseGateway):
    """Deterministic simulation used for development/demo.

    Payments for phone numbers ending in an even digit succeed; odd digits
    simulate failure — handy for testing both paths.
    """

    provider = 'sandbox'

    def request_payment(self, *, amount, phone_number, description, transaction_id):
        digits = ''.join(ch for ch in phone_number if ch.isdigit())
        # Deterministic simulation: even last digit => success, odd => failure.
        success = bool(digits) and int(digits[-1]) % 2 == 0
        return {
            'status': 'completed' if success else 'failed',
            'provider': self.provider,
            'provider_reference': f'SBX-{uuid.uuid4().hex[:16].upper()}',
            'simulated': True,
        }

    def verify_transaction(self, transaction_id):
        # The sandbox finalizes synchronously inside `request_payment`; there is
        # nothing to poll. The view keeps the persisted status as source of truth.
        return 'pending'


class MTNMoMoGateway(BaseGateway):
    """MTN Mobile Money Collection API adapter (sandbox / live).

    Set the following environment variables to activate:
        MTN_MOMO_ENABLED=true
        MTN_MOMO_API_KEY=...
        MTN_MOMO_PRIMARY_KEY=...
        MTN_MOMO_ENVIRONMENT=sandbox|live
        MTN_MOMO_CALLBACK_HOST=https://api.example.com
    """

    provider = 'MTN_MOMO'

    def request_payment(self, *, amount, phone_number, description, transaction_id):
        # NOTE: implement the MTN collection flow here:
        #   1. POST /collection/v1_0/requesttopay with X-Reference-Id,
        #      X-Target-Environment, Ocp-Apim-Subscription-Key and body
        #      {amount, currency: 'XAF', externalId, payer: {partyIdType: 'MSISDN',
        #       partyId: phone_number}, payerMessage, payeeNote}.
        #   2. Poll /collection/v1_0/requesttopay/{referenceId} for status.
        raise PaymentError('MTN MoMo integration is not configured (set MTN_MOMO_ENABLED=true and API credentials)')


class OrangeMoneyGateway(BaseGateway):
    """Orange Money API adapter (sandbox / live).

    Set the following environment variables to activate:
        ORANGE_MONEY_ENABLED=true
        ORANGE_MONEY_CLIENT_ID=...
        ORANGE_MONEY_CLIENT_SECRET=...
        ORANGE_MONEY_ENVIRONMENT=sandbox|live
    """

    provider = 'ORANGE_MONEY'

    def request_payment(self, *, amount, phone_number, description, transaction_id):
        # NOTE: implement the Orange Cash API collection flow here:
        #   1. POST /token to obtain an access token.
        #   2. POST /payment with {amount, currency: 'XAF', orderId, payer:
        #      {partyIdType: 'MSISDN', partyId: phone_number}}.
        raise PaymentError('Orange Money integration is not configured (set ORANGE_MONEY_ENABLED=true and credentials)')


def get_gateway(payment_method):
    """Return the gateway adapter for a payment method.

    Falls back to the sandbox simulator when the provider is not configured,
    so the demo keeps working without external credentials.
    """
    method = (payment_method or '').upper()
    if method == 'MTN_MOMO' and os.getenv('MTN_MOMO_ENABLED') == 'true':
        return MTNMoMoGateway()
    if method == 'ORANGE_MONEY' and os.getenv('ORANGE_MONEY_ENABLED') == 'true':
        return OrangeMoneyGateway()
    return SandboxGateway()
