from django.db import models
from django.conf import settings

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

class Order(models.Model):
    STATUS_CHOICES = (
        ('pending', 'Pending'),
        ('confirmed', 'Confirmed'),
        ('shipped', 'Shipped'),
        ('delivered', 'Delivered'),
        ('cancelled', 'Cancelled'),
    )
    
    id = models.AutoField(primary_key=True)
    farmer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='orders')
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='orders')
    quantity = models.IntegerField(default=1)
    total_price = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    shipping_address = models.TextField(blank=True, default='')
    payment_method = models.CharField(max_length=50, blank=True, default='')
    payment_status = models.CharField(max_length=20, default='unpaid')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    def __str__(self):
        return f"Order {self.id} - {self.farmer.email}"

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
        ]