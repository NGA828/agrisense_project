import uuid
from datetime import timedelta

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from diagnosis.models import Diagnosis, Location, OutbreakAlert
from diagnosis.services import detect_outbreak_alerts


def make_user(username, role='farmer'):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name='F', last_name='T', email=f'{username}@t.com',
        phone_number='+237600000000', role=role,
    )


def make_diag(user, disease, crop, lat, lon, days_ago=0):
    loc = Location.objects.create(latitude=lat, longitude=lon,
                                  address='loc', climate_zone='tropical')
    d = Diagnosis.objects.create(id=str(uuid.uuid4()), user=user, crop_type=crop,
                                 disease_name=disease, severity='medium',
                                 confidence=90, location=loc)
    d.created_at = timezone.now() - timedelta(days=days_ago)
    d.save(update_fields=['created_at'])
    return d


class OutbreakDetectionTests(TestCase):
    def test_growing_cluster_is_detected_and_notifies(self):
        farmer = make_user('farmer1')
        nearby = make_user('farmer2')

        # Two nearby farmers have diagnosed 'Early Blight' around Yaoundé.
        # Recent window (now): 4 diagnoses (2 from each farmer) in same bucket.
        for i in range(2):
            make_diag(farmer, 'Early Blight', 'Tomato', 3.86, 11.50)
            make_diag(nearby, 'Early Blight', 'Tomato', 3.87, 11.51)
        # Previous window: only 1 case (so it grew 4x).
        make_diag(farmer, 'Early Blight', 'Tomato', 3.85, 11.49, days_ago=10)

        alerts = detect_outbreak_alerts(save=True)
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0]['disease'], 'Early Blight')
        self.assertGreaterEqual(alerts[0]['cluster_size'], 4)
        # Both nearby farmers are notified (they have diagnoses near the cluster).
        self.assertGreater(alerts[0]['notified'], 0)
        self.assertEqual(OutbreakAlert.objects.count(), 1)
        self.assertGreater(farmer.notifications.filter(reference_id__contains='outbreak').count(), 0)

    def test_non_growing_cluster_not_alerted(self):
        user = make_user('farmer1')
        # 3 cases now, but 4 in the previous window -> not growing.
        for i in range(3):
            make_diag(user, 'Rust', 'Maize', 5.0, 10.0)
        for i in range(4):
            make_diag(user, 'Rust', 'Maize', 5.0, 10.0, days_ago=10)

        alerts = detect_outbreak_alerts(save=True)
        self.assertEqual(len(alerts), 0)
        self.assertEqual(OutbreakAlert.objects.count(), 0)

    def test_cooldown_prevents_repeat_alert(self):
        user = make_user('farmer1')
        for i in range(3):
            make_diag(user, 'Late Blight', 'Tomato', 4.0, 9.0)
        detect_outbreak_alerts(save=True)
        self.assertEqual(OutbreakAlert.objects.count(), 1)
        # A second run within cooldown does not create another alert.
        detect_outbreak_alerts(save=True)
        self.assertEqual(OutbreakAlert.objects.count(), 1)


class OutbreakAdminEndpointTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin')
        self.farmer = make_user('farmer1')
        OutbreakAlert.objects.create(
            disease_name='Early Blight', crop_name='Tomato',
            latitude=3.8, longitude=11.5, cluster_size=5, previous_size=1,
            notified_users=3, status='notified',
        )

    def test_admin_lists_outbreaks(self):
        self.client.force_authenticate(user=self.admin)
        resp = self.client.get(reverse('admin_outbreaks'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['count'], 1)
        self.assertEqual(resp.data['alerts'][0]['disease_name'], 'Early Blight')

    def test_farmer_forbidden(self):
        self.client.force_authenticate(user=self.farmer)
        resp = self.client.get(reverse('admin_outbreaks'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
