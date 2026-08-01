"""Tests for the Celery tasks (run in eager mode during the test suite)."""

from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from users.models import User
from products.models import Product, Order
from payments.models import Payment


def make_user(username, role, premium=False, expiry=None):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role, is_premium=premium, premium_expiry=expiry,
    )


class ReleaseStaleReservationsTaskTests(TestCase):
    def test_task_expires_stale_orders_and_releases_stock(self):
        from products.tasks import release_stale_reservations_task
        farmer = make_user('farmer1', 'farmer')
        dealer = make_user('dealer1', 'dealer')
        product = Product.objects.create(dealer=dealer, name='Seed', description='s',
                                         category='seed', price=100, stock_quantity=5)
        order = Order.objects.create(
            farmer=farmer, product=product, quantity=2, total_price=200,
            reserved_until=timezone.now() - timedelta(minutes=1),
        )
        # Simulate the reservation: stock is already decremented by the order.
        product.stock_quantity = 3
        product.save(update_fields=['stock_quantity'])

        released = release_stale_reservations_task.apply().result
        self.assertEqual(released, 1)
        order.refresh_from_db()
        self.assertEqual(order.status, 'expired')
        product.refresh_from_db()
        self.assertEqual(product.stock_quantity, 5)


class ExpirePremiumsTaskTests(TestCase):
    def test_task_expires_overdue_premiums(self):
        from users.tasks import expire_premiums_task
        make_user('dealer1', 'dealer', premium=True,
                  expiry=timezone.now() - timedelta(days=1))
        make_user('dealer2', 'dealer', premium=True,
                  expiry=timezone.now() + timedelta(days=5))
        count = expire_premiums_task.apply().result
        self.assertEqual(count, 1)


class ReconcilePaymentsTaskTests(TestCase):
    def test_task_runs_without_error_on_sandbox(self):
        from payments.tasks import reconcile_payments_task
        farmer = make_user('farmer1', 'farmer')
        dealer = make_user('dealer1', 'dealer')
        product = Product.objects.create(dealer=dealer, name='Seed', description='s',
                                         category='seed', price=100, stock_quantity=5)
        order = Order.objects.create(farmer=farmer, product=product, quantity=1, total_price=100)
        Payment.objects.create(
            order=order, user=farmer, amount=100, payment_method='MTN_MOMO',
            phone_number='+237670000001', transaction_id='TXN-REC', status='pending',
        )
        # Sandbox gateway is skipped; task must complete without error.
        reconciled = reconcile_payments_task.apply().result
        self.assertEqual(reconciled, 0)


class FanOutAnnouncementTaskTests(TestCase):
    def test_task_fans_out_to_target(self):
        from announcements.models import Announcement
        from announcements.tasks import fan_out_announcement_task
        admin = make_user('admin1', 'admin')
        farmer = make_user('farmer1', 'farmer')
        dealer = make_user('dealer1', 'dealer')
        ann = Announcement.objects.create(
            title='Alert', content='Spray', target_audience='farmers', created_by=admin,
        )
        created = fan_out_announcement_task.apply(kwargs={'announcement_id': ann.id}).result
        self.assertEqual(created, 1)
        self.assertEqual(farmer.notifications.count(), 1)
        self.assertEqual(dealer.notifications.count(), 0)
