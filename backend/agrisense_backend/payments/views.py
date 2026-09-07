import hashlib
import hmac
import json
import uuid
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from rest_framework import viewsets, permissions
from rest_framework.response import Response
from rest_framework.decorators import (
    action, api_view, permission_classes, authentication_classes,
)
from rest_framework.parsers import JSONParser

from .models import Payment
from .serializers import PaymentSerializer
from .gateway import get_gateway, payment_methods, PaymentError, PREMIUM_PRICE_PER_MONTH
from .services import (
    process_collection, reconcile_payment, complete_payment,
    finalize_payment_failed, refund_payment, _premium_months,
)


def payment_result(payment):
    messages = {
        'pending': 'Payment is ready to submit.',
        'processing': 'Approve the payment on your phone. Awaiting confirmation; do not pay again.',
        'completed': ('Test payment confirmed. No money was transferred.' if payment.is_test
                      else 'Payment confirmed. Your order has been sent to the dealer.'),
        'failed': 'Payment was not completed. No order was sent to the dealer. You may retry.',
        'review_required': 'Funds were received but this order needs support review. Do not pay again.',
        'refunded': 'Refund recorded.',
    }
    return {'id': payment.pk, 'status': payment.status, 'order': payment.order_id,
            'amount': str(payment.amount),
            'duration_months': _premium_months(payment.description) if payment.payment_type == 'premium' else None,
            'transaction_id': payment.transaction_id,
            'provider_reference': str(payment.provider_reference),
            'gateway_environment': payment.gateway_environment, 'is_test': payment.is_test,
            'message': payment.last_error or messages.get(payment.status, 'Check payment status.'),
            'last_error': payment.last_error}


class PaymentViewSet(viewsets.ModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    permission_classes = [permissions.IsAuthenticated]
    parser_classes = [JSONParser]
    # Amount, owner, method and order must be immutable once an attempt starts.
    http_method_names = ['get', 'post', 'head', 'options']

    def get_queryset(self):
        return Payment.objects.all() if self.request.user.role == 'admin' else Payment.objects.filter(user=self.request.user)

    @action(detail=False, methods=['get'])
    def methods(self, request):
        return Response({'methods': payment_methods(),
                         'premium_price_per_month': str(PREMIUM_PRICE_PER_MONTH)})

    @transaction.atomic
    def create(self, request, *args, **kwargs):
        from products.models import Order
        try:
            order_id = int(request.data.get('order'))
        except (TypeError, ValueError):
            return Response({'error': 'A valid order is required.'}, status=400)
        order = get_object_or_404(Order.objects.select_for_update(), pk=order_id)
        if order.farmer_id != request.user.pk:
            return Response({'error': 'You cannot pay for another user\'s order.'}, status=403)
        try:
            amount = Decimal(str(request.data.get('amount')))
            if not amount.is_finite() or amount <= 0 or amount != order.total_price:
                raise ValueError
        except (InvalidOperation, TypeError, ValueError):
            return Response({'error': f'Amount must exactly match the order total ({order.total_price:.2f}).'}, status=400)

        # Serialised by the order lock. Retries after a lost HTTP response return
        # the same in-flight attempt, never issue a new charge/reference.
        existing = order.payments.filter(status__in=(
            'pending', 'processing', 'completed', 'review_required')).order_by('-created_at').first()
        if existing and existing.status != 'pending':
            return Response(self.get_serializer(existing).data, status=200)
        if order.payment_status != 'unpaid' or order.status not in ('pending', 'payment_failed'):
            return Response({'error': f'Order is closed ({order.status}) and cannot be paid.'}, status=400)
        method = str(request.data.get('payment_method') or '').upper()
        try:
            gateway = get_gateway(method)
            phone = gateway.validate_phone(request.data.get('phone_number'))
        except PaymentError as exc:
            return Response({'error': str(exc), 'code': exc.code}, status=400)
        if existing:
            # Not yet submitted: a farmer may correct their number or method.
            existing.phone_number = phone
            existing.payment_method = method
            existing.gateway_environment = gateway.environment
            existing.save(update_fields=['phone_number', 'payment_method', 'gateway_environment', 'updated_at'])
            return Response(self.get_serializer(existing).data, status=200)
        payment = Payment.objects.create(
            order=order, user=request.user, amount=order.total_price,
            payment_method=method, phone_number=phone, payment_type='order',
            transaction_id=f'TXN-{uuid.uuid4().hex.upper()}',
            gateway_environment=gateway.environment,
            description=f'Order #{order.pk} - {order.product.name} x{order.quantity}',
        )
        return Response(self.get_serializer(payment).data, status=201)

    @action(detail=True, methods=['post'])
    def process_payment(self, request, pk=None):
        payment = self.get_object()  # scoped ownership and clean 404, before locking
        try:
            payment = process_collection(payment.pk, expected_amount=request.data.get('expected_amount'))
        except ValueError as exc:
            return Response({'error': str(exc), 'code': 'invalid_payment_transition'}, status=400)
        return Response(payment_result(payment))

    @action(detail=True, methods=['get'])
    def verify(self, request, pk=None):
        payment = reconcile_payment(self.get_object().pk)
        return Response(payment_result(payment))

    @action(detail=True, methods=['post'])
    def refund(self, request, pk=None):
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=403)
        payment = self.get_object()
        try:
            payment = refund_payment(payment.pk)
        except ValueError as exc:
            return Response({'error': str(exc)}, status=400)
        from auditlog.services import log_action
        log_action(request.user, 'refund_payment', category='payment', target_type='payment',
                   target_id=payment.transaction_id, description='Test refund recorded',
                   metadata={'order_id': payment.order_id}, request=request)
        return Response(payment_result(payment))

    @action(detail=False, methods=['get'])
    def my_payments(self, request):
        return Response(self.get_serializer(Payment.objects.filter(user=request.user), many=True).data)


def _callback_payment(payload):
    if not isinstance(payload, dict):
        return None
    txn = payload.get('transaction_id') or payload.get('externalId')
    if not isinstance(txn, str) or not txn or len(txn) > 100:
        return None
    return Payment.objects.filter(transaction_id=txn).first()


@api_view(['POST'])
@authentication_classes([])
@permission_classes([permissions.AllowAny])
def payment_webhook(request):
    """Signed integration bridge. Real payments are still verified with MTN.

    The development default secret is explicitly disabled outside DEBUG.
    This is NOT MTN's native callback protocol; see payment_mtn_callback.
    """
    secret = settings.PAYMENT_WEBHOOK_SECRET
    if not secret or (not settings.DEBUG and (secret == 'dev-webhook-secret' or len(secret) < 32)):
        return Response({'error': 'Webhook is not configured.'}, status=503)
    signature = request.headers.get('X-Signature') or request.headers.get('X-Webhook-Signature', '')
    expected = hmac.new(secret.encode(), request.body, hashlib.sha256).hexdigest()
    if not signature or not hmac.compare_digest(signature, expected):
        return Response({'error': 'Invalid signature'}, status=400)
    try:
        payload = json.loads(request.body)
    except (ValueError, TypeError):
        return Response({'error': 'Malformed payload'}, status=400)
    payment = _callback_payment(payload)
    if payment is None:
        return Response({'error': 'Unknown transaction'}, status=404)
    if payment.gateway_environment == 'simulated' and settings.DEBUG and settings.PAYMENT_SIMULATOR_ENABLED:
        event = str(payload.get('status') or payload.get('event') or '').lower()
        if event in ('completed', 'successful', 'success', 'paid'):
            complete_payment(payment.pk)
        elif event in ('failed', 'rejected', 'cancelled'):
            finalize_payment_failed(payment.pk)
    else:
        reconcile_payment(payment.pk)
    return Response({'status': 'ok'})


@api_view(['POST', 'PUT'])
@authentication_classes([])
@permission_classes([permissions.AllowAny])
def payment_mtn_callback(request):
    """MTN notification is only a hint: authenticate a status GET to MTN.

    Never trust the callback's SUCCESSFUL text, amount or caller. A forged
    callback cannot mark an order paid. Periodic reconciliation handles missed
    callbacks, and sandbox uses polling without requiring a callback.
    """
    payment = _callback_payment(request.data)
    if payment is None or payment.payment_method != 'MTN_MOMO' or payment.gateway_environment == 'simulated':
        return Response({'error': 'Unknown transaction'}, status=404)
    reconcile_payment(payment.pk)
    return Response({'status': 'ok'})
