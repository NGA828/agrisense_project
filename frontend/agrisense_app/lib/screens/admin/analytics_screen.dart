import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/analytics.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

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
      backgroundColor: AdminTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AdminHeader(
              title: 'Platform Analytics',
              subtitle: 'Performance across the selected period',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            // Period selector
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
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primary
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          period.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? AdminErrorState(message: _error!, onRetry: _load)
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
    final totalUsers =
        a.userGrowth.fold<double>(0, (s, p) => s + p.value);
    final totalDiagnoses =
        a.diagnoses.fold<double>(0, (s, p) => s + p.value);
    final totalOrders =
        a.orderVolume.fold<double>(0, (s, p) => s + p.value);
    final totalRevenue =
        a.revenue.fold<double>(0, (s, p) => s + p.value);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.5,
            children: [
              AdminStatCard(
                  value: '${totalUsers.toInt()}',
                  label: 'New Users',
                  icon: Icons.people_alt_rounded,
                  color: AppTheme.primary),
              AdminStatCard(
                  value: '${totalDiagnoses.toInt()}',
                  label: 'Diagnoses',
                  icon: Icons.eco_rounded,
                  color: AppTheme.info),
              AdminStatCard(
                  value: '${totalOrders.toInt()}',
                  label: 'Orders',
                  icon: Icons.receipt_long_rounded,
                  color: AppTheme.accent),
              AdminStatCard(
                  value: '${totalRevenue.toInt()} FCFA',
                  label: 'Revenue',
                  icon: Icons.payments_rounded,
                  color: AdminTheme.purple),
            ],
          ),
          const SizedBox(height: 22),
          _chartCard('User Growth', Icons.people_alt_rounded, a.userGrowth,
              AppTheme.primary),
          const SizedBox(height: 14),
          _chartCard('Diagnosis Frequency', Icons.eco_rounded, a.diagnoses,
              AppTheme.info),
          const SizedBox(height: 14),
          _chartCard('Order Volume (FCFA)', Icons.receipt_long_rounded,
              a.orderVolume, AppTheme.accent),
          const SizedBox(height: 14),
          _chartCard('Revenue (FCFA)', Icons.payments_rounded, a.revenue,
              AdminTheme.purple),
          const SizedBox(height: 22),
          _topListCard('Top Products', a.topProducts, isDealer: false),
          const SizedBox(height: 14),
          _topListCard('Top Dealers', a.topDealers, isDealer: true),
        ],
      ),
    );
  }

  Widget _chartCard(String title, IconData icon, List<AnalyticsPoint> points,
      Color color) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Text(title, style: AdminTheme.sectionTitle()),
            ],
          ),
          const SizedBox(height: 14),
          AdminBarChart(
            points: points.map((p) => (p.label, p.value)).toList(),
            color: color,
            height: 140,
          ),
          const SizedBox(height: 8),
          if (points.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(points.first.label,
                    style: AdminTheme.smallMuted()),
                if (points.length > 2)
                  Text(points[points.length ~/ 2].label,
                      style: AdminTheme.smallMuted()),
                Text(points.last.label, style: AdminTheme.smallMuted()),
              ],
            ),
        ],
      ),
    );
  }

  Widget _topListCard(String title, List<Map<String, dynamic>> items,
      {required bool isDealer}) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                    isDealer
                        ? Icons.storefront_rounded
                        : Icons.shopping_bag_rounded,
                    size: 18,
                    color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              Text(title, style: AdminTheme.sectionTitle()),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('No data yet',
                  style: AdminTheme.smallMuted()),
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
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                          isDealer
                              ? Icons.store_rounded
                              : Icons.inventory_2_rounded,
                          size: 16,
                          color: AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${revenue.toInt()} FCFA',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppTheme.primary),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
