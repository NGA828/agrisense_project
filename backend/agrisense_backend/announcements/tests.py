from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from announcements.models import Announcement, Notification, notify_user


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class AnnouncementTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin')
        self.farmer = make_user('farmer1', 'farmer')

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_only_admin_creates_announcement(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('announcement-list'), {
            'title': 'x', 'content': 'y', 'target_audience': 'all',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_creates_and_targets(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('announcement-list'), {
            'title': 'Weather alert', 'content': 'Rain expected',
            'target_audience': 'farmers',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['created_by'], self.admin.id)

    def test_farmer_sees_only_their_target(self):
        Announcement.objects.create(title='A', content='a', target_audience='all',
                                    created_by=self.admin)
        Announcement.objects.create(title='D', content='d', target_audience='dealers',
                                    created_by=self.admin)
        self.auth(self.farmer)
        resp = self.client.get(reverse('announcement-active'))
        titles = [a['title'] for a in resp.data]
        self.assertIn('A', titles)
        self.assertNotIn('D', titles)

    def test_toggle_active(self):
        ann = Announcement.objects.create(title='A', content='a',
                                          target_audience='all', created_by=self.admin)
        self.auth(self.admin)
        resp = self.client.post(reverse('announcement-toggle-active', args=[ann.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data['is_active'])

    def test_active_announcement_fans_out_to_target_users(self):
        """Creating/activating a broadcast materialises per-user notifications."""
        farmer = make_user('farmer2', 'farmer')
        dealer = make_user('dealer1', 'dealer')
        self.auth(self.admin)
        resp = self.client.post(reverse('announcement-list'), {
            'title': 'Locust alert', 'content': 'Spray your fields',
            'target_audience': 'farmers', 'is_active': True,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        # Farmers (both) get a notification; the dealer does not.
        self.assertEqual(farmer.notifications.count(), 1)
        self.assertEqual(self.farmer.notifications.count(), 1)
        self.assertEqual(dealer.notifications.count(), 0)
        self.assertEqual(farmer.notifications.first().reference_id,
                         f"announcement:{resp.data['id']}")

    def test_activating_inactive_announcement_broadcasts(self):
        ann = Announcement.objects.create(title='A', content='a',
                                          target_audience='all', created_by=self.admin,
                                          is_active=False)
        self.auth(self.admin)
        self.assertEqual(self.farmer.notifications.count(), 0)
        self.client.post(reverse('announcement-toggle-active', args=[ann.id]))
        self.assertEqual(self.farmer.notifications.count(), 1)


class NotificationTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.dealer = make_user('dealer1', 'dealer')

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_notify_user_creates_record(self):
        notify_user(self.farmer, 'Title', 'Message', type='order', reference_id='7')
        n = Notification.objects.get()
        self.assertEqual(n.recipient, self.farmer)
        self.assertEqual(n.reference_id, '7')
        self.assertFalse(n.is_read)

    def test_user_only_sees_own_notifications(self):
        notify_user(self.farmer, 'Yours', 'm', type='system')
        notify_user(self.dealer, 'Not yours', 'm', type='system')
        self.auth(self.farmer)
        resp = self.client.get(reverse('notification-list'))
        results = resp.data.get('results') if isinstance(resp.data, dict) else resp.data
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['title'], 'Yours')

    def test_unread_count_and_mark_read(self):
        n = notify_user(self.farmer, 'T', 'm', type='system')
        self.auth(self.farmer)
        resp = self.client.get(reverse('notification-unread-count'))
        self.assertEqual(resp.data['count'], 1)
        self.client.post(reverse('notification-mark-read', args=[n.id]))
        resp = self.client.get(reverse('notification-unread-count'))
        self.assertEqual(resp.data['count'], 0)
