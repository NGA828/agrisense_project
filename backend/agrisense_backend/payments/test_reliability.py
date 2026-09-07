import io
import uuid
from decimal import Decimal
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from django.core.cache import cache
from django.core.management import call_command
from django.test import SimpleTestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APITestCase

from announcements.models import Notification
from ledger.models import LedgerEntry
from products.models import Order, Product
from products.tasks import release_stale_reservations_task
from users.models import User
from .gateway import (MTNMoMoGateway, PaymentError, PaymentStatusUnknown,
                      PaymentVerificationMismatch, get_gateway, normalize_phone)
from .models import Payment
from .services import complete_payment, finalize_payment_failed, process_collection


@override_settings(MTN_MOMO_ENABLED=True, MTN_MOMO_API_USER='test-api-user',
                   MTN_MOMO_API_KEY='test-api-key', MTN_MOMO_PRIMARY_KEY='test-collection-key',
                   MTN_MOMO_ENVIRONMENT='sandbox', MTN_MOMO_BASE_URL='',
                   MTN_MOMO_CALLBACK_URL='', PAYMENT_SIMULATOR_ENABLED=False)
class GatewayContractTests(SimpleTestCase):
    def setUp(self):
        cache.clear()
        self.reference = uuid.uuid4()

    def test_disabled_gateway_does_not_fall_back_to_fake_success(self):
        with override_settings(MTN_MOMO_ENABLED=False):
            with self.assertRaises(PaymentError):
                get_gateway('MTN_MOMO')

    def test_missing_credentials_and_unimplemented_methods_are_unavailable(self):
        with override_settings(MTN_MOMO_API_KEY=''):
            with self.assertRaises(PaymentError):
                get_gateway('MTN_MOMO')
        for method in ('ORANGE_MONEY', 'CARD'):
            with self.assertRaises(PaymentError):
                get_gateway(method)

    @override_settings(DEBUG=False, PAYMENT_SIMULATOR_ENABLED=True)
    def test_simulation_is_blocked_in_production(self):
        with self.assertRaises(PaymentError):
            get_gateway('MTN_MOMO')

    def test_phone_validation_and_normalization(self):
        self.assertEqual(normalize_phone('+237 670 000 008'), '237670000008')
        self.assertEqual(normalize_phone('670000008'), '237670000008')
        self.assertEqual(normalize_phone('00237670000008'), '237670000008')
        for phone in ('', '+2376', '6000000000', 'abc670000008', '+234670000008'):
            with self.assertRaises(PaymentError):
                normalize_phone(phone)

    def test_sandbox_uses_eur_and_does_not_rewrite_mtn_test_msisdn(self):
        gateway = MTNMoMoGateway()
        with patch.object(gateway, '_token', return_value='token'), patch.object(
                gateway, '_request', return_value=(202, {})) as request:
            result = gateway.request_payment(amount=Decimal('2000.00'), phone_number='46733123454',
                transaction_id='TXN-TEST', description='Order', provider_reference=self.reference)
        kwargs = request.call_args.kwargs
        self.assertEqual(kwargs['body']['currency'], 'EUR')
        self.assertEqual(kwargs['body']['amount'], '2000.00')
        self.assertEqual(kwargs['body']['payer']['partyId'], '46733123454')
        self.assertEqual(kwargs['headers']['X-Target-Environment'], 'sandbox')
        self.assertEqual(kwargs['headers']['X-Reference-Id'], str(self.reference))
        self.assertEqual(result['status'], 'processing')
        self.assertTrue(result['is_test'])

    @override_settings(MTN_MOMO_ENVIRONMENT='live', MTN_MOMO_CALLBACK_URL='https://api.example.com/api/payments/mtn/callback/')
    def test_cameroon_live_uses_country_target_xaf_and_callback(self):
        gateway = MTNMoMoGateway()
        with patch.object(gateway, '_token', return_value='token'), patch.object(
                gateway, '_request', return_value=(202, {})) as request:
            gateway.request_payment(amount=Decimal('1000'), phone_number='670000008',
                transaction_id='TXN-LIVE', description='Order', provider_reference=self.reference)
        self.assertEqual(request.call_args.kwargs['headers']['X-Target-Environment'], 'mtncameroon')
        self.assertEqual(request.call_args.kwargs['body']['currency'], 'XAF')
        self.assertEqual(request.call_args.kwargs['headers']['X-Callback-Url'],
                         'https://api.example.com/api/payments/mtn/callback/')
        self.assertFalse(gateway.is_test)

    def test_legacy_uuid5_is_kept_for_verification_not_submitted_or_silently_rotated(self):
        gateway = MTNMoMoGateway()
        with patch.object(gateway, '_request') as request, self.assertRaises(PaymentStatusUnknown):
            gateway.request_payment(amount=1000, phone_number='670000008', description='Order',
                transaction_id='OLD-TXN', provider_reference=uuid.uuid5(uuid.NAMESPACE_URL, 'OLD-TXN'))
        request.assert_not_called()

    def test_token_request_has_no_grant_type_body_and_is_cached(self):
        gateway = MTNMoMoGateway()
        with patch.object(gateway, '_request', return_value=(200, {'access_token': 'private-token', 'expires_in': 3600})) as request:
            self.assertEqual(gateway._token(), gateway._token())
            self.assertEqual(request.call_count, 1)
            self.assertNotIn('body', request.call_args.kwargs)

    def test_token_cache_read_failure_still_submits_one_collection(self):
        gateway = MTNMoMoGateway()
        with patch('payments.gateway.cache.get', side_effect=ConnectionError('private-cache-password')), patch.object(
                gateway, '_request', side_effect=[(200, {'access_token': 'fresh-test-token'}), (202, {})]) as request:
            with self.assertLogs('agrisense.payments', level='WARNING') as logs:
                result = gateway.request_payment(amount=1000, phone_number='670000008', description='Order',
                    transaction_id='TXN-CACHE', provider_reference=self.reference)
        self.assertEqual(result['status'], 'processing')
        self.assertEqual([c.args[1] for c in request.call_args_list],
                         ['/collection/token/', '/collection/v1_0/requesttopay'])
        self.assertNotIn('private-cache-password', str(logs.output))
        self.assertNotIn('fresh-test-token', str(logs.output))

    def test_token_cache_write_failure_still_submits_one_collection(self):
        gateway = MTNMoMoGateway()
        with patch('payments.gateway.cache.set', side_effect=ConnectionError('private-cache-password')), patch.object(
                gateway, '_request', side_effect=[(200, {'access_token': 'fresh-test-token'}), (202, {})]) as request:
            with self.assertLogs('agrisense.payments', level='WARNING') as logs:
                result = gateway.request_payment(amount=1000, phone_number='670000008', description='Order',
                    transaction_id='TXN-CACHE', provider_reference=self.reference)
        self.assertEqual(result['status'], 'processing')
        self.assertEqual(request.call_count, 2)  # one token, one collection; no retries
        self.assertNotIn('private-cache-password', str(logs.output))
        self.assertNotIn('fresh-test-token', str(logs.output))

    def test_corrupt_cached_token_is_not_used_as_authorization(self):
        gateway = MTNMoMoGateway()
        with patch('payments.gateway.cache.get', return_value={'unexpected': 'data'}), patch.object(
                gateway, '_request', return_value=(200, {'access_token': 'fresh-test-token'})) as request:
            self.assertEqual(gateway._token(), 'fresh-test-token')
        request.assert_called_once()

    def test_success_is_checked_against_amount_currency_payer_and_reference(self):
        gateway = MTNMoMoGateway()
        valid = {'status': 'SUCCESSFUL', 'externalId': 'TXN-TEST', 'amount': '2000.00',
                 'currency': 'EUR', 'payer': {'partyId': '237670000008'}}
        with patch.object(gateway, '_token', return_value='token'), patch.object(
                gateway, '_request', return_value=(200, valid)):
            self.assertEqual(gateway.verify_transaction('TXN-TEST', provider_reference=self.reference,
                amount=Decimal('2000'), phone_number='670000008'), 'completed')
        for changes in ({'externalId': 'different'}, {'amount': '1'}, {'amount': 'NaN'},
                        {'currency': 'XAF'}, {'payer': {'partyId': '237670000009'}}):
            with self.subTest(changes=changes), patch.object(gateway, '_token', return_value='token'), patch.object(
                    gateway, '_request', return_value=(200, {**valid, **changes})):
                with self.assertRaises(PaymentVerificationMismatch):
                    gateway.verify_transaction('TXN-TEST', provider_reference=self.reference,
                        amount=Decimal('2000'), phone_number='670000008')

    def test_collection_409_is_polled_not_retried_with_new_reference(self):
        gateway = MTNMoMoGateway()
        error = HTTPError(gateway.host, 409, 'duplicate', {}, io.BytesIO(b'provider detail'))
        with patch('payments.gateway.urlopen', side_effect=error):
            self.assertEqual(gateway._request('POST', '/request', collection=True), (202, {}))

    def test_http_500_does_not_mean_payment_failed_and_diagnostics_are_private(self):
        gateway = MTNMoMoGateway()
        error = HTTPError(gateway.host, 500, 'error', {}, io.BytesIO(b'secret-provider-diagnostics'))
        with patch('payments.gateway.urlopen', side_effect=error), self.assertRaises(PaymentStatusUnknown) as caught:
            gateway._request('POST', '/request', collection=True)
        self.assertNotIn('secret-provider-diagnostics', str(caught.exception))

    def test_token_timeout_is_a_definite_no_collection_sent_failure(self):
        gateway = MTNMoMoGateway()
        with patch.object(gateway, '_token', side_effect=PaymentStatusUnknown('token timeout')):
            with self.assertRaises(PaymentError) as caught:
                gateway.request_payment(amount=1000, phone_number='670000008', description='Order',
                    transaction_id='TXN-TEST', provider_reference=self.reference)
        self.assertNotIsInstance(caught.exception, PaymentStatusUnknown)

    def test_environment_switch_cannot_verify_an_old_payment_against_new_credentials(self):
        with self.assertRaises(PaymentStatusUnknown):
            get_gateway('MTN_MOMO', environment='mtncameroon')

    def test_configuration_command_does_not_initiate_charge_or_print_keys(self):
        output = io.StringIO()
        with patch.object(MTNMoMoGateway, '_token', return_value='secret-token'), patch.object(
                MTNMoMoGateway, 'request_payment') as charge:
            call_command('check_payments', '--check-auth', stdout=output)
        charge.assert_not_called()
        for secret in ('test-api-key', 'test-collection-key', 'secret-token'):
            self.assertNotIn(secret, output.getvalue())
        self.assertIn('No charge was made', output.getvalue())


@override_settings(DEBUG=True, PAYMENT_SIMULATOR_ENABLED=True)
class PaymentReliabilityTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.farmer = User.objects.create_user(username='buyer', email='buyer@test.com', role='farmer')
        self.dealer = User.objects.create_user(username='seller', email='seller@test.com', role='dealer')
        self.admin = User.objects.create_user(username='admin', email='admin@test.com', role='admin')
        self.product = Product.objects.create(dealer=self.dealer, name='Seeds', description='seeds',
                                             category='seed', price=1000, stock_quantity=5)
        self.client.force_authenticate(self.farmer)
        self.gateway = Mock(spec=MTNMoMoGateway)
        self.gateway.provider = 'MTN_MOMO'
        self.gateway.environment = 'sandbox'
        self.gateway.is_test = True
        self.gateway.validate_phone.side_effect = normalize_phone
        self.gateway.request_payment.return_value = {'status': 'processing'}
        self.gateway.verify_transaction.return_value = 'processing'

    def reserve(self, key=None):
        data = {'product': self.product.pk, 'quantity': 2}
        if key:
            data['checkout_key'] = str(key)
        response = self.client.post(reverse('order-list'), data, format='json')
        self.assertIn(response.status_code, (200, 201), response.data)
        return Order.objects.get(pk=response.data['id'])

    def attempt(self, order, phone='670000008'):
        response = self.client.post(reverse('payment-list'), {'order': order.pk,
            'amount': '2000.00', 'payment_method': 'MTN_MOMO', 'phone_number': phone}, format='json')
        self.assertIn(response.status_code, (200, 201), response.data)
        return Payment.objects.get(pk=response.data['id'])

    def process(self, payment):
        return self.client.post(reverse('payment-process-payment', args=[payment.pk]))

    def assert_dealer_has_no_order(self):
        self.client.force_authenticate(self.dealer)
        response = self.client.get(reverse('order-order-history'))
        self.assertEqual(response.data, [])
        self.assertFalse(Notification.objects.filter(recipient=self.dealer, type='order').exists())
        self.client.force_authenticate(self.farmer)

    def test_unpaid_reservation_is_not_a_dealer_order(self):
        self.reserve()
        self.assert_dealer_has_no_order()
        self.client.force_authenticate(self.dealer)
        self.assertEqual(self.client.get(reverse('order-list')).data['count'], 0)

    def test_checkout_idempotency_key_reserves_stock_once(self):
        key = uuid.uuid4()
        first, second = self.reserve(key), self.reserve(key)
        self.assertEqual(first.pk, second.pk)
        self.assertEqual(Order.objects.count(), 1)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)

    def test_unresolved_payment_does_not_create_second_attempt_or_repeat_charge(self):
        order = self.reserve()
        payment = self.attempt(order)
        self.gateway.request_payment.side_effect = PaymentStatusUnknown('Confirmation delayed')
        with patch('payments.services.get_gateway', return_value=self.gateway):
            first = self.process(payment)
            retry = self.attempt(order)
            second = self.process(payment)
        self.assertEqual(first.data['status'], 'processing')
        self.assertEqual(second.data['status'], 'processing')
        self.assertEqual(retry.pk, payment.pk)
        self.assertEqual(self.gateway.request_payment.call_count, 1)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)
        self.assert_dealer_has_no_order()

    def test_changed_quote_is_rejected_before_submitting_or_changing_payment_state(self):
        payment = self.attempt(self.reserve())
        with patch('payments.services.get_gateway', return_value=self.gateway):
            response = self.client.post(reverse('payment-process-payment', args=[payment.pk]),
                                        {'expected_amount': '1999.00'}, format='json')
        self.assertEqual(response.status_code, 400)
        self.gateway.request_payment.assert_not_called()
        payment.refresh_from_db()
        self.assertEqual(payment.status, 'pending')
        self.assertIsNone(payment.submitted_at)
        self.assert_dealer_has_no_order()

    @override_settings(DEBUG=False, PAYMENT_SIMULATOR_ENABLED=False, MTN_MOMO_ENABLED=False)
    def test_readiness_exposes_server_premium_price_and_no_fake_enabled_methods(self):
        with patch('payments.views.PREMIUM_PRICE_PER_MONTH', Decimal('1500')):
            response = self.client.get(reverse('payment-methods'))
        self.assertEqual(response.data['premium_price_per_month'], '1500')
        self.assertTrue(all(not m['available'] for m in response.data['methods']))

    def test_processing_is_claimed_before_external_call(self):
        payment = self.attempt(self.reserve())
        def external(**kwargs):
            self.assertEqual(Payment.objects.get(pk=payment.pk).status, 'processing')
            self.assertEqual(process_collection(payment.pk).status, 'processing')
            return {'status': 'processing'}
        self.gateway.request_payment.side_effect = external
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.process(payment)
        self.assertEqual(self.gateway.request_payment.call_count, 1)

    def test_verified_success_publishes_order_and_ledger_exactly_once(self):
        order = self.reserve()
        payment = self.attempt(order)
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.process(payment)
            self.assert_dealer_has_no_order()
            self.gateway.verify_transaction.return_value = 'completed'
            for _ in range(2):
                response = self.client.get(reverse('payment-verify', args=[payment.pk]))
                self.assertEqual(response.data['status'], 'completed')
        order.refresh_from_db()
        self.assertEqual(order.status, 'confirmed')
        self.assertEqual(order.payment_status, 'paid')
        self.assertIsNone(order.reserved_until)
        self.assertEqual(LedgerEntry.objects.filter(payment=payment).count(), 1)
        self.assertEqual(Notification.objects.filter(recipient=self.dealer, type='order').count(), 1)
        self.client.force_authenticate(self.dealer)
        self.assertEqual(len(self.client.get(reverse('order-order-history')).data), 1)

    def test_failed_payment_and_cancelling_it_restore_stock_only_once(self):
        order = self.reserve()
        payment = self.attempt(order, phone='670000009')
        self.assertEqual(self.process(payment).data['status'], 'failed')
        finalize_payment_failed(payment.pk)
        self.client.post(reverse('order-cancel', args=[order.pk]))
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)
        self.assert_dealer_has_no_order()
        self.assertFalse(LedgerEntry.objects.exists())

    def test_failed_retry_gets_new_reference_and_rechecks_stock(self):
        order = self.reserve()
        failed = self.attempt(order, phone='670000009')
        self.process(failed)
        retry = self.attempt(order)
        self.assertNotEqual(failed.provider_reference, retry.provider_reference)
        self.product.stock_quantity = 0
        self.product.save(update_fields=['stock_quantity'])
        self.assertEqual(self.process(retry).status_code, 400)
        order.refresh_from_db()
        self.assertEqual(order.status, 'payment_failed')

    def test_processing_payment_cannot_be_cancelled_or_expired(self):
        order = self.reserve()
        payment = self.attempt(order)
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.process(payment)
        self.assertEqual(self.client.post(reverse('order-cancel', args=[order.pk])).status_code, 409)
        order.reserved_until = timezone.now() - timezone.timedelta(hours=1)
        order.save(update_fields=['reserved_until'])
        self.assertEqual(release_stale_reservations_task(), 0)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)

    def test_late_success_after_cancellation_requires_review_not_fulfilment(self):
        order = self.reserve()
        payment = self.attempt(order)
        self.client.post(reverse('order-cancel', args=[order.pk]))
        result = complete_payment(payment.pk)
        self.assertEqual(result.status, 'review_required')
        order.refresh_from_db()
        self.assertEqual(order.status, 'cancelled')
        self.assertEqual(order.payment_status, 'unpaid')
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)
        self.assert_dealer_has_no_order()
        complete_payment(payment.pk)
        self.assertEqual(LedgerEntry.objects.filter(payment=payment).count(), 1)
        self.assertEqual(Notification.objects.filter(recipient=self.admin, type='payment').count(), 1)

    def test_legacy_unreserved_order_cannot_submit_a_new_collection(self):
        order = Order.objects.create(farmer=self.farmer, product=self.product,
                                     quantity=2, total_price=2000)
        payment = self.attempt(order)
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.assertEqual(self.process(payment).status_code, 400)
        self.gateway.request_payment.assert_not_called()
        self.assert_dealer_has_no_order()
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 5)

    def test_verified_legacy_unreserved_collection_is_held_for_review(self):
        order = Order.objects.create(farmer=self.farmer, product=self.product,
                                     quantity=2, total_price=2000)
        payment = self.attempt(order)
        result = complete_payment(payment.pk)
        self.assertEqual(result.status, 'review_required')
        self.assertEqual(LedgerEntry.objects.filter(payment=payment).count(), 1)
        order.refresh_from_db()
        self.assertEqual(order.payment_status, 'unpaid')
        self.assert_dealer_has_no_order()

    def test_failed_retry_cannot_charge_for_a_withdrawn_product(self):
        order = self.reserve()
        failed = self.attempt(order, phone='670000009')
        self.process(failed)
        self.product.is_available = False
        self.product.save(update_fields=['is_available'])
        retry = self.attempt(order)
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.assertEqual(self.process(retry).status_code, 400)
        self.gateway.request_payment.assert_not_called()
        self.assert_dealer_has_no_order()

    def test_dealer_cannot_delete_a_product_and_erase_payment_order_history(self):
        order = self.reserve()
        payment = self.attempt(order)
        self.client.force_authenticate(self.dealer)
        response = self.client.delete(reverse('product-detail', args=[self.product.pk]))
        self.assertEqual(response.status_code, 409)
        self.assertTrue(Order.objects.filter(pk=order.pk).exists())
        self.assertTrue(Payment.objects.filter(pk=payment.pk, order=order).exists())

    def test_collected_payment_with_missing_legacy_order_is_not_lost(self):
        order = self.reserve()
        payment = self.attempt(order)
        # An old admin cascade could remove the order while MTN was processing.
        order.delete()
        for _ in range(2):
            self.assertEqual(complete_payment(payment.pk).status, 'review_required')
        self.assertEqual(LedgerEntry.objects.filter(payment=payment).count(), 1)
        self.assertEqual(Notification.objects.filter(recipient=self.admin, type='payment').count(), 1)
        self.assert_dealer_has_no_order()

    def test_forged_mtn_callback_cannot_mark_order_paid(self):
        order = self.reserve()
        payment = self.attempt(order)
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.process(payment)
            self.client.force_authenticate(None)
            response = self.client.post(reverse('payment_mtn_callback'),
                {'externalId': payment.transaction_id, 'status': 'SUCCESSFUL'}, format='json')
        self.assertEqual(response.status_code, 200)
        order.refresh_from_db()
        self.assertEqual(order.payment_status, 'unpaid')
        self.assertFalse(LedgerEntry.objects.exists())

    def test_duplicate_real_callbacks_cannot_duplicate_ledger_or_notification(self):
        order = self.reserve()
        payment = self.attempt(order)
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.process(payment)
            self.gateway.verify_transaction.return_value = 'completed'
            for _ in range(2):
                self.client.post(reverse('payment_mtn_callback'), {'externalId': payment.transaction_id,
                                  'status': 'FAILED'}, format='json')
        order.refresh_from_db()
        self.assertEqual(order.payment_status, 'paid', 'Callback body is only a hint; authenticated GET is truth')
        self.assertEqual(LedgerEntry.objects.filter(payment=payment).count(), 1)
        self.assertEqual(Notification.objects.filter(recipient=self.dealer, type='order').count(), 1)

    def test_verification_errors_keep_reservation_and_allow_reconciliation(self):
        payment = self.attempt(self.reserve())
        with patch('payments.services.get_gateway', return_value=self.gateway):
            self.process(payment)
            self.gateway.verify_transaction.side_effect = PaymentError('Provider not reachable')
            response = self.client.get(reverse('payment-verify', args=[payment.pk]))
        self.assertEqual(response.data['status'], 'processing')
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock_quantity, 3)

    def test_non_finite_or_wrong_amount_is_rejected(self):
        order = self.reserve()
        for amount in ('NaN', 'Infinity', '-Infinity', '2000.001', '-1', '0'):
            response = self.client.post(reverse('payment-list'), {'order': order.pk, 'amount': amount,
                'payment_method': 'MTN_MOMO', 'phone_number': '670000008'}, format='json')
            self.assertEqual(response.status_code, 400)
        self.assertFalse(Payment.objects.exists())

    def test_order_and_payment_cannot_be_patched_to_fake_paid(self):
        order = self.reserve()
        payment = self.attempt(order)
        self.assertEqual(self.client.patch(reverse('order-detail', args=[order.pk]),
                         {'payment_status': 'paid', 'status': 'confirmed'}, format='json').status_code, 405)
        self.assertEqual(self.client.patch(reverse('payment-detail', args=[payment.pk]),
                         {'status': 'completed', 'amount': 1}, format='json').status_code, 405)
        self.assert_dealer_has_no_order()

    def test_unknown_or_other_buyers_payment_is_clean_404(self):
        self.assertEqual(self.client.post(reverse('payment-process-payment', args=[99999])).status_code, 404)
        payment = self.attempt(self.reserve())
        self.client.force_authenticate(self.dealer)
        self.assertEqual(self.process(payment).status_code, 404)

    @override_settings(DEBUG=False, PAYMENT_WEBHOOK_SECRET='dev-webhook-secret')
    def test_development_webhook_secret_is_not_valid_in_production(self):
        response = self.client.post(reverse('payment_webhook'), {}, format='json')
        self.assertEqual(response.status_code, 503)

    def test_push_only_happens_after_transaction_commit(self):
        payment = self.attempt(self.reserve())
        with patch('realtime.services.send_to_user') as push:
            with self.captureOnCommitCallbacks(execute=True):
                self.process(payment)
                push.assert_not_called()
            self.assertTrue(push.called)
