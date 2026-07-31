from django.db import models
from django.db.models import Q
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action, api_view
from rest_framework.parsers import MultiPartParser, FormParser
from .models import Diagnosis, Location, TreatmentPlan, Disease
from .serializers import DiagnosisSerializer, LocationSerializer, TreatmentPlanSerializer, DiseaseSerializer
import uuid
from ai_engine.services import analyze_disease


class DiagnosisViewSet(viewsets.ModelViewSet):
    queryset = Diagnosis.objects.all()
    serializer_class = DiagnosisSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

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
        """Upload image and get AI analysis"""
        if 'image' not in request.FILES:
            return Response({'error': 'No image provided'}, status=status.HTTP_400_BAD_REQUEST)

        image = request.FILES['image']
        crop_type = request.data.get('crop_type', 'unknown')

        # Call AI engine
        ai_result = analyze_disease(image, crop_type)

        # Create diagnosis
        diagnosis = Diagnosis.objects.create(
            id=str(uuid.uuid4()),
            user=request.user,
            crop_type=crop_type,
            image=image,
            symptoms=ai_result['symptoms'],
            confidence=ai_result['confidence'],
            disease_name=ai_result['disease_name'],
            severity=ai_result['severity'],
            causes=ai_result['causes'],
            prevention=ai_result['prevention'],
        )

        # Create treatment plan
        from datetime import date, timedelta
        follow_up = date.today() + timedelta(days=ai_result.get('duration', 14))
        treatment = TreatmentPlan.objects.create(
            diagnosis=diagnosis,
            treatment_type=ai_result.get('treatment_type', 'Cultural Management'),
            medication=ai_result.get('medication', 'No chemical treatment recommended'),
            instructions=ai_result.get('instructions', 'Follow integrated pest management practices.'),
            duration=ai_result.get('duration', 14),
            follow_up_date=follow_up,
        )

        serializer = self.get_serializer(diagnosis)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['get'])
    def history(self, request):
        """Get user's diagnosis history"""
        diagnoses = Diagnosis.objects.filter(user=request.user).order_by('-created_at')
        serializer = self.get_serializer(diagnoses, many=True)
        return Response(serializer.data)


class DiseaseDatabaseViewSet(viewsets.ModelViewSet):
    """Admin endpoints for managing the disease database"""
    permission_classes = [permissions.IsAuthenticated]
    queryset = Disease.objects.all().order_by('crop_name', 'disease_name')
    serializer_class = DiseaseSerializer

    def get_queryset(self):
        return Disease.objects.all().order_by('crop_name', 'disease_name')

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)

    @action(detail=False, methods=['get'])
    def list_diseases(self, request):
        """List all diseases in the database"""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

        queryset = self.get_queryset()
        crop_filter = request.query_params.get('crop')
        if crop_filter:
            queryset = queryset.filter(crop_name__icontains=crop_filter)
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['get'])
    def disease_detail(self, request, pk=None):
        """Get a specific disease detail"""
        disease = self.get_object()
        serializer = self.get_serializer(disease)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def supported_crops(self, request):
        """List supported crop types"""
        crops = Disease.objects.values_list('crop_name', flat=True).distinct().order_by('crop_name')
        return Response(list(crops))

    @action(detail=False, methods=['get'])
    def search(self, request):
        """Search diseases by name or crop"""
        query = request.query_params.get('q', '')
        if not query:
            return Response([])
        results = Disease.objects.filter(
            models.Q(disease_name__icontains=query) | models.Q(crop_name__icontains=query)
        )
        serializer = self.get_serializer(results, many=True)
        return Response(serializer.data)
