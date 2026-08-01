"""
Ledger & settlement — double-entry accounting for the AgriSense marketplace.

This app records every movement of money so that:

* no collected payment can be "lost" (each has a full debit/credit trail),
* dealer balances are derived, never stored redundantly,
* refunds and platform commissions are auditable,
* the "where did the money go?" question has a definitive, immutable answer.

Ledger primitives
-----------------
``Account``       — a named bucket of value. Non-user system accounts (escrow,
                    mobile-money clearing, platform fees) have ``owner=None``;
                    dealer/farmer balances have an owner FK.
``LedgerEntry``   — one immutable double-entry row: money moves from a debit
                    account to a credit account. The sum of all debits always
                    equals the sum of all credits across the whole ledger (each
                    ``post_entry`` creates one row with a non-zero amount and
                    distinct debit/credit accounts).

Business rules encoded here (via :mod:`ledger.services`):
    payment completed   → MOBILE_MONEY → ESCROW
    order delivered     → ESCROW → DEALER:{id} (net of commission) + PLATFORM_FEES
    order refunded      → ESCROW → MOBILE_MONEY
    premium purchased   → MOBILE_MONEY → PLATFORM_FEES

All posting helpers are wrapped in ``transaction.atomic`` and are therefore
safe to call from within an existing outer transaction.
"""

from django.conf import settings
from django.db import models


class Account(models.Model):
    ACCOUNT_TYPE_CHOICES = (
        ('external', 'External clearing (mobile money)'),
        ('escrow', 'Platform escrow'),
        ('dealer', 'Dealer balance'),
        ('farmer', 'Farmer balance'),
        ('platform', 'Platform fee / income'),
    )

    code = models.CharField(max_length=50, unique=True)
    name = models.CharField(max_length=200)
    account_type = models.CharField(max_length=20, choices=ACCOUNT_TYPE_CHOICES)
    # System accounts have no owner. Dealer/farmer balances link to the user.
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        null=True, blank=True, related_name='ledger_accounts',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.code} ({self.name})'

    class Meta:
        db_table = 'ledger_account'
        ordering = ['code']

    @property
    def balance(self):
        """Current balance = total credits - total debits."""
        credits = self.credit_entries.aggregate(s=models.Sum('amount'))['s'] or 0
        debits = self.debit_entries.aggregate(s=models.Sum('amount'))['s'] or 0
        return credits - debits


class LedgerEntry(models.Model):
    # Money flows out of the debit account and into the credit account.
    debit = models.ForeignKey(Account, on_delete=models.PROTECT, related_name='debit_entries')
    credit = models.ForeignKey(Account, on_delete=models.PROTECT, related_name='credit_entries')
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    description = models.CharField(max_length=255)
    # Optional linkage for traceability (payment / order / refund).
    payment = models.ForeignKey(
        'payments.Payment', on_delete=models.SET_NULL,
        null=True, blank=True, related_name='ledger_entries',
    )
    reference = models.CharField(max_length=100, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return (f'{self.amount:.2f} {self.debit.code} → {self.credit.code} '
                f'({self.description})')

    class Meta:
        db_table = 'ledger_entry'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['debit', '-created_at'], name='idx_ledger_debit'),
            models.Index(fields=['credit', '-created_at'], name='idx_ledger_credit'),
            models.Index(fields=['payment'], name='idx_ledger_payment'),
        ]
