from rest_framework import serializers
from .models import Payment


class PaymentSerializer(serializers.ModelSerializer):
    user_name = serializers.CharField(source='user.get_full_name', read_only=True)

    class Meta:
        model = Payment
        fields = ['id', 'order', 'user', 'user_name', 'amount', 'payment_method',
                  'phone_number', 'transaction_id', 'status', 'description',
                  'created_at', 'updated_at']
        read_only_fields = ['id', 'user', 'transaction_id', 'status', 'created_at', 'updated_at']

    def create(self, validated_data):
        import uuid
        validated_data['user'] = self.context['request'].user
        validated_data['transaction_id'] = f"TXN-{uuid.uuid4().hex[:12].upper()}"
        return super().create(validated_data)
