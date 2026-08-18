"""Seed missing crops (Cassava, Pepper, Cocoa, Potato, Rice) and their diseases."""

from django.core.management.base import BaseCommand
from diagnosis.models import Disease


class Command(BaseCommand):
    help = 'Seed missing crops with diseases from the fallback database'

    def handle(self, *args, **options):
        # Disease data for missing crops
        missing_crops = {
            'Cassava': [
                {
                    'disease_name': 'Cassava Mosaic Disease',
                    'pathogen': 'Cassava mosaic virus (CMV)',
                    'symptoms': 'Mosaic pattern of light and dark green on leaves. Leaf distortion, curling, and reduction in size. Stunted growth.',
                    'causes': 'Viral disease transmitted by whitefly (Bemisia tabaci). Also spread through infected cuttings.',
                    'severity': 'high',
                    'prevention': 'Use certified virus-free planting material. Plant resistant varieties (e.g., NAROCASS 1). Control whitefly populations. Remove and destroy infected plants early.',
                    'treatment_type': 'Viral Control',
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
                    'treatment_type': 'Bactericide Application',
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
                    'treatment_type': 'Fungicide Application',
                    'medication': 'Fungicide (Metalaxyl + Mancozeb) spray on pods. Cadusafos for swollen shoot vector control.',
                    'instructions': 'Remove all infected pods from tree and ground. Spray remaining pods with fungicide. Repeat monthly during rainy season.',
                    'duration': 30,
                },
            ],
            'Potato': [
                {
                    'disease_name': 'Potato Late Blight',
                    'pathogen': 'Phytophthora infestans',
                    'symptoms': 'Water-soaked lesions on leaves and stems. White fuzzy growth on undersides. Brown rot in tubers.',
                    'causes': 'Oomycete pathogen. Favored by cool, wet weather (15-25°C). Spreads rapidly.',
                    'severity': 'high',
                    'prevention': 'Plant resistant varieties. Ensure proper spacing. Remove infected leaves. Avoid overhead irrigation.',
                    'treatment_type': 'Fungicide Application',
                    'medication': 'Mancozeb 80% WP or Metalaxyl-based fungicides.',
                    'instructions': 'Remove and destroy infected plant material. Apply fungicide weekly during wet seasons. Harvest tubers carefully.',
                    'duration': 21,
                },
                {
                    'disease_name': 'Potato Early Blight',
                    'pathogen': 'Alternaria solani',
                    'symptoms': 'Dark concentric ring spots on older leaves. Yellowing around spots. Leaf defoliation.',
                    'causes': 'Fungal pathogen. Favored by warm, humid conditions and overhead watering.',
                    'severity': 'medium',
                    'prevention': 'Mulch around plants. Remove lower leaves. Practice crop rotation. Use drip irrigation.',
                    'treatment_type': 'Fungicide Application',
                    'medication': 'Chlorothalonil or Azoxystrobin. Organic: Bacillus subtilis.',
                    'instructions': 'Remove affected leaves. Apply fungicide at first sign. Reapply after rain every 7-10 days.',
                    'duration': 14,
                },
            ],
            'Rice': [
                {
                    'disease_name': 'Rice Leaf Blast',
                    'pathogen': 'Magnaporthe grisea',
                    'symptoms': 'Diamond-shaped lesions on leaves with brown margins and gray center. Progressive leaf death.',
                    'causes': 'Fungal pathogen. Favored by high humidity and moderate temperatures (20-28°C).',
                    'severity': 'high',
                    'prevention': 'Use resistant varieties. Avoid excessive nitrogen fertilizer. Ensure good drainage and air circulation.',
                    'treatment_type': 'Fungicide Application',
                    'medication': 'Triazole fungicides (Tebuconazole) or Strobilurin-based fungicides.',
                    'instructions': 'Apply fungicide at first sign of lesions. Spray when wind is calm. Repeat every 10-14 days if needed.',
                    'duration': 14,
                },
                {
                    'disease_name': 'Rice Sheath Blight',
                    'pathogen': 'Rhizoctonia solani',
                    'symptoms': 'Water-soaked elliptical lesions on leaf sheaths. Lesions expand and turn ash-colored.',
                    'causes': 'Fungal pathogen. Favored by high humidity and dense planting.',
                    'severity': 'medium',
                    'prevention': 'Reduce plant density. Improve air circulation. Drain fields properly. Rotate crops.',
                    'treatment_type': 'Fungicide Application',
                    'medication': 'Validamycin or Azoxystrobin-based fungicides.',
                    'instructions': 'Apply fungicide when disease appears. Spray lower plant parts thoroughly. Repeat as needed during growth.',
                    'duration': 14,
                },
            ],
        }

        for crop_name, diseases in missing_crops.items():
            self.stdout.write(f'Seeding {crop_name}...')
            for disease_data in diseases:
                disease, created = Disease.objects.get_or_create(
                    crop_name=crop_name,
                    disease_name=disease_data['disease_name'],
                    defaults={
                        'pathogen': disease_data['pathogen'],
                        'symptoms': disease_data['symptoms'],
                        'causes': disease_data['causes'],
                        'severity': disease_data['severity'],
                        'prevention': disease_data['prevention'],
                        'treatment_type': disease_data['treatment_type'],
                        'medication': disease_data['medication'],
                        'instructions': disease_data['instructions'],
                        'duration': disease_data['duration'],
                    }
                )
                status = 'Created' if created else 'Already exists'
                self.stdout.write(
                    self.style.SUCCESS(f'  ✓ {disease_data["disease_name"]} ({status})'))

        self.stdout.write(
            self.style.SUCCESS('✓ All missing crops and diseases seeded successfully!'))
