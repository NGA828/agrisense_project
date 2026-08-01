class User {
  final int? id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String role;
  final String? profilePhoto;
  final bool isVerified;
  final bool isPremium;
  final DateTime? premiumExpiry;
  final DateTime? dateJoined;

  User({
    this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    required this.role,
    this.profilePhoto,
    this.isVerified = false,
    this.isPremium = false,
    this.premiumExpiry,
    this.dateJoined,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      role: json['role'] ?? 'farmer',
      profilePhoto: json['profile_photo'],
      isVerified: json['is_verified'] ?? false,
      isPremium: json['is_premium'] ?? false,
      premiumExpiry: json['premium_expiry'] != null
          ? DateTime.tryParse(json['premium_expiry'].toString())
          : null,
      dateJoined: json['date_joined'] != null
          ? DateTime.tryParse(json['date_joined'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone_number': phoneNumber,
      'role': role,
      'profile_photo': profilePhoto,
      'is_verified': isVerified,
      'is_premium': isPremium,
    };
  }

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }

  bool get isFarmer => role == 'farmer';
  bool get isDealer => role == 'dealer';
  bool get isAdmin => role == 'admin';

  /// Premium is only 'active' if not expired (mirrors the backend property).
  bool get isPremiumActive {
    if (!isPremium) return false;
    if (premiumExpiry == null) return true;
    return premiumExpiry!.isAfter(DateTime.now());
  }
}
