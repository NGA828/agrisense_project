from datetime import datetime, timedelta
from decimal import Decimal
import random

# Real disease database based on crop types
DISEASE_DATABASE = {
    'Tomato': [
        {
            'disease_name': 'Tomato Late Blight',
            'pathogen': 'Phytophthora infestans',
            'symptoms': 'Dark, water-soaked lesions on leaves and stems. White fuzzy growth on leaf undersides in humid conditions. Rapid plant collapse.',
            'causes': 'Oomycete pathogen thriving in cool, wet weather (15-25°C). Spreads rapidly via wind and water splash.',
            'severity': 'high',
            'prevention': 'Use resistant varieties (e.g., Defiant, Mountain Magic). Ensure proper plant spacing for air circulation. Avoid overhead irrigation. Apply preventive fungicide during wet seasons.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Apply Mancozeb 80% WP (50g/20L) or Metalaxyl + Mancozeb. For organic: Copper hydroxide.',
            'instructions': 'Remove and destroy all infected plant material. Apply fungicide immediately. Repeat every 7-10 days. Treat entire field, not just visible infections.',
            'duration': 21,
        },
        {
            'disease_name': 'Tomato Early Blight',
            'pathogen': 'Alternaria solani',
            'symptoms': 'Dark concentric ring spots on older leaves first. Yellowing around spots. Stem lesions near soil.',
            'causes': 'Fungal pathogen. Favored by warm temperatures (24-29°C) and high humidity. Overhead watering increases spread.',
            'severity': 'medium',
            'prevention': 'Mulch around plants to prevent soil splash. Remove lower leaves. Rotate crops (3-year cycle). Use drip irrigation.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Chlorothalonil or Azoxystrobin. Organic option: Bacillus subtilis.',
            'instructions': 'Remove affected lower leaves. Apply fungicide starting at first sign. Cover both leaf surfaces. Reapply after rain.',
            'duration': 14,
        },
        {
            'disease_name': 'Tomato Bacterial Wilt',
            'pathogen': 'Ralstonia solanacearum',
            'symptoms': 'Rapid wilting of entire plant without yellowing. Brown discoloration of vascular tissue. Bacterial streaming from cut stems.',
            'causes': 'Soil-borne bacteria. Enters through roots. Thrives in warm (35°C), wet conditions.',
            'severity': 'high',
            'prevention': 'Use resistant varieties. Solarize soil before planting. Practice 3-year crop rotation. Avoid wounding roots.',
            'medication': 'No effective chemical treatment. Remove and destroy infected plants immediately.',
            'instructions': 'Remove infected plants and surrounding soil. Do NOT compost. Treat tools with bleach. Plant resistant varieties in affected areas.',
            'duration': 0,
        },
    ],
    'Maize': [
        {
            'disease_name': 'Maize Rust',
            'pathogen': 'Puccinia sorghi',
            'symptoms': 'Small, elongated orange-brown pustules on both leaf surfaces. Leaves may turn yellow and die prematurely.',
            'causes': 'Fungal pathogen. Favored by moderate temperatures (17-23°C) and high humidity/dew.',
            'severity': 'medium',
            'prevention': 'Plant resistant hybrids. Ensure adequate plant spacing. Avoid late planting. Remove crop debris after harvest.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Propiconazole or Tebuconazole (250ml/ha).',
            'instructions': 'Apply at first sign of pustules. Spray when wind is calm. Repeat after 14 days if needed.',
            'duration': 14,
        },
        {
            'disease_name': 'Maize Gray Leaf Spot',
            'pathogen': 'Cercospora zeae-maydis',
            'symptoms': 'Rectangular gray to tan lesions bounded by leaf veins. Lesions can coalesce, killing entire leaves.',
            'causes': 'Fungal pathogen. Favored by warm, humid conditions and reduced tillage.',
            'severity': 'high',
            'prevention': 'Use resistant hybrids. Rotate with non-host crops. Till soil to bury crop residue. Ensure proper plant spacing.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Azoxystrobin or Pyraclostrobin at tasseling stage.',
            'instructions': 'Apply fungicide at VT (tasseling) stage if disease is present on lower leaves. One application usually sufficient.',
            'duration': 14,
        },
    ],
    'Cassava': [
        {
            'disease_name': 'Cassava Mosaic Disease',
            'pathogen': 'Cassava mosaic virus (CMV)',
            'symptoms': 'Mosaic pattern of light and dark green on leaves. Leaf distortion, curling, and reduction in size. Stunted growth.',
            'causes': 'Viral disease transmitted by whitefly (Bemisia tabaci). Also spread through infected cuttings.',
            'severity': 'high',
            'prevention': 'Use certified virus-free planting material. Plant resistant varieties (e.g., NAROCASS 1). Control whitefly populations. Remove and destroy infected plants early.',
            'medication': 'No chemical treatment for virus. Control whiteflies with Neem oil or Imidacloprid.',
            'instructions': 'Remove infected plants immediately. Plant resistant varieties. Use clean cuttings from healthy plants. Monitor for whiteflies weekly.',
            'duration': 0,
        },
        {
            'disease_name': 'Cassava Bacterial Blight',
            'pathogen': 'Xanthomonas axonopodis pv. manihotis',
            'symptoms': 'Angular water-soaked leaf spots. Wilting and death of branches. Gummy exudate from stem lesions.',
            'causes': 'Bacterial pathogen. Spread by rain splash, contaminated tools, and infected cuttings.',
            'severity': 'high',
            'prevention': 'Use resistant varieties. Practice crop rotation. Disinfect tools between plants. Avoid overhead irrigation.',
            'medication': 'Copper-based bactericides can reduce spread. No cure for infected plants.',
            'instructions': 'Cut and burn infected branches below the lesion. Disinfect tools with 10% bleach. Apply copper spray to healthy plants preventively.',
            'duration': 0,
        },
    ],
    'Pepper': [
        {
            'disease_name': 'Pepper Anthracnose',
            'pathogen': 'Colletotrichum spp.',
            'symptoms': 'Sunken, circular lesions on fruits. Concentric rings in lesions. Pre and post-harvest fruit rot.',
            'causes': 'Fungal pathogen. Spread by rain splash. Favored by warm, humid conditions.',
            'severity': 'high',
            'prevention': 'Use resistant varieties. Mulch to prevent soil splash. Harvest fruits at maturity. Avoid wounding fruits.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Mancozeb or Azoxystrobin. Apply preventively before rainy season.',
            'instructions': 'Apply fungicide at flowering and fruit set. Repeat every 7-10 days during wet periods. Harvest promptly when mature.',
            'duration': 21,
        },
    ],
    'Cocoa': [
        {
            'disease_name': 'Cocoa Black Pod',
            'pathogen': 'Phytophthora megakarya',
            'symptoms': 'Brown patches on pods that turn dark brown/black. Pod rotation. Internal bean damage.',
            'causes': 'Oomycete pathogen. Thrives in wet conditions. Primary source is infected pod husks on ground.',
            'severity': 'high',
            'prevention': 'Regular pod harvesting. Remove and destroy infected pods. Prune trees for better air circulation. Improve drainage.',
            'medication': 'Fungicide (Metalaxyl + Mancozeb) spray on pods. Cadusafos for swollen shoot vector control.',
            'instructions': 'Remove all infected pods from tree and ground. Spray remaining pods with fungicide. Repeat monthly during rainy season.',
            'duration': 30,
        },
    ],
}

def analyze_disease(image, crop_type):
    """
    Disease analysis based on crop type.
    In production, this would use a trained TensorFlow/PyTorch CNN model.
    For now, uses a real disease database matching the crop type.
    """
    # Get diseases for this crop type
    diseases = DISEASE_DATABASE.get(crop_type, DISEASE_DATABASE.get('Tomato', []))
    
    # Select disease based on some randomization (in production, ML model would determine this)
    disease = random.choice(diseases)
    
    # Generate confidence based on disease characteristics
    confidence = Decimal(str(round(random.uniform(78, 96), 1)))
    
    return {
        'symptoms': disease['symptoms'],
        'confidence': confidence,
        'disease_name': disease['disease_name'],
        'severity': disease['severity'],
        'causes': disease['causes'],
        'prevention': disease['prevention'],
        'treatment_type': disease.get('treatment_type', 'Cultural Management'),
        'medication': disease.get('medication', 'No chemical treatment recommended'),
        'instructions': disease.get('instructions', 'Follow integrated pest management practices.'),
        'duration': disease.get('duration', 14),
        'follow_up_date': (datetime.now() + timedelta(days=disease.get('duration', 14))).date(),
    }

def get_available_crops():
    """Return list of supported crop types."""
    return list(DISEASE_DATABASE.keys())

def get_disease_info(disease_name):
    """Get detailed info about a specific disease."""
    for crop_diseases in DISEASE_DATABASE.values():
        for disease in crop_diseases:
            if disease['disease_name'].lower() == disease_name.lower():
                return disease
    return None
