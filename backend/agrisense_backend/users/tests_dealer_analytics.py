from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from products.models import Product, Order


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class DealerAnalyticsTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.other_dealer = make_user('dealer2', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )
        Order.objects.create(farmer=self.farmer, product=self.product, quantity=2,
                             total_price=2000, payment_status='paid', status='delivered')

    def test_dealer_analytics_scoped(self):
        self.client.force_authenticate(user=self.dealer)
        resp = self.client.get(reverse('dealer_analytics') + '?period=30d')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['total_orders'], 1)
        self.assertEqual(resp.data['total_revenue'], 2000.0)
        self.assertEqual(resp.data['top_products'][0]['name'], 'Seed')

    def test_farmer_cannot_access_dealer_analytics(self):
        self.client.force_authenticate(user=self.farmer)
        resp = self.client.get(reverse('dealer_analytics'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_dealer_only_sees_own_orders(self):
        other = Product.objects.create(dealer=self.other_dealer, name='Other',
                                       description='o', category='seed', price=5,
                                       stock_quantity=5)
        Order.objects.create(farmer=self.farmer, product=other, quantity=1,
                             total_price=5, payment_status='paid', status='delivered')
        self.client.force_authenticate(user=self.dealer)
        resp = self.client.get(reverse('dealer_analytics'))
        self.assertEqual(resp.data['total_orders'], 1)
        self.assertEqual(resp.data['total_revenue'], 2000.0)
