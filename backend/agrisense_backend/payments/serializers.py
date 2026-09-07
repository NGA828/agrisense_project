from rest_framework import serializers
from .models import Payment


class PaymentSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()
    is_test = serializers.BooleanField(read_only=True)

    class Meta:
        model = Payment
        fields = ['id', 'order', 'user', 'user_name', 'amount', 'payment_method',
                  'payment_type', 'phone_number', 'transaction_id', 'status',
                  'description', 'provider_reference', 'gateway_environment', 'last_error',
                  'submitted_at', 'is_test', 'created_at', 'updated_at']
        read_only_fields = ['id', 'user', 'transaction_id', 'status', 'payment_type',
                            'created_at', 'updated_at', 'provider_reference', 'gateway_environment',
                            'submitted_at', 'last_error', 'is_test']

    def get_user_name(self, obj):
        if not obj.user:
            return ""
        name = f"{obj.user.first_name} {obj.user.last_name}".strip()
        return name or getattr(obj.user, 'username', '') or getattr(obj.user, 'email', '')

    def create(self, validated_data):
        import uuid
        validated_data['user'] = self.context['request'].user
        validated_data['transaction_id'] = f"TXN-{uuid.uuid4().hex[:12].upper()}"
        return super().create(validated_data)
