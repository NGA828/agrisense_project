from rest_framework import serializers
from .models import Product, Order

class ProductSerializer(serializers.ModelSerializer):
    dealer_name = serializers.CharField(source='dealer.first_name', read_only=True)
    dealer_email = serializers.EmailField(source='dealer.email', read_only=True)
    
    class Meta:
        model = Product
        fields = '__all__'
        read_only_fields = ['dealer', 'created_at', 'updated_at']

class OrderSerializer(serializers.ModelSerializer):
    farmer_name = serializers.CharField(source='farmer.first_name', read_only=True)
    product_name = serializers.CharField(source='product.name', read_only=True)
    
    class Meta:
        model = Order
        fields = '__all__'
        read_only_fields = ['farmer', 'total_price', 'created_at', 'updated_at']