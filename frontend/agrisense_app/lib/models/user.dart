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
    this.dateJoined,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      email: json['email'],
      phoneNumber: json['phone_number'],
      role: json['role'],
      profilePhoto: json['profile_photo'],
      isVerified: json['is_verified'] ?? false,
      dateJoined: json['date_joined'] != null 
          ? DateTime.parse(json['date_joined']) 
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
    };
  }

  bool get isFarmer => role == 'farmer';
  bool get isDealer => role == 'dealer';
  bool get isAdmin => role == 'admin';
}