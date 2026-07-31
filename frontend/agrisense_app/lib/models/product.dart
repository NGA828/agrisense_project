class Product {
  final int idProduct;
  final String name;
  final String description;
  final String category;
  final double price;
  final int stockQuantity;
  final String image;
  final bool isAvailable;
  final String dealerName;
  final String dealerEmail;

  Product({
    required this.idProduct,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.stockQuantity,
    required this.image,
    required this.isAvailable,
    required this.dealerName,
    required this.dealerEmail,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      idProduct: json['id_product'],
      name: json['name'],
      description: json['description'],
      category: json['category'],
      price: double.parse(json['price'].toString()),
      stockQuantity: json['stock_quantity'],
      image: json['image'],
      isAvailable: json['is_available'],
      dealerName: json['dealer_name'],
      dealerEmail: json['dealer_email'],
    );
  }
}