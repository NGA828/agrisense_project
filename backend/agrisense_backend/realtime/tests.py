import asyncio

from channels.testing import WebsocketCommunicator
from django.test import TestCase, TransactionTestCase, override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from users.models import User
from realtime.models import PushDevice
from realtime.push_provider import NoopPushProvider, get_push_provider

from agrisense_backend.asgi import application


def make_user(username, role='farmer'):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


def _access_token(user):
    return str(RefreshToken.for_user(user).access_token)


class PushTokenRegistrationTests(APITestCase):
    def setUp(self):
        self.user = make_user('farmer1')
        self.client.force_authenticate(user=self.user)

    def test_register_push_token(self):
        resp = self.client.post(reverse('register_push_token'), {
            'token': 'fcm-token-abc123', 'provider': 'fcm', 'platform': 'android',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        device = PushDevice.objects.get(user=self.user)
        self.assertEqual(device.token, 'fcm-token-abc123')
        self.assertTrue(device.is_active)

    def test_register_requires_auth(self):
        self.client.force_authenticate(user=None)
        resp = self.client.post(reverse('register_push_token'), {
            'token': 'fcm-token-abc123', 'provider': 'fcm', 'platform': 'android',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_register_rejects_short_token(self):
        resp = self.client.post(reverse('register_push_token'), {
            'token': 'short', 'provider': 'fcm', 'platform': 'android',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unregister_deactivates(self):
        PushDevice.objects.create(user=self.user, token='t1', provider='fcm', platform='android')
        resp = self.client.post(reverse('unregister_push_token'), {'token': 't1'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(PushDevice.objects.get(user=self.user, token='t1').is_active)


class PushConsumerTests(TransactionTestCase):
    # Uses TransactionTestCase (not TestCase) because the WebSocket consumer
    # resolves the user via database_sync_to_async in a threadpool thread,
    # which cannot see data inside a per-test transaction.
    def test_unauthenticated_connection_closed(self):
        async def scenario():
            comm = WebsocketCommunicator(application, '/ws/push/')
            connected, _ = await comm.connect()
            await comm.disconnect()
            return connected
        self.assertFalse(asyncio.run(scenario()))

    def test_authenticated_connection_joins_user_group(self):
        user = make_user('farmer1')
        token = _access_token(user)

        async def scenario():
            comm = WebsocketCommunicator(application, f'/ws/push/?token={token}')
            connected, _ = await comm.connect()
            response = await comm.receive_json_from(timeout=2)
            await comm.disconnect()
            return connected, response
        connected, response = asyncio.run(scenario())
        self.assertTrue(connected)
        self.assertEqual(response['type'], 'connected')
        self.assertEqual(response['user_id'], user.id)

    def test_receives_pushed_notification_event(self):
        user = make_user('farmer1')
        token = _access_token(user)

        async def scenario():
            comm = WebsocketCommunicator(application, f'/ws/push/?token={token}')
            await comm.connect()
            await comm.receive_json_from(timeout=2)  # consume 'connected' ack
            from realtime.services import asend_to_user
            await asend_to_user(user.id, 'notification', title='Hi', message='Test')
            event = await comm.receive_json_from(timeout=2)
            await comm.disconnect()
            return event
        event = asyncio.run(scenario())
        self.assertEqual(event['type'], 'notification')
        self.assertEqual(event['payload']['title'], 'Hi')

    def test_ping_gets_pong(self):
        user = make_user('farmer1')
        token = _access_token(user)

        async def scenario():
            comm = WebsocketCommunicator(application, f'/ws/push/?token={token}')
            await comm.connect()
            await comm.receive_json_from(timeout=2)  # ack
            await comm.send_json_to({'type': 'ping'})
            pong = await comm.receive_json_from(timeout=2)
            await comm.disconnect()
            return pong
        self.assertEqual(asyncio.run(scenario())['type'], 'pong')


class PushProviderTests(TestCase):
    def test_default_provider_is_noop(self):
        with override_settings(PUSH_PROVIDER='noop'):
            self.assertIsInstance(get_push_provider(), NoopPushProvider)

    def test_notify_creates_notification_and_device_push_is_best_effort(self):
        user = make_user('farmer1')
        from realtime.models import PushDevice
        PushDevice.objects.create(user=user, token='fcm-tok', provider='fcm', platform='android')
        from announcements.models import notify_user
        n = notify_user(user, 'Title', 'Body', type='system', reference_id='1')
        self.assertIsNotNone(n)
        self.assertEqual(user.notifications.count(), 1)
