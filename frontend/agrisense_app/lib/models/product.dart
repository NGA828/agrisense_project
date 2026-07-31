import '../services/api/api_service.dart';

class Product {
  final int idProduct;
  final String name;
  final String description;
  final String category;
  final double price;
  final int stockQuantity;
  final String image;
  final bool isAvailable;
  final int dealerId;
  final String dealerName;
  final String dealerEmail;
  final String dealerPhone;
  final bool dealerIsVerified;
  final bool dealerIsPremium;

  Product({
    required this.idProduct,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.stockQuantity,
    required this.image,
    required this.isAvailable,
    required this.dealerId,
    required this.dealerName,
    required this.dealerEmail,
    this.dealerPhone = '',
    this.dealerIsVerified = false,
    this.dealerIsPremium = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      idProduct: json['id_product'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      price: double.parse((json['price'] ?? 0).toString()),
      stockQuantity: json['stock_quantity'] ?? 0,
      image: ApiService.resolveMedia(json['image'] as String?),
      isAvailable: json['is_available'] ?? true,
      dealerId: json['dealer'] ?? 0,
      dealerName: json['dealer_name'] ?? '',
      dealerEmail: json['dealer_email'] ?? '',
      dealerPhone: json['dealer_phone'] ?? '',
      dealerIsVerified: json['dealer_is_verified'] ?? false,
      dealerIsPremium: json['dealer_is_premium'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_product': idProduct,
      'name': name,
      'description': description,
      'category': category,
      'price': price,
      'stock_quantity': stockQuantity,
      'is_available': isAvailable,
    };
  }

  bool get inStock => stockQuantity > 0 && isAvailable;
  String get categoryLabel {
    switch (category) {
      case 'fertilizer': return 'Fertilizer';
      case 'seed': return 'Seed';
      case 'herbicide': return 'Herbicide';
      case 'pesticide': return 'Pesticide';
      case 'fungicide': return 'Fungicide';
      case 'equipment': return 'Equipment';
      default: return category;
    }
  }
}
