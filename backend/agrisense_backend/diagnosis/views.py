from datetime import date, timedelta

import logging
import uuid

from django.db import models, transaction
from django.conf import settings
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser

from .models import Diagnosis, Location, TreatmentPlan, Disease
from .serializers import (DiagnosisSerializer, DiseaseSerializer)
from ai_engine.services import (AIEngineUnavailable, AIInferenceError, AIImageRejected,
                                analyze_disease)

logger = logging.getLogger('agrisense.ai')


class DiagnosisViewSet(viewsets.ReadOnlyModelViewSet):
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

    def get_throttles(self):
        # Reading history must not consume the scan throttle.
        self.throttle_scope = 'ai' if self.action == 'analyze' else None
        return super().get_throttles()

    @action(detail=False, methods=['post'])
    def analyze(self, request):
        """Validate, deduplicate, screen the selected crop, then save atomically."""
        image = request.FILES.get('image')
        if image is None:
            return Response({'error': 'No image provided', 'code': 'invalid_image'}, status=400)
        if image.size > settings.AI_MAX_UPLOAD_BYTES:
            return Response({'error': 'Photo is too large. Upload an image under 10 MB.',
                             'code': 'image_too_large'}, status=400)
        try:
            from PIL import Image as PilImage
            image.seek(0)
            parsed = PilImage.open(image)
            if (parsed.format not in {'JPEG', 'PNG', 'WEBP'}
                    or parsed.width * parsed.height > settings.AI_MAX_IMAGE_PIXELS
                    or min(parsed.size) < 32):
                raise ValueError('Unsupported image')
            parsed.verify()
        except Exception:
            return Response({'error': 'Upload a valid JPEG, PNG or WebP photo with '
                                      'a clear view of the crop.', 'code': 'invalid_image'},
                            status=400)
        finally:
            image.seek(0)

        from ai_engine.services import get_available_crops
        crop_type = str(request.data.get('crop_type') or '').strip()
        if not crop_type:
            return Response({'error': 'Please select the crop you are diagnosing.',
                             'code': 'crop_required'}, status=400)
        supported = get_available_crops()
        if not supported:
            return Response({'error': 'Crop diagnosis is not ready yet. The administrator '
                                      'needs to add reviewed crop disease data.',
                             'code': 'ai_knowledge_base_empty'}, status=503)
        matched_crop = next((c for c in supported if c.casefold() == crop_type.casefold()), None)
        if matched_crop is None:
            return Response({'error': f'"{crop_type}" is not available for analysis. '
                                      f'Choose one of: {", ".join(supported)}.',
                             'code': 'unsupported_crop'}, status=400)
        crop_type = matched_crop

        from ai_engine.cache import AnalysisLease, analysis_cache_key, cache_result
        key = analysis_cache_key(request.user.pk, image, crop_type)
        lease = None
        try:
            previous = self._cached_response(key, crop_type)
            if previous is not None:
                return previous
            lock_ttl = int(max(settings.OPENROUTER_TIMEOUT_SECONDS,
                               settings.OLLAMA_TIMEOUT_SECONDS,
                               getattr(settings, 'GROQ_TIMEOUT_SECONDS', 0))) + 30
            lease = AnalysisLease(key + ':lock', lock_ttl)
            if not lease.acquire():
                return Response({'error': 'This photo is already being analysed. Please wait '
                                          'a moment before checking again.',
                                 'code': 'analysis_in_progress'}, status=409,
                                headers={'Retry-After': '5'})
            # Another request may have completed after our first cache read but
            # before we acquired its released lease. Do not spend a second scan.
            previous = self._cached_response(key, crop_type)
            if previous is not None:
                return previous
            ai_result = analyze_disease(image, crop_type)
            from ai_engine.services import crop_key
            detected = ai_result.get('detected_crop')
            if detected and crop_key(detected) != crop_key(crop_type):
                raise AIImageRejected('The model result did not match your selected crop. '
                                      'Please check the photo.', 'crop_mismatch', str(detected))
            image.seek(0)
            diagnosis = self._save_analysis(request, image, crop_type, ai_result)
            cache_result(key, diagnosis.pk, settings.AI_ANALYSIS_CACHE_SECONDS)
            return Response(self.get_serializer(diagnosis).data, status=201)
        except AIImageRejected as exc:
            # No diagnosis, treatment plan, or stored image for a rejected subject.
            return Response({'error': str(exc), 'code': exc.code,
                             'selected_crop': crop_type,
                             'detected_crop': exc.detected_crop}, status=422)
        except AIEngineUnavailable as exc:
            logger.warning('AI service unavailable: %s', exc)
            messages = {
                'ai_rate_limited': 'The free AI service is busy or its shared quota has '
                                   'been reached. Please try again later.',
                'ai_timeout': 'The AI service took too long to respond. No diagnosis '
                              'was saved. Please try again shortly.',
                'ai_invalid_response': 'The AI service returned an unusable answer. '
                                       'No diagnosis was saved. Please retry shortly.',
            }
            payload = {'error': messages.get(exc.code, 'Crop analysis is temporarily '
                                           'unavailable. Please try again later.'),
                       'code': exc.code}
            if settings.DEBUG:
                payload['detail'] = str(exc)
            headers = {}
            if exc.retry_after:
                payload['retry_after'] = exc.retry_after
                headers['Retry-After'] = str(exc.retry_after)
            return Response(payload, status=429 if exc.code == 'ai_rate_limited' else 503,
                            headers=headers)
        except AIInferenceError as exc:
            logger.warning('AI inference failed: %s', exc)
            payload = {'error': 'The model could not produce a safe diagnosis. No result '
                                 'was saved; try again or ask an agronomist.',
                       'code': 'ai_inference_failed'}
            if settings.DEBUG:
                payload['detail'] = str(exc)
            return Response(payload, status=503)
        finally:
            if lease is not None:
                lease.release()

    def _cached_response(self, key, crop_type):
        from ai_engine.cache import get_cached_result_id
        cached_id = get_cached_result_id(key)
        if cached_id:
            previous = self.get_queryset().filter(pk=cached_id, crop_type=crop_type).first()
            if previous is not None:
                return Response(self.get_serializer(previous).data, status=200,
                                headers={'X-Analysis-Cached': 'true'})
        return None

    @transaction.atomic
    def _save_analysis(self, request, image, crop_type, ai_result):
        location = None
        try:
            import math
            lat, lon = float(request.data['latitude']), float(request.data['longitude'])
            if math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180:
                location, _ = Location.objects.get_or_create(
                    latitude=lat, longitude=lon,
                    defaults={'address': str(request.data.get('address', ''))[:255],
                              'climate_zone': str(request.data.get('climate_zone', ''))[:100]},
                )
        except (KeyError, TypeError, ValueError):
            pass
        diagnosis = Diagnosis.objects.create(
            id=str(uuid.uuid4()), user=request.user, crop_type=crop_type, image=image,
            symptoms=ai_result.get('symptoms', ''), confidence=ai_result['confidence'],
            disease_name=ai_result['disease_name'], severity=ai_result['severity'],
            is_healthy=ai_result.get('is_healthy', False),
            is_inconclusive=ai_result.get('is_inconclusive', ai_result.get('low_confidence', False)),
            causes=ai_result['causes'], prevention=ai_result['prevention'],
            inference_engine=ai_result.get('engine', 'unknown'),
            used_trained_model=ai_result.get('trained_model', False),
            model_version=ai_result.get('model_version', ''),
            model_label=ai_result.get('model_label', ''),
            alternatives=ai_result.get('alternatives', []),
            detected_crop=ai_result.get('detected_crop', ''),
            crop_confidence=ai_result.get('crop_confidence'),
            visual_evidence=ai_result.get('visual_evidence', []), location=location,
        )
        duration = int(ai_result.get('duration', 0))
        TreatmentPlan.objects.create(
            diagnosis=diagnosis,
            treatment_type=ai_result.get('treatment_type', 'Consult an agronomist'),
            medication=ai_result.get('medication', 'No chemical treatment recommended'),
            instructions=ai_result.get('instructions', 'Seek local agronomic advice.'),
            duration=duration, follow_up_date=date.today() + timedelta(days=duration),
        )
        return diagnosis

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
