from django.contrib import admin

from .models import AuditLog


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'actor', 'category', 'action', 'target_type', 'target_id')
    list_filter = ('category', 'action')
    search_fields = ('actor__username', 'description', 'target_id')
    date_hierarchy = 'created_at'
    readonly_fields = ('actor', 'category', 'action', 'target_type', 'target_id',
                       'description', 'metadata', 'request_id', 'ip_address', 'created_at')

    def has_add_permission(self, request):
        return False  # write-only through service helpers

    def has_change_permission(self, request, obj=None):
        return False  # immutable once written
