from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action
from .models import Payment
from .serializers import PaymentSerializer


class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            return Payment.objects.all()
        return Payment.objects.filter(user=user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=['post'])
    def process_payment(self, request, pk=None):
        payment = self.get_object()

        # Simulate payment processing - in real app, integrate MTN MoMo / Orange Money API
        import uuid
        payment.transaction_id = f"TXN-{uuid.uuid4().hex[:12].upper()}"
        payment.status = 'completed'
        payment.save()

        # Update related order status if exists
        if payment.order:
            payment.order.payment_status = 'paid'
            payment.order.status = 'confirmed'
            payment.order.save()

        return Response({
            'status': 'completed',
            'transaction_id': payment.transaction_id,
            'message': 'Payment processed successfully'
        })

    @action(detail=False, methods=['get'])
    def my_payments(self, request):
        payments = Payment.objects.filter(user=request.user).order_by('-created_at')
        serializer = self.get_serializer(payments, many=True)
        return Response(serializer.data)
