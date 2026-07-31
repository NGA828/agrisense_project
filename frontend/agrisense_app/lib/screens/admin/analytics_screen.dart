import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/analytics.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Platform analytics: user growth, diagnoses, order volume and revenue,
/// fed by GET /api/admin/analytics/?period=7d|30d|90d|1y.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = '30d';
  AdminAnalytics? _analytics;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService().getAdminAnalytics(_selectedPeriod);
      if (mounted) {
        setState(() {
          _analytics = AdminAnalytics.fromJson(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3A1A), Color(0xFF2D5016)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
                      Text('Platform Analytics',
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: ['7d', '30d', '90d', '1y'].map((period) {
                      final isSelected = period == _selectedPeriod;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedPeriod = period);
                          _load();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            period.toUpperCase(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? AppTheme.primaryDark : Colors.white,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text('Could not load analytics', style: AppTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(_error!, style: AppTheme.bodySmall, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(onPressed: _load, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final a = _analytics;
    if (a == null) return const SizedBox.shrink();
    final totalUsers = a.userGrowth.fold<double>(0, (s, p) => s + p.value);
    final totalDiagnoses = a.diagnoses.fold<double>(0, (s, p) => s + p.value);
    final totalOrders = a.orderVolume.fold<double>(0, (s, p) => s + p.value);
    final totalRevenue = a.revenue.fold<double>(0, (s, p) => s + p.value);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _statCard('${totalUsers.toInt()}', 'New Users', Icons.people_rounded, AppTheme.primary),
              _statCard('${totalDiagnoses.toInt()}', 'Diagnoses', Icons.eco_rounded, AppTheme.info),
              _statCard('${totalOrders.toInt()}', 'Orders', Icons.receipt_long_rounded, AppTheme.accent),
              _statCard('${totalRevenue.toInt()} FCFA', 'Revenue', Icons.attach_money_rounded, const Color(0xFF9C27B0)),
            ],
          ),
          const SizedBox(height: 24),
          _chartCard('User Growth', Icons.people_rounded, a.userGrowth, AppTheme.primary),
          const SizedBox(height: 16),
          _chartCard('Diagnosis Frequency', Icons.eco_rounded, a.diagnoses, AppTheme.info),
          const SizedBox(height: 16),
          _chartCard('Order Volume (FCFA)', Icons.receipt_long_rounded, a.orderVolume, AppTheme.accent),
          const SizedBox(height: 16),
          _chartCard('Revenue (FCFA)', Icons.attach_money_rounded, a.revenue, const Color(0xFF9C27B0)),
          const SizedBox(height: 24),
          _topListCard('Top Products', a.topProducts, isDealer: false),
          const SizedBox(height: 16),
          _topListCard('Top Dealers', a.topDealers, isDealer: true),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
          Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _chartCard(String title, IconData icon, List<AnalyticsPoint> points, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No data for this period', style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
            )
          else
            SizedBox(
              height: 130,
              child: CustomPaint(
                size: const Size(double.infinity, 130),
                painter: _BarChartPainter(points, color),
              ),
            ),
          const SizedBox(height: 10),
          // X labels (sparse)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(points.first.label, style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
              if (points.length > 2) Text(points[points.length ~/ 2].label, style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
              Text(points.last.label, style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topListCard(String title, List<Map<String, dynamic>> items, {required bool isDealer}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isDealer ? Icons.store_rounded : Icons.shopping_bag_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No data yet', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            )
          else
            ...items.take(5).map((item) {
              final name = item['name'] ?? 'Unknown';
              final revenue = (item['revenue'] ?? 0) as num;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                      child: Icon(isDealer ? Icons.storefront_rounded : Icons.inventory_2_rounded, size: 16, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text('${revenue.toInt()} FCFA',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Lightweight bar chart — no external chart dependency needed.
class _BarChartPainter extends CustomPainter {
  final List<AnalyticsPoint> points;
  final Color color;

  _BarChartPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxValue = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final barWidth = size.width / points.length * 0.55;

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < points.length; i++) {
      final height = (points[i].value / safeMax) * (size.height - 8);
      final left = i * (size.width / points.length) + (size.width / points.length - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()..color = color.withOpacity(0.85));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
