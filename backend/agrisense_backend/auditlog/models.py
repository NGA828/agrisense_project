"""Immutable audit log for admin/platform actions.

Every privileged mutation (suspend/delete/verify, premium grants, refunds,
product moderation, disease edits, broadcasts) writes an ``AuditLog`` row so
there is a complete, attributable trail of *who did what to whom and when* —
essential for a governed marketplace and for regulators.

Rows are write-only through the service helper (:func:`log_action`) and are
never editable or deletable through the API or admin.
"""

from django.conf import settings
from django.db import models


class AuditLog(models.Model):
    # Action category constants (used for filtering / UI grouping).
    ACTION_USER = 'user'          # suspend / activate / verify / delete / premium
    ACTION_PRODUCT = 'product'    # moderation (hide / remove / restore)
    ACTION_PAYMENT = 'payment'    # refund / dispute resolution
    ACTION_CONTENT = 'content'    # disease / announcement / knowledge base
    ACTION_ORDER = 'order'        # admin order intervention

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='audit_logs',
        help_text='Admin who performed the action (null for system/CLI).',
    )
    category = models.CharField(max_length=20, default=ACTION_USER)
    action = models.CharField(max_length=100)
    # What was acted upon (e.g. user id, product id, payment id...).
    target_type = models.CharField(max_length=50, blank=True, default='')
    target_id = models.CharField(max_length=100, blank=True, default='')
    # Human-readable context (e.g. "Suspended user dealer3 for fraud").
    description = models.CharField(max_length=500, blank=True, default='')
    # Structured detail (before/after, reason, request id...).
    metadata = models.JSONField(default=dict, blank=True)
    # Request-id for cross-referencing logs (see RequestIDMiddleware).
    request_id = models.CharField(max_length=50, blank=True, default='')
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.created_at:%Y-%m-%d %H:%M} {self.actor} {self.action} {self.target_type}:{self.target_id}'

    class Meta:
        db_table = 'audit_log'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['actor', '-created_at'], name='idx_audit_actor'),
            models.Index(fields=['category', '-created_at'], name='idx_audit_category'),
            models.Index(fields=['target_type', 'target_id'], name='idx_audit_target'),
        ]
