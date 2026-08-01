from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class OTPRequest(models.Model):
    """One-time-password for phone-based verification (registration / reset).

    The code is stored hashed (never plaintext). A request is single-use,
    expires after ``OTP_TTL_SECONDS`` and allows a limited number of attempts.
    """
    PURPOSE_CHOICES = (
        ('register', 'Account registration'),
        ('password_reset', 'Password reset'),
    )

    phone_number = models.CharField(max_length=20, db_index=True)
    purpose = models.CharField(max_length=20, choices=PURPOSE_CHOICES, default='register')
    code_hash = models.CharField(max_length=128)  # sha256 of the code
    is_used = models.BooleanField(default=False)
    expires_at = models.DateTimeField()
    attempts = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f'{self.purpose} → {self.phone_number} (used={self.is_used})'

    class Meta:
        db_table = 'otp_request'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['phone_number', 'purpose', 'is_used'],
                         name='idx_otp_phone_purpose'),
        ]


class User(AbstractUser):
    ROLE_CHOICES = (
        ('farmer', 'Farmer'),
        ('dealer', 'Agro-input Dealer'),
        ('admin', 'Administrator'),
    )

    first_name = models.CharField(max_length=50)
    last_name = models.CharField(max_length=50)
    email = models.EmailField(unique=True)
    phone_number = models.CharField(max_length=15)
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='farmer')
    profile_photo = models.ImageField(upload_to='profile_photos/', null=True, blank=True)
    is_verified = models.BooleanField(default=False)
    is_premium = models.BooleanField(default=False)
    premium_expiry = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.role})"

    @property
    def is_premium_active(self):
        """Premium is only 'active' if not expired."""
        if not self.is_premium:
            return False
        if self.premium_expiry is None:
            return True
        return self.premium_expiry > timezone.now()

    class Meta:
        db_table = 'users'
        indexes = [
            models.Index(fields=['role', 'is_active'], name='idx_user_role_active'),
            models.Index(fields=['role', 'is_verified'], name='idx_user_role_verified'),
        ]