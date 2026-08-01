import uuid

from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from diagnosis.models import Diagnosis, Location


def make_diagnosis(**kwargs):
    kwargs.setdefault('id', str(uuid.uuid4()))
    return Diagnosis.objects.create(**kwargs)


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class RegionalAnalyticsTests(APITestCase):
    def setUp(self):
        self.admin = make_user('admin1', 'admin')
        self.farmer = make_user('farmer1', 'farmer')
        # Two diagnoses near each other (same ~0.4° bucket) and one far away.
        loc_a = Location.objects.create(latitude=3.85, longitude=11.50,
                                        address='Yaoundé', climate_zone='tropical')
        loc_b = Location.objects.create(latitude=3.86, longitude=11.52,
                                        address='Yaoundé N', climate_zone='tropical')
        loc_far = Location.objects.create(latitude=10.1, longitude=14.2,
                                          address='Far North', climate_zone='sahel')
        for _ in range(2):
            make_diagnosis(user=self.farmer, crop_type='Tomato',
                           disease_name='Early Blight', severity='medium',
                           confidence=90, location=loc_a)
        make_diagnosis(user=self.farmer, crop_type='Maize',
                       disease_name='Rust', severity='medium',
                       confidence=85, location=loc_b)
        make_diagnosis(user=self.farmer, crop_type='Tomato',
                       disease_name='Late Blight', severity='high',
                       confidence=92, location=loc_far)

    def test_admin_only(self):
        self.client.force_authenticate(user=self.farmer)
        resp = self.client.get(reverse('admin_regional_analytics'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_regional_aggregation(self):
        self.client.force_authenticate(user=self.admin)
        resp = self.client.get(reverse('admin_regional_analytics'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['total_diagnoses'], 4)
        # by_crop groups diseases per crop.
        self.assertEqual(resp.data['by_crop']['Tomato']['Early Blight'], 2)
        self.assertEqual(resp.data['by_crop']['Maize']['Rust'], 1)
        # geo_points clusters the two Yaoundé diagnoses into one bucket.
        points = resp.data['geo_points']
        self.assertEqual(len(points), 2)
        biggest = max(points, key=lambda p: p['total'])
        self.assertEqual(biggest['total'], 3)
        self.assertEqual(biggest['top_disease'], 'Early Blight')
