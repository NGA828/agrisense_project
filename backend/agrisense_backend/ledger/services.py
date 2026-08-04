"""
Ledger service helpers — the only supported way to move money.

These helpers enforce double-entry balance integrity (every credit has a
matching debit, amounts are positive) and are safe to call inside an existing
``transaction.atomic`` block. System accounts are looked up by code and created
on demand.
"""

from decimal import Decimal

from django.conf import settings
from django.db import transaction

from .models import Account, LedgerEntry

# Canonical system-account codes.
ESCROW_CODE = 'escrow'
MOBILE_MONEY_CODE = 'mobile_money'
PLATFORM_FEES_CODE = 'platform_fees'
DEALER_CODE_PREFIX = 'dealer'
FARMER_CODE_PREFIX = 'farmer'


def _get_system_account(code, name, account_type):
    account, _ = Account.objects.get_or_create(
        code=code, defaults={'name': name, 'account_type': account_type},
    )
    return account


def escrow_account():
    return _get_system_account(ESCROW_CODE, 'Platform escrow', 'escrow')


def mobile_money_account():
    return _get_system_account(
        MOBILE_MONEY_CODE, 'Mobile money clearing (external)', 'external',
    )


def platform_fees_account():
    return _get_system_account(PLATFORM_FEES_CODE, 'Platform fees / income', 'platform')


def dealer_account(user):
    """Return (create if needed) the dealer's balance account."""
    if user.role != 'dealer':
        raise ValueError('dealer_account() requires a dealer user')
    account, _ = Account.objects.get_or_create(
        code=f'{DEALER_CODE_PREFIX}:{user.id}',
        defaults={'name': f'{user.get_full_name() or user.username} (dealer balance)',
                  'account_type': 'dealer', 'owner': user},
    )
    return account


def farmer_account(user):
    account, _ = Account.objects.get_or_create(
        code=f'{FARMER_CODE_PREFIX}:{user.id}',
        defaults={'name': f'{user.get_full_name() or user.username} (farmer balance)',
                  'account_type': 'farmer', 'owner': user},
    )
    return account


def account_balance(account_or_code):
    """Balance of an Account instance or its code."""
    if isinstance(account_or_code, Account):
        return account_or_code.balance
    account = Account.objects.get(code=account_or_code)
    return account.balance


@transaction.atomic
def post_entry(debit, credit, amount, description, payment=None, reference=''):
    """Create one double-entry row: move ``amount`` from ``debit`` to ``credit``.

    Args:
        debit, credit: Account instances.
        amount: positive Decimal / number.
        description: human-readable reason.
        payment: optional payments.Payment for traceability.
        reference: optional business reference (e.g. 'order:42').

    Returns the created ``LedgerEntry``.
    """
    amount = Decimal(str(amount))
    if amount <= 0:
        raise ValueError('Ledger amounts must be positive')
    if debit.id == credit.id:
        raise ValueError('Ledger debit and credit accounts must differ')
    return LedgerEntry.objects.create(
        debit=debit, credit=credit, amount=amount,
        description=description, payment=payment,
        reference=str(reference or ''),
    )


# ── Business flows (called by payments/products) ─────────────────────────
@transaction.atomic
def record_payment_collected(payment, reference=''):
    """Money arrives from the farmer via mobile money into platform escrow."""
    debit = mobile_money_account()
    credit = escrow_account()
    return post_entry(
        debit, credit, payment.amount,
        f'Collection for payment {payment.transaction_id}',
        payment=payment, reference=reference,
    )


@transaction.atomic
def settle_order(order):
    """Release escrowed funds to the dealer on fulfilment.

    Dealer is credited ``total_price - commission``; the platform fee account
    is credited the commission. Idempotent: if the order has already been
    settled (a settlement entry exists) it is a no-op.
    """
    settled = LedgerEntry.objects.filter(
        reference=f'order:{order.id}', debit__code=ESCROW_CODE,
    ).exists()
    if settled:
        return None

    escrow = escrow_account()
    dealer = dealer_account(order.product.dealer)
    fees = platform_fees_account()
    total = Decimal(str(order.total_price))
    commission = (total * Decimal(str(settings.PLATFORM_COMMISSION_RATE))).quantize(Decimal('0.01'))
    net = total - commission

    ref = f'order:{order.id}'
    entry = post_entry(escrow, dealer, net, f'Settlement of order #{order.id} to dealer', reference=ref)
    if commission > 0:
        post_entry(escrow, fees, commission, f'Platform commission on order #{order.id}', reference=ref)
    return entry


@transaction.atomic
def record_refund(payment, reference=''):
    """Reverse escrowed funds back out (refund to the farmer).

    Only valid for a completed, non-settled order payment (the settlement entry
    must not exist yet); the caller enforces that business rule.
    """
    escrow = escrow_account()
    money = mobile_money_account()
    return post_entry(
        escrow, money, payment.amount,
        f'Refund of payment {payment.transaction_id}',
        payment=payment, reference=reference,
    )


@transaction.atomic
def record_premium_income(payment, reference=''):
    """Premium subscription purchase is platform income."""
    money = mobile_money_account()
    fees = platform_fees_account()
    return post_entry(
        money, fees, payment.amount,
        f'Premium subscription {payment.transaction_id}',
        payment=payment, reference=reference,
    )
