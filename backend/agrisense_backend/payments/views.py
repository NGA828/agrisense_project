from datetime import timedelta

from django.utils import timezone
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action
from rest_framework.parsers import JSONParser

from .models import Payment
from .serializers import PaymentSerializer
from .gateway import get_gateway, PaymentError

# Payment statuses from which a payment may transition into processing/completed.
PROCESSABLE_FROM = {'pending', 'failed'}


class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [JSONParser]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            return Payment.objects.all()
        return Payment.objects.filter(user=user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    def create(self, request, *args, **kwargs):
        """Create a payment. Validates amount against the linked order and
        enforces that only the order's farmer can pay for it."""
        data = request.data.copy()

        order_id = data.get('order')
        if order_id is None:
            return Response({'error': 'order is required'}, status=status.HTTP_400_BAD_REQUEST)

        from products.models import Order
        try:
            order = Order.objects.select_related('product').get(id=order_id)
        except Order.DoesNotExist:
            return Response({'error': 'Order not found'}, status=status.HTTP_400_BAD_REQUEST)

        if order.farmer_id != request.user.id:
            return Response({'error': 'You cannot pay for another user\'s order'},
                            status=status.HTTP_403_FORBIDDEN)
        if order.payment_status == 'paid':
            return Response({'error': 'Order is already paid'}, status=status.HTTP_400_BAD_REQUEST)

        amount = data.get('amount')
        try:
            amount = float(amount)
        except (TypeError, ValueError):
            return Response({'error': 'amount is required and must be a number'},
                            status=status.HTTP_400_BAD_REQUEST)

        # Server-side price integrity: the client cannot pay a different amount.
        expected = float(order.total_price)
        if abs(amount - expected) > 0.005:
            return Response({'error': f'Amount must match the order total ({expected:.2f})'},
                            status=status.HTTP_400_BAD_REQUEST)

        method = (data.get('payment_method') or '').upper()
        valid_methods = {c[0] for c in Payment.PAYMENT_TYPE_CHOICES}
        if method not in valid_methods:
            return Response({'error': f'payment_method must be one of {sorted(valid_methods)}'},
                            status=status.HTTP_400_BAD_REQUEST)

        phone = str(data.get('phone_number') or '').strip()
        if not phone:
            return Response({'error': 'phone_number is required for mobile money'},
                            status=status.HTTP_400_BAD_REQUEST)

        payment = Payment.objects.create(
            order=order,
            user=request.user,
            amount=order.total_price,
            payment_method=method,
            phone_number=phone,
            payment_type='order',
            transaction_id=f'TXN-{__import__("uuid").uuid4().hex[:12].upper()}',
            status='pending',
            description=f'Order #{order.id} - {order.product.name} x{order.quantity}',
        )
        serializer = self.get_serializer(payment)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def process_payment(self, request, pk=None):
        """Initiate collection with the provider gateway and finalize the payment.

        Guards:
        * only the payer (or an admin) can process a payment;
        * a payment can only move from pending/failed -> processing/completed;
        * completing an order payment marks the order paid + confirmed;
        * completing a premium payment activates the dealer's premium tier.
        """
        payment = self.get_object()
        if request.user.id != payment.user_id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        if payment.status not in PROCESSABLE_FROM:
            return Response({'error': f'Payment is already {payment.status} and cannot be reprocessed'},
                            status=status.HTTP_400_BAD_REQUEST)

        gateway = get_gateway(payment.payment_method)
        try:
            result = gateway.request_payment(
                amount=float(payment.amount),
                phone_number=payment.phone_number,
                description=payment.description or '',
                transaction_id=payment.transaction_id,
            )
        except PaymentError as exc:
            payment.status = 'failed'
            payment.save(update_fields=['status'])
            return Response({'error': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

        new_status = result.get('status', 'processing')
        if new_status not in ('completed', 'failed', 'processing', 'pending'):
            new_status = 'processing'
        payment.status = new_status
        payment.save(update_fields=['status'])

        if new_status == 'completed':
            self._on_completed(payment)

        return Response({
            'status': payment.status,
            'transaction_id': payment.transaction_id,
            'provider': result.get('provider', gateway.provider),
            'provider_reference': result.get('provider_reference'),
            'message': 'Payment processed successfully' if payment.status == 'completed'
                       else 'Payment is being processed',
        })

    @action(detail=True, methods=['get'])
    def verify(self, request, pk=None):
        """Poll the provider for the final transaction state (webhook-ready)."""
        payment = self.get_object()
        gateway = get_gateway(payment.payment_method)
        if gateway.provider == 'sandbox':
            # Sandbox finalizes synchronously; the persisted status is truth.
            return Response({'status': payment.status, 'transaction_id': payment.transaction_id})

        try:
            provider_status = gateway.verify_transaction(payment.transaction_id)
        except PaymentError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

        if provider_status == 'completed' and payment.status != 'completed':
            payment.status = 'completed'
            payment.save(update_fields=['status'])
            self._on_completed(payment)
        elif provider_status == 'failed' and payment.status not in ('completed', 'refunded'):
            payment.status = 'failed'
            payment.save(update_fields=['status'])

        return Response({'status': payment.status, 'transaction_id': payment.transaction_id})

    @action(detail=False, methods=['get'])
    def my_payments(self, request):
        payments = Payment.objects.filter(user=request.user).order_by('-created_at')
        serializer = self.get_serializer(payments, many=True)
        return Response(serializer.data)

    # ── helpers ───────────────────────────────────────────────────────
    def _on_completed(self, payment):
        from announcements.models import notify_user

        if payment.payment_type == 'premium' and payment.user.role == 'dealer':
            months = self._premium_months(payment.description)
            user = payment.user
            base = user.premium_expiry if (user.is_premium and user.premium_expiry and
                                           user.premium_expiry > timezone.now()) else timezone.now()
            user.is_premium = True
            user.premium_expiry = base + timedelta(days=30 * months)
            user.save(update_fields=['is_premium', 'premium_expiry'])
            notify_user(
                user,
                'Premium activated 🚀',
                f'Your premium dealer subscription is active until '
                f'{user.premium_expiry.strftime("%d %b %Y")}. Your products now rank '
                f'higher in farmer searches.',
                type='premium',
            )
            return

        if payment.order:
            order = payment.order
            order.payment_status = 'paid'
            if order.status == 'pending':
                order.status = 'confirmed'
            order.save(update_fields=['payment_status', 'status'])
            notify_user(
                payment.user,
                'Payment successful ✅',
                f'Your payment of {payment.amount:.2f} FCFA for {order.product.name} '
                f'was confirmed. The dealer has been notified.',
                type='payment',
                reference_id=order.id,
            )
            notify_user(
                order.product.dealer,
                'Payment confirmed 💰',
                f'{payment.user.first_name or payment.user.username} paid '
                f'{payment.amount:.2f} FCFA for order #{order.id}.',
                type='payment',
                reference_id=order.id,
            )

    @staticmethod
    def _premium_months(description):
        import re
        match = re.search(r'\((\d+)\s*month', description or '')
        return max(1, int(match.group(1))) if match else 1
