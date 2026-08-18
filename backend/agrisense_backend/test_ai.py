#!/usr/bin/env python
"""Test the AI engine directly"""
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agrisense_backend.settings')
django.setup()

from ai_engine.services import analyze_disease, AIEngineUnavailable, AIInferenceError
from PIL import Image
import io

# Create a dummy test image
img = Image.new('RGB', (100, 100), color='red')
img_bytes = io.BytesIO()
img.save(img_bytes, format='JPEG')
img_bytes.seek(0)

try:
    result = analyze_disease(img_bytes, 'Tomato')
    print('Success! Disease:', result.get('disease_name'))
    print('Confidence:', result.get('confidence'))
except AIEngineUnavailable as e:
    print('❌ Engine unavailable:', str(e))
except AIInferenceError as e:
    print('❌ Inference error:', str(e))
except Exception as e:
    print('❌ Other error:', type(e).__name__, str(e))
    import traceback
    traceback.print_exc()
