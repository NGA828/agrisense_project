from django.contrib import admin
from .models import Diagnosis, Location, TreatmentPlan, Disease, OutbreakAlert

@admin.register(Diagnosis)
class DiagnosisAdmin(admin.ModelAdmin):
    list_display = ['id', 'crop_type', 'disease_name', 'severity', 'confidence']
    search_fields = ['disease_name']

@admin.register(Location)
class LocationAdmin(admin.ModelAdmin):
    list_display = ['id', 'address']

@admin.register(TreatmentPlan)
class TreatmentPlanAdmin(admin.ModelAdmin):
    list_display = ['id', 'treatment_type', 'medication', 'status']

@admin.register(Disease)
class DiseaseAdmin(admin.ModelAdmin):
    list_display = ['disease_name', 'crop_name', 'severity', 'created_at']
    search_fields = ['disease_name', 'crop_name']
    list_filter = ['crop_name', 'severity']


@admin.register(OutbreakAlert)
class OutbreakAlertAdmin(admin.ModelAdmin):
    list_display = ['disease_name', 'crop_name', 'cluster_size', 'previous_size',
                    'notified_users', 'status', 'created_at']
    list_filter = ['status', 'crop_name']
    search_fields = ['disease_name']
