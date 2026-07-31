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
    payment_type = models.CharField(max_length=20, choices=PAYMENT_KIND_CHOICES, default='order')
    status = models.CharField(max_length=20, default='pending', choices=[
        ('pending', 'Pending'),
        ('processing', 'Processing'),
        ('completed', 'Completed'),
        ('failed', 'Failed'),
        ('refunded', 'Refunded'),
    ])
    description = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.transaction_id} - {self.amount}"

    class Meta:
        db_table = 'payment'
        ordering = ['-created_at']