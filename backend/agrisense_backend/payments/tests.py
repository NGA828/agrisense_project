from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from products.models import Product, Order
from payments.models import Payment


def make_user(username, role, **kwargs):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com',
        phone_number=kwargs.pop('phone_number', '+237600000000'),
        role=role, **kwargs,
    )


class PaymentTests(APITestCase):
    def setUp(self):
        # Even final digit => sandbox payment succeeds; odd => fails.
        self.farmer = make_user('farmer1', 'farmer', phone_number='+237670000008')
        self.other = make_user('farmer2', 'farmer', phone_number='+237670000002')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=10,
        )
        self.order = Order.objects.create(
            farmer=self.farmer, product=self.product, quantity=2,
            total_price=2000,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_create_payment_validates_amount(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('payment-list'), {
            'order': self.order.id, 'amount': 1,
            'payment_method': 'MTN_MOMO', 'phone_number': '+237670000008',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_cannot_pay_for_others_order(self):
        self.auth(self.other)
        resp = self.client.post(reverse('payment-list'), {
            'order': self.order.id, 'amount': 2000,
            'payment_method': 'MTN_MOMO', 'phone_number': '+237670000002',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_successful_payment_flow(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('payment-list'), {
            'order': self.order.id, 'amount': 2000,
            'payment_method': 'MTN_MOMO', 'phone_number': '+237670000008',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        payment_id = resp.data['id']

        process = self.client.post(reverse('payment-process-payment', args=[payment_id]))
        self.assertEqual(process.status_code, status.HTTP_200_OK)
        self.assertEqual(process.data['status'], 'completed')

        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, 'paid')
        self.assertEqual(self.order.status, 'confirmed')

    def test_failed_payment_flow(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('payment-list'), {
            'order': self.order.id, 'amount': 2000,
            'payment_method': 'MTN_MOMO', 'phone_number': '+237670000009',  # odd => fail
        }, format='json')
        payment_id = resp.data['id']
        process = self.client.post(reverse('payment-process-payment', args=[payment_id]))
        self.assertEqual(process.data['status'], 'failed')
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, 'unpaid')

    def test_double_processing_guard(self):
        self.auth(self.farmer)
        payment = Payment.objects.create(
            order=self.order, user=self.farmer, amount=2000,
            payment_method='MTN_MOMO', phone_number='+237670000001',
            transaction_id='TXN-DOUBLE', status='completed',
        )
        resp = self.client.post(reverse('payment-process-payment', args=[payment.id]))
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_premium_payment_activates_premium(self):
        dealer = make_user('dealer2', 'dealer', phone_number='+237670000008')
        self.auth(dealer)
        payment = Payment.objects.create(
            order=None, user=dealer, amount=1000,
            payment_method='MTN_MOMO', phone_number='+237670000008',
            transaction_id='TXN-PREM', status='pending', payment_type='premium',
            description='Premium dealer subscription (1 month(s))',
        )
        resp = self.client.post(reverse('payment-process-payment', args=[payment.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        dealer.refresh_from_db()
        self.assertTrue(dealer.is_premium)
        self.assertIsNotNone(dealer.premium_expiry)

    def test_verify_endpoint(self):
        self.auth(self.farmer)
        payment = Payment.objects.create(
            order=self.order, user=self.farmer, amount=2000,
            payment_method='MTN_MOMO', phone_number='+237670000001',
            transaction_id='TXN-VERIFY', status='completed',
        )
        resp = self.client.get(reverse('payment-verify', args=[payment.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'completed')


class PaymentMoneyFlowTests(APITestCase):
    """Phase A: payment failure releases stock; retry re-holds; refunds reverse."""

    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer', phone_number='+237670000008')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )
        self.order = Order.objects.create(
            farmer=self.farmer, product=self.product, quantity=2,
            total_price=2000,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def place_order(self):
        """Place a real order through the API so stock is reserved correctly."""
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 2,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        return resp.data['id']

    def create_payment(self, order_id, phone):
        self.auth(self.farmer)
        resp = self.client.post(reverse('payment-list'), {
            'order': order_id, 'amount': 2000,
            'payment_method': 'MTN_MOMO', 'phone_number': phone,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        return resp.data['id']

    def test_payment_failure_releases_stock_and_marks_order(self):
        order_id = self.place_order()  # stock 5 -> 3
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)

        # odd final digit => sandbox payment fails
        payment_id = self.create_payment(order_id, '+237670000009')
        resp = self.client.post(reverse('payment-process-payment', args=[payment_id]))
        self.assertEqual(resp.data['status'], 'failed')

        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5, 'stock must be released on failure')
        order = Order.objects.get(id=order_id)
        self.assertEqual(order.status, 'payment_failed')
        self.assertEqual(order.payment_status, 'unpaid')
        self.assertIsNone(order.reserved_until)

    def test_payment_retry_reholds_stock_and_succeeds(self):
        order_id = self.place_order()
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)

        payment_id = self.create_payment(order_id, '+237670000009')
        resp = self.client.post(reverse('payment-process-payment', args=[payment_id]))
        self.assertEqual(resp.data['status'], 'failed')

        # Retry with a working phone (even final digit): stock re-held, payment succeeds.
        payment_id2 = self.create_payment(order_id, '+237670000008')
        resp = self.client.post(reverse('payment-process-payment', args=[payment_id2]))
        self.assertEqual(resp.data['status'], 'completed')

        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3, 'stock stays held after successful payment')
        order = Order.objects.get(id=order_id)
        self.assertEqual(order.payment_status, 'paid')
        self.assertEqual(order.status, 'confirmed')

    def test_cannot_pay_for_cancelled_order(self):
        order_id = self.place_order()
        self.auth(self.farmer)
        self.client.post(reverse('order-cancel', args=[order_id]))
        # Payment creation for a cancelled order is rejected outright.
        resp = self.client.post(reverse('payment-list'), {
            'order': order_id, 'amount': 2000,
            'payment_method': 'MTN_MOMO', 'phone_number': '+237670000008',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_refund_workflow_releases_stock_and_reverses_ledger(self):
        order_id = self.place_order()  # stock 5 -> 3
        payment_id = self.create_payment(order_id, '+237670000008')
        self.client.post(reverse('payment-process-payment', args=[payment_id]))
        order = Order.objects.get(id=order_id)
        self.assertEqual(order.payment_status, 'paid')

        from ledger import services as ledger
        self.assertEqual(ledger.escrow_account().balance, 2000)

        # Admin issues the refund.
        self.auth(make_user('admin1', 'admin'))
        resp = self.client.post(reverse('payment-refund', args=[payment_id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5, 'stock restored on refund')
        order.refresh_from_db()
        self.assertEqual(order.payment_status, 'refunded')
        self.assertEqual(order.status, 'cancelled')
        self.assertEqual(ledger.escrow_account().balance, 0, 'escrow reversed on refund')

    def test_refund_requires_admin(self):
        order_id = self.place_order()
        payment_id = self.create_payment(order_id, '+237670000008')
        self.client.post(reverse('payment-process-payment', args=[payment_id]))
        self.auth(self.farmer)
        resp = self.client.post(reverse('payment-refund', args=[payment_id]))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)


class PaymentWebhookTests(APITestCase):
    """HMAC-signed, idempotent provider webhook endpoint."""

    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )
        self.order = Order.objects.create(
            farmer=self.farmer, product=self.product, quantity=1,
            total_price=1000,
        )
        self.payment = Payment.objects.create(
            order=self.order, user=self.farmer, amount=1000,
            payment_method='MTN_MOMO', phone_number='+237670000008',
            transaction_id='TXN-WEBHOOK', status='processing',
        )

    def _sign(self, body):
        import hashlib
        import hmac
        from django.conf import settings
        return hmac.new(
            settings.PAYMENT_WEBHOOK_SECRET.encode(), body, hashlib.sha256,
        ).hexdigest()

    def _post(self, payload, signature=None):
        body = __import__('json').dumps(payload).encode()
        if signature is None:
            signature = self._sign(body)
        return self.client.post(reverse('payment_webhook'), body,
                                content_type='application/json',
                                HTTP_X_SIGNATURE=signature)

    def test_invalid_signature_rejected(self):
        resp = self._post({'transaction_id': 'TXN-WEBHOOK', 'status': 'completed'},
                          signature='wrong')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_valid_signature_completes_payment(self):
        resp = self._post({'transaction_id': 'TXN-WEBHOOK', 'status': 'completed'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.status, 'completed')
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, 'paid')

    def test_webhook_is_idempotent(self):
        self._post({'transaction_id': 'TXN-WEBHOOK', 'status': 'completed'})
        self._post({'transaction_id': 'TXN-WEBHOOK', 'status': 'completed'})
        self.payment.refresh_from_db()
        self.assertEqual(self.payment.status, 'completed')

    def test_unknown_transaction_404(self):
        resp = self._post({'transaction_id': 'TXN-NOPE', 'status': 'completed'})
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)


class PaymentServiceIdempotencyTests(APITestCase):
    """Reusable service functions (shared with Celery) are idempotent."""

    def setUp(self):
        from ledger import services as ledger
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )
        self.order = Order.objects.create(
            farmer=self.farmer, product=self.product, quantity=2, total_price=2000,
        )

    def test_complete_payment_idempotent_and_posts_ledger_once(self):
        from ledger import services as ledger
        from .services import complete_payment
        payment = Payment.objects.create(
            order=self.order, user=self.farmer, amount=2000,
            payment_method='MTN_MOMO', phone_number='+237670000008',
            transaction_id='TXN-SVC', status='pending',
        )
        complete_payment(payment.pk)
        complete_payment(payment.pk)  # second call is a no-op
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, 'paid')
        self.assertEqual(ledger.escrow_account().balance, 2000)

    def test_finalize_failed_releases_stock_once(self):
        from django.utils import timezone
        from .services import finalize_payment_failed
        # Simulate a real reservation: stock already decremented + window set.
        self.product.stock_quantity = 3
        self.product.save(update_fields=['stock_quantity'])
        self.order.reserved_until = timezone.now() + timezone.timedelta(minutes=30)
        self.order.save(update_fields=['reserved_until'])

        payment = Payment.objects.create(
            order=self.order, user=self.farmer, amount=2000,
            payment_method='MTN_MOMO', phone_number='+237670000009',
            transaction_id='TXN-FAIL', status='pending',
        )
        finalize_payment_failed(payment.pk)
        finalize_payment_failed(payment.pk)  # no double release
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)
