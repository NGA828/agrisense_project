import io
from decimal import Decimal
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from PIL import Image
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User
from diagnosis.models import Disease, Diagnosis


def make_user(username, role):
    return User.objects.create_user(
        username=username, password='Str0ngPass!',
        first_name=username.title(), last_name='Test',
        email=f'{username}@test.com', phone_number='+237600000000',
        role=role,
    )


def png_bytes(color=(120, 140, 100), size=(64, 64)):
    buf = io.BytesIO()
    Image.new('RGB', size, color).save(buf, format='PNG')
    buf.seek(0)
    return buf


@override_settings(AI_ENGINE='rules', AI_REQUIRE_TRAINED_MODEL=False)
class DiagnosisTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.admin = make_user('admin1', 'admin')
        self.dealer = make_user('dealer1', 'dealer')
        Disease.objects.create(
            disease_name='Test Blight', crop_name='Tomato', pathogen='X',
            symptoms='spots', causes='fungus', severity='medium',
            prevention='rotate', medication='copper',
            instructions='spray', duration=14,
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_analyze_with_image(self):
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(), 'crop_type': 'Tomato'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertIn('disease_name', resp.data)
        self.assertIn('confidence', resp.data)
        self.assertGreaterEqual(float(resp.data['confidence']), 0)
        self.assertIn('treatment_plan', resp.data)
        self.assertEqual(resp.data['engine'], 'rule-based')
        self.assertEqual(resp.data['model_version'], 'v2.0-rules')
        self.assertTrue(Diagnosis.objects.filter(user=self.farmer).exists())

    @patch('diagnosis.views.analyze_disease')
    def test_analyze_persists_trained_model_provenance(self, mock_analyze):
        mock_analyze.return_value = {
            'disease_name': 'Test Blight',
            'confidence': Decimal('91.25'),
            'severity': 'medium',
            'is_healthy': False,
            'symptoms': 'spots',
            'causes': 'fungus',
            'prevention': 'rotate',
            'treatment_type': 'Fungicide',
            'medication': 'copper',
            'instructions': 'spray',
            'duration': 14,
            'engine': 'tensorflow-cnn',
            'trained_model': True,
            'model_version': 'field-model-3',
            'model_label': 'Tomato___Test_blight',
            'alternatives': [
                {'disease_name': 'Test Blight', 'confidence': 91.25},
            ],
        }
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(), 'crop_type': 'Tomato'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['engine'], 'tensorflow-cnn')
        self.assertTrue(resp.data['trained_model'])
        self.assertEqual(resp.data['model_version'], 'field-model-3')
        diagnosis = Diagnosis.objects.get(user=self.farmer)
        self.assertEqual(diagnosis.inference_engine, 'tensorflow-cnn')
        self.assertTrue(diagnosis.used_trained_model)
        self.assertEqual(diagnosis.model_label, 'Tomato___Test_blight')
        self.assertEqual(len(diagnosis.alternatives), 1)

    @patch('diagnosis.views.analyze_disease')
    def test_unavailable_model_returns_503_without_saving(self, mock_analyze):
        from ai_engine.services import AIEngineUnavailable
        mock_analyze.side_effect = AIEngineUnavailable('model file missing')
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(), 'crop_type': 'Tomato'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(resp.data['code'], 'ai_model_unavailable')
        self.assertFalse(Diagnosis.objects.filter(user=self.farmer).exists())

    def test_analyze_requires_crop_type(self):
        """AI v2 crop-mandatory guard: no crop -> rejected, not Tomato fallback."""
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes()},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('select the crop', resp.data['error'].lower())

    def test_analyze_rejects_unsupported_crop(self):
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(), 'crop_type': 'Mango'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_analyze_healthy_leaf_stores_healthy_flag(self):
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(color=(80, 160, 70)), 'crop_type': 'Tomato'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(resp.data['is_healthy'])
        diagnosis = Diagnosis.objects.get(user=self.farmer)
        self.assertTrue(diagnosis.is_healthy)

    def test_analyze_rejects_bad_type(self):
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': io.BytesIO(b'not-an-image'), 'crop_type': 'Tomato'},
            format='multipart',
        )
        # Content type is text/plain by default for BytesIO => rejected pre-inference.
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_analyze_rejects_fake_image_even_with_allowed_content_type(self):
        self.auth(self.farmer)
        fake = SimpleUploadedFile(
            'fake.png', b'not really a png', content_type='image/png')
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': fake, 'crop_type': 'Tomato'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_analyze_requires_auth(self):
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(), 'crop_type': 'Tomato'},
            format='multipart',
        )
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_history_scoped_to_user(self):
        self.auth(self.farmer)
        resp = self.client.post(
            reverse('diagnosis-analyze'),
            {'image': png_bytes(), 'crop_type': 'Tomato'},
            format='multipart',
        )
        resp = self.client.get(reverse('diagnosis-history'))
        self.assertEqual(len(resp.data), 1)


class DiseaseDatabaseTests(APITestCase):
    def setUp(self):
        self.farmer = make_user('farmer1', 'farmer')
        self.admin = make_user('admin1', 'admin')
        self.disease = Disease.objects.create(
            disease_name='Existing', crop_name='Maize', severity='low',
        )

    def auth(self, user):
        self.client.force_authenticate(user=user)

    def test_admin_can_add_disease(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('disease-db-add-disease'), {
            'disease_name': 'New Rust', 'crop_name': 'Maize',
            'pathogen': 'Puccinia', 'symptoms': 'pustules',
            'causes': 'fungus', 'severity': 'medium',
            'prevention': 'rotate', 'medication': 'azole',
            'instructions': 'spray', 'duration': 14,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(Disease.objects.filter(disease_name='New Rust').exists())

    def test_duplicate_disease_name_for_crop_is_rejected_case_insensitively(self):
        self.auth(self.admin)
        resp = self.client.post(reverse('disease-db-add-disease'), {
            'disease_name': 'existing', 'crop_name': 'maize', 'severity': 'low',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Disease.objects.count(), 1)

    def test_farmer_cannot_add_disease(self):
        self.auth(self.farmer)
        resp = self.client.post(reverse('disease-db-add-disease'), {
            'disease_name': 'Hack', 'crop_name': 'Maize', 'severity': 'low',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_farmer_cannot_update_disease(self):
        self.auth(self.farmer)
        resp = self.client.patch(reverse('disease-db-detail', args=[self.disease.id]),
                                 {'disease_name': 'Hacked'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_farmer_cannot_delete_disease(self):
        self.auth(self.farmer)
        resp = self.client.delete(reverse('disease-db-detail', args=[self.disease.id]))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_list_diseases_admin_only(self):
        self.auth(self.farmer)
        resp = self.client.get(reverse('disease-db-list-diseases'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_read_access_for_all_users(self):
        self.auth(self.farmer)
        resp = self.client.get(reverse('disease-db-supported-crops'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('Maize', resp.data)
