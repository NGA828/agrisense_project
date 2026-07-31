from django.test import TestCase

from .views import get_farming_advice


class FarmingAdviceTests(TestCase):
    def test_rain_advice(self):
        advice = get_farming_advice('Rain', 85, 90)
        self.assertIn('Avoid spraying chemicals', advice)
        self.assertIn('High humidity', advice)

    def test_clear_advice(self):
        advice = get_farming_advice('Clear', 20, 5)
        self.assertIn('Good day for spraying', advice)
        self.assertIn('Low humidity', advice)

    def test_generic_advice(self):
        advice = get_farming_advice('Fog', 50, 10)
        self.assertIn('Good conditions for general farm work', advice)
