from django.core.management.base import BaseCommand
from users.models import User
from products.models import Product
from chat.models import ChatRoom, Message


class Command(BaseCommand):
    help = 'Seed the database with demo data'

    def handle(self, *args, **kwargs):
        self.stdout.write('Seeding database...')

        # Create demo users
        users_data = [
            {
                'username': 'farmer1',
                'password': 'password123',
                'first_name': 'Jean',
                'last_name': 'Dupont',
                'email': 'jean@farmer.com',
                'phone_number': '+237670000001',
                'role': 'farmer',
            },
            {
                'username': 'farmer2',
                'password': 'password123',
                'first_name': 'Marie',
                'last_name': 'Ngo',
                'email': 'marie@farmer.com',
                'phone_number': '+237670000002',
                'role': 'farmer',
            },
            {
                'username': 'dealer1',
                'password': 'password123',
                'first_name': 'Paul',
                'last_name': 'Mbarga',
                'email': 'paul@agroshop.com',
                'phone_number': '+237670000003',
                'role': 'dealer',
            },
            {
                'username': 'dealer2',
                'password': 'password123',
                'first_name': 'Mary',
                'last_name': 'Ekotto',
                'email': 'mary@farmstore.com',
                'phone_number': '+237670000004',
                'role': 'dealer',
            },
            {
                'username': 'admin1',
                'password': 'password123',
                'first_name': 'David',
                'last_name': 'Admin',
                'email': 'david@agrisense.com',
                'phone_number': '+237670000005',
                'role': 'admin',
            },
        ]

        for data in users_data:
            user, created = User.objects.get_or_create(
                username=data['username'],
                defaults={
                    'first_name': data['first_name'],
                    'last_name': data['last_name'],
                    'email': data['email'],
                    'phone_number': data['phone_number'],
                    'role': data['role'],
                    'is_verified': True,
                }
            )
            if created:
                user.set_password(data['password'])
                user.save()
                self.stdout.write(f'  Created user: {user.username} ({user.role})')
            else:
                self.stdout.write(f'  User already exists: {user.username}')

        # Create demo products
        dealer1 = User.objects.get(username='dealer1')
        dealer2 = User.objects.get(username='dealer2')

        products_data = [
            {
                'dealer': dealer1,
                'name': 'Mancozeb 80% WP Fungicide',
                'description': 'A reliable, protective contact fungicide for controlling fungal diseases like Late Blight and Early Blight in tomatoes, potatoes, and other vegetables. Apply at first sign of disease.',
                'category': 'pesticide',
                'price': 15000,
                'stock_quantity': 50,
                'is_available': True,
                'is_featured': True,
            },
            {
                'dealer': dealer1,
                'name': 'Organic NPK Fertilizer (50kg)',
                'description': 'Premium organic NPK 15-15-15 fertilizer for all crop types. Enhances soil fertility and promotes healthy plant growth. Suitable for tomatoes, maize, cassava.',
                'category': 'fertilizer',
                'price': 25000,
                'stock_quantity': 100,
                'is_available': True,
                'is_featured': True,
            },
            {
                'dealer': dealer1,
                'name': 'Hybrid Tomato Seeds (500g)',
                'description': 'High-yield hybrid tomato seeds resistant to common diseases. Produces large, firm fruits ideal for both fresh consumption and processing.',
                'category': 'seed',
                'price': 8000,
                'stock_quantity': 200,
                'is_available': True,
                'is_featured': False,
            },
            {
                'dealer': dealer2,
                'name': 'Copper Hydroxide Fungicide',
                'description': 'Organic-approved copper-based fungicide for prevention of bacterial and fungal diseases. Safe for use on vegetables, fruits, and ornamentals.',
                'category': 'pesticide',
                'price': 12000,
                'stock_quantity': 75,
                'is_available': True,
                'is_featured': True,
            },
            {
                'dealer': dealer2,
                'name': 'Maize Seed - CMS Hybrid',
                'description': 'Premium CMS hybrid maize seed with excellent drought tolerance. Average yield of 8 tonnes per hectare under good management.',
                'category': 'seed',
                'price': 5000,
                'stock_quantity': 300,
                'is_available': True,
                'is_featured': False,
            },
            {
                'dealer': dealer2,
                'name': 'Sprayer Pump - 20L',
                'description': 'Durable 20-liter manual compression sprayer for applying pesticides and fertilizers. Ergonomic handle and adjustable nozzle.',
                'category': 'equipment',
                'price': 18000,
                'stock_quantity': 30,
                'is_available': True,
                'is_featured': False,
            },
            {
                'dealer': dealer1,
                'name': 'Urea Fertilizer (50kg)',
                'description': 'High-nitrogen urea fertilizer (46% N) for top-dressing crops. Promotes rapid vegetative growth in maize, rice, and vegetables.',
                'category': 'fertilizer',
                'price': 22000,
                'stock_quantity': 80,
                'is_available': True,
                'is_featured': False,
            },
            {
                'dealer': dealer2,
                'name': 'Neem Oil Pesticide (1L)',
                'description': 'Natural neem oil concentrate for organic pest control. Effective against aphids, whiteflies, caterpillars, and mites.',
                'category': 'pesticide',
                'price': 6500,
                'stock_quantity': 120,
                'is_available': True,
                'is_featured': True,
            },
        ]

        for data in products_data:
            product, created = Product.objects.get_or_create(
                name=data['name'],
                defaults=data,
            )
            if created:
                self.stdout.write(f'  Created product: {product.name}')

        # Create demo chat rooms
        farmer1 = User.objects.get(username='farmer1')
        farmer2 = User.objects.get(username='farmer2')

        room1, created = ChatRoom.objects.get_or_create(farmer=farmer1, dealer=dealer1)
        if created:
            self.stdout.write('  Created chat room: Jean <-> Paul')

        room2, created = ChatRoom.objects.get_or_create(farmer=farmer1, dealer=dealer2)
        if created:
            self.stdout.write('  Created chat room: Jean <-> Mary')

        # Create demo messages
        messages_data = [
            (room1, farmer1, 'Bonjour Paul! Is the Mancozeb fungicide safe for tomato plants?'),
            (room1, dealer1, 'Bonjour Jean! Yes, it is perfectly safe for tomatoes. Apply 50g per 20L of water.'),
            (room1, farmer1, 'Thank you! How often should I apply it?'),
            (room1, dealer1, 'Apply every 7-10 days during wet season. After rain, reapply immediately.'),
            (room2, farmer1, 'Hello Mary, do you have copper fungicide in stock?'),
            (room2, dealer2, 'Yes Jean! We have Copper Hydroxide Fungicide. 12,000 Fcfa per bottle.'),
        ]

        for room, sender, content in messages_data:
            msg, created = Message.objects.get_or_create(
                chat_room=room,
                sender=sender,
                message=content,
            )
            if created:
                self.stdout.write(f'  Created message from {sender.first_name}')

        self.stdout.write(self.style.SUCCESS('Database seeded successfully!'))
        self.stdout.write('')
        self.stdout.write('Demo credentials:')
        self.stdout.write('  Farmer: farmer1 / password123')
        self.stdout.write('  Dealer: dealer1 / password123')
        self.stdout.write('  Admin:  admin1 / password123')
