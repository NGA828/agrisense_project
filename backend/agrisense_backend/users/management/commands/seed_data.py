from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from users.models import User
from products.models import Product, Order
from chat.models import ChatRoom, Message
from diagnosis.models import Disease, Diagnosis, TreatmentPlan
from payments.models import Payment
from weather.models import WeatherData
from announcements.models import Announcement, Notification
from ai_engine.services import FALLBACK_DISEASE_DATABASE


class Command(BaseCommand):
    help = 'Seed the database with a complete demo dataset (idempotent).'

    def handle(self, *args, **kwargs):
        self.stdout.write('Seeding database...')
        self._users()
        self._diseases()
        self._products()
        self._chats()
        self._diagnoses()
        self._orders_and_payments()
        self._weather()
        self._announcements()
        self._notifications()
        self.stdout.write(self.style.SUCCESS('Database seeded successfully!'))
        self.stdout.write('')
        self.stdout.write('Demo credentials:')
        self.stdout.write('  Farmer: farmer1 / password123')
        self.stdout.write('  Dealer: dealer1 / password123')
        self.stdout.write('  Dealer (pending): dealer3 / password123')
        self.stdout.write('  Admin:  admin1 / password123')

    # ── helpers ───────────────────────────────────────────────────────
    def _get_or_create_user(self, username, password, first_name, last_name,
                            email, phone, role, is_verified=True, is_premium=False):
        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'first_name': first_name,
                'last_name': last_name,
                'email': email,
                'phone_number': phone,
                'role': role,
                'is_verified': is_verified,
                'is_premium': is_premium,
            },
        )
        if created:
            user.set_password(password)
            user.is_verified = is_verified
            user.is_premium = is_premium
            if is_premium:
                user.premium_expiry = timezone.now() + timedelta(days=30)
            user.save()
            self.stdout.write(f'  Created user: {user.username} ({user.role})')
        return user

    def _users(self):
        self._get_or_create_user('farmer1', 'password123', 'Jean', 'Dupont',
                                 'jean@farmer.com', '+237670000001', 'farmer')
        self._get_or_create_user('farmer2', 'password123', 'Marie', 'Ngo',
                                 'marie@farmer.com', '+237670000002', 'farmer')
        # Phone ends in an even digit so the sandbox mobile-money simulator
        # accepts premium payments out of the box.
        self._get_or_create_user('dealer1', 'password123', 'Paul', 'Mbarga',
                                 'paul@agroshop.com', '+237670000008', 'dealer',
                                 is_premium=True)
        self._get_or_create_user('dealer2', 'password123', 'Mary', 'Ekotto',
                                 'mary@farmstore.com', '+237670000004', 'dealer')
        self._get_or_create_user('dealer3', 'password123', 'Samuel', 'Fotso',
                                 'samuel@agrosupply.com', '+237670000006', 'dealer',
                                 is_verified=False)
        self._get_or_create_user('admin1', 'password123', 'David', 'Admin',
                                 'david@agrisense.com', '+237670000005', 'admin')

    def _diseases(self):
        created_count = 0
        for crop, diseases in FALLBACK_DISEASE_DATABASE.items():
            for d in diseases:
                _, created = Disease.objects.get_or_create(
                    disease_name=d['disease_name'],
                    defaults={
                        'crop_name': crop,
                        'pathogen': d.get('pathogen', ''),
                        'symptoms': d.get('symptoms', ''),
                        'causes': d.get('causes', ''),
                        'severity': d.get('severity', 'low'),
                        'prevention': d.get('prevention', ''),
                        'treatment_type': d.get('treatment_type', ''),
                        'medication': d.get('medication', ''),
                        'instructions': d.get('instructions', ''),
                        'duration': d.get('duration', 14),
                    },
                )
                created_count += created
        if created_count:
            self.stdout.write(f'  Seeded {created_count} diseases into knowledge base')

    def _products(self):
        dealer1 = User.objects.get(username='dealer1')
        dealer2 = User.objects.get(username='dealer2')

        products_data = [
            (dealer1, 'Mancozeb 80% WP Fungicide',
             'A reliable, protective contact fungicide for controlling fungal diseases like Late Blight and Early Blight in tomatoes, potatoes, and other vegetables. Apply at first sign of disease.',
             'pesticide', 15000, 50, True),
            (dealer1, 'Organic NPK Fertilizer (50kg)',
             'Premium organic NPK 15-15-15 fertilizer for all crop types. Enhances soil fertility and promotes healthy plant growth. Suitable for tomatoes, maize, cassava.',
             'fertilizer', 25000, 100, True),
            (dealer1, 'Hybrid Tomato Seeds (500g)',
             'High-yield hybrid tomato seeds resistant to common diseases. Produces large, firm fruits ideal for both fresh consumption and processing.',
             'seed', 8000, 200, False),
            (dealer1, 'Urea Fertilizer (50kg)',
             'High-nitrogen urea fertilizer (46% N) for top-dressing crops. Promotes rapid vegetative growth in maize, rice, and vegetables.',
             'fertilizer', 22000, 80, False),
            (dealer2, 'Copper Hydroxide Fungicide',
             'Organic-approved copper-based fungicide for prevention of bacterial and fungal diseases. Safe for use on vegetables, fruits, and ornamentals.',
             'pesticide', 12000, 75, True),
            (dealer2, 'Maize Seed - CMS Hybrid',
             'Premium CMS hybrid maize seed with excellent drought tolerance. Average yield of 8 tonnes per hectare under good management.',
             'seed', 5000, 300, False),
            (dealer2, 'Sprayer Pump - 20L',
             'Durable 20-liter manual compression sprayer for applying pesticides and fertilizers. Ergonomic handle and adjustable nozzle.',
             'equipment', 18000, 30, False),
            (dealer2, 'Neem Oil Pesticide (1L)',
             'Natural neem oil concentrate for organic pest control. Effective against aphids, whiteflies, caterpillars, and mites.',
             'pesticide', 6500, 120, True),
        ]

        for dealer, name, desc, category, price, stock, featured in products_data:
            _, created = Product.objects.get_or_create(
                name=name,
                defaults={
                    'dealer': dealer, 'description': desc, 'category': category,
                    'price': price, 'stock_quantity': stock,
                    'is_available': True, 'is_featured': featured,
                },
            )
            if created:
                self.stdout.write(f'  Created product: {name}')

    def _chats(self):
        farmer1 = User.objects.get(username='farmer1')
        farmer2 = User.objects.get(username='farmer2')
        dealer1 = User.objects.get(username='dealer1')
        dealer2 = User.objects.get(username='dealer2')

        room1, created = ChatRoom.objects.get_or_create(farmer=farmer1, dealer=dealer1)
        room2, created = ChatRoom.objects.get_or_create(farmer=farmer1, dealer=dealer2)
        room3, created = ChatRoom.objects.get_or_create(farmer=farmer2, dealer=dealer1)

        messages = [
            (room1, farmer1, 'Bonjour Paul! Is the Mancozeb fungicide safe for tomato plants?'),
            (room1, dealer1, 'Bonjour Jean! Yes, it is perfectly safe for tomatoes. Apply 50g per 20L of water.'),
            (room1, farmer1, 'Thank you! How often should I apply it?'),
            (room1, dealer1, 'Apply every 7-10 days during wet season. After rain, reapply immediately.'),
            (room2, farmer1, 'Hello Mary, do you have copper fungicide in stock?'),
            (room2, dealer2, 'Yes Jean! We have Copper Hydroxide Fungicide. 12,000 Fcfa per bottle.'),
            (room3, dealer1, 'Hi Marie, saw you ordered maize seed. It ships tomorrow!'),
        ]
        for room, sender, content in messages:
            _, created = Message.objects.get_or_create(
                chat_room=room, sender=sender, message=content,
            )
            if created:
                self.stdout.write(f'  Created message from {sender.first_name}')

    def _diagnoses(self):
        farmer1 = User.objects.get(username='farmer1')
        farmer2 = User.objects.get(username='farmer2')

        from ai_engine.services import get_disease_info
        samples = [
            (farmer1, 'Tomato', 'Tomato Early Blight', 92),
            (farmer2, 'Maize', 'Maize Rust', 88),
        ]
        for user, crop, disease_name, confidence in samples:
            info = get_disease_info(disease_name) or {}
            existing = Diagnosis.objects.filter(user=user, disease_name=disease_name).first()
            if existing:
                continue
            diagnosis = Diagnosis.objects.create(
                id=f'SEED-{user.id}-{disease_name.split()[0]}',
                user=user,
                crop_type=crop,
                symptoms=info.get('symptoms', ''),
                confidence=confidence,
                disease_name=disease_name,
                severity=info.get('severity', 'medium'),
                causes=info.get('causes', ''),
                prevention=info.get('prevention', ''),
            )
            TreatmentPlan.objects.create(
                diagnosis=diagnosis,
                treatment_type=info.get('treatment_type', 'Cultural Management'),
                medication=info.get('medication', ''),
                instructions=info.get('instructions', ''),
                duration=info.get('duration', 14),
                follow_up_date=timezone.now().date() + timedelta(days=info.get('duration', 14)),
            )
            self.stdout.write(f'  Created diagnosis: {disease_name} for {user.username}')

    def _orders_and_payments(self):
        farmer1 = User.objects.get(username='farmer1')
        farmer2 = User.objects.get(username='farmer2')

        mancozeb = Product.objects.filter(name__icontains='Mancozeb').first()
        maize_seed = Product.objects.filter(name__icontains='CMS Hybrid').first()
        npk = Product.objects.filter(name__icontains='NPK').first()

        seed_orders = [
            (farmer1, mancozeb, 2, 'delivered', 'paid'),
            (farmer2, maize_seed, 3, 'shipped', 'paid'),
            (farmer1, npk, 1, 'pending', 'unpaid'),
        ]
        for farmer, product, qty, status_, payment_status in seed_orders:
            if not product:
                continue
            order, created = Order.objects.get_or_create(
                farmer=farmer, product=product, quantity=qty, status=status_,
                defaults={
                    'total_price': product.price * qty,
                    'payment_status': payment_status,
                    'shipping_address': 'Demo village, Cameroon',
                },
            )
            if created:
                self.stdout.write(f'  Created order #{order.id}')
                if payment_status == 'paid':
                    Payment.objects.get_or_create(
                        order=order,
                        defaults={
                            'user': farmer,
                            'amount': order.total_price,
                            'payment_method': 'MTN_MOMO',
                            'phone_number': farmer.phone_number,
                            'transaction_id': f'TXN-SEED-{order.id}',
                            'status': 'completed',
                            'payment_type': 'order',
                            'description': f'Order #{order.id} - {product.name}',
                        },
                    )

    def _weather(self):
        WeatherData.objects.get_or_create(
            location_name='Yaoundé, Cameroon',
            defaults={
                'latitude': 3.8480, 'longitude': 11.5021,
                'temperature': 28, 'feels_like': 31, 'humidity': 72,
                'wind_speed': 10, 'condition': 'Partly Cloudy',
                'rain_probability': 45,
                'description': 'scattered clouds',
                'farming_advice': 'Moderate conditions for field work. Good time for planting seedlings.',
            },
        )

    def _announcements(self):
        admin = User.objects.get(username='admin1')
        Announcement.objects.get_or_create(
            title='Welcome to AgriSense AI!',
            defaults={
                'content': 'Scan a leaf, get a diagnosis, and buy certified inputs from verified dealers — all in one place.',
                'target_audience': 'all',
                'created_by': admin,
            },
        )
        Announcement.objects.get_or_create(
            title='Rainy season alert',
            defaults={
                'content': 'High rainfall expected this week across the Centre region. Delay pesticide spraying and check field drainage.',
                'target_audience': 'farmers',
                'created_by': admin,
            },
        )

    def _notifications(self):
        dealer1 = User.objects.get(username='dealer1')
        Notification.objects.get_or_create(
            recipient=dealer1,
            title='New order received 🎉',
            defaults={
                'message': 'Jean ordered 2 x Mancozeb 80% WP Fungicide (30000 FCFA).',
                'type': 'order',
                'reference_id': '1',
            },
        )
