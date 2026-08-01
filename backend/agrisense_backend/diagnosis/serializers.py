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


class DiagnosisSerializer(serializers.ModelSerializer):
    user_email = serializers.EmailField(source='user.email', read_only=True)
    location_data = LocationSerializer(source='location', read_only=True)
    treatment_plan = TreatmentPlanSerializer(read_only=True)

    class Meta:
        model = Diagnosis
        fields = ['id', 'user', 'user_email', 'crop_type', 'image', 'symptoms',
                  'confidence', 'disease_name', 'severity', 'is_healthy',
                  'is_inconclusive', 'causes', 'prevention',
                  'created_at', 'location', 'location_data', 'treatment_plan']
        read_only_fields = ['user', 'confidence', 'disease_name', 'symptoms', 'severity']
