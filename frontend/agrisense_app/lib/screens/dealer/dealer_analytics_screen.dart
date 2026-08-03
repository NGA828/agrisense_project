import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/percent_indicator.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../admin/admin_widgets.dart' show AdminHeader;

/// Dealer sales analytics, fed by GET /api/dealers/analytics/?period=... .
class DealerAnalyticsScreen extends StatefulWidget {
  const DealerAnalyticsScreen({super.key});

  @override
  State<DealerAnalyticsScreen> createState() => _DealerAnalyticsScreenState();
}

class _DealerAnalyticsScreenState extends State<DealerAnalyticsScreen> {
  final ApiService _api = ApiService();
  String _selectedPeriod = '30d';
  Map<String, dynamic>? _data;
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
      final data = await _api.getDealerAnalytics(_selectedPeriod);
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AdminHeader(
              title: 'Sales Analytics',
              subtitle: 'Your store performance',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: ['7d', '30d', '90d', '1y'].map((period) {
                  final isSelected = period == _selectedPeriod;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedPeriod = period);
                        _load();
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primary : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : Colors.grey.shade300),
                        ),
                        child: Text(
                          period,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? _buildError()
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(color: AppTheme.error)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final data = _data ?? {};
    final totalOrders = (data['total_orders'] ?? 0) as num;
    final totalRevenue = (data['total_revenue'] ?? 0).toDouble();
    final lowStock = (data['low_stock_products'] ?? 0) as num;
    final topProducts =
        (data['top_products'] as List? ?? []).cast<Map<String, dynamic>>();
    final recentOrders =
        (data['recent_orders'] as List? ?? []).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            _statCard('Orders', totalOrders.toString(), Icons.receipt_rounded,
                AppTheme.primary),
            const SizedBox(width: 12),
            _statCard('Revenue (FCFA)', totalRevenue.toStringAsFixed(0),
                Icons.payments_rounded, AppTheme.success),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard('Low stock', lowStock.toString(), Icons.inventory_rounded,
                AppTheme.warning),
            const SizedBox(width: 12),
            _statCard(
                'Top product',
                topProducts.isNotEmpty
                    ? topProducts.first['name']?.toString() ?? '—'
                    : '—',
                Icons.star_rounded,
                AppTheme.info),
          ],
        ),
        const SizedBox(height: 24),
        Text('Top selling products',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (topProducts.isEmpty)
          const _EmptyNote('No sales in this period yet.')
        else
          ...topProducts.map(_productBar),
        const SizedBox(height: 24),
        Text('Recent orders',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        if (recentOrders.isEmpty)
          const _EmptyNote('No orders yet.')
        else
          ...recentOrders.map(_orderTile),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.grey.shade600, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _productBar(Map<String, dynamic> product) {
    final name = product['name']?.toString() ?? '—';
    final revenue = (product['revenue'] ?? 0).toDouble();
    final units = product['units'] ?? 0;
    final topProductsData = (_data?['top_products'] as List? ?? []);
    final maxRev = topProductsData.isEmpty
        ? 1.0
        : topProductsData
            .map((e) => (e['revenue'] ?? 0).toDouble())
            .fold(1.0, (a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12)),
              ),
              Text('$units units',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 4),
          LinearPercentIndicator(
            percent: maxRev > 0 ? (revenue / maxRev).clamp(0.0, 1.0) : 0,
            lineHeight: 8,
            progressColor: AppTheme.primary,
            backgroundColor: Colors.grey.shade200,
            animateFromLastPercent: true,
          ),
        ],
      ),
    );
  }

  Widget _orderTile(Map<String, dynamic> order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
            child: const Icon(Icons.shopping_bag_rounded,
                color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order['product']?.toString() ?? '',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                Text(order['farmer']?.toString() ?? '',
                    style: GoogleFonts.poppins(
                        color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${order['amount'] ?? 0} FCFA',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 12)),
              Text(order['status']?.toString() ?? '',
                  style:
                      GoogleFonts.poppins(color: AppTheme.info, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String message;
  const _EmptyNote(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(message,
          style:
              GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 12)),
    );
  }
}
