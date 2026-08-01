import hashlib
import hmac

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.parsers import JSONParser

from .models import Payment
from .serializers import PaymentSerializer
from .gateway import get_gateway, PaymentError
from .services import complete_payment, finalize_payment_failed, refund_payment

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
        if order.status in ('cancelled', 'expired', 'delivered'):
            return Response({'error': f'Order is {order.status} and cannot be paid.'},
                            status=status.HTTP_400_BAD_REQUEST)

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

        Two-phase execution:
        1. Inside a transaction: lock the payment (+ order), validate the
           transition, and re-hold stock on a retry of a ``payment_failed`` order.
        2. Outside the transaction: call the provider gateway (the only slow /
           external part), then finalize the outcome in a fresh transaction so a
           failure releases stock and a success marks the order paid + ledged.

        Guards:
        * only the payer (or an admin) can process a payment;
        * a payment can only move from pending/failed -> processing/completed;
        * completing an order payment marks the order paid + confirmed and posts
          a ledger entry (escrow);
        * completing a premium payment activates the dealer's premium tier and
          posts a ledger entry (income);
        * failing an order payment releases the reserved stock and marks the
          order ``payment_failed`` (retryable).
        """
        # Phase 1 — validation & reservation inside a transaction.
        with transaction.atomic():
            payment = Payment.objects.select_for_update().get(pk=pk)
            if request.user.id != payment.user_id and request.user.role != 'admin':
                return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
            if payment.status not in PROCESSABLE_FROM:
                return Response(
                    {'error': f'Payment is already {payment.status} and cannot be reprocessed'},
                    status=status.HTTP_400_BAD_REQUEST)

            order = None
            if payment.payment_type == 'order' and payment.order_id:
                from products.models import Order, Product
                order = Order.objects.select_for_update().get(id=payment.order_id)
                if order.status in ('cancelled', 'expired', 'delivered') \
                        or order.payment_status == 'paid':
                    return Response(
                        {'error': f'Order is closed ({order.status}); cannot process payment.'},
                        status=status.HTTP_400_BAD_REQUEST)
                if order.status == 'payment_failed':
                    # Retry: re-reserve the stock within the reservation window,
                    # using the same row-locked product the order path uses.
                    product = Product.objects.select_for_update().get(
                        id_product=order.product_id)
                    if product.stock_quantity < order.quantity:
                        return Response(
                            {'error': f'Insufficient stock. Only {product.stock_quantity} left.'},
                            status=status.HTTP_400_BAD_REQUEST)
                    product.stock_quantity -= order.quantity
                    if product.stock_quantity == 0:
                        product.is_available = False
                    product.save(update_fields=['stock_quantity', 'is_available'])
                    order.status = 'pending'
                    order.reserved_until = timezone.now() + timezone.timedelta(
                        minutes=settings.ORDER_RESERVATION_MINUTES)
                    order.save(update_fields=['status', 'reserved_until'])

        # Phase 2 — external provider call (kept outside the DB transaction).
        gateway = get_gateway(payment.payment_method)
        try:
            result = gateway.request_payment(
                amount=float(payment.amount),
                phone_number=payment.phone_number,
                description=payment.description or '',
                transaction_id=payment.transaction_id,
            )
        except PaymentError as exc:
            finalize_payment_failed(payment.pk, provider_error=str(exc))
            return Response({'error': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

        new_status = result.get('status', 'processing')
        if new_status not in ('completed', 'failed', 'processing', 'pending'):
            new_status = 'processing'

        if new_status == 'failed':
            payment = finalize_payment_failed(payment.pk)
        elif new_status == 'completed':
            payment = complete_payment(payment.pk)
        else:
            with transaction.atomic():
                payment = Payment.objects.select_for_update().get(pk=payment.pk)
                payment.status = new_status
                payment.save(update_fields=['status'])

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
            payment = complete_payment(payment.pk)
        elif provider_status == 'failed' and payment.status not in ('completed', 'refunded'):
            payment = finalize_payment_failed(payment.pk)

        return Response({'status': payment.status, 'transaction_id': payment.transaction_id})

    @action(detail=True, methods=['post'])
    def refund(self, request, pk=None):
        """Refund a completed, unsettled order payment (admin/platform only).

        Reverses the escrow ledger entry, marks the payment ``refunded``,
        returns the reserved stock, and notifies both the farmer and the dealer.
        An order that was already settled (delivered) cannot be refunded through
        this endpoint because the dealer's funds would need clawing back.
        """
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

        try:
            payment = refund_payment(pk)
        except ValueError as exc:
            return Response({'error': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

        from auditlog.services import log_action
        log_action(
            request.user, 'refund_payment', category='payment',
            target_type='payment', target_id=payment.transaction_id,
            description=f'Refunded payment {payment.transaction_id} ({payment.amount:.2f} FCFA)',
            metadata={'order_id': payment.order_id}, request=request,
        )
        return Response({'status': 'refunded',
                         'transaction_id': payment.transaction_id,
                         'message': 'Payment refunded and ledger reversed.'})

    @action(detail=False, methods=['get'])
    def my_payments(self, request):
        payments = Payment.objects.filter(user=request.user).order_by('-created_at')
        serializer = self.get_serializer(payments, many=True)
        return Response(serializer.data)

@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def payment_webhook(request):
    """Provider webhook callback (real MTN/Orange integration).

    Providers call this server-to-server with an event for a ``transaction_id``.
    The request must carry an ``X-Signature`` header equal to an HMAC-SHA256 of
    the raw body signed with ``settings.PAYMENT_WEBHOOK_SECRET``.

    Handling is idempotent: processing an already-final transaction is a no-op.
    """
    raw_body = request.body
    signature = request.META.get('HTTP_X_SIGNATURE', '') or \
        request.META.get('HTTP_X_WEBHOOK_SIGNATURE', '')
    if not signature:
        return Response({'error': 'Missing signature header'}, status=status.HTTP_400_BAD_REQUEST)

    expected = hmac.new(
        settings.PAYMENT_WEBHOOK_SECRET.encode('utf-8'),
        raw_body, hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(signature, expected):
        return Response({'error': 'Invalid signature'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        import json
        payload = json.loads(raw_body)
    except (ValueError, TypeError):
        return Response({'error': 'Malformed payload'}, status=status.HTTP_400_BAD_REQUEST)

    txn = payload.get('transaction_id') or payload.get('externalId')
    event = (payload.get('status') or payload.get('event') or '').lower()
    if not txn:
        return Response({'error': 'transaction_id required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        payment = Payment.objects.select_for_update().get(transaction_id=txn)
    except Payment.DoesNotExist:
        return Response({'error': 'Unknown transaction'}, status=status.HTTP_404_NOT_FOUND)

    with transaction.atomic():
        if event in ('completed', 'success', 'paid'):
            complete_payment(payment.pk)
        elif event in ('failed', 'rejected', 'cancelled'):
            finalize_payment_failed(payment.pk)

    return Response({'status': 'ok'})
