from rest_framework import serializers
from .models import Diagnosis, Location, TreatmentPlan, Disease


class LocationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Location
        fields = ['id', 'longitude', 'latitude', 'address', 'climate_zone']


class TreatmentPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = TreatmentPlan
        fields = ['id', 'diagnosis', 'treatment_type', 'medication', 'instructions',
                  'duration', 'follow_up_date', 'status', 'created_at', 'updated_at']
        read_only_fields = ['diagnosis']


class DiseaseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Disease
        fields = ['id', 'disease_name', 'crop_name', 'pathogen', 'symptoms', 'causes',
                  'severity', 'prevention', 'treatment_type', 'medication', 'instructions',
                  'duration', 'created_by', 'created_at', 'updated_at']
        read_only_fields = ['created_by', 'created_at', 'updated_at']

    def validate(self, attrs):
        """Keep the OpenRouter crop allow-list unambiguous (case-insensitive)."""
        disease_name = str(attrs.get(
            'disease_name', getattr(self.instance, 'disease_name', '')) or '').strip()
        crop_name = str(attrs.get(
            'crop_name', getattr(self.instance, 'crop_name', '')) or '').strip()
        if 'disease_name' in attrs:
            attrs['disease_name'] = disease_name
        if 'crop_name' in attrs:
            attrs['crop_name'] = crop_name
        duplicate = Disease.objects.filter(
            disease_name__iexact=disease_name,
            crop_name__iexact=crop_name,
        )
        if self.instance is not None:
            duplicate = duplicate.exclude(pk=self.instance.pk)
        if disease_name and crop_name and duplicate.exists():
            raise serializers.ValidationError({
                'disease_name': 'This disease is already reviewed for this crop.',
            })
        return attrs


class DiagnosisSerializer(serializers.ModelSerializer):
    user_email = serializers.EmailField(source='user.email', read_only=True)
    location_data = LocationSerializer(source='location', read_only=True)
    treatment_plan = TreatmentPlanSerializer(read_only=True)
    engine = serializers.CharField(source='inference_engine', read_only=True)
    trained_model = serializers.BooleanField(
        source='used_trained_model', read_only=True)

    class Meta:
        model = Diagnosis
        fields = ['id', 'user', 'user_email', 'crop_type', 'image', 'symptoms',
                  'confidence', 'disease_name', 'severity', 'is_healthy',
                  'is_inconclusive', 'causes', 'prevention', 'engine',
                  'trained_model', 'model_version', 'model_label', 'alternatives',
                  'created_at', 'location', 'location_data', 'treatment_plan']
        read_only_fields = [
            'user', 'confidence', 'disease_name', 'symptoms', 'severity',
            'is_healthy', 'is_inconclusive', 'causes', 'prevention',
            'model_version', 'model_label', 'alternatives',
        ]
