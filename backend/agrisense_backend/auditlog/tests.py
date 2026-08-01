from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from .models import AuditLog


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class AuditLogTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin')
        self.farmer = make_user('farmer1', 'farmer')

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_suspend_writes_audit_log(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('user-suspend', args=[self.farmer.id]),
                                {'reason': 'fraud'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        log = AuditLog.objects.get(action='suspend_user')
        self.assertEqual(log.actor, self.admin)
        self.assertEqual(log.target_type, 'user')
        self.assertEqual(str(log.target_id), str(self.farmer.id))
        self.assertEqual(log.metadata['reason'], 'fraud')

    def test_non_admin_cannot_read_audit_log(self):
        self.auth(self.farmer)
        resp = self.client.get(reverse('audit-log-list'))
        # Filtered to empty for non-admins.
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['count'], 0)

    def test_admin_can_read_and_filter_audit_log(self):
        self.auth(self.admin)
        self.client.post(reverse('user-suspend', args=[self.farmer.id]))
        resp = self.client.get(reverse('audit-log-list') + '?category=user')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertGreater(resp.data['count'], 0)

    def test_audit_log_cannot_be_created_via_api(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('audit-log-list'), {
            'action': 'x', 'category': 'user',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_delete_user_writes_audit_log(self):
        self.auth(self.admin)
        resp = self.client.delete(reverse('user-detail', args=[self.farmer.id]))
        self.assertEqual(resp.status_code, status.HTTP_204_NO_CONTENT)
        self.assertTrue(AuditLog.objects.filter(action='delete_user').exists())
