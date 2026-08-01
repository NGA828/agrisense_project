from django.contrib import admin

from .models import Account, LedgerEntry


@admin.register(Account)
class AccountAdmin(admin.ModelAdmin):
    list_display = ('code', 'name', 'account_type', 'balance')
    search_fields = ('code', 'name')
    list_filter = ('account_type',)
    readonly_fields = ('created_at',)


@admin.register(LedgerEntry)
class LedgerEntryAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'debit', 'credit', 'amount', 'description')
    list_filter = ('debit', 'credit')
    search_fields = ('description', 'reference', 'payment__transaction_id')
    date_hierarchy = 'created_at'
    readonly_fields = ('debit', 'credit', 'amount', 'description', 'payment',
                       'reference', 'created_at')

    def has_add_permission(self, request):
        # Money only moves through the service helpers, never through the admin.
        return False

    def has_change_permission(self, request, obj=None):
        # Ledger entries are immutable once written.
        return False
