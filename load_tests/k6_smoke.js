// k6 smoke test for AgriSense AI (Phase F).
// Run: k6 run -e BASE_URL=https://staging.agrisense.example load_tests/k6_smoke.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 5,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:8000/api';

export default function () {
  // Login with a seeded farmer.
  const login = http.post(`${BASE}/auth/login/`, JSON.stringify({
    username: 'farmer1', password: 'password123',
  }), { headers: { 'Content-Type': 'application/json' } });
  check(login, { 'login 200': (r) => r.status === 200 });
  const token = login.json('access');

  const headers = { Authorization: `Bearer ${token}` };

  const market = http.get(`${BASE}/products/marketplace/`, { headers });
  check(market, { 'marketplace 200': (r) => r.status === 200 });

  const weather = http.post(`${BASE}/weather/`,
    JSON.stringify({ latitude: 3.848, longitude: 11.5021 }),
    { headers: { ...headers, 'Content-Type': 'application/json' } });
  check(weather, { 'weather 200': (r) => r.status === 200 });

  sleep(1);
}
