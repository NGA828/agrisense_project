from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from products.models import Product, Order


def make_user(username, role, verified=True, premium=False):
    user = User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role, is_verified=verified, is_premium=premium,
    )
    return user


class ProductTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin')
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.unverified = make_user('dealer2', 'dealer', verified=False)
        self.premium = make_user('dealer3', 'dealer', premium=True)
        self.product = Product.objects.create(
            dealer=self.dealer, name='Test Seed', description='Nice seed',
            category='seed', price=1000, stock_quantity=10,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_unverified_dealer_cannot_create_product(self):
        self.auth(self.unverified)
        resp = self.client.post(reverse('product-list'), {
            'name': 'Illegal', 'description': 'x', 'category': 'seed',
            'price': 100, 'stock_quantity': 5,
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_farmer_cannot_create_product(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('product-list'), {
            'name': 'Illegal', 'description': 'x', 'category': 'seed',
            'price': 100, 'stock_quantity': 5,
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_verified_dealer_can_create_product(self):
        self.auth(self.dealer)
        resp = self.client.post(reverse('product-list'), {
            'name': 'Good Seed', 'description': 'x', 'category': 'seed',
            'price': 100, 'stock_quantity': 5,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['dealer'], self.dealer.id)

    def test_dealer_cannot_edit_others_product(self):
        self.auth(self.dealer)
        other = Product.objects.create(dealer=self.premium, name='O',
                                       description='o', category='seed',
                                       price=5, stock_quantity=1)
        resp = self.client.patch(reverse('product-detail', args=[other.id_product]),
                                 {'price': 999}, format='json')
        # The queryset is scoped to the dealer, so another dealer's product
        # is invisible (404) — no information leak, no mutation.
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_marketplace_premium_boost(self):
        # Same name; premium dealer's copy must come first.
        premium_copy = Product.objects.create(dealer=self.premium, name='Boosted',
                                              description='p', category='fertilizer',
                                              price=500, stock_quantity=5, is_available=True)
        normal_copy = Product.objects.create(dealer=self.dealer, name='Boosted',
                                             description='n', category='fertilizer',
                                             price=300, stock_quantity=5, is_available=True)
        self.auth(self.farmer)
        resp = self.client.get(reverse('product-marketplace'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        ids = [p['id_product'] for p in resp.data]
        self.assertLess(ids.index(premium_copy.id_product), ids.index(normal_copy.id_product))

    def test_marketplace_search(self):
        self.auth(self.farmer)
        resp = self.client.get(reverse('product-marketplace') + '?search=Test')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]['name'], 'Test Seed')


class OrderTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_farmer_creates_order_decrements_stock(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 2,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(float(resp.data['total_price']), 2000.0)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)

    def test_order_over_stock_rejected(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 99,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)

    def test_unavailable_product_rejected(self):
        self.product.is_available = False
        self.product.save()
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 1,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_dealer_cannot_order(self):
        self.auth(self.dealer)
        resp = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 1,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_dealer_updates_status_and_cancel_restores_stock(self):
        self.auth(self.farmer)
        order = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 2,
        }, format='json').data
        self.auth(self.dealer)
        resp = self.client.post(reverse('order-update-status', args=[order['id']]),
                                {'status': 'cancelled'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)

    def test_farmer_cannot_update_status(self):
        self.auth(self.farmer)
        order = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 1,
        }, format='json').data
        resp = self.client.post(reverse('order-update-status', args=[order['id']]),
                                {'status': 'shipped'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_order_history_scoped(self):
        self.auth(self.farmer)
        self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': 1,
        }, format='json')
        resp = self.client.get(reverse('order-order-history'))
        self.assertEqual(len(resp.data), 1)
        # Dealer sees the same order (it belongs to their product).
        self.auth(self.dealer)
        resp = self.client.get(reverse('order-order-history'))
        self.assertEqual(len(resp.data), 1)
