from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from sensors.models import SensorDevice, SensorReading


def make_user(username, role='farmer'):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


class SensorTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1')
        self.client.force_authenticate(user=self.farmer)

    def test_register_device(self):
        resp = self.client.post(reverse('sensor-list'), {
            'device_id': 'SENS-001', 'name': 'Field A', 'sensor_type': 'soil_moisture',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['owner'], self.farmer.id)

    def test_ingest_single_reading(self):
        device = SensorDevice.objects.create(owner=self.farmer, device_id='SENS-002',
                                             sensor_type='soil_moisture')
        resp = self.client.post(reverse('sensor-ingest', args=[device.id]), {
            'device_id': 'SENS-002', 'sensor_type': 'soil_moisture', 'value': 35.0,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['ingested'], 1)
        self.assertEqual(SensorReading.objects.count(), 1)

    def test_ingest_batch(self):
        device = SensorDevice.objects.create(owner=self.farmer, device_id='SENS-003',
                                             sensor_type='soil_moisture')
        resp = self.client.post(reverse('sensor-ingest', args=[device.id]), {
            'device_id': 'SENS-003', 'sensor_type': 'soil_moisture',
            'readings': [{'value': 30}, {'value': 40}],
        }, format='json')
        self.assertEqual(resp.data['ingested'], 2)

    def test_latest_with_advice(self):
        device = SensorDevice.objects.create(owner=self.farmer, device_id='SENS-004',
                                             sensor_type='soil_moisture')
        SensorReading.objects.create(device=device, value=20, recorded_at='2026-01-01T00:00:00Z')
        resp = self.client.get(reverse('sensor-latest', args=[device.id]))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('irrigation', resp.data['advice'].lower())

    def test_users_only_see_own_devices(self):
        other = make_user('farmer2')
        SensorDevice.objects.create(owner=other, device_id='SENS-OTHER',
                                    sensor_type='soil_moisture')
        resp = self.client.get(reverse('sensor-list'))
        self.assertEqual(resp.data['count'], 0)


class UssdTests(APITestCase):
    def setUp(self):
        self.farmer = User.objects.create_user(
            username='farmer1', password='Str0ngPass!',
            first_name='F', last_name='T', email='f@t.com',
            phone_number='+237670000001', role='farmer',
        )

    def test_unknown_number(self):
        resp = self.client.post(reverse('ussd_handler'),
                                {'phoneNumber': '+237699999999', 'text': ''}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data['release'])

    def test_root_menu(self):
        resp = self.client.post(reverse('ussd_handler'),
                                {'phoneNumber': '+237670000001', 'text': ''}, format='json')
        self.assertFalse(resp.data['release'])
        self.assertIn('Weather', resp.data['text'])

    def test_last_diagnosis(self):
        from diagnosis.models import Diagnosis
        import uuid
        Diagnosis.objects.create(id=str(uuid.uuid4()), user=self.farmer,
                                 crop_type='Tomato', disease_name='Early Blight',
                                 confidence=90, severity='medium')
        resp = self.client.post(reverse('ussd_handler'),
                                {'phoneNumber': '+237670000001', 'text': '2'}, format='json')
        self.assertTrue(resp.data['release'])
        self.assertIn('Early Blight', resp.data['text'])
