import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';
import 'analytics_screen.dart';
import 'content_management_screen.dart';
import 'dealer_verification_screen.dart';
import 'notifications_screen.dart';
import 'system_health_screen.dart';
import 'audit_log_screen.dart';
import 'outbreaks_screen.dart';

/// AgriSense admin console.
///
/// Redesigned around a single coherent design system (see admin_widgets.dart):
/// a slide-out navigation drawer listing every console section, a bottom
/// navigation bar for the four primary tabs, and shared cards/headers/pills
/// across all pages.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;

  /// Standalone pages reachable from the drawer (and quick actions).
  static const List<AdminNavItem> _pages = [
    AdminNavItem(100, Icons.analytics_rounded, Icons.analytics_rounded,
        'Analytics', isPage: true),
    AdminNavItem(101, Icons.verified_user_rounded,
        Icons.verified_user_rounded, 'Dealer Verification', isPage: true),
    AdminNavItem(102, Icons.article_rounded, Icons.article_rounded,
        'Content Management', isPage: true),
    AdminNavItem(103, Icons.campaign_rounded, Icons.campaign_rounded,
        'Broadcast Center', isPage: true),
    AdminNavItem(104, Icons.monitor_heart_rounded,
        Icons.monitor_heart_rounded, 'System Health', isPage: true),
  ];

  void _openPage(int id) {
    final Widget page = switch (id) {
      100 => const AnalyticsScreen(),
      101 => const DealerVerificationScreen(),
      102 => const ContentManagementScreen(),
      103 => const NotificationsScreen(),
      104 => const SystemHealthScreen(),
      105 => const AuditLogScreen(),
      _ => const AnalyticsScreen(),
    };
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      backgroundColor: AdminTheme.canvas,
      drawer: AdminDrawer(
        selectedIndex: _selectedIndex,
        onSelect: (i) => setState(() => _selectedIndex = i),
        onPageSelected: _openPage,
        pages: _pages,
        onLogout: _logout,
        adminName: user?.fullName,
        adminEmail: user?.email,
        adminPhoto: user?.profilePhoto,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _AdminOverview(),
          _AdminUsers(),
          _AdminOrders(),
          _AdminSettings(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.14),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded,
                color: AppTheme.primaryDark),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon:
                Icon(Icons.people_alt_rounded, color: AppTheme.primaryDark),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded,
                color: AppTheme.primaryDark),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon:
                Icon(Icons.settings_rounded, color: AppTheme.primaryDark),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Overview tab ────────────────────────────

class _AdminOverview extends StatefulWidget {
  const _AdminOverview();

  @override
  State<_AdminOverview> createState() => _AdminOverviewState();
}

class _AdminOverviewState extends State<_AdminOverview> {
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;
  String? _error;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final r = await api.getAdminStats();
      Map<String, dynamic>? analytics;
      try {
        analytics = await api.getAdminAnalytics('7d');
      } catch (_) {
        analytics = null;
      }
      var unread = 0;
      try {
        unread = await api.getUnreadNotificationCount();
      } catch (_) {
        unread = 0;
      }
      if (!mounted) return;
      setState(() {
        _stats = r;
        _analytics = analytics;
        _unreadNotifications = unread;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<(String, double)> get _growthSeries {
    final raw = _analytics?['user_growth'];
    if (raw is! Map || raw.isEmpty) return [];
    final entries = raw.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final series = <(String, double)>[];
    for (final entry in entries) {
      final date = DateTime.tryParse(entry.key.toString());
      final label =
          date == null ? entry.key.toString() : '${date.day}/${date.month}';
      final value = entry.value is num ? (entry.value as num).toDouble() : 0.0;
      series.add((label, value));
    }
    return series;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String _formatFcfa(num? value) {
    final v = value ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return SafeArea(
      bottom: false,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? AdminErrorState(message: _error!, onRetry: _loadStats)
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  color: AppTheme.primary,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildHeader(context, user),
                      const SizedBox(height: 20),
                      // KPI grid
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.35,
                          children: [
                            AdminStatCard(
                              value: '${_stats?['total_users'] ?? 0}',
                              label: 'Total Users',
                              icon: Icons.people_alt_rounded,
                              color: AppTheme.primary,
                              footnote:
                                  '${_stats?['active_users'] ?? 0} active',
                            ),
                            AdminStatCard(
                              value: '${_stats?['total_dealers'] ?? 0}',
                              label: 'Dealers',
                              icon: Icons.storefront_rounded,
                              color: AppTheme.accent,
                              footnote:
                                  '${_stats?['pending_dealer_requests'] ?? 0} pending',
                            ),
                            AdminStatCard(
                              value: '${_stats?['total_diagnoses'] ?? 0}',
                              label: 'Diagnoses',
                              icon: Icons.eco_rounded,
                              color: AppTheme.info,
                              footnote:
                                  '${_stats?['premium_dealers'] ?? 0} premium dealers',
                            ),
                            AdminStatCard(
                              value:
                                  '${_formatFcfa((_stats?['total_revenue'] as num?) ?? 0)} FCFA',
                              label: 'Revenue',
                              icon: Icons.payments_rounded,
                              color: AdminTheme.purple,
                              footnote: '${_stats?['total_orders'] ?? 0} orders',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Activity chart
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AdminCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                        Icons.insights_rounded,
                                        color: AppTheme.primary,
                                        size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Platform Activity',
                                            style:
                                                AdminTheme.sectionTitle()),
                                        Text('New user registrations · 7 days',
                                            style: AdminTheme.smallMuted()),
                                      ],
                                    ),
                                  ),
                                  AdminPill(
                                    label: 'Last 7 days',
                                    color: AppTheme.primary,
                                    icon: Icons.trending_up_rounded,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary
                                      .withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: AdminBarChart(
                                  points: _growthSeries,
                                  color: AppTheme.primary,
                                  height: 150,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AdminSectionTitle(
                          title: 'Quick Actions',
                          action: TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SystemHealthScreen()),
                            ),
                            icon: const Icon(Icons.monitor_heart_rounded,
                                size: 16, color: AppTheme.primary),
                            label: const Text('System Health',
                                style: TextStyle(
                                    color: AppTheme.primary, fontSize: 12)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            _action(
                                Icons.analytics_rounded,
                                'Analytics',
                                AppTheme.primary,
                                () => _push(const AnalyticsScreen())),
                            const SizedBox(width: 10),
                            _action(
                                Icons.verified_user_rounded,
                                'Verify Dealers',
                                AppTheme.info,
                                () =>
                                    _push(const DealerVerificationScreen())),
                            const SizedBox(width: 10),
                            _action(
                                Icons.article_rounded,
                                'Manage Content',
                                AppTheme.success,
                                () => _push(const ContentManagementScreen())),
                            const SizedBox(width: 10),
                            _action(
                                Icons.campaign_rounded,
                                'Send Notice',
                                AdminTheme.purple,
                                () => _push(const NotificationsScreen())),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AdminSectionTitle(
                          title: 'Recent Activity',
                          action: TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const AnalyticsScreen()),
                            ),
                            icon: const Icon(Icons.open_in_new_rounded,
                                size: 14, color: AppTheme.primary),
                            label: const Text('View analytics',
                                style: TextStyle(
                                    color: AppTheme.primary, fontSize: 12)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AdminCard(child: _activityList()),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
    );
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildHeader(BuildContext context, dynamic user) {
    final firstName = user?.firstName?.isNotEmpty == true
        ? user.firstName
        : (user?.username ?? 'Admin');
    return Container(
      width: double.infinity,
      decoration: AdminTheme.headerGradient,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded,
                      color: Colors.white, size: 24),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _push(const NotificationsScreen()),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    children: [
                      const Center(
                        child: Icon(Icons.notifications_none_rounded,
                            color: Colors.white, size: 21),
                      ),
                      if (_unreadNotifications > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: Text(
                              _unreadNotifications > 9
                                  ? '9+'
                                  : '$_unreadNotifications',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$_greeting, $firstName 👋',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Here's what's happening on your platform today",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded,
                    color: Colors.white.withValues(alpha: 0.9), size: 13),
                const SizedBox(width: 7),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityList() {
    final items = <Widget>[];
    final recentOrders =
        (_stats?['recent_orders'] as List? ?? []).take(3).toList();
    final recentDiagnoses =
        (_stats?['recent_diagnoses'] as List? ?? []).take(2).toList();

    for (final order in recentOrders) {
      items.add(_activityRow(
        icon: Icons.receipt_long_rounded,
        color: AppTheme.info,
        title: 'New order #${order['id']}',
        detail:
            '${order['farmer']} · ${order['product']} · ${order['amount']} FCFA',
        time: _timeAgo(order['date']),
      ));
      items.add(const Divider(height: 20, color: Color(0xFFF0F0F0)));
    }
    for (final d in recentDiagnoses) {
      items.add(_activityRow(
        icon: Icons.eco_rounded,
        color: AppTheme.success,
        title: 'AI diagnosis',
        detail:
            '${d['user']} · ${d['crop']}: ${d['disease']} (${d['confidence']}%)',
        time: _timeAgo(d['date']),
      ));
      items.add(const Divider(height: 20, color: Color(0xFFF0F0F0)));
    }
    if (items.isNotEmpty) items.removeLast();
    if (items.isEmpty) {
      items.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No activity yet — orders and diagnoses will appear here.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      ));
    }
    return Column(children: items);
  }

  Widget _activityRow({
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
    required String time,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(detail,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(time,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ],
    );
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

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          decoration: AdminTheme.cardDecoration,
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Users tab ───────────────────────────────

class _AdminUsers extends StatefulWidget {
  const _AdminUsers();

  @override
  State<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<_AdminUsers> {
  List<dynamic> _users = [];
  bool _isLoading = true;
  String? _error;
  String _filter = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final r = await ApiService().getUsers();
      if (mounted) {
        setState(() {
          _users = r;
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

  List<dynamic> get _filtered {
    var list = _users;
    if (_filter != 'all') {
      list = list.where((u) => u['role'] == _filter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((u) {
        final haystack = [
          u['first_name'],
          u['last_name'],
          u['username'],
          u['email'],
          u['phone_number'],
        ].join(' ').toLowerCase();
        return haystack.contains(q);
      }).toList();
    }
    return list;
  }

  int get _pendingCount =>
      _users.where((u) => u['role'] == 'dealer' && u['is_verified'] == false).length;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'User Management',
            subtitle:
                '${_users.length} account(s) · ${_pendingCount} awaiting dealer verification',
            leading: const Icon(Icons.people_alt_rounded,
                color: Colors.white, size: 22),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: AdminSearchField(
              hint: 'Search by name, username, email or phone...',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _countChip('All', '${_users.length}', AppTheme.primary),
                const SizedBox(width: 10),
                _countChip(
                    'Farmers',
                    '${_users.where((u) => u['role'] == 'farmer').length}',
                    AppTheme.info),
                const SizedBox(width: 10),
                _countChip(
                    'Dealers',
                    '${_users.where((u) => u['role'] == 'dealer').length}',
                    AppTheme.accent),
                const SizedBox(width: 10),
                _countChip('Pending', '$_pendingCount', AppTheme.warning),
              ],
            ),
          ),
          // Filter tabs
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: ['All', 'Farmers', 'Dealers', 'Admins'].map((t) {
                final f =
                    t == 'All' ? 'all' : t.toLowerCase().replaceAll('s', '');
                final selected = f == _filter;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: selected
                                ? AppTheme.primaryDark
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        t,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppTheme.primaryDark
                              : AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : _error != null
                    ? AdminErrorState(
                        message: _error!, onRetry: _loadUsers)
                    : _filtered.isEmpty
                        ? AdminEmptyState(
                            icon: Icons.person_search_rounded,
                            title: 'No users found',
                            subtitle: 'Try a different search or filter.',
                          )
                        : RefreshIndicator(
                            onRefresh: _loadUsers,
                            color: AppTheme.primary,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 8, 20, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (context, i) =>
                                  _userCard(_filtered[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800, fontSize: 17, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _userCard(dynamic u) {
    final active = u['is_active'] ?? true;
    final role = u['role'] ?? 'farmer';
    final roleColor = switch (role) {
      'farmer' => AppTheme.primary,
      'dealer' => AppTheme.info,
      'admin' => AppTheme.accent,
      _ => AppTheme.textMuted,
    };
    final roleLabel = switch (role) {
      'farmer' => 'Farmer',
      'dealer' => 'Dealer',
      'admin' => 'Admin',
      _ => role,
    };
    final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    final verified = u['is_verified'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AdminTheme.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminUserAvatar(
            photoUrl: u['profile_photo'],
            name: name.isEmpty ? u['username'] : name,
            radius: 26,
            tint: roleColor,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? '@${u['username']}' : name,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AdminPill(label: roleLabel, color: roleColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text('@${u['username']}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11.5)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.email_outlined,
                        size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        u['email'] ?? '',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if ((u['phone_number'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 12, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(u['phone_number'],
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AdminPill(
                      label: active ? 'Active' : 'Suspended',
                      color: active ? AppTheme.success : AppTheme.error,
                      icon: active
                          ? Icons.check_circle_rounded
                          : Icons.pause_circle_rounded,
                    ),
                    if (role == 'dealer')
                      AdminPill(
                        label: verified ? 'Verified' : 'Pending',
                        color:
                            verified ? AppTheme.info : AppTheme.warning,
                        icon: verified
                            ? Icons.verified_rounded
                            : Icons.hourglass_top_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              _iconAction(
                icon: active
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: active ? AppTheme.warning : AppTheme.success,
                tooltip: active ? 'Suspend' : 'Activate',
                onTap: () => _toggleUserActive(u),
              ),
              const SizedBox(height: 6),
              _iconAction(
                icon: Icons.delete_rounded,
                color: AppTheme.error,
                tooltip: 'Delete account',
                onTap: () => _deleteUser(u),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }

  Future<void> _toggleUserActive(dynamic u) async {
    final active = u['is_active'] ?? true;
    if (active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Suspend account?'),
          content: Text(
              '${u['first_name'] ?? ''} ${u['last_name'] ?? ''} will no longer be able to sign in.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.warning),
              child: const Text('Suspend'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      final api = ApiService();
      if (active) {
        await api.suspendUser(u['id']);
      } else {
        await api.activateUser(u['id']);
      }
      _loadUsers();
      _toast(active ? 'User suspended' : 'User activated',
          active ? AppTheme.warning : AppTheme.success);
    } catch (e) {
      _toast('Failed to update user: $e', AppTheme.error);
    }
  }

  Future<void> _deleteUser(dynamic u) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
            '${u['first_name'] ?? ''} ${u['last_name'] ?? ''} (@${u['username']}) '
            'will be permanently removed from the platform. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
      _loadUsers();
      _toast('User deleted', AppTheme.success);
    } catch (e) {
      _toast('Failed to delete user: $e', AppTheme.error);
    }
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ─────────────────────────── Orders tab ──────────────────────────────

class _AdminOrders extends StatefulWidget {
  const _AdminOrders();

  @override
  State<_AdminOrders> createState() => _AdminOrdersState();
}

class _AdminOrdersState extends State<_AdminOrders> {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all';
  String _query = '';

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
      final orders = await ApiService().getOrders();
      if (mounted) {
        setState(() {
          _orders = orders;
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

  List<dynamic> get _filtered {
    var list = _orders;
    if (_statusFilter != 'all') {
      list = list.where((o) => o['status'] == _statusFilter).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((o) {
        final haystack = [
          '${o['id']}',
          o['farmer_name'],
          o['product_name'],
          o['dealer_name'],
        ].join(' ').toLowerCase();
        return haystack.contains(q);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final total = _orders.length;
    final pending = _orders.where((o) => o['status'] == 'pending').length;
    final inTransit =
        _orders.where((o) => o['status'] == 'shipped').length;
    final completed =
        _orders.where((o) => o['status'] == 'delivered').length;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Order Management',
            subtitle: '$total order(s) across the platform',
            leading: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 22),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: AdminSearchField(
              hint: 'Search by order id, farmer, product...',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _countChip('$total', 'Total', AppTheme.primary),
                const SizedBox(width: 10),
                _countChip('$pending', 'Pending', AppTheme.warning),
                const SizedBox(width: 10),
                _countChip('$inTransit', 'In Transit', AppTheme.info),
                const SizedBox(width: 10),
                _countChip('$completed', 'Completed', AppTheme.success),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  'All', 'Pending', 'Confirmed', 'Shipped', 'Delivered',
                  'Cancelled'
                ].map((t) {
                  final f = t.toLowerCase();
                  final selected = _statusFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _statusFilter = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary
                              : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? AppTheme.primary
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
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
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : _error != null
                    ? AdminErrorState(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? AdminEmptyState(
                            icon: Icons.receipt_long_rounded,
                            title: 'No orders found',
                            subtitle:
                                'Orders matching your filters will appear here.',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppTheme.primary,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) =>
                                  _orderCard(_filtered[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800, fontSize: 17, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'pending' => AppTheme.warning,
      'confirmed' => AppTheme.info,
      'shipped' => AppTheme.info,
      'delivered' => AppTheme.success,
      'cancelled' => AppTheme.error,
      _ => AppTheme.textMuted,
    };
  }

  Widget _orderCard(dynamic order) {
    final status = order['status'] ?? 'pending';
    final statusColor = _statusColor(status);
    final amount = '${order['total_price'] ?? 0} FCFA';
    final farmer = order['farmer_name'] ?? 'Farmer';
    final product = order['product_name'] ?? 'Product';
    final details =
        '${order['quantity']}× $product · ${order['payment_status'] ?? 'unpaid'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AdminTheme.cardDecoration,
      child: Row(
        children: [
          AdminProductThumb(
            imageUrl: order['product_image'],
            size: 56,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order #${order['id']}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    AdminPill(label: status, color: statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text(farmer,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12.5)),
                const SizedBox(height: 3),
                Text(details,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _dateLabel(order['created_at']),
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _dateLabel(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) return '';
    return DateFormat('d MMM yyyy').format(date);
  }
}

// ─────────────────────────── Settings tab ────────────────────────────

class _AdminSettings extends StatelessWidget {
  const _AdminSettings();

  Future<void> _editProfile(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;

    final firstName = TextEditingController(text: user.firstName);
    final lastName = TextEditingController(text: user.lastName);
    final phone = TextEditingController(text: user.phoneNumber);
    File? profilePhoto;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final picked =
                        await picker.pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      setStateDialog(() => profilePhoto = File(picked.path));
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.1),
                        backgroundImage: profilePhoto != null
                            ? FileImage(profilePhoto!) as ImageProvider
                            : (user.profilePhoto != null &&
                                    user.profilePhoto!.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    ApiService.resolveMedia(
                                        user.profilePhoto))
                                : null),
                        child: (profilePhoto == null &&
                                (user.profilePhoto == null ||
                                    user.profilePhoto!.isEmpty))
                            ? const Icon(Icons.person,
                                size: 42, color: AppTheme.primary)
                            : null,
                      ),
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.3),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Tap to change profile photo',
                    style: AdminTheme.smallMuted()),
                const SizedBox(height: 16),
                TextField(
                  controller: firstName,
                  decoration: const InputDecoration(
                    labelText: 'First name',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(
                    labelText: 'Last name',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12))),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await auth.updateProfile(
          firstName: firstName.text.trim(),
          lastName: lastName.text.trim(),
          phoneNumber: phone.text.trim(),
          profilePhoto: profilePhoto,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile updated successfully'),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Update failed: $e'),
                backgroundColor: AppTheme.error,
                behavior: SnackBarBehavior.floating),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Settings',
            subtitle: 'Profile, platform configuration and security',
            leading:
                const Icon(Icons.settings_rounded, color: Colors.white, size: 22),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile card
                  AdminCard(
                    child: Row(
                      children: [
                        AdminUserAvatar(
                          photoUrl: user?.profilePhoto,
                          name: user?.fullName,
                          radius: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.fullName ?? 'Administrator',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? '',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              AdminPill(
                                label: 'Administrator',
                                color: AppTheme.primary,
                                icon: Icons.admin_panel_settings_rounded,
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _editProfile(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primaryDark),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Edit',
                              style: TextStyle(
                                  color: AppTheme.primaryDark,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Platform Settings', style: AdminTheme.sectionTitle()),
                  const SizedBox(height: 12),
                  _settingTile(
                    context,
                    Icons.settings_rounded,
                    'General',
                    'Language, region and app details',
                    onTap: null,
                  ),
                  _settingTile(
                    context,
                    Icons.admin_panel_settings_rounded,
                    'Roles & Permissions',
                    'Manage administrator access',
                  ),
                  _settingTile(
                    context,
                    Icons.payment_rounded,
                    'Payment Configuration',
                    'MTN MoMo and Orange Money',
                  ),
                  _settingTile(
                    context,
                    Icons.cloud_rounded,
                    'Weather API',
                    'Connected',
                  ),
                  _settingTile(
                    context,
                    Icons.smart_toy_rounded,
                    'AI Model Settings',
                    'OpenRouter · reviewed diseases only',
                  ),
                  const SizedBox(height: 20),
                  Text('Operations', style: AdminTheme.sectionTitle()),
                  const SizedBox(height: 12),
                  _navTile(
                    context,
                    Icons.monitor_heart_rounded,
                    'System Health',
                    'Monitor API, database, AI engine',
                    const SystemHealthScreen(),
                  ),
                  _navTile(
                    context,
                    Icons.article_rounded,
                    'Content Management',
                    'Manage the disease knowledge base',
                    const ContentManagementScreen(),
                  ),
                  _navTile(
                    context,
                    Icons.verified_user_rounded,
                    'Dealer Verification',
                    'Review pending dealer applications',
                    const DealerVerificationScreen(),
                  ),
                  _navTile(
                    context,
                    Icons.campaign_rounded,
                    'Broadcast Center',
                    'Compose and manage announcements',
                    const NotificationsScreen(),
                  ),
                  _navTile(
                    context,
                    Icons.receipt_long_rounded,
                    'Audit Log',
                    'Immutable record of admin actions',
                    const AuditLogScreen(),
                  ),
                  _navTile(
                    context,
                    Icons.warning_amber_rounded,
                    'Outbreak Alerts',
                    'Growing disease clusters detected',
                    const OutbreaksScreen(),
                  ),
                  const SizedBox(height: 20),
                  Text('Security', style: AdminTheme.sectionTitle()),
                  const SizedBox(height: 12),
                  _toggleTile(Icons.lock_rounded, 'Two-Factor Authentication',
                      true),
                  _settingTile(context, Icons.history_rounded, 'Login Activity',
                      ''),
                  _settingTile(context, Icons.folder_rounded, 'Data & Privacy',
                      ''),
                  const SizedBox(height: 20),
                  Text('Communication', style: AdminTheme.sectionTitle()),
                  const SizedBox(height: 12),
                  _toggleTile(Icons.notifications_rounded,
                      'Push Notifications', true),
                  _toggleTile(Icons.email_rounded, 'Email Reports', false),
                  const SizedBox(height: 24),
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
                      icon: const Icon(Icons.logout_rounded,
                          color: AppTheme.error, size: 18),
                      label: Text('Sign Out',
                          style: TextStyle(
                              color: AppTheme.error,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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

  Widget _settingTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: AppTheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _navTile(BuildContext context, IconData icon, String title,
      String subtitle, Widget page) {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page)),
      child: _settingTile(context, icon, title, subtitle),
    );
  }

  Widget _toggleTile(IconData icon, String title, bool value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AdminCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: AppTheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary)),
            ),
            Switch(
              value: value,
              onChanged: (_) {},
              activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
              thumbColor: WidgetStateProperty.all(AppTheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
