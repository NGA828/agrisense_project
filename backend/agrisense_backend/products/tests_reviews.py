from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from products.models import Product, Order, Review, ProductReport


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class ReviewTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def _mark_purchased(self):
        Order.objects.create(
            farmer=self.farmer, product=self.product, quantity=1,
            total_price=1000, payment_status='paid', status='delivered',
        )

    def test_farmer_reviews_purchased_product(self):
        self._mark_purchased()
        self.auth(self.farmer)
        resp = self.client.post(reverse('review-list'), {
            'product': self.product.id_product, 'rating': 5, 'comment': 'Great!',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Review.objects.count(), 1)

    def test_farmer_cannot_review_without_purchase(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('review-list'), {
            'product': self.product.id_product, 'rating': 5,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_dealer_cannot_review(self):
        self.auth(self.dealer)
        resp = self.client.post(reverse('review-list'), {
            'product': self.product.id_product, 'rating': 5,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_only_one_review_per_farmer_product(self):
        self._mark_purchased()
        self.auth(self.farmer)
        self.client.post(reverse('review-list'), {
            'product': self.product.id_product, 'rating': 5,
        }, format='json')
        resp = self.client.post(reverse('review-list'), {
            'product': self.product.id_product, 'rating': 4,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_product_serializer_includes_rating(self):
        self._mark_purchased()
        self.auth(self.farmer)
        self.client.post(reverse('review-list'), {
            'product': self.product.id_product, 'rating': 4, 'comment': 'ok',
        }, format='json')
        resp = self.client.get(reverse('product-detail', args=[self.product.id_product]))
        self.assertEqual(resp.data['rating_count'], 1)
        self.assertEqual(resp.data['rating_avg'], 4.0)


class ProductReportTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.admin = make_user('admin1', 'admin')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Bad Seed', description='s',
            category='seed', price=100, stock_quantity=5,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_farmer_reports_product(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('product-report-list'), {
            'product': self.product.id_product, 'reason': 'counterfeit',
            'details': 'Looks fake',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(ProductReport.objects.get().status, 'pending')

    def test_admin_resolves_report_by_removing_product(self):
        report = ProductReport.objects.create(
            product=self.product, reporter=self.farmer, reason='fraud', status='pending')
        self.auth(self.admin)
        resp = self.client.post(reverse('product-report-resolve', args=[report.id]),
                                {'decision': 'removed'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        report.refresh_from_db()
        self.assertEqual(report.status, 'removed')
        self.product.refresh_from_db()
        self.assertFalse(self.product.is_available)
        from auditlog.models import AuditLog
        self.assertTrue(AuditLog.objects.filter(action='resolve_report').exists())

    def test_non_admin_cannot_resolve(self):
        report = ProductReport.objects.create(
            product=self.product, reporter=self.farmer, reason='fraud', status='pending')
        self.auth(self.farmer)
        resp = self.client.post(reverse('product-report-resolve', args=[report.id]),
                                {'decision': 'dismissed'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
