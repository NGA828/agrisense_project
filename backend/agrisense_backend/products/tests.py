import struct
import zlib

from django.core.files.uploadedfile import SimpleUploadedFile
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

    @staticmethod
    def _png(name='photo.png'):
        """Minimal valid 1x1 PNG that Pillow can verify."""
        def chunk(tag, data):
            body = tag + data
            return (struct.pack('>I', len(data)) + body
                    + struct.pack('>I', zlib.crc32(body)))
        ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
        idat = zlib.compress(b'\x00\x2e\x7d\x32')
        png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
               + chunk(b'IDAT', idat) + chunk(b'IEND', b''))
        return SimpleUploadedFile(name, png, content_type='image/png')

    def test_multipart_create_preserves_is_available_default(self):
        """Multipart create (the mobile app's upload path) must NOT flip
        is_available to False when the client omits the boolean fields."""
        self.auth(self.dealer)
        resp = self.client.post(reverse('product-list'), {
            'name': 'Photo Seed', 'description': 'x', 'category': 'seed',
            'price': 100, 'stock_quantity': 5,
            'image': self._png(),
        }, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(resp.data['is_available'])
        # Image is stored and returned as a relative media path.
        self.assertTrue(resp.data['image'].startswith('product_images/'))
        product = Product.objects.get(id_product=resp.data['id_product'])
        self.assertTrue(product.is_available)
        self.assertTrue(product.image.name.startswith('product_images/'))

    def test_multipart_update_preserves_is_available(self):
        self.auth(self.dealer)
        resp = self.client.put(
            reverse('product-detail', args=[self.product.id_product]),
            {'name': 'Renamed', 'description': 'x', 'category': 'seed',
             'price': 100, 'stock_quantity': 5, 'image': self._png()},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['is_available'])
        self.product.refresh_from_db()
        self.assertTrue(self.product.is_available)
        self.assertTrue(self.product.image.name.startswith('product_images/'))

    def test_explicit_is_available_false_respected(self):
        self.auth(self.dealer)
        resp = self.client.post(reverse('product-list'), {
            'name': 'Hidden Seed', 'description': 'x', 'category': 'seed',
            'price': 100, 'stock_quantity': 5, 'is_available': 'false',
        }, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertFalse(resp.data['is_available'])

    def test_product_image_serialized_as_relative_path(self):
        self.product.image = self._png('product.png')
        self.product.save()
        self.auth(self.dealer)
        resp = self.client.get(reverse('product-detail', args=[self.product.id_product]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['image'].startswith('product_images/'))
        self.assertNotIn('http', resp.data['image'])

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


class OrderLifecycleTests(APITestCase):
    """Phase A: farmer cancel, reservation expiry, settlement on delivery."""

    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.admin = make_user('admin1', 'admin')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def place_order(self, qty=1):
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-list'), {
            'product': self.product.id_product, 'quantity': qty,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        return resp.data['id']

    def test_farmer_can_cancel_unpaid_order_and_stock_released(self):
        order_id = self.place_order(2)  # stock 5 -> 3
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-cancel', args=[order_id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)
        order = Order.objects.get(id=order_id)
        self.assertEqual(order.status, 'cancelled')

    def test_other_farmer_cannot_cancel(self):
        order_id = self.place_order()
        other = make_user('farmer2', 'farmer')
        self.auth(other)
        resp = self.client.post(reverse('order-cancel', args=[order_id]))
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_paid_order_cannot_be_cancelled_without_refund(self):
        order_id = self.place_order()
        order = Order.objects.get(id=order_id)
        order.payment_status = 'paid'
        order.status = 'confirmed'
        order.save()
        self.auth(self.farmer)
        resp = self.client.post(reverse('order-cancel', args=[order_id]))
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_reservation_expiry_releases_stock(self):
        from django.utils import timezone
        order_id = self.place_order(2)  # stock 5 -> 3
        order = Order.objects.get(id=order_id)
        order.reserved_until = timezone.now() - timezone.timedelta(minutes=1)
        order.save(update_fields=['reserved_until'])

        from django.core.management import call_command
        call_command('release_stale_reservations')

        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)
        order.refresh_from_db()
        self.assertEqual(order.status, 'expired')

    def test_delivery_settles_funds_to_dealer(self):
        from payments.models import Payment
        order_id = self.place_order(1)
        order = Order.objects.get(id=order_id)
        order.payment_status = 'paid'
        order.status = 'confirmed'
        order.save()
        Payment.objects.create(
            order=order, user=self.farmer, amount=1000,
            payment_method='MTN_MOMO', phone_number='+237670000008',
            transaction_id='TXN-SETTLE', status='completed',
        )
        from ledger import services as ledger
        ledger.record_payment_collected(Payment.objects.get(transaction_id='TXN-SETTLE'),
                                        reference=f'order:{order.id}')

        self.auth(self.dealer)
        resp = self.client.post(reverse('order-update-status', args=[order_id]),
                                {'status': 'shipped'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        resp = self.client.post(reverse('order-update-status', args=[order_id]),
                                {'status': 'delivered'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

        order.refresh_from_db()
        self.assertEqual(order.status, 'delivered')
        self.assertEqual(ledger.dealer_account(self.dealer).balance, 1000)
        self.assertEqual(ledger.escrow_account().balance, 0)

    def test_unpaid_order_cannot_be_shipped(self):
        order_id = self.place_order(1)
        self.auth(self.dealer)
        resp = self.client.post(reverse('order-update-status', args=[order_id]),
                                {'status': 'shipped'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_status_cannot_regress(self):
        order_id = self.place_order(1)
        order = Order.objects.get(id=order_id)
        order.payment_status = 'paid'
        order.status = 'delivered'
        order.save()
        self.auth(self.dealer)
        resp = self.client.post(reverse('order-update-status', args=[order_id]),
                                {'status': 'shipped'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
