# AgriSense AI — Load Testing

Phase F provides two complementary load-testing tools.

## Locust (Python, scenario-based)

Install and run:

```bash
pip install locust
locust -f load_tests/locustfile.py --host https://staging.agrisense.example
```

Open http://localhost:8089 to start a run with N users and a spawn rate. The
scenario (`FarmerUser`) covers login, marketplace browse, weather, diagnosis
history and notifications.

> ⚠️ Always target a **staging** environment with a disposable DB. Each user
> registers a fresh account so tests don't collide with real data.

## k6 (Go/JS, scripted)

Install from https://grafana.com/grafana/k6/, then:

```bash
k6 run -e BASE_URL=https://staging.agrisense.example load_tests/k6_smoke.js
```

`k6_smoke.js` is a lightweight smoke test (login + marketplace + weather) that
fails the run if error rate or latency exceeds a threshold — useful in CI as a
gate before deploys.

## What to watch

- **Auth throttle** — registration/login are rate-limited (10/min per IP). For
  high concurrency, reuse a shared pool of seed accounts instead of per-user
  registration.
- **AI throttle** — `/diagnosis/analyze/` is rate-limited (30/min/user); keep
  diagnosis load within that or scale the throttle for the test.
- **Weather cache** — responses are cached, so repeated requests hit the cache
  rather than OpenWeatherMap.
