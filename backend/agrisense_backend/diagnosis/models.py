from django.db import models
from django.conf import settings


class Diagnosis(models.Model):
    id = models.CharField(max_length=50, primary_key=True, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='diagnoses')
    crop_type = models.CharField(max_length=100)
    image = models.ImageField(upload_to='diagnosis_images/', null=True, blank=True)
    symptoms = models.TextField(blank=True, default='')
    confidence = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    disease_name = models.CharField(max_length=200, blank=True, default='Unknown')
    severity = models.CharField(max_length=20, choices=[
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High'),
        ('unknown', 'Unknown')
    ], default='low')
    is_healthy = models.BooleanField(default=False)
    is_inconclusive = models.BooleanField(default=False)
    causes = models.TextField(blank=True, default='')
    prevention = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    location = models.ForeignKey('Location', on_delete=models.SET_NULL, null=True, blank=True, related_name='diagnoses')

    def __str__(self):
        return f"{self.disease_name} - {self.user.email}"

    class Meta:
        db_table = 'diagnosis'
        ordering = ['-created_at']


class Location(models.Model):
    longitude = models.FloatField()
    latitude = models.FloatField()
    address = models.CharField(max_length=255)
    climate_zone = models.CharField(max_length=100, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.address} ({self.latitude}, {self.longitude})"

    class Meta:
        db_table = 'location'


class TreatmentPlan(models.Model):
    diagnosis = models.OneToOneField(Diagnosis, on_delete=models.CASCADE, related_name='treatment_plan')
    treatment_type = models.CharField(max_length=100, blank=True, default='')
    medication = models.TextField(blank=True, default='')
    instructions = models.TextField(blank=True, default='')
    duration = models.IntegerField(default=14, help_text="Duration in days")
    follow_up_date = models.DateField(null=True, blank=True)
    status = models.CharField(max_length=20, default='active', choices=[
        ('active', 'Active'),
        ('completed', 'Completed'),
        ('cancelled', 'Cancelled')
    ])
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Treatment for {self.diagnosis.disease_name}"

    class Meta:
        db_table = 'treatment_plan'


class OutbreakAlert(models.Model):
    """A detected, growing disease cluster (predictive outbreak alerting).

    Created by the ``detect_outbreak_alerts`` service / Celery task when the
    number of diagnoses for a disease in a geographic bucket grows significantly
    vs. the previous window. Used to proactively warn nearby farmers and for the
    admin outbreak console. Re-notification is throttled by ``cooldown_until``.
    """
    STATUS_CHOICES = (
        ('active', 'Active'),
        ('notified', 'Notified'),
        ('expired', 'Expired'),
    )

    disease_name = models.CharField(max_length=200)
    crop_name = models.CharField(max_length=100, blank=True, default='')
    latitude = models.FloatField()
    longitude = models.FloatField()
    radius_km = models.IntegerField(default=50)
    cluster_size = models.IntegerField(default=0)      # current window count
    previous_size = models.IntegerField(default=0)     # prior window count
    notified_users = models.IntegerField(default=0)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    cooldown_until = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.disease_name} @ ({self.latitude:.1f},{self.longitude:.1f}) x{self.cluster_size}'

    class Meta:
        db_table = 'outbreak_alert'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', '-created_at'], name='idx_outbreak_status'),
            models.Index(fields=['disease_name', 'latitude', 'longitude'],
                         name='idx_outbreak_disease_loc'),
        ]


class Disease(models.Model):
    disease_name = models.CharField(max_length=200)
    crop_name = models.CharField(max_length=100)
    pathogen = models.CharField(max_length=200, blank=True, default='')
    symptoms = models.TextField(blank=True, default='')
    causes = models.TextField(blank=True, default='')
    severity = models.CharField(max_length=20, choices=[
        ('low', 'Low'),
        ('medium', 'Medium'),
        ('high', 'High')
    ], default='low')
    prevention = models.TextField(blank=True, default='')
    treatment_type = models.CharField(max_length=100, blank=True, default='')
    medication = models.TextField(blank=True, default='')
    instructions = models.TextField(blank=True, default='')
    duration = models.IntegerField(default=14, help_text="Duration in days")
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='created_diseases', null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.disease_name} ({self.crop_name})"

    class Meta:
        db_table = 'disease'
        ordering = ['disease_name']