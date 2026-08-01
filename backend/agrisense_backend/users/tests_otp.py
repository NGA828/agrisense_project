from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from users.models import User, OTPRequest
from users.otp_service import send_otp, verify_otp


class OTPTests(APITestCase):
    def test_send_otp_creates_request_and_returns_debug_code_in_debug(self):
        with override_settings(DEBUG=True):
            code = send_otp('+237670000001', 'register')
        self.assertIsNotNone(code)
        req = OTPRequest.objects.get()
        self.assertEqual(req.phone_number, '237670000001')
        self.assertEqual(req.purpose, 'register')
        # Code is stored hashed, never plaintext.
        self.assertNotEqual(req.code_hash, code)
        self.assertFalse(req.is_used)

    def test_verify_otp_success_is_single_use(self):
        with override_settings(DEBUG=True):
            code = send_otp('+237670000002', 'register')
        ok, _ = verify_otp('+237670000002', 'register', code)
        self.assertTrue(ok)
        # Reusing the same code fails (single-use).
        ok2, _ = verify_otp('+237670000002', 'register', code)
        self.assertFalse(ok2)

    def test_verify_wrong_code_increments_attempts(self):
        with override_settings(DEBUG=True):
            send_otp('+237670000003', 'register')
        ok, _ = verify_otp('+237670000003', 'register', '000000')
        self.assertFalse(ok)
        req = OTPRequest.objects.get()
        self.assertEqual(req.attempts, 1)

    def test_verify_no_request_rejected(self):
        ok, _ = verify_otp('+237699999999', 'register', '123456')
        self.assertFalse(ok)

    def test_otp_send_endpoint(self):
        with override_settings(DEBUG=True):
            resp = self.client.post(reverse('request_otp'),
                                    {'phone_number': '+237670000004', 'purpose': 'register'},
                                    format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('debug_code', resp.data)

    def test_otp_verify_endpoint(self):
        with override_settings(DEBUG=True):
            code = send_otp('+237670000005', 'register')
            resp = self.client.post(reverse('verify_otp'),
                                    {'phone_number': '+237670000005', 'purpose': 'register',
                                     'code': code}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_registration_requires_otp_when_enabled(self):
        with override_settings(OTP_REQUIRED_FOR_REGISTRATION=True):
            with override_settings(DEBUG=True):
                code = send_otp('+237670000006', 'register')
            # Missing code -> rejected.
            resp = self.client.post(reverse('register'), {
                'username': 'farmer1', 'password': 'Str0ngPass!1',
                'first_name': 'A', 'last_name': 'B', 'email': 'a@b.com',
                'phone_number': '+237670000006', 'role': 'farmer',
            }, format='json')
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
            # Valid code -> created.
            resp = self.client.post(reverse('register'), {
                'username': 'farmer1', 'password': 'Str0ngPass!1',
                'first_name': 'A', 'last_name': 'B', 'email': 'a@b.com',
                'phone_number': '+237670000006', 'role': 'farmer',
                'otp_code': code,
            }, format='json')
            self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
            self.assertTrue(User.objects.filter(username='farmer1').exists())
