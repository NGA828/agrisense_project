"""Audit log service helper — the only supported way to write audit entries."""

from .models import AuditLog


def log_action(actor, action, category=AuditLog.ACTION_USER, target_type='',
               target_id='', description='', metadata=None, request=None):
    """Record a privileged action in the immutable audit log.

    Args:
        actor: the User who performed the action (or None for system/CLI).
        action: short verb, e.g. 'suspend', 'verify_dealer', 'refund'.
        category: one of AuditLog.ACTION_* constants.
        target_type/target_id: what was acted upon.
        description: human-readable summary.
        metadata: optional dict of structured context.
        request: optional DRF request (captures request-id + IP).
    """
    request_id = ''
    ip_address = None
    if request is not None:
        request_id = getattr(request, 'request_id', '') or ''
        ip_address = getattr(request, 'META', {}).get('REMOTE_ADDR', None)

    return AuditLog.objects.create(
        actor=actor if actor and actor.is_authenticated else None,
        category=category,
        action=action,
        target_type=target_type,
        target_id=str(target_id or ''),
        description=description[:500],
        metadata=metadata or {},
        request_id=request_id,
        ip_address=ip_address,
    )
