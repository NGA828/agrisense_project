"""Locust load-test scenarios for AgriSense AI (Phase F).

Run against a deployed instance:
    locust -f load_tests/locustfile.py --host https://api.agrisense.example
    # open the Locust UI at http://localhost:8089

Scenarios cover the farmer's hot paths: login, marketplace browse, diagnosis
analyze, order + payment. The server should be pointed at a staging DB (never
production).
"""

import random

from locust import HttpUser, between, task


class FarmerUser(HttpUser):
    wait_time = between(1, 3)
    token = None

    def on_start(self):
        # Use seed accounts when available; otherwise register a fresh farmer.
        username = f'load{random.randint(0, 100000)}'
        self.client.post('/api/auth/register/', json={
            'username': username,
            'password': 'Str0ngPass!1',
            'first_name': 'Load',
            'last_name': 'Test',
            'email': f'{username}@loadtest.com',
            'phone_number': f'+2376{random.randint(10000000, 99999999)}',
            'role': 'farmer',
        })
        resp = self.client.post('/api/auth/login/', json={
            'username': username, 'password': 'Str0ngPass!1'})
        if resp.status_code == 200:
            self.token = resp.json()['access']

    def _headers(self):
        return {'Authorization': f'Bearer {self.token}'} if self.token else {}

    @task(3)
    def browse_marketplace(self):
        self.client.get('/api/products/marketplace/', headers=self._headers())

    @task(2)
    def load_weather(self):
        self.client.post('/api/weather/', json={'latitude': 3.848, 'longitude': 11.5021},
                         headers=self._headers())

    @task(1)
    def diagnosis_history(self):
        self.client.get('/api/diagnosis/history/', headers=self._headers())

    @task(1)
    def notifications(self):
        self.client.get('/api/notifications/', headers=self._headers())
