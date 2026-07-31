from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action
from .models import Announcement
from .serializers import AnnouncementSerializer

class AnnouncementViewSet(viewsets.ModelViewSet):
    queryset = Announcement.objects.all()
    serializer_class = AnnouncementSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            return Announcement.objects.all()
        
        # Filter by target audience
        if user.role == 'farmer':
            return Announcement.objects.filter(is_active=True, target_audience__in=['all', 'farmers'])
        elif user.role == 'dealer':
            return Announcement.objects.filter(is_active=True, target_audience__in=['all', 'dealers'])
        return Announcement.objects.filter(is_active=True, target_audience='all')

    def perform_create(self, serializer):
        if self.request.user.role != 'admin':
            raise permissions.PermissionDenied('Only admins can create announcements')
        serializer.save(created_by=self.request.user)

    def perform_update(self, serializer):
        if self.request.user.role != 'admin':
            raise permissions.PermissionDenied('Only admins can update announcements')
        serializer.save()

    def perform_destroy(self, instance):
        if self.request.user.role != 'admin':
            raise permissions.PermissionDenied('Only admins can delete announcements')
        instance.delete()

    @action(detail=False, methods=['get'])
    def active(self, request):
        """Get only active announcements for the current user"""
        announcements = self.get_queryset().filter(is_active=True)
        serializer = self.get_serializer(announcements, many=True)
        return Response(serializer.data)
