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
