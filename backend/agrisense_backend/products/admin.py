from django.contrib import admin
from .models import Product, Order

@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ['id_product', 'name', 'category', 'price', 'stock_quantity', 'is_available']
    list_filter = ['category', 'is_available']
    search_fields = ['name']

@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ['id', 'product', 'quantity', 'status']
    list_filter = ['status']
