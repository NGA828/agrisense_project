from django.db import models
from django.conf import settings

from ledger.services import settle_order


class Product(models.Model):
    CATEGORY_CHOICES = (
        ('fertilizer', 'Fertilizer'),
        ('seed', 'Seed'),
        ('herbicide', 'Herbicide'),
        ('pesticide', 'Pesticide'),
        ('fungicide', 'Fungicide'),
        ('equipment', 'Farm Equipment'),
    )
    
    id_product = models.AutoField(primary_key=True)
    dealer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='products')
    name = models.CharField(max_length=200)
    description = models.TextField()
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    stock_quantity = models.IntegerField(default=0)
    image = models.ImageField(upload_to='product_images/', null=True, blank=True)
    is_available = models.BooleanField(default=True)
    is_featured = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return self.name

    class Meta:
        db_table = 'product'
        ordering = ['-created_at']
        constraints = [
            models.CheckConstraint(check=models.Q(price__gte=0), name='product_price_non_negative'),
            models.CheckConstraint(check=models.Q(stock_quantity__gte=0), name='product_stock_non_negative'),
        ]
        indexes = [
            models.Index(fields=['dealer', 'is_available', '-created_at'], name='idx_product_dealer_avail'),
            models.Index(fields=['category', 'is_available'], name='idx_product_cat_avail'),
        ]

class Review(models.Model):
    """Farmer rating + comment on a product (trust signal).

    A farmer may leave at most one review per product. Reviews are scoped to
    verified purchases to keep them trustworthy, and the product's average
    rating is surfaced in the marketplace.
    """
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='reviews')
    farmer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='reviews')
    rating = models.PositiveSmallIntegerField(choices=[(i, i) for i in range(1, 6)])
    comment = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'review'
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(fields=['product', 'farmer'], name='uniq_review_product_farmer'),
            models.CheckConstraint(check=models.Q(rating__gte=1) & models.Q(rating__lte=5),
                                   name='review_rating_range'),
        ]


class ProductReport(models.Model):
    """User report of an inappropriate/fraudulent product (moderation queue)."""
    STATUS_CHOICES = (
        ('pending', 'Pending'),
        ('reviewed', 'Reviewed'),
        ('dismissed', 'Dismissed'),
        ('removed', 'Removed'),
    )
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='reports')
    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='product_reports')
    reason = models.CharField(max_length=100)
    details = models.TextField(blank=True, default='')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'product_report'
        ordering = ['-created_at']
        indexes = [models.Index(fields=['status', '-created_at'], name='idx_report_status')]


class Order(models.Model):
    # Lifecycle:
    #   pending        → stock is reserved, awaiting payment
    #   payment_failed → a payment attempt failed; stock is released, retryable
    #   confirmed      → payment received
    #   shipped        → dealer dispatched
    #   delivered      → fulfilled; settlement (ledger) released to the dealer
    #   cancelled      → before fulfilment (stock restored); if paid, refunded
    #   expired        → reservation window lapsed unpaid (reconciler)
    STATUS_CHOICES = (
        ('pending', 'Pending'),
        ('payment_failed', 'Payment failed'),
        ('confirmed', 'Confirmed'),
        ('shipped', 'Shipped'),
        ('delivered', 'Delivered'),
        ('cancelled', 'Cancelled'),
        ('expired', 'Expired'),
    )
    PAYMENT_STATUS_CHOICES = (
        ('unpaid', 'Unpaid'),
        ('paid', 'Paid'),
        ('refunded', 'Refunded'),
    )
    # Statuses in which the order is NOT holding stock (stock released).
    STOCK_RELEASED_STATUSES = ('payment_failed', 'cancelled', 'expired', 'delivered')
    # Statuses in which a farmer may cancel without a refund.
    CANCEL_NO_REFUND_STATUSES = ('pending', 'payment_failed', 'expired')

    id = models.AutoField(primary_key=True)
    farmer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='orders')
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='orders')
    quantity = models.IntegerField(default=1)
    total_price = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    shipping_address = models.TextField(blank=True, default='')
    payment_method = models.CharField(max_length=50, blank=True, default='')
    payment_status = models.CharField(max_length=20, choices=PAYMENT_STATUS_CHOICES, default='unpaid')
    # While the order is 'pending' this is when the stock reservation expires.
    # Set at creation; extended on a payment retry; cleared once released.
    reserved_until = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Order {self.id} - {self.farmer.email}"

    def is_reservation_active(self):
        from django.utils import timezone
        return self.status == 'pending' and self.reserved_until is not None

    def hold_stock(self):
        """Re-reserve the product stock for this order (call within a lock)."""
        from django.utils import timezone
        product = self.product
        if product.stock_quantity < self.quantity:
            raise ValueError(f'Insufficient stock. Only {product.stock_quantity} left.')
        product.stock_quantity -= self.quantity
        if product.stock_quantity == 0:
            product.is_available = False
        product.save(update_fields=['stock_quantity', 'is_available'])
        self.status = 'pending'
        self.reserved_until = timezone.now() + timezone.timedelta(
            minutes=settings.ORDER_RESERVATION_MINUTES)
        self.save(update_fields=['status', 'reserved_until'])

    def release_stock(self):
        """Return the reserved stock to the product (call within a lock)."""
        product = self.product
        product.stock_quantity += self.quantity
        if product.stock_quantity > 0:
            product.is_available = True
        product.save(update_fields=['stock_quantity', 'is_available'])
        self.reserved_until = None

    def mark_delivered(self):
        """Fulfil the order and settle funds to the dealer (idempotent)."""
        if self.status != 'delivered':
            self.status = 'delivered'
            self.save(update_fields=['status'])
            settle_order(self)

    class Meta:
        db_table = 'order'
        ordering = ['-created_at']
        constraints = [
            models.CheckConstraint(check=models.Q(quantity__gte=1), name='order_quantity_positive'),
            models.CheckConstraint(check=models.Q(total_price__gte=0), name='order_total_non_negative'),
        ]
        indexes = [
            models.Index(fields=['farmer', '-created_at'], name='idx_order_farmer'),
            models.Index(fields=['product', '-created_at'], name='idx_order_product'),
            models.Index(fields=['status', 'reserved_until'], name='idx_order_status_reserved'),
        ]