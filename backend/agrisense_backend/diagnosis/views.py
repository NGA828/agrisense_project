from datetime import date, timedelta

import uuid

from django.db import models
from django.conf import settings
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser

from .models import Diagnosis, Location, TreatmentPlan, Disease
from .serializers import (DiagnosisSerializer, LocationSerializer,
                          TreatmentPlanSerializer, DiseaseSerializer)
from ai_engine.services import analyze_disease


class DiagnosisViewSet(viewsets.ModelViewSet):
    queryset = Diagnosis.objects.all()
    serializer_class = DiagnosisSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]
    throttle_scope = 'ai'

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            return Diagnosis.objects.all()
        return Diagnosis.objects.filter(user=user)

    def perform_create(self, serializer):
        diagnosis_id = str(uuid.uuid4())
        serializer.save(user=self.request.user, id=diagnosis_id)

    @action(detail=False, methods=['post'])
    def analyze(self, request):
        """Upload image and get AI analysis."""
        if 'image' not in request.FILES:
            return Response({'error': 'No image provided'}, status=status.HTTP_400_BAD_REQUEST)

        image = request.FILES['image']

        # Validate the image. Trust an explicit Content-Type when present;
        # otherwise (or when the client lied) verify by parsing the header
        # with Pillow so fake uploads never reach the inference engine.
        allowed = getattr(settings, 'ALLOWED_IMAGE_TYPES', [])
        if image.content_type and image.content_type in allowed:
            is_valid_image = True
        else:
            try:
                from PIL import Image as PilImage
                image.seek(0)
                PilImage.open(image).verify()
                is_valid_image = True
                image.seek(0)
            except Exception:
                is_valid_image = False
        if not is_valid_image:
            return Response(
                {'error': 'Unsupported image. Upload a valid JPEG, PNG or WebP photo.'},
                status=status.HTTP_400_BAD_REQUEST)

        # Crop-mandatory guard (AI v2): an "unknown"/missing crop is rejected
        # rather than silently diagnosed against Tomato. Forces the farmer to
        # select the crop for an honest, relevant result.
        from ai_engine.services import get_available_crops
        crop_type = str(request.data.get('crop_type') or '').strip()
        supported = get_available_crops()
        if not crop_type:
            return Response({'error': 'Please select the crop you are diagnosing.'},
                            status=status.HTTP_400_BAD_REQUEST)
        if crop_type not in supported:
            return Response(
                {'error': f'"{crop_type}" is not a supported crop. Supported crops: '
                          f'{", ".join(supported)}.'},
                status=status.HTTP_400_BAD_REQUEST)

        symptoms_text = request.data.get('symptoms', '')

        # Call AI engine (DB knowledge base + rule-based/TF backend)
        ai_result = analyze_disease(image, crop_type)

        # Optional location binding
        location = None
        lat = request.data.get('latitude')
        lon = request.data.get('longitude')
        if lat is not None and lon is not None:
            try:
                location, _ = Location.objects.get_or_create(
                    latitude=float(lat),
                    longitude=float(lon),
                    defaults={'address': request.data.get('address', ''),
                              'climate_zone': request.data.get('climate_zone', '')},
                )
            except (TypeError, ValueError):
                location = None

        diagnosis = Diagnosis.objects.create(
            id=str(uuid.uuid4()),
            user=request.user,
            crop_type=crop_type,
            image=image,
            symptoms=ai_result.get('symptoms', symptoms_text),
            confidence=ai_result['confidence'],
            disease_name=ai_result['disease_name'],
            severity=ai_result['severity'],
            is_healthy=ai_result.get('is_healthy', False),
            is_inconclusive=ai_result.get('low_confidence', False),
            causes=ai_result['causes'],
            prevention=ai_result['prevention'],
            location=location,
        )

        duration = int(ai_result.get('duration', 14))
        follow_up = date.today() + timedelta(days=duration)
        TreatmentPlan.objects.create(
            diagnosis=diagnosis,
            treatment_type=ai_result.get('treatment_type', 'Cultural Management'),
            medication=ai_result.get('medication', 'No chemical treatment recommended'),
            instructions=ai_result.get('instructions', 'Follow integrated pest management practices.'),
            duration=duration,
            follow_up_date=follow_up,
        )

        serializer = self.get_serializer(diagnosis)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['get'])
    def history(self, request):
        """Get user's diagnosis history."""
        diagnoses = Diagnosis.objects.filter(user=request.user).order_by('-created_at')
        serializer = self.get_serializer(diagnoses, many=True)
        return Response(serializer.data)


class DiseaseDatabaseViewSet(viewsets.ModelViewSet):
    """Admin-managed disease knowledge base.

    All authenticated users may READ the database (the AI needs it, and the
    mobile content screens list it), but only admins may create/update/delete.
    """

    permission_classes = [permissions.IsAuthenticated]
    queryset = Disease.objects.all().order_by('crop_name', 'disease_name')
    serializer_class = DiseaseSerializer
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_queryset(self):
        return Disease.objects.all().order_by('crop_name', 'disease_name')

    def _admin_or_403(self):
        if self.request.user.role != 'admin':
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Admin only')

    def create(self, request, *args, **kwargs):
        self._admin_or_403()
        instance = super().create(request, *args, **kwargs)
        from auditlog.services import log_action
        log_action(request.user, 'create_disease', category='content',
                   target_type='disease', target_id=instance.data.get('id', ''),
                   description=f'Added disease "{instance.data.get("disease_name")}" '
                               f'({instance.data.get("crop_name")})', request=request)
        return instance

    def update(self, request, *args, partial=False, **kwargs):
        self._admin_or_403()
        instance = super().update(request, *args, partial=partial, **kwargs)
        from auditlog.services import log_action
        log_action(request.user, 'update_disease', category='content',
                   target_type='disease', target_id=kwargs.get('pk', ''),
                   description=f'Updated disease {instance.data.get("disease_name")}',
                   request=request)
        return instance

    def partial_update(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)

    def destroy(self, request, *args, **kwargs):
        self._admin_or_403()
        disease = self.get_object()
        from auditlog.services import log_action
        log_action(request.user, 'delete_disease', category='content',
                   target_type='disease', target_id=disease.id,
                   description=f'Deleted disease {disease.disease_name} '
                               f'({disease.crop_name})', request=request)
        return super().destroy(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

    @action(detail=False, methods=['post'])
    def add_disease(self, request):
        """Dedicated endpoint used by the mobile content-management console."""
        self._admin_or_403()
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(created_by=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['get'])
    def list_diseases(self, request):
        """List the full disease database (admin console)."""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        queryset = self.get_queryset()
        crop_filter = request.query_params.get('crop')
        search = request.query_params.get('q')
        if crop_filter:
            queryset = queryset.filter(crop_name__icontains=crop_filter)
        if search:
            queryset = queryset.filter(
                models.Q(disease_name__icontains=search) | models.Q(crop_name__icontains=search))
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['get'])
    def disease_detail(self, request, pk=None):
        """Get a specific disease detail."""
        disease = self.get_object()
        serializer = self.get_serializer(disease)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def supported_crops(self, request):
        """List supported crop types."""
        from ai_engine.services import get_available_crops
        return Response(get_available_crops())

    @action(detail=False, methods=['get'])
    def search(self, request):
        """Search diseases by name or crop."""
        query = request.query_params.get('q', '')
        if not query:
            return Response([])
        results = Disease.objects.filter(
            models.Q(disease_name__icontains=query) | models.Q(crop_name__icontains=query)
        )
        serializer = self.get_serializer(results, many=True)
        return Response(serializer.data)
