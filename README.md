# AgriSense AI - Intelligent Agricultural Assistant

## Overview
AgriSense AI is a comprehensive mobile application that acts as a plant doctor, weather forecaster, and farm supply store, all rolled into one. Built with Flutter (frontend) and Django (backend) with MySQL database.

## Architecture
- **Frontend**: Flutter with Provider state management
- **Backend**: Django REST Framework with JWT authentication
- **Database**: MySQL
- **Real-time Chat**: Django Channels with WebSockets
- **AI Engine**: Disease detection using image analysis

## Features

### Farmer Features
- **Dashboard**: Weather info, quick actions, recent diagnoses
- **AI Scan**: Take/upload plant photos for disease diagnosis
- **Diagnosis Results**: Disease identification with severity and treatment plans
- **Marketplace**: Browse and purchase agro-inputs from verified dealers
- **Chat**: Real-time messaging with dealers
- **Weather**: Localized weather forecasts with farming advice
- **Order History**: Track past purchases
- **Payment**: MTN Mobile Money and Orange Money integration

### Dealer Features
- **Dashboard**: Sales stats, product management, order tracking
- **Product Management**: Add, edit, delete products with images
- **Order Management**: View and update order status (pending, shipped, delivered)
- **Premium**: Upgrade to premium for better visibility
- **Customer Chat**: Respond to farmer inquiries

### Administrator Features
- **Dashboard**: Platform statistics (users, orders, revenue, diagnoses)
- **User Management**: View, suspend, activate user accounts
- **Content Management**: Disease database management
- **System Health**: Monitor API, database, AI engine status
- **Settings**: System configuration

## Setup Instructions

### Backend (Django)
```bash
cd backend/agrisense_backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
venv\Scripts\activate     # Windows

# Install dependencies
pip install -r requirements.txt

# Create MySQL database
mysql -u root -p -e "CREATE DATABASE agrisense_db;"
mysql -u root -p -e "CREATE USER 'agrisense_user'@'localhost' IDENTIFIED BY 'password123';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON agrisense_db.* TO 'agrisense_user'@'localhost';"

# Run migrations
python manage.py makemigrations
python manage.py migrate

# Seed database with demo data
python manage.py seed_data

# Create superuser
python manage.py createsuperuser

# Start server
python manage.py runserver
```

### Frontend (Flutter)
```bash
cd frontend/agrisense_app

# Get dependencies
flutter pub get

# Run on emulator/device
flutter run
```

## Demo Credentials
- **Farmer**: farmer1 / password123
- **Dealer**: dealer1 / password123
- **Admin**: admin1 / password123

## API Endpoints

### Authentication
- `POST /api/auth/login/` - Login and get JWT tokens
- `POST /api/auth/register/` - Register new user
- `POST /api/auth/refresh/` - Refresh access token

### Users
- `GET /api/users/` - List users (admin only)
- `GET /api/users/me/` - Get current user
- `GET /api/users/farmers/` - List farmers
- `GET /api/users/dealers/` - List dealers
- `POST /api/users/{id}/suspend/` - Suspend user (admin)
- `POST /api/users/{id}/activate/` - Activate user (admin)

### Diagnosis
- `POST /api/diagnosis/analyze/` - Analyze plant image
- `GET /api/diagnosis/history/` - Get diagnosis history
- `GET /api/diagnosis/` - List all diagnoses

### Products
- `GET /api/products/marketplace/` - Get marketplace products
- `POST /api/products/` - Create product (dealer)
- `GET /api/products/my_products/` - Get dealer's products
- `PUT /api/products/{id}/` - Update product
- `DELETE /api/products/{id}/` - Delete product

### Orders
- `GET /api/orders/` - List orders
- `POST /api/orders/` - Create order
- `POST /api/orders/{id}/update_status/` - Update order status (dealer)

### Payments
- `POST /api/payments/` - Create payment
- `POST /api/payments/{id}/process_payment/` - Process payment
- `GET /api/payments/my_payments/` - Get user's payments

### Chat
- `GET /api/chat/` - List chat rooms
- `POST /api/chat/` - Create chat room
- `GET /api/chat/{id}/messages/` - Get messages
- `POST /api/chat/{id}/send_message/` - Send message
- `WS /ws/chat/{room_id}/` - WebSocket for real-time chat

### Weather
- `POST /api/weather/` - Get weather data

### Admin
- `GET /api/admin/stats/` - Get admin statistics
- `GET /api/diseases/list_diseases/` - List disease database

## Project Structure
```
agrisense_project/
+-- backend/
¦   +-- agrisense_backend/
¦       +-- agrisense_backend/    # Django project settings
¦       +-- users/                # User management app
¦       +-- diagnosis/            # Disease diagnosis app
¦       +-- products/             # Product & order management
¦       +-- chat/                 # Real-time chat
¦       +-- payments/             # Payment processing
¦       +-- weather/              # Weather service
¦       +-- ai_engine/            # AI disease detection
+-- frontend/
    +-- agrisense_app/
        +-- lib/
            +-- main.dart         # App entry point
            +-- models/           # Data models
            +-- providers/        # State management
            +-- screens/          # UI screens
            +-- services/         # API services
            +-- theme/            # App theme
            +-- widgets/          # Reusable widgets
```
