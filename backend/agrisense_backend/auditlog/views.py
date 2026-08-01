from rest_framework import viewsets, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied

from .models import AuditLog
from .serializers import AuditLogSerializer


class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    """Immutable, filterable audit log (admin only)."""

    queryset = AuditLog.objects.all()
    serializer_class = AuditLogSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        if self.request.user.role != 'admin':
            return AuditLog.objects.none()
        qs = AuditLog.objects.all()
        category = self.request.query_params.get('category')
        actor = self.request.query_params.get('actor')
        if category:
            qs = qs.filter(category=category)
        if actor:
            qs = qs.filter(actor__username__icontains=actor)
        return qs

    def create(self, request, *args, **kwargs):
        raise PermissionDenied('Audit log is write-only through service helpers')

    @action(detail=False, methods=['get'])
    def summary(self, request):
        """Category counts for the audit console."""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=403)
        from django.db.models import Count
        counts = AuditLog.objects.values('category').annotate(total=Count('id'))
        return Response({c['category']: c['total'] for c in counts})
