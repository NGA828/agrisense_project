/// Lightweight models for the admin analytics endpoint.
class AnalyticsPoint {
  final String label;
  final double value;
  AnalyticsPoint(this.label, this.value);
}

class AdminAnalytics {
  final String period;
  final List<AnalyticsPoint> userGrowth;
  final List<AnalyticsPoint> diagnoses;
  final List<AnalyticsPoint> orderVolume;
  final List<AnalyticsPoint> revenue;
  final List<Map<String, dynamic>> topProducts;
  final List<Map<String, dynamic>> topDealers;

  AdminAnalytics({
    required this.period,
    required this.userGrowth,
    required this.diagnoses,
    required this.orderVolume,
    required this.revenue,
    required this.topProducts,
    required this.topDealers,
  });

  factory AdminAnalytics.fromJson(Map<String, dynamic> json) {
    List<AnalyticsPoint> series(String key) {
      final raw = json[key];
      if (raw is! Map) return [];
      final entries = raw.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      return entries
          .map((e) => AnalyticsPoint(_shortDate(e.key), _toDouble(e.value)))
          .toList();
    }

    return AdminAnalytics(
      period: json['period'] ?? '30d',
      userGrowth: series('user_growth'),
      diagnoses: series('diagnoses'),
      orderVolume: series('order_volume'),
      revenue: series('revenue'),
      topProducts: (json['top_products'] as List? ?? []).cast<Map<String, dynamic>>(),
      topDealers: (json['top_dealers'] as List? ?? []).cast<Map<String, dynamic>>(),
    );
  }

  static String _shortDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    return '${date.day}/${date.month}';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
