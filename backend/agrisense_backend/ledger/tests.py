from decimal import Decimal

from django.test import TestCase

from users.models import User
from products.models import Product, Order
from payments.models import Payment
from ledger import services as ledger
from ledger.models import Account, LedgerEntry


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role, is_verified=(role == 'dealer'),
    )


class LedgerDoubleEntryTests(TestCase):
    def test_entry_recorded_with_distinct_accounts(self):
        money = ledger.mobile_money_account()
        escrow = ledger.escrow_account()
        entry = ledger.post_entry(money, escrow, '5000.00', 'test flow')
        self.assertEqual(entry.amount, Decimal('5000.00'))
        self.assertNotEqual(entry.debit_id, entry.credit_id)
        self.assertEqual(entry.debit, money)
        self.assertEqual(entry.credit, escrow)
        self.assertEqual(escrow.balance, Decimal('5000.00'))
        self.assertEqual(money.balance, Decimal('-5000.00'))

    def test_post_entry_rejects_non_positive_and_self_transfer(self):
        money = ledger.mobile_money_account()
        escrow = ledger.escrow_account()
        with self.assertRaises(ValueError):
            ledger.post_entry(money, escrow, 0, 'zero')
        with self.assertRaises(ValueError):
            ledger.post_entry(money, money, 5, 'same account')


class LedgerBusinessFlowTests(TestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.product = Product.objects.create(
            dealer=self.dealer, name='Seed', description='s',
            category='seed', price=1000, stock_quantity=5,
        )
        self.order = Order.objects.create(
            farmer=self.farmer, product=self.product, quantity=2,
            total_price=2000, payment_method='MTN_MOMO',
        )
        self.payment = Payment.objects.create(
            order=self.order, user=self.farmer, amount=2000,
            payment_method='MTN_MOMO', phone_number='+237670000008',
            transaction_id='TXN-LEDGER', status='completed',
        )

    def test_collection_moves_money_to_escrow(self):
        ledger.record_payment_collected(self.payment, reference=f'order:{self.order.id}')
        self.assertEqual(ledger.escrow_account().balance, Decimal('2000.00'))

    def test_settlement_releases_escrow_to_dealer(self):
        ledger.record_payment_collected(self.payment, reference=f'order:{self.order.id}')
        ledger.settle_order(self.order)
        dealer_bal = ledger.dealer_account(self.dealer).balance
        self.assertEqual(dealer_bal, Decimal('2000.00'))
        self.assertEqual(ledger.escrow_account().balance, Decimal('0.00'))

    def test_settlement_is_idempotent(self):
        ledger.record_payment_collected(self.payment, reference=f'order:{self.order.id}')
        ledger.settle_order(self.order)
        ledger.settle_order(self.order)
        self.assertEqual(ledger.dealer_account(self.dealer).balance, Decimal('2000.00'))
        self.assertEqual(ledger.escrow_account().balance, Decimal('0.00'))

    def test_commission_split_at_settlement(self):
        self.product.save()
        with self.settings(PLATFORM_COMMISSION_RATE=0.10):
            ledger.record_payment_collected(self.payment, reference=f'order:{self.order.id}')
            ledger.settle_order(self.order)
            self.assertEqual(ledger.dealer_account(self.dealer).balance, Decimal('1800.00'))
            self.assertEqual(ledger.platform_fees_account().balance, Decimal('200.00'))
            self.assertEqual(ledger.escrow_account().balance, Decimal('0.00'))

    def test_refund_reverses_escrow(self):
        ledger.record_payment_collected(self.payment, reference=f'order:{self.order.id}')
        ledger.record_refund(self.payment, reference=f'payment:{self.payment.transaction_id}')
        self.assertEqual(ledger.escrow_account().balance, Decimal('0.00'))

    def test_premium_income(self):
        premium = Payment.objects.create(
            order=None, user=self.dealer, amount=1000,
            payment_method='MTN_MOMO', phone_number='+237670000008',
            transaction_id='TXN-PREM', status='completed', payment_type='premium',
            description='Premium dealer subscription (1 month(s))',
        )
        ledger.record_premium_income(premium, reference=f'premium:{self.dealer.id}')
        self.assertEqual(ledger.platform_fees_account().balance, Decimal('1000.00'))
        self.assertEqual(ledger.escrow_account().balance, Decimal('0.00'))
