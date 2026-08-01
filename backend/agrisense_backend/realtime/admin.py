from django.contrib import admin

from .models import PushDevice


@admin.register(PushDevice)
class PushDeviceAdmin(admin.ModelAdmin):
    list_display = ('user', 'provider', 'platform', 'is_active', 'last_seen')
    list_filter = ('provider', 'platform', 'is_active')
    search_fields = ('user__username', 'token')
    readonly_fields = ('created_at', 'last_seen')
