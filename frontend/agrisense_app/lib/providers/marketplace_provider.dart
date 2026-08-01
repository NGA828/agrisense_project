import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../services/api/api_service.dart';
import '../services/local/cache_service.dart';
import 'realtime_provider.dart';

class MarketplaceProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<Product> _products = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  MarketplaceProvider() {
    // Live stock/availability updates over the push bus keep the marketplace
    // honest without refreshing the whole catalog.
    _rtSub = RealtimeProvider.instance.events.listen((event) {
      if (event['type'] == 'stock_update') {
        _applyStockUpdate(event['payload'] as Map<String, dynamic>? ?? {});
      }
    });
  }

  void _applyStockUpdate(Map<String, dynamic> payload) {
    final productId = payload['product_id'];
    if (productId == null) return;
    final index = _products.indexWhere((p) => p.idProduct == productId);
    if (index < 0) return;
    final p = _products[index];
    _products[index] = Product(
      idProduct: p.idProduct,
      dealerId: p.dealerId,
      dealerName: p.dealerName,
      dealerEmail: p.dealerEmail,
      dealerPhone: p.dealerPhone,
      dealerIsVerified: p.dealerIsVerified,
      dealerIsPremium: p.dealerIsPremium,
      name: p.name,
      description: p.description,
      category: p.category,
      price: p.price,
      stockQuantity: payload['stock_quantity'] as int? ?? p.stockQuantity,
      image: p.image,
      isAvailable: payload['is_available'] as bool? ?? p.isAvailable,
    );
    notifyListeners();
  }

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadProducts({String? category, String? search}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final fetched = await _api.getMarketplaceProducts(category: category, search: search);
      _products = fetched;
      // Cache the catalog (as raw JSON maps) for offline browsing.
      if (category == null && search == null) {
        await LocalCacheService.instance
            .cacheMarketplace(fetched.map((p) => p.toJson()).toList());
      }
    } catch (e) {
      // Offline-first: fall back to the last-known cached catalog.
      _error = e.toString();
      final cached = await LocalCacheService.instance.getMarketplace();
      if (cached != null && category == null && search == null) {
        _products = cached
            .map((j) => Product.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _products = [];
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    super.dispose();
  }
}
