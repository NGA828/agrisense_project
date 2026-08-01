import struct
import zlib
from datetime import timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from products.models import Product, Order
from payments.models import Payment


def make_user(username, role, **kwargs):
    user = User.objects.create_user(
        username=username,
        password='Str0ngPass!',
        first_name=kwargs.pop('first_name', username.title()),
        last_name=kwargs.pop('last_name', 'Test'),
        email=kwargs.pop('email', f'{username}@test.com'),
        phone_number=kwargs.pop('phone_number', '+237600000000'),
        role=role,
        **kwargs,
    )
    return user


class AuthAndRegistrationTests(APITestCase):
    def test_register_farmer_success(self):
        resp = self.client.post(reverse('register'), {
            'username': 'newfarmer', 'password': 'Str0ngPass!123',
            'first_name': 'A', 'last_name': 'B', 'email': 'a@b.com',
            'phone_number': '+237670000010', 'role': 'farmer',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(username='newfarmer').exists())

    def test_register_admin_blocked(self):
        resp = self.client.post(reverse('register'), {
            'username': 'hacker', 'password': 'Str0ngPass!123',
            'first_name': 'H', 'last_name': 'K', 'email': 'h@k.com',
            'phone_number': '+237670000011', 'role': 'admin',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(username='hacker').exists())

    def test_register_invalid_role_blocked(self):
        resp = self.client.post(reverse('register'), {
            'username': 'bot', 'password': 'Str0ngPass!123',
            'first_name': 'B', 'last_name': 'B', 'email': 'b@b.com',
            'phone_number': '+237670000012', 'role': 'superuser',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_register_weak_password_blocked(self):
        resp = self.client.post(reverse('register'), {
            'username': 'weakpass', 'password': '123',
            'first_name': 'W', 'last_name': 'P', 'email': 'w@p.com',
            'phone_number': '+237670000013', 'role': 'farmer',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_login_returns_tokens(self):
        make_user('farmer1', 'farmer')
        resp = self.client.post(reverse('token_obtain_pair'), {
            'username': 'farmer1', 'password': 'Str0ngPass!',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('access', resp.data)
        self.assertIn('refresh', resp.data)

    def test_suspended_user_cannot_login(self):
        user = make_user('farmer1', 'farmer')
        user.is_active = False
        user.save()
        resp = self.client.post(reverse('token_obtain_pair'), {
            'username': 'farmer1', 'password': 'Str0ngPass!',
        })
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_password_reset_with_valid_phone(self):
        make_user('farmer1', 'farmer', phone_number='+237670000001')
        resp = self.client.post(reverse('password_reset'), {
            'username': 'farmer1', 'phone_number': '+237 670 000 001',
            'new_password': 'NewStr0ngPass!',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        user = User.objects.get(username='farmer1')
        self.assertTrue(user.check_password('NewStr0ngPass!'))

    def test_password_reset_wrong_phone_rejected(self):
        make_user('farmer1', 'farmer', phone_number='+237670000001')
        resp = self.client.post(reverse('password_reset'), {
            'username': 'farmer1', 'phone_number': '+237699999999',
            'new_password': 'NewStr0ngPass!',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        user = User.objects.get(username='farmer1')
        self.assertTrue(user.check_password('Str0ngPass!'))

    def test_password_reset_weak_password_rejected(self):
        make_user('farmer1', 'farmer', phone_number='+237670000001')
        resp = self.client.post(reverse('password_reset'), {
            'username': 'farmer1', 'phone_number': '+237670000001',
            'new_password': '123',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_refresh_token_rotation_works_with_blacklist(self):
        make_user('farmer1', 'farmer')
        tokens = self.client.post(reverse('token_obtain_pair'), {
            'username': 'farmer1', 'password': 'Str0ngPass!',
        }).data
        resp = self.client.post(reverse('token_refresh'), {
            'refresh': tokens['refresh'],
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Rotated refresh token must be blacklisted now.
        resp2 = self.client.post(reverse('token_refresh'), {
            'refresh': tokens['refresh'],
        })
        self.assertEqual(resp2.status_code, status.HTTP_401_UNAUTHORIZED)


class UserManagementTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin', is_staff=True, is_superuser=True)
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer', is_verified=True)

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_non_admin_cannot_list_all_users(self):
        self.auth(self.farmer)
        resp = self.client.get(reverse('user-list'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        # Non-admins see only themselves (queryset filtered; paginated response).
        results = resp.data.get('results') if isinstance(resp.data, dict) else resp.data
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['id'], self.farmer.id)

    def test_non_admin_cannot_suspend(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('user-suspend', args=[self.dealer.id]))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_suspend_activate(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('user-suspend', args=[self.dealer.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.dealer.refresh_from_db()
        self.assertFalse(self.dealer.is_active)
        self.client.post(reverse('user-activate', args=[self.dealer.id]))
        self.dealer.refresh_from_db()
        self.assertTrue(self.dealer.is_active)

    def test_non_admin_cannot_delete(self):
        self.auth(self.farmer)
        resp = self.client.delete(reverse('user-detail', args=[self.dealer.id]))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_delete_user(self):
        self.auth(self.admin)
        resp = self.client.delete(reverse('user-detail', args=[self.farmer.id]))
        self.assertEqual(resp.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(id=self.farmer.id).exists())

    def test_user_cannot_promote_self_to_admin(self):
        self.auth(self.farmer)
        resp = self.client.patch(reverse('user-detail', args=[self.farmer.id]),
                                 {'role': 'admin'})
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_dealer_requests_queue(self):
        pending = make_user('dealer_pending', 'dealer', is_verified=False)
        self.auth(self.admin)
        resp = self.client.get(reverse('user-dealer-requests'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        ids = [u['id'] for u in resp.data]
        self.assertIn(pending.id, ids)
        self.assertNotIn(self.dealer.id, ids)  # verified dealers not in queue

    def test_verify_dealer(self):
        pending = make_user('dealer_pending', 'dealer', is_verified=False)
        self.auth(self.admin)
        resp = self.client.post(reverse('user-verify-dealer', args=[pending.id]),
                                {'approve': True}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        pending.refresh_from_db()
        self.assertTrue(pending.is_verified)

    def test_upgrade_premium_creates_payment(self):
        self.auth(self.dealer)
        resp = self.client.post(reverse('user-upgrade-premium', args=[self.dealer.id]),
                                {'duration_months': 2}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['status'], 'payment_required')
        payment = Payment.objects.filter(user=self.dealer, payment_type='premium').first()
        self.assertIsNotNone(payment)
        self.assertEqual(float(payment.amount), 2000)


class ProfilePhotoUploadTests(APITestCase):
    """Regression tests for profile-picture uploads via /api/users/me/.

    The mobile client uploads photos with a multipart PATCH to
    /api/users/me/. The `me` action must accept PATCH (it used to be
    GET-only, which produced HTTP 405 and silently dropped the photo).
    """

    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.admin = make_user('admin1', 'admin', is_staff=True, is_superuser=True)

    def auth(self, user):
        self.client.force_authenticate(user=user)

    @staticmethod
    def _photo(name='photo.png'):
        """Build a minimal valid 1x1 PNG (Pillow must be able to open it)."""
        def chunk(tag, data):
            body = tag + data
            return (struct.pack('>I', len(data)) + body
                    + struct.pack('>I', zlib.crc32(body)))
        ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
        idat = zlib.compress(b'\x00\x2e\x7d\x32')
        png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
               + chunk(b'IDAT', idat) + chunk(b'IEND', b''))
        return SimpleUploadedFile(name, png, content_type='image/png')

    def test_patch_me_accepts_multipart_profile_photo(self):
        self.auth(self.farmer)
        resp = self.client.patch(
            reverse('user-me'),
            {'first_name': 'Jean', 'profile_photo': self._photo()},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['first_name'], 'Jean')
        # Response must carry the stored photo as a relative media path so the
        # client resolves it against its own base URL.
        self.assertTrue(resp.data['profile_photo'].startswith('profile_photos/'))
        self.farmer.refresh_from_db()
        self.assertTrue(self.farmer.profile_photo.name.startswith('profile_photos/'))

    def test_patch_me_without_photo_keeps_existing_photo(self):
        self.auth(self.farmer)
        self.farmer.profile_photo = self._photo('existing.png')
        self.farmer.save()
        resp = self.client.patch(
            reverse('user-me'),
            {'phone_number': '+237600000001'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.farmer.refresh_from_db()
        # The media directory persists across test runs, so the storage may
        # append a random suffix on name collisions — only the prefix matters.
        self.assertTrue(
            self.farmer.profile_photo.name.startswith('profile_photos/existing'),
            self.farmer.profile_photo.name,
        )

    def test_patch_me_cannot_promote_self(self):
        self.auth(self.farmer)
        resp = self.client.patch(reverse('user-me'), {'role': 'admin'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.farmer.refresh_from_db()
        self.assertEqual(self.farmer.role, 'farmer')

    def test_get_me_still_returns_profile(self):
        self.auth(self.admin)
        resp = self.client.get(reverse('user-me'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['username'], 'admin1')


class AdminStatsTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin', is_staff=True, is_superuser=True)
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer', is_verified=True)

    def test_admin_stats(self):
        self.client.force_authenticate(user=self.admin)
        resp = self.client.get(reverse('admin_stats'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['total_farmers'], 1)
        self.assertEqual(resp.data['total_dealers'], 1)

    def test_admin_stats_forbidden_for_farmer(self):
        self.client.force_authenticate(user=self.farmer)
        resp = self.client.get(reverse('admin_stats'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_analytics_series(self):
        self.client.force_authenticate(user=self.admin)
        resp = self.client.get(reverse('admin_analytics') + '?period=7d')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('user_growth', resp.data)
        self.assertIn('top_products', resp.data)

    def test_admin_analytics_with_order_data(self):
        """Series with real orders + payments must aggregate correctly."""
        product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5)
        order = Order.objects.create(farmer=self.farmer, product=product,
                                     quantity=2, total_price=2000)
        Payment.objects.create(
            order=order, user=self.farmer, amount=2000,
            payment_method='MTN_MOMO', phone_number='+237600000001',
            transaction_id='TXN-ANALYTICS', status='completed',
            payment_type='order')
        self.client.force_authenticate(user=self.admin)
        resp = self.client.get(reverse('admin_analytics') + '?period=7d')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['order_volume'])
        self.assertTrue(resp.data['revenue'])
        self.assertTrue(resp.data['top_products'])
