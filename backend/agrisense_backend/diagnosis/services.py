"""Predictive outbreak alerting (Phase F — innovation #4).

Detects disease clusters that are *growing* (this window vs. the previous
window) and proactively warns nearby farmers, turning the passive regional
map into an early-warning system.

Detection:
  1. Bucket diagnoses with a location onto a ~0.4° grid, grouped by disease.
  2. Count each (bucket, disease) in the recent window vs. the previous window.
  3. A cluster "grows" when current >= MIN_CLUSTER_SIZE and it increased by at
     least GROWTH_FACTOR (or appeared from zero).
  4. Persist an ``OutbreakAlert`` (respecting a per-cluster cooldown) and notify
     farmers whose past diagnoses lie near the cluster centre.
"""

from django.conf import settings
from django.utils import timezone

from .models import Diagnosis, OutbreakAlert

GRID_SIZE = 0.4  # degrees per bucket (~44 km at the equator)


def _bucket(lat, lon):
    return round(lat / GRID_SIZE) * GRID_SIZE, round(lon / GRID_SIZE) * GRID_SIZE


def _detection_window():
    recent_days = int(getattr(settings, 'OUTBREAK_RECENT_DAYS', '7'))
    now = timezone.now()
    return now - timezone.timedelta(days=recent_days), \
        now - timezone.timedelta(days=2 * recent_days)


def _cluster_counts(window_start, window_end):
    """Map (bucket_lat, bucket_lon, disease) -> count within a window."""
    counts = {}
    qs = (
        Diagnosis.objects
        .filter(created_at__gte=window_start, created_at__lt=window_end,
                location__isnull=False)
        .select_related('location')
    )
    for d in qs.iterator():
        lat, lon = _bucket(d.location.latitude, d.location.longitude)
        key = (lat, lon, d.disease_name, d.crop_type)
        counts[key] = counts.get(key, 0) + 1
    return counts


def _nearby_farmers(lat, lon, radius_deg):
    """Farmers who have previously submitted a diagnosis near this cluster."""
    nearby_ids = set()
    diagnoses = (
        Diagnosis.objects
        .filter(location__isnull=False,
                location__latitude__range=(lat - radius_deg, lat + radius_deg),
                location__longitude__range=(lon - radius_deg, lon + radius_deg))
        .select_related('user')
    )
    for d in diagnoses.iterator():
        if d.user_id is not None:
            nearby_ids.add(d.user_id)
    from users.models import User
    return User.objects.filter(id__in=nearby_ids, is_active=True)


def _notify(farmers, alert, disease_name, crop_name):
    from announcements.models import notify_user
    from realtime.services import send_to_user, send_push_notification

    title = f'⚠️ {disease_name} outbreak alert'
    message = (f'Cases of {disease_name}' +
               (f' on {crop_name}' if crop_name else '') +
               f' are rising in your area (from {alert.previous_size} to '
               f'{alert.cluster_size} recently). Inspect your crops and apply '
               'preventive measures.')

    count = 0
    for user in farmers:
        notify_user(user, title, message, type='system',
                    reference_id=f'outbreak:{alert.id}')
        send_to_user(user.id, 'outbreak_alert', disease=disease_name,
                     lat=alert.latitude, lon=alert.longitude,
                     cluster_size=alert.cluster_size)
        send_push_notification(user, title, message,
                               data={'type': 'outbreak', 'outbreak_id': alert.id})
        count += 1
    return count


def detect_outbreak_alerts(save=True):
    """Detect growing clusters and (optionally) notify + persist alerts.

    Returns a list of dicts describing new alerts (for tests / logs).
    """
    recent_start, prev_start = _detection_window()
    now = timezone.now()

    recent = _cluster_counts(recent_start, now)
    previous = _cluster_counts(prev_start, recent_start)

    min_size = int(getattr(settings, 'OUTBREAK_MIN_CLUSTER_SIZE', '3'))
    growth_factor = float(getattr(settings, 'OUTBREAK_GROWTH_FACTOR', '2.0'))
    cooldown_hours = int(getattr(settings, 'OUTBREAK_COOLDOWN_HOURS', '24'))
    notify_radius = float(getattr(settings, 'OUTBREAK_NOTIFY_RADIUS_DEG', '0.8'))

    created_alerts = []

    for key, current in recent.items():
        lat, lon, disease_name, crop_name = key
        prev_count = previous.get(key, 0)

        # A cluster "grows" if it meets the size bar AND grew by the factor
        # (or appeared from zero).
        grew = current >= min_size and (
            (prev_count == 0) or (current >= prev_count * growth_factor)
        )
        if not grew:
            continue

        # Respect cooldown: skip if an alert for this (disease, bucket) is still
        # active within its cooldown window.
        existing = (
            OutbreakAlert.objects
            .filter(disease_name=disease_name, latitude=lat, longitude=lon)
            .exclude(status='expired')
            .order_by('-created_at')
            .first()
        )
        if existing and existing.cooldown_until and existing.cooldown_until > now:
            continue
        if existing and existing.status == 'notified':
            continue

        alert = OutbreakAlert(
            disease_name=disease_name, crop_name=crop_name,
            latitude=lat, longitude=lon,
            cluster_size=current, previous_size=prev_count,
            status='active', cooldown_until=now + timezone.timedelta(hours=cooldown_hours),
        )
        if save:
            alert.save()

        # Notify nearby farmers.
        farmers = _nearby_farmers(lat, lon, notify_radius)
        notified = _notify(farmers, alert, disease_name, crop_name)

        if save:
            alert.notified_users = notified
            alert.status = 'notified' if notified else 'active'
            alert.save(update_fields=['notified_users', 'status'])

        created_alerts.append({
            'disease': disease_name,
            'crop': crop_name,
            'lat': lat, 'lon': lon,
            'cluster_size': current,
            'previous_size': prev_count,
            'notified': notified,
        })

    return created_alerts
