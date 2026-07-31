import os
import django
from django.test import RequestFactory
from rest_framework_simplejwt.views import TokenObtainPairView

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agrisense_backend.settings')
django.setup()

factory = RequestFactory()
request = factory.post(
    '/api/auth/login/',
    content_type='application/json',
    data='{"username":"test","password":"test"}'
)

try:
    view = TokenObtainPairView.as_view()
    response = view(request)
    print('status', response.status_code)
    if hasattr(response, 'data'):
        print('data', response.data)
    else:
        print('content', response.content)
except Exception as e:
    import traceback
    traceback.print_exc()
