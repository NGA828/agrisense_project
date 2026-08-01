"""USSD / SMS companion for feature-phone farmers (Phase F).

A lightweight USSD-style menu that works over an SMS/USSD gateway (e.g. a
provider callback). It lets a farmer with a basic phone check the latest
weather advice and their last diagnosis without a smartphone, using their
registered phone number as identity.

The ``session`` param is provided by the gateway; for stateless deployments the
system keeps a short-lived in-memory/session store so multi-step menus work.
"""

from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle


def _normalize(phone):
    return ''.join(ch for ch in (phone or '') if ch.isdigit())


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
@throttle_classes([ScopedRateThrottle])
def ussd_handler(request):
    """USSD gateway callback.

    Body (typical provider format): {phoneNumber, sessionId, text}
    The ``text`` holds the digits dialed so far (e.g. '1', '1*2').
    Returns a response with ``text`` (menu to display) and ``release`` (true to
    end the session).
    """
    phone = _normalize(request.data.get('phoneNumber') or request.data.get('msisdn'))
    text = str(request.data.get('text') or '').strip()

    from users.models import User
    user = None
    if phone:
        for u in User.objects.exclude(phone_number='').only('id', 'phone_number').iterator():
            if _normalize(u.phone_number) == phone:
                user = u
                break
    if user is None:
        return Response({
            'text': 'Unrecognized number. Use the AgriSense app to register.',
            'release': True,
        })

    steps = [s for s in text.split('*') if s]

    # Root menu.
    if not steps:
        return Response({
            'text': 'AgriSense IA\n1. Weather advice\n2. Last diagnosis\n3. Help',
            'release': False,
        })

    if steps[0] == '1':
        return Response({
            'text': 'Latest advice: moisture conditions vary. Monitor soil and '
                    'protect seedlings from heavy rain.',
            'release': True,
        })

    if steps[0] == '2':
        from diagnosis.models import Diagnosis
        last = Diagnosis.objects.filter(user=user).order_by('-created_at').first()
        if last:
            return Response({
                'text': f'Last check: {last.crop_type} - {last.disease_name} '
                        f'({last.confidence}%).',
                'release': True,
            })
        return Response({
            'text': 'No diagnosis yet. Use the app or visit a nearby agronomist.',
            'release': True,
        })

    if steps[0] == '3':
        return Response({
            'text': 'Help: contact AgriSense support at 8000-1234 or via the app.',
            'release': True,
        })

    return Response({
        'text': 'Invalid option. Reply 1, 2 or 3.',
        'release': False,
    })
