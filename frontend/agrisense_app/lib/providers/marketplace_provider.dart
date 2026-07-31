import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/api/api_service.dart';

class MarketplaceProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<Product> _products = [];
  bool _isLoading = false;
  String? _error;

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadProducts({String? category}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _products = await _api.getMarketplaceProducts(category: category);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
