from django.db import models as _models
from rest_framework import serializers
from .models import Product, Order, Review, ProductReport


class ProductSerializer(serializers.ModelSerializer):
    dealer_name = serializers.SerializerMethodField()
    dealer_email = serializers.EmailField(source='dealer.email', read_only=True)
    dealer_phone = serializers.CharField(source='dealer.phone_number', read_only=True)
    dealer_is_verified = serializers.BooleanField(source='dealer.is_verified', read_only=True)
    dealer_is_premium = serializers.BooleanField(source='dealer.is_premium', read_only=True)
    rating_avg = serializers.SerializerMethodField()
    rating_count = serializers.SerializerMethodField()

    # Explicit boolean fields with the model's defaults.
    #
    # DRF treats multipart/form-data as "HTML input": for every boolean field
    # that is NOT present in the request, BooleanField.get_value() returns its
    # `default_empty_html` (False) instead of skipping the field. That silently
    # saved is_available=False for products created/updated through the mobile
    # app (which always uploads photos via multipart), making brand-new
    # products invisible in the marketplace. Passing `default` here rewires
    # `default_empty_html` to the model defaults so missing booleans keep their
    # intended values.
    is_available = serializers.BooleanField(required=False, default=True)
    is_featured = serializers.BooleanField(required=False, default=False)

    class Meta:
        model = Product
        fields = '__all__'
        read_only_fields = ['dealer', 'created_at', 'updated_at']

    def get_dealer_name(self, obj):
        name = f'{obj.dealer.first_name} {obj.dealer.last_name}'.strip()
        return name or obj.dealer.username

    def get_rating_avg(self, obj):
        agg = obj.reviews.aggregate(avg=_models.Avg('rating'))
        return round(agg['avg'], 1) if agg['avg'] is not None else None

    def get_rating_count(self, obj):
        return obj.reviews.count()

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


class ReviewSerializer(serializers.ModelSerializer):
    farmer_name = serializers.CharField(source='farmer.first_name', read_only=True)

    class Meta:
        model = Review
        fields = ['id', 'product', 'farmer', 'farmer_name', 'rating', 'comment',
                  'created_at', 'updated_at']
        read_only_fields = ['id', 'farmer', 'farmer_name', 'created_at', 'updated_at']

    def validate_rating(self, value):
        if value < 1 or value > 5:
            raise serializers.ValidationError('Rating must be between 1 and 5.')
        return value


class ProductReportSerializer(serializers.ModelSerializer):
    reporter_name = serializers.CharField(source='reporter.first_name', read_only=True)
    product_name = serializers.CharField(source='product.name', read_only=True)

    class Meta:
        model = ProductReport
        fields = ['id', 'product', 'product_name', 'reporter', 'reporter_name',
                  'reason', 'details', 'status', 'created_at', 'updated_at']
        read_only_fields = ['id', 'reporter', 'reporter_name', 'product_name',
                            'status', 'created_at', 'updated_at']
