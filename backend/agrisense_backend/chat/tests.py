from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from chat.models import ChatRoom, Message


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class ChatRoomTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')
        self.admin = make_user('admin1', 'admin')
        self.room = ChatRoom.objects.create(farmer=self.farmer, dealer=self.dealer)

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_get_or_create_room_is_idempotent(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('chat-list'), {'dealer': self.dealer.id}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)  # existing => 200
        self.assertEqual(ChatRoom.objects.count(), 1)

    def test_new_room_created(self):
        dealer2 = make_user('dealer2', 'dealer')
        self.auth(self.farmer)
        resp = self.client.post(reverse('chat-list'), {'dealer': dealer2.id}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(ChatRoom.objects.count(), 2)

    def test_admin_cannot_start_chat(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('chat-list'), {'dealer': self.dealer.id}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_room_list_scoped_to_participants(self):
        self.auth(self.farmer)
        resp = self.client.get(reverse('chat-list'))
        results = resp.data.get('results') if isinstance(resp.data, dict) else resp.data
        self.assertEqual(len(results), 1)
        self.assertIn('Dealer1', results[0]['other_user_name'])

    def test_send_and_list_messages(self):
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('chat-send-message', args=[self.room.id]),
            {'content': 'Hello dealer!'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['message'], 'Hello dealer!')
        self.assertEqual(resp.data['sender'], self.farmer.id)

        resp = self.client.get(reverse('chat-messages', args=[self.room.id]))
        self.assertEqual(len(resp.data), 1)
        self.assertIn('message', resp.data[0])
        self.assertIn('image_url', resp.data[0])

    def test_non_participant_blocked(self):
        stranger = make_user('farmer2', 'farmer')
        self.auth(stranger)
        resp = self.client.get(reverse('chat-messages', args=[self.room.id]))
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)
        resp2 = self.client.post(reverse('chat-send-message', args=[self.room.id]),
                                 {'content': 'hack'}, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_404_NOT_FOUND)

    def test_messages_marked_read_on_fetch(self):
        Message.objects.create(chat_room=self.room, sender=self.dealer, message='hi')
        self.auth(self.farmer)
        self.client.get(reverse('chat-messages', args=[self.room.id]))
        msg = Message.objects.get()
        self.assertTrue(msg.is_read)

    def test_unread_counts(self):
        Message.objects.create(chat_room=self.room, sender=self.dealer, message='hi')
        self.auth(self.farmer)
        resp = self.client.get(reverse('chat-unread-counts'))
        self.assertEqual(resp.data[self.room.id], 1)
