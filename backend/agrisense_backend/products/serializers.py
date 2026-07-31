from rest_framework import serializers
from .models import Product, Order


class ProductSerializer(serializers.ModelSerializer):
    dealer_name = serializers.SerializerMethodField()
    dealer_email = serializers.EmailField(source='dealer.email', read_only=True)
    dealer_phone = serializers.CharField(source='dealer.phone_number', read_only=True)
    dealer_is_verified = serializers.BooleanField(source='dealer.is_verified', read_only=True)
    dealer_is_premium = serializers.BooleanField(source='dealer.is_premium', read_only=True)

    class Meta:
        model = Product
        fields = '__all__'
        read_only_fields = ['dealer', 'created_at', 'updated_at']

    def get_dealer_name(self, obj):
        name = f'{obj.dealer.first_name} {obj.dealer.last_name}'.strip()
        return name or obj.dealer.username

    def validate(self, attrs):
        if 'price' in attrs and attrs['price'] < 0:
            raise serializers.ValidationError({'price': 'Price cannot be negative.'})
        if 'stock_quantity' in attrs and attrs['stock_quantity'] < 0:
            raise serializers.ValidationError({'stock_quantity': 'Stock cannot be negative.'})
        return attrs


class OrderSerializer(serializers.ModelSerializer):
    farmer_name = serializers.CharField(source='farmer.first_name', read_only=True)
    farmer_phone = serializers.CharField(source='farmer.phone_number', read_only=True)
    product_name = serializers.CharField(source='product.name', read_only=True)
    product_image = serializers.ImageField(source='product.image', read_only=True)
    dealer_id = serializers.IntegerField(source='product.dealer_id', read_only=True)
    dealer_name = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = '__all__'
        read_only_fields = ['farmer', 'total_price', 'created_at', 'updated_at']

    def get_dealer_name(self, obj):
        dealer = obj.product.dealer
        name = f'{dealer.first_name} {dealer.last_name}'.strip()
        return name or dealer.username
