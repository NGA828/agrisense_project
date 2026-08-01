import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';
import 'analytics_screen.dart';
import 'content_management_screen.dart';
import 'dealer_verification_screen.dart';
import 'notifications_screen.dart';
import 'system_health_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EDE5),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _AdminOverview(),
          _AdminUsers(),
          _AdminOrders(),
          _AdminSettings(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _nav(0, Icons.home_rounded, 'Overview'),
                _nav(1, Icons.people_rounded, 'Users'),
                _nav(2, Icons.receipt_long_rounded, 'Orders'),
                _nav(3, Icons.settings_rounded, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nav(int i, IconData icon, String label) {
    final s = i == _selectedIndex;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: s ? AppTheme.primaryDark : AppTheme.textMuted),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: s ? FontWeight.w700 : FontWeight.w400,
              color: s ? AppTheme.primaryDark : AppTheme.textMuted,
            ),
          ),
          if (s)
            Container(
              width: 20,
              height: 3,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Overview ────────────────────────────────────────────────────────────────

class _AdminOverview extends StatefulWidget {
  const _AdminOverview();
  @override
  State<_AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<_AdminOverview> {
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final r = await api.getAdminStats();
      Map<String, dynamic>? analytics;
      try {
        analytics = await api.getAdminAnalytics('7d');
      } catch (_) {
        analytics = null;
      }
      setState(() {
        _stats = r;
        _analytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// User-growth series as (label, value) pairs for the overview chart.
  List<(String, double)> get _growthSeries {
    final raw = _analytics?['user_growth'];
    if (raw is! Map || raw.isEmpty) return [];

    final entries = raw.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final List<(String, double)> series = [];

    for (final entry in entries) {
      final date = DateTime.tryParse(entry.key.toString());
      final label = date == null ? entry.key.toString() : '${date.day}/${date.month}';
      final value = entry.value is num ? (entry.value as num).toDouble() : 0.0;
      series.add((label, value));
    }

    return series;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.of(context).padding.top + 20, 20, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A3A1A), Color(0xFF2D5016), Color(0xFF3A6B20)],
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Admin Dashboard',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          children: [
                            const Icon(Icons.notifications_none_rounded,
                                color: Colors.white, size: 22),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppTheme.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Good morning, Admin',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Here's what's happening on your platform today",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            color: Colors.white.withValues(alpha: 0.9), size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'July 24, 2026',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Stats grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.4,
                children: [
                  _stat('${_stats?['total_users'] ?? 0}', 'Total Users',
                      Icons.people_rounded, const Color(0xFFE8F5E9), AppTheme.primary,
                      '${_stats?['active_users'] ?? 0} active'),
                  _stat('${_stats?['total_dealers'] ?? 0}', 'Dealers',
                      Icons.store_rounded, const Color(0xFFFFF3E0), AppTheme.accent,
                      '${_stats?['pending_dealer_requests'] ?? 0} pending'),
                  _stat('${_stats?['total_diagnoses'] ?? 0}', 'Diagnoses',
                      Icons.eco_rounded, const Color(0xFFE3F2FD), AppTheme.info,
                      '${_stats?['premium_dealers'] ?? 0} premium dealers'),
                  _stat('${_stats?['total_orders'] ?? 0}', 'Total Orders',
                      Icons.receipt_long_rounded, const Color(0xFFF3E5F5),
                      const Color(0xFF9C27B0), '${_stats?['total_revenue'] ?? 0} FCFA'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Activity chart
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Platform Activity',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: AppTheme.textPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.trending_up_rounded,
                                  color: AppTheme.primary, size: 14),
                              const SizedBox(width: 4),
                              Text('Last 7 Days',
                                  style: TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      height: 140,
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _growthSeries.isEmpty
                          ? Center(
                              child: Text('New user registrations (last 7 days)',
                                  style: TextStyle(
                                      color: AppTheme.primary.withValues(alpha: 0.6),
                                      fontSize: 12)),
                            )
                          : CustomPaint(
                              size: const Size(double.infinity, 116),
                              painter: _AdminMiniBarChart(_growthSeries),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                            width: 12,
                            height: 3,
                            decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('New users',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 20),
                        Container(
                            width: 12,
                            height: 3,
                            decoration: BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('7 days',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 20),
                        Container(
                            width: 12,
                            height: 3,
                            decoration: BoxDecoration(
                                color: AppTheme.info,
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 6),
                        Text('Growth',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Quick Actions',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _action(Icons.analytics_rounded, 'View Analytics', AppTheme.primary,
                      () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AnalyticsScreen()))),
                  const SizedBox(width: 12),
                  _action(
                      Icons.verified_user_rounded, 'Verify Dealers', AppTheme.info,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DealerVerificationScreen()))),
                  const SizedBox(width: 12),
                  _action(Icons.article_rounded, 'Manage Content', AppTheme.success,
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ContentManagementScreen()))),
                  const SizedBox(width: 12),
                  _action(Icons.notifications_rounded, 'Send Notice',
                      const Color(0xFF9C27B0),
                      () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Recent Activity',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._recentActivityItems(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Real recent orders + diagnoses from the admin stats endpoint.
  List<Widget> _recentActivityItems() {
    final items = <Widget>[];
    final recentOrders = (_stats?['recent_orders'] as List? ?? []).take(3).toList();
    final recentDiagnoses = (_stats?['recent_diagnoses'] as List? ?? []).take(2).toList();

    for (final order in recentOrders) {
      items.add(_act(
        Icons.receipt_long_rounded,
        'New order #${order['id']}',
        '${order['farmer']} · ${order['product']} · ${order['amount']} FCFA',
        _timeAgo(order['date']),
        AppTheme.info,
      ));
      items.add(const SizedBox(height: 12));
    }
    for (final d in recentDiagnoses) {
      items.add(_act(
        Icons.eco_rounded,
        'AI diagnosis',
        '${d['user']} · ${d['crop']}: ${d['disease']} (${d['confidence']}%)',
        _timeAgo(d['date']),
        AppTheme.success,
      ));
      items.add(const SizedBox(height: 12));
    }
    if (items.isEmpty) {
      items.add(Text('No activity yet — orders and diagnoses will appear here.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
    }
    return items;
  }

  String _timeAgo(String? dateTime) {
    final date = DateTime.tryParse(dateTime ?? '');
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  Widget _stat(String v, String l, IconData i, Color bg, Color ic, String s) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(i, color: ic, size: 22),
            ),
            const SizedBox(height: 12),
            Text(v,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800, fontSize: 26)),
            Text(l,
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ic.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(s,
                  style: TextStyle(
                      color: ic, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  Widget _action(IconData i, String l, Color c, [VoidCallback? onTap]) =>
      GestureDetector(
        onTap: onTap,
        child: Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(i, color: c, size: 24),
                ),
                const SizedBox(height: 12),
                Text(l,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: AppTheme.textPrimary)),
              ],
            ),
          ),
        ),
      );

  Widget _act(IconData i, String t, String d, String time, Color c) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(i, color: c, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(d,
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Text(time,
                style:
                    TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ],
        ),
      );
}

// ─── Users ───────────────────────────────────────────────────────────────────

class _AdminUsers extends StatefulWidget {
  const _AdminUsers();
  @override
  State<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<_AdminUsers> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final r = await api.getUsers();
      setState(() {
        _users = r;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _filter == 'all'
        ? _users
        : _users.where((u) => u['role'] == _filter).toList();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A3A1A), Color(0xFF2D5016)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('User Management',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 20)),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: Colors.grey.shade400, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Search users by name or email...',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                _us('All', '${_users.length}', AppTheme.primary),
                const SizedBox(width: 12),
                _us('Farmers',
                    '${_users.where((u) => u['role'] == 'farmer').length}',
                    AppTheme.info),
                const SizedBox(width: 12),
                _us('Dealers',
                    '${_users.where((u) => u['role'] == 'dealer').length}',
                    AppTheme.accent),
                const SizedBox(width: 12),
                _us('Pending',
                    '${_users.where((u) => u['is_active'] == false).length}',
                    AppTheme.warning),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: ['All', 'Farmers', 'Dealers', 'Admins'].map((t) {
                final s = (t.toLowerCase() == _filter) ||
                    (t == 'All' && _filter == 'all');
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() =>
                        _filter = t == 'All' ? 'all' : t.toLowerCase().replaceAll('s', '')),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: s ? AppTheme.primaryDark : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(t,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  s ? FontWeight.w700 : FontWeight.w500,
                              color: s
                                  ? AppTheme.primaryDark
                                  : AppTheme.textMuted)),
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
                : RefreshIndicator(
                    onRefresh: _loadUsers,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: f.length,
                      itemBuilder: (c, i) => _uc(f[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _us(String l, String v, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(v,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800, fontSize: 20, color: c)),
              Text(l,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );

  Widget _uc(dynamic u) {
    final a = u['is_active'] ?? true;
    final r = u['role'] ?? 'farmer';
    final rc =
        {'farmer': AppTheme.primary, 'dealer': AppTheme.info, 'admin': AppTheme.accent}[r] ??
            Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: rc.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.person_rounded, color: rc, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                    Icon(Icons.verified_rounded,
                        size: 16, color: a ? AppTheme.success : Colors.grey),
                  ],
                ),
                const SizedBox(height: 4),
                Text(u['email'] ?? '',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: a
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    a ? 'Active' : 'Suspended',
                    style: TextStyle(
                        fontSize: 11,
                        color: a ? AppTheme.success : AppTheme.error,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (!a) ...[
            Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.grey.shade200),
            GestureDetector(
              onTap: () => _toggleUserActive(u['id'], true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Activate',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.success,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ] else ...[
            Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: Colors.grey.shade200),
            GestureDetector(
              onTap: () => _toggleUserActive(u['id'], false),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Suspend',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.error,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _deleteUser(u),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_rounded, size: 16, color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(dynamic u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''} (@${u['username']}) '
            'will be permanently removed from the platform. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteUser(u['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted'), backgroundColor: AppTheme.success),
        );
        _loadUsers();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete user: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  Future<void> _toggleUserActive(int userId, bool active) async {
    try {
      final api = ApiService();
      if (active) {
        await api.activateUser(userId);
      } else {
        await api.suspendUser(userId);
      }
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update user: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}

// ─── Orders ──────────────────────────────────────────────────────────────────

class _AdminOrders extends StatefulWidget {
  const _AdminOrders();

  @override
  State<_AdminOrders> createState() => _AdminOrdersState();
}

class _AdminOrdersState extends State<_AdminOrders> {
  List<dynamic> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final orders = await ApiService().getOrders();
      if (mounted) setState(() {
        _orders = orders is List ? orders : [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _orders.length;
    final pending = _orders.where((o) => o['status'] == 'pending').length;
    final inTransit = _orders.where((o) => o['status'] == 'shipped').length;
    final completed = _orders.where((o) => o['status'] == 'delivered').length;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A3A1A), Color(0xFF2D5016)],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order Management',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20)),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                _os('$total', 'Total Orders', AppTheme.primary),
                const SizedBox(width: 12),
                _os('$pending', 'Pending', AppTheme.warning),
                const SizedBox(width: 12),
                _os('$inTransit', 'In Transit', AppTheme.info),
                const SizedBox(width: 12),
                _os('$completed', 'Completed', AppTheme.success),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _orders.isEmpty
                    ? Center(
                        child: Text('No orders yet', style: TextStyle(color: AppTheme.textMuted)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          itemCount: _orders.length,
                          itemBuilder: (context, index) => _buildOrderItem(_orders[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(dynamic order) {
    final status = order['status'] ?? 'pending';
    final statusColor = {
      'pending': AppTheme.warning,
      'confirmed': AppTheme.info,
      'shipped': AppTheme.info,
      'delivered': AppTheme.success,
      'cancelled': AppTheme.error,
    }[status] ?? AppTheme.textMuted;
    final farmer = order['farmer_name'] ?? 'Farmer';
    final product = order['product_name'] ?? 'Product';
    final amount = '${order['total_price'] ?? 0} FCFA';
    final details = '${order['quantity']}x $product · ${order['payment_status'] ?? 'unpaid'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.inventory_2_rounded, color: statusColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order['id']}',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(farmer,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(details, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11, color: statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _os(String v, String l, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(v,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800, fontSize: 20, color: c)),
              Text(l,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );

  Widget _oi(String id, String c, String city, String amt, String st,
      Color sc, String details) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: sc.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.inventory_2_rounded, color: sc, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text('$c - $city',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(details,
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amt,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sc.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(st,
                    style: TextStyle(
                        fontSize: 11,
                        color: sc,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class _AdminSettings extends StatelessWidget {
  const _AdminSettings();

  Future<void> _editProfile(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final firstName = TextEditingController(text: user.firstName);
    final lastName = TextEditingController(text: user.lastName);
    final phone = TextEditingController(text: user.phoneNumber);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: firstName, decoration: const InputDecoration(labelText: 'First name')),
              const SizedBox(height: 8),
              TextField(controller: lastName, decoration: const InputDecoration(labelText: 'Last name')),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved == true) {
      try {
        await auth.updateProfile(
          firstName: firstName.text.trim(),
          lastName: lastName.text.trim(),
          phoneNumber: phone.text.trim(),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated'), backgroundColor: AppTheme.success),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 8, 20, 16),
            decoration: const BoxDecoration(color: Color(0xFF2D5016)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Admin Settings',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18)),
                Row(
                  children: [
                    const Icon(Icons.notifications_none_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person_rounded,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Platform Administrator',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(user?.email ?? 'admin@agrisense.cm',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => _editProfile(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primaryDark),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Edit Profile',
                        style: TextStyle(
                            color: AppTheme.primaryDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Platform Settings',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  _si(Icons.settings_rounded, 'General',
                      'Language, region, and app details'),
                  _si(Icons.admin_panel_settings_rounded, 'Roles & Permissions',
                      'Manage administrator access'),
                  _si(Icons.payment_rounded, 'Payment Configuration',
                      'MTN MoMo and Orange Money'),
                  _si(Icons.cloud_rounded, 'Weather API', 'Connected'),
                  _si(Icons.smart_toy_rounded, 'AI Model Settings',
                      'Version 3.2 active'),
                  _si(
                      Icons.health_and_safety_rounded,
                      'System Health',
                      'Monitor API, database, AI engine',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SystemHealthScreen()))),
                  _si(
                      Icons.article_rounded,
                      'Content Management',
                      'Manage disease database',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ContentManagementScreen()))),
                  _si(
                      Icons.verified_user_rounded,
                      'Dealer Verification',
                      'Review dealer applications',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const DealerVerificationScreen()))),
                  const SizedBox(height: 20),
                  Text('Security',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  _sWI(Icons.lock_rounded, 'Two-Factor Authentication', true),
                  _si(Icons.history_rounded, 'Login Activity', ''),
                  _si(Icons.folder_rounded, 'Data & Privacy', ''),
                  const SizedBox(height: 20),
                  Text('Communication',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 10),
                  _sWI(Icons.notifications_rounded, 'Push Notifications', true),
                  _sWI(Icons.email_rounded, 'Email Reports', false),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await context.read<AuthProvider>().logout();
                        if (context.mounted) {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/', (route) => false);
                        }
                      },
                      icon: Icon(Icons.logout_rounded,
                          color: AppTheme.error, size: 18),
                      label: Text('Sign Out',
                          style: TextStyle(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _si(IconData i, String t, String s, [VoidCallback? onTap]) =>
      GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(i, size: 22, color: AppTheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: AppTheme.textPrimary)),
                      if (s.isNotEmpty)
                        Text(s,
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.grey.shade400, size: 16)
                else
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.grey.shade400, size: 24),
              ],
            ),
          ),
        ),
      );

  Widget _sWI(IconData i, String t, bool v) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(i, size: 22, color: AppTheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(t,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppTheme.textPrimary)),
              ),
              Switch(
                value: v,
                onChanged: (newVal) {},
                activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
                thumbColor: WidgetStateProperty.all(AppTheme.primary),
              ),
            ],
          ),
        ),
      );
}

/// Lightweight vertical bar chart for the admin overview (no chart dependency).
class _AdminMiniBarChart extends CustomPainter {
  final List<(String, double)> points;
  _AdminMiniBarChart(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxValue = points.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final barWidth = size.width / points.length * 0.5;

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 0.8;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < points.length; i++) {
      final height = (points[i].$2 / safeMax) * (size.height - 6);
      final left = i * (size.width / points.length) +
          (size.width / points.length - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, barWidth, height),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = AppTheme.primary.withOpacity(0.85));
    }
  }

  @override
  bool shouldRepaint(covariant _AdminMiniBarChart oldDelegate) =>
      oldDelegate.points != points;
}
