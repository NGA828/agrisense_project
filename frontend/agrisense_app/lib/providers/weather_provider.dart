import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api/api_service.dart';
import '../services/local/cache_service.dart';

class WeatherData {
  final double temperature;
  final double feelsLike;
  final double humidity;
  final double windSpeed;
  final String condition;
  final String location;
  final List<DailyForecast> forecast;
  final String advice;

  WeatherData({
    required this.temperature, required this.feelsLike, required this.humidity,
    required this.windSpeed, required this.condition, required this.location,
    this.forecast = const [], this.advice = '',
  });

  factory WeatherData.fromApi(Map<String, dynamic> json) {
    return WeatherData(
      temperature: (json['temperature'] ?? 0).toDouble(),
      feelsLike: (json['feels_like'] ?? 0).toDouble(),
      humidity: (json['humidity'] ?? 0).toDouble(),
      windSpeed: (json['wind_speed'] ?? 0).toDouble(),
      condition: json['condition'] ?? '',
      location: json['location'] ?? '',
      advice: json['farming_advice'] ?? '',
      forecast: (json['forecast'] as List? ?? []).map((f) => DailyForecast(
        day: _dayName(f['dt']),
        high: (f['temp_max'] ?? f['temp'] ?? 0).toDouble(),
        low: (f['temp_min'] ?? f['temp'] ?? 0).toDouble(),
        condition: f['condition'] ?? '',
      )).toList(),
    );
  }

  static String _dayName(dynamic timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch((timestamp is int ? timestamp : 0) * 1000);
    return ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][date.weekday % 7];
  }
}

class DailyForecast {
  final String day;
  final double high;
  final double low;
  final String condition;
  DailyForecast({required this.day, required this.high, required this.low, required this.condition});
}

class WeatherProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  WeatherData? _weather;
  bool _isLoading = false;
  String? _error;
  bool _locationPermissionDenied = false;

  WeatherData? get weather => _weather;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get locationPermissionDenied => _locationPermissionDenied;

  Future<void> loadWeather({double? lat, double? lon}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      double? latitude = lat;
      double? longitude = lon;
      
      // If no coordinates provided, get current location
      if (latitude == null || longitude == null) {
        try {
          Position position = await _getCurrentLocation();
          latitude = position.latitude;
          longitude = position.longitude;
        } catch (e) {
          _locationPermissionDenied = true;
          // Fall back to default location
          latitude = 3.8480; // Yaoundé
          longitude = 11.5021;
        }
      }
      
      final data = await _api.getWeather(lat: latitude, lon: longitude);
      _weather = WeatherData.fromApi(data);
      // Cache the latest weather for offline display.
      await LocalCacheService.instance.cacheWeather(data);
    } catch (e) {
      // Offline-first: fall back to the last-known cached weather.
      _error = e.toString();
      final cached = await LocalCacheService.instance.getWeather();
      if (cached != null) {
        _weather = WeatherData.fromApi(cached);
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}
