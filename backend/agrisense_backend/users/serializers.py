from rest_framework import serializers
from .models import User

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'username', 'first_name', 'last_name', 'email', 
                  'phone_number', 'role', 'profile_photo', 'is_verified', 
                  'is_premium', 'premium_expiry', 'date_joined', 'last_login']
        read_only_fields = ['id', 'is_verified', 'date_joined', 'last_login']

class FarmerSerializer(UserSerializer):
    class Meta(UserSerializer.Meta):
        fields = UserSerializer.Meta.fields

class DealerSerializer(UserSerializer):
    class Meta(UserSerializer.Meta):
        fields = UserSerializer.Meta.fields

class AdminSerializer(UserSerializer):
    class Meta(UserSerializer.Meta):
        fields = UserSerializer.Meta.fields