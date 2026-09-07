import uuid

from django.db import models
from django.conf import settings


class Payment(models.Model):
    PAYMENT_TYPE_CHOICES = (
        ('MTN_MOMO', 'MTN Mobile Money'),
        ('ORANGE_MONEY', 'Orange Money'),
        ('CARD', 'Credit Card'),
    )

    PAYMENT_KIND_CHOICES = (
        ('order', 'Marketplace Order'),
        ('premium', 'Premium Subscription'),
    )

    id = models.AutoField(primary_key=True)
    order = models.ForeignKey('products.Order', on_delete=models.SET_NULL, null=True, blank=True, related_name='payments')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='payments')
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    payment_method = models.CharField(max_length=20, choices=PAYMENT_TYPE_CHOICES, default='MTN_MOMO')
    phone_number = models.CharField(max_length=20, blank=True, default='')
    transaction_id = models.CharField(max_length=100, unique=True)
    # Persist the UUIDv4 BEFORE contacting MTN; retries/polls use the same ID.
    provider_reference = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    gateway_environment = models.CharField(max_length=32, blank=True, default='')
    last_error = models.CharField(max_length=300, blank=True, default='')
    submitted_at = models.DateTimeField(null=True, blank=True)
    payment_type = models.CharField(max_length=20, choices=PAYMENT_KIND_CHOICES, default='order')
    status = models.CharField(max_length=20, default='pending', choices=[
        ('pending', 'Pending'),
        ('processing', 'Processing'),
        ('completed', 'Completed'),
        ('failed', 'Failed'),
        ('refunded', 'Refunded'),
        ('review_required', 'Collected - manual review required'),
    ])
    description = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def is_test(self):
        return self.gateway_environment in ('simulated', 'sandbox')

    def __str__(self):
        return f"{self.transaction_id} - {self.amount}"

    class Meta:
        db_table = 'payment'
        ordering = ['-created_at']