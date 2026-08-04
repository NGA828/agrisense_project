import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_list_screen.dart';
import '../chat/chat_screen.dart';
import '../notifications/notifications_screen.dart';
import 'add_product_screen.dart';
import 'dealer_widgets.dart';
import 'edit_product_screen.dart';
import 'premium_screen.dart';
import 'dealer_analytics_screen.dart';

/// AgriSense dealer console.
///
/// Information architecture (designed around the dealer's daily workflow):
///
///   Bottom tabs   Dashboard · Products · Orders · Chats · Profile
///   Drawer        My Store (Dashboard / Products / Orders / Premium)
///                 Customers (Chats / Notifications)
///                 Account (Profile / Help & Support)
///
/// The dashboard focuses on attention signals (pending orders, low stock) so
/// the dealer can act fast, while Products/Orders provide search + filters and
/// one-tap status actions.
class DealerDashboard extends StatefulWidget {
  const DealerDashboard({super.key});

  @override
  State<DealerDashboard> createState() => _DealerDashboardState();
}

class _DealerDashboardState extends State<DealerDashboard> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const _DealerHome(),
    const _DealerProducts(),
    const _DealerOrders(),
    const _DealerChatList(),
    const _DealerProfile(),
  ];

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  void _openPage(int id) {
    final Widget page = switch (id) {
      100 => const PremiumScreen(),
      101 => const NotificationsListScreen(),
      102 => const _HelpSupportScreen(),
      _ => const PremiumScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      backgroundColor: DealerTheme.canvas,
      drawer: DealerDrawer(
        selectedTab: _selectedIndex,
        onTabSelected: _onItemTapped,
        onPageSelected: _openPage,
        onLogout: _logout,
        storeName: user?.fullName,
        email: user?.email,
        photo: user?.profilePhoto,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.space_dashboard_rounded, 'Dashboard'),
                _buildNavItem(1, Icons.inventory_2_rounded, 'Products'),
                _buildNavItem(2, Icons.receipt_long_rounded, 'Orders'),
                _buildNavItem(3, Icons.chat_rounded, 'Chats'),
                _buildNavItem(4, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = index == _selectedIndex;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 22,
            color: isSelected ? AppTheme.primary : AppTheme.textMuted,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
              color: isSelected ? AppTheme.primary : AppTheme.textMuted,
            ),
          ),
          if (isSelected)
            Container(
              width: 20,
              height: 3,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Dashboard tab ───────────────────────────

class _DealerHome extends StatefulWidget {
  const _DealerHome();

  @override
  State<_DealerHome> createState() => _DealerHomeState();
}

class _DealerHomeState extends State<_DealerHome> {
  List<dynamic> _orders = [];
  int _productCount = 0;
  int _lowStockCount = 0;
  double _revenue = 0;
  bool _isLoading = true;
  String? _error;

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
      final orders = await api.getOrders();
      final products = await api.getMyProducts();
      if (mounted) {
        setState(() {
          _orders = orders is List ? orders : [];
          _productCount = products.length;
          _lowStockCount =
              products.where((p) => (p.stockQuantity ?? 0) <= 5).length;
          _revenue = _orders
              .where((o) => (o['payment_status'] ?? '') == 'paid')
              .fold<double>(
                  0, (sum, o) => sum + ((o['total_price'] ?? 0) as num).toDouble());
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

  int get _pendingCount =>
      _orders.where((o) => o['status'] == 'pending').length;

  String _formatFcfa(num? value) {
    final v = value ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final recentOrders = _orders.take(3).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _loadStats,
        color: AppTheme.primary,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(user),
            // Attention banner
            if (_pendingCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _attentionBanner(_pendingCount, _lowStockCount),
              ),
            const SizedBox(height: 20),
            // KPI grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: [
                  DealerStatCard(
                    value: '$_productCount',
                    label: 'Products',
                    icon: Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                    footnote: _lowStockCount > 0
                        ? '$_lowStockCount low stock'
                        : 'All in stock',
                  ),
                  DealerStatCard(
                    value: '${_orders.length}',
                    label: 'Orders',
                    icon: Icons.receipt_long_rounded,
                    color: DealerTheme.sky,
                    footnote: '$_pendingCount pending action',
                  ),
                  DealerStatCard(
                    value: '${_formatFcfa(_revenue)} FCFA',
                    label: 'Revenue',
                    icon: Icons.payments_rounded,
                    color: DealerTheme.teal,
                    footnote: 'Excludes cancelled',
                  ),
                  DealerStatCard(
                    value: '${_orders.where((o) => o['status'] == 'delivered').length}',
                    label: 'Delivered',
                    icon: Icons.check_circle_rounded,
                    color: AppTheme.success,
                    footnote: 'Completed orders',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Recent orders
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: DealerSectionTitle(
                title: 'Recent Orders',
                action: TextButton.icon(
                  onPressed: () => _switchToOrders(context),
                  icon: const Icon(Icons.arrow_forward_rounded,
                      size: 15, color: AppTheme.primary),
                  label: const Text('View All',
                      style:
                          TextStyle(color: AppTheme.primary, fontSize: 13)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: recentOrders.isEmpty
                  ? DealerCard(
                      child: Text(
                        'No orders yet — new orders will appear here in real time.',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12.5),
                      ),
                    )
                  : Column(
                      children: recentOrders
                          .map((order) => _orderRow(order))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 24),
            // Quick actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Quick Actions', style: DealerTheme.sectionTitle()),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _actionCard(
                    icon: Icons.add_circle_rounded,
                    label: 'Add Product',
                    color: AppTheme.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddProductScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _actionCard(
                    icon: Icons.chat_rounded,
                    label: 'Messages',
                    color: DealerTheme.grape,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatListScreen()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _actionCard(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    color: DealerTheme.sun,
                    onTap: _loadStats,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Premium banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _premiumBanner(context),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  void _switchToOrders(BuildContext context) {
    final state = context.findAncestorStateOfType<_DealerDashboardState>();
    if (state != null) state._onItemTapped(2);
  }

  Widget _buildHeader(dynamic user) {
    return Container(
      width: double.infinity,
      decoration: DealerTheme.headerGradient,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AgriSense AI',
                      style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                    Text(
                      'Dealer Console',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: NotificationBell(color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              DealerAvatar(
                photoUrl: user?.profilePhoto,
                name: user?.fullName,
                radius: 20,
                tint: const Color(0xFFFFB74D),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Welcome back,',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '${user?.firstName ?? 'Dealer'}\'s Store',
            style: GoogleFonts.poppins(
                fontSize: 23, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, MMMM d').format(DateTime.now()),
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _attentionBanner(int pending, int lowStock) {
    final items = <String>[];
    if (pending > 0) items.add('$pending order(s) awaiting action');
    if (lowStock > 0) items.add('$lowStock product(s) low on stock');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: DealerTheme.sun.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: DealerTheme.sun.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notification_important_rounded,
                color: DealerTheme.sun, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              items.join(' · '),
              style: GoogleFonts.poppins(
                color: const Color(0xFFE65100),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _switchToOrders(context),
            child: const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFE65100), size: 22),
          ),
        ],
      ),
    );
  }

  Widget _orderRow(dynamic order) {
    final statusColor = {
      'pending': AppTheme.warning,
      'confirmed': AppTheme.info,
      'shipped': AppTheme.primary,
      'delivered': AppTheme.success,
      'cancelled': AppTheme.error,
    }[order['status']] ??
        AppTheme.textMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: DealerTheme.cardDecoration,
      child: Row(
        children: [
          DealerProductThumb(
            imageUrl: order['product_image'],
            size: 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order['quantity']}x ${order['product_name'] ?? 'Product'}',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  order['farmer_name'] ?? 'Farmer',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${order['total_price'] ?? 0} FCFA',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppTheme.primary),
              ),
              const SizedBox(height: 4),
              DealerPill(
                  label: order['status'] ?? 'pending', color: statusColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          decoration: DealerTheme.cardDecoration,
          child: Column(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PremiumScreen()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFA726), Color(0xFFFF6F00)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: DealerTheme.sun.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12),
                ],
              ),
              child:
                  const Icon(Icons.star_rounded, color: DealerTheme.sun, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upgrade to Premium',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Featured listings, 3x visibility & analytics',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 11.5),
                  ),
                  const SizedBox(height: 7),
                  Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      '3x More Visibility',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 26),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Products tab ────────────────────────────

class _DealerProducts extends StatefulWidget {
  const _DealerProducts();

  @override
  State<_DealerProducts> createState() => _DealerProductsState();
}

class _DealerProductsState extends State<_DealerProducts> {
  List<dynamic> _products = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';
  String _categoryFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final response = await api.getMyProducts();
      if (mounted) {
        setState(() {
          _products = response is List ? response : [];
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
    var list = _products;
    if (_categoryFilter != 'all') {
      list = list
          .where((p) => (p.category ?? '').toLowerCase() == _categoryFilter)
          .toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list
          .where((p) =>
              (p.name ?? '').toLowerCase().contains(q) ||
              (p.category ?? '').toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  int get _activeCount =>
      _products.where((p) => p.isAvailable == true).length;
  int get _lowStockCount =>
      _products.where((p) => (p.stockQuantity ?? 0) <= 5).length;

  Future<void> _deleteProduct(dynamic product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('"${product.name}" will be permanently removed.'),
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
      await ApiService().deleteProduct(product.idProduct);
      if (mounted) {
        setState(() =>
            _products.removeWhere((p) => p.idProduct == product.idProduct));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Product deleted'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleAvailability(dynamic product, bool value) async {
    try {
      await ApiService().toggleProductAvailability(product.idProduct);
      // Reload from the server: Product.isAvailable is final and the server
      // is the source of truth for availability.
      await _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Product is now available' : 'Product hidden'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DealerHeader(
            title: 'My Products',
            subtitle: '${_products.length} listing(s) · $_activeCount active · '
                '$_lowStockCount low stock',
            leading: const Icon(Icons.inventory_2_rounded,
                color: Colors.white, size: 22),
            trailing: [
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddProductScreen()),
                ),
                icon: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 26),
                tooltip: 'Add product',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      color: AppTheme.textMuted, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search products...',
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: TextStyle(fontSize: 13),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Category chips
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  'all', 'seed', 'fertilizer', 'pesticide', 'fungicide',
                  'herbicide', 'equipment'
                ].map((cat) {
                  final label = cat == 'all'
                      ? 'All'
                      : cat[0].toUpperCase() + cat.substring(1);
                  final selected = _categoryFilter == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _categoryFilter = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primary : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color:
                                selected ? AppTheme.primary : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          label,
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
                    ? DealerErrorState(message: _error!, onRetry: _loadProducts)
                    : _filtered.isEmpty
                        ? DealerEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: _products.isEmpty
                                ? 'No products yet'
                                : 'No products match',
                            subtitle: _products.isEmpty
                                ? 'Add your first product to start selling'
                                : 'Try a different search or category.',
                            action: _products.isEmpty
                                ? ElevatedButton.icon(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const AddProductScreen()),
                                    ),
                                    icon: const Icon(Icons.add_rounded,
                                        size: 18),
                                    label: const Text('Add product'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  )
                                : null,
                          )
                        : RefreshIndicator(
                            onRefresh: _loadProducts,
                            color: AppTheme.primary,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) =>
                                  _buildProductItem(_filtered[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(dynamic product) {
    final lowStock = (product.stockQuantity ?? 0) <= 5;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: DealerTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DealerProductThumb(
                imageUrl: product.image,
                size: 62,
                fallbackIcon: _categoryIcon(product.category),
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
                            product.name,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DealerPill(
                          label: product.category,
                          color: AppTheme.primary,
                          icon: Icons.eco_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.attach_money_rounded,
                          size: 13, color: AppTheme.primary),
                      Text(
                        '${product.price.toInt()} FCFA',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.inventory_2_rounded,
                          size: 13,
                          color: lowStock
                              ? AppTheme.warning
                              : AppTheme.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        '${product.stockQuantity} units',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: lowStock
                              ? AppTheme.warning
                              : AppTheme.textMuted,
                          fontWeight:
                              lowStock ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      if (lowStock) ...[
                        const SizedBox(width: 6),
                        const DealerPill(
                            label: 'Low stock',
                            color: AppTheme.warning,
                            icon: Icons.warning_amber_rounded),
                      ],
                    ]),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditProductScreen(
                              product: product.toMap()),
                        ),
                      );
                      if (result == true) _loadProducts();
                    },
                    icon: Icon(Icons.edit_rounded,
                        color: AppTheme.primary, size: 19),
                  ),
                  IconButton(
                    onPressed: () => _deleteProduct(product),
                    icon: Icon(Icons.delete_rounded,
                        color: AppTheme.error, size: 19),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DealerPill(
                label: product.isAvailable ? 'Active' : 'Hidden',
                color:
                    product.isAvailable ? AppTheme.success : AppTheme.textMuted,
                icon: product.isAvailable
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Available',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  Switch(
                    value: product.isAvailable,
                    onChanged: (v) => _toggleAvailability(product, v),
                    activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
                    thumbColor: WidgetStateProperty.all(AppTheme.primary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'seed':
        return Icons.eco_rounded;
      case 'fertilizer':
        return Icons.science_rounded;
      case 'pesticide':
        return Icons.bug_report_rounded;
      case 'fungicide':
        return Icons.healing_rounded;
      case 'equipment':
        return Icons.build_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }
}

// ─────────────────────────── Orders tab ──────────────────────────────

class _DealerOrders extends StatefulWidget {
  const _DealerOrders();

  @override
  State<_DealerOrders> createState() => _DealerOrdersState();
}

class _DealerOrdersState extends State<_DealerOrders> {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final response = await api.getOrders();
      if (mounted) {
        setState(() {
          _orders = response is List ? response : [];
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

  List<dynamic> get _filtered => _statusFilter == 'all'
      ? _orders
      : _orders.where((o) => o['status'] == _statusFilter).toList();

  Future<void> _updateStatus(dynamic order, String status) async {
    try {
      await ApiService().updateOrderStatus(order['id'], status);
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order #${order['id']} updated to $status'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update order: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        _orders.where((o) => o['status'] == 'pending').length;
    final shippedCount =
        _orders.where((o) => o['status'] == 'shipped').length;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DealerHeader(
            title: 'Orders',
            subtitle: pendingCount > 0
                ? '$pendingCount order(s) awaiting action'
                : '${_orders.length} order(s) total',
            leading: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 22),
            trailing: [
              IconButton(
                onPressed: _loadOrders,
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 22),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                _countChip('${_orders.length}', 'Total', AppTheme.primary),
                const SizedBox(width: 10),
                _countChip('$pendingCount', 'Pending', AppTheme.warning),
                const SizedBox(width: 10),
                _countChip('$shippedCount', 'Shipped', AppTheme.info),
                const SizedBox(width: 10),
                _countChip(
                    '${_orders.where((o) => o['status'] == 'delivered').length}',
                    'Delivered',
                    AppTheme.success),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
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
                          color: selected ? AppTheme.primary : Colors.white,
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
                    ? DealerErrorState(message: _error!, onRetry: _loadOrders)
                    : _filtered.isEmpty
                        ? DealerEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: _orders.isEmpty
                                ? 'No orders yet'
                                : 'No orders in this status',
                            subtitle: _orders.isEmpty
                                ? 'Orders from farmers will appear here'
                                : 'Try a different status filter.',
                          )
                        : RefreshIndicator(
                            onRefresh: _loadOrders,
                            color: AppTheme.primary,
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) =>
                                  _buildOrderCard(_filtered[index]),
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
                    fontWeight: FontWeight.w800, fontSize: 16, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final status = order['status'] ?? 'pending';
    final statusColor = {
      'pending': AppTheme.warning,
      'confirmed': AppTheme.info,
      'shipped': AppTheme.primary,
      'delivered': AppTheme.success,
      'cancelled': AppTheme.error,
    }[status] ??
        AppTheme.textMuted;
    final paid = (order['payment_status'] == 'paid' ||
        order['payment_status'] == 'completed');
    final farmerName = order['farmer_name'] ?? 'Farmer';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: DealerTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DealerAvatar(
                name: farmerName,
                radius: 20,
                tint: AppTheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(farmerName,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Order #${order['id']}',
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              DealerPill(
                label: status,
                color: statusColor,
                icon: switch (status) {
                  'pending' => Icons.hourglass_empty_rounded,
                  'confirmed' => Icons.check_circle_outline_rounded,
                  'shipped' => Icons.local_shipping_rounded,
                  'delivered' => Icons.check_circle_rounded,
                  'cancelled' => Icons.cancel_rounded,
                  _ => Icons.receipt_rounded,
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              DealerProductThumb(
                imageUrl: order['product_image'],
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${order['quantity']}x ${order['product_name'] ?? 'Product'}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${order['total_price'] ?? 0} FCFA',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.primary)),
                  const SizedBox(height: 3),
                  DealerPill(
                    label: paid ? 'Paid' : 'Unpaid',
                    color: paid ? AppTheme.success : AppTheme.textMuted,
                    icon: paid
                        ? Icons.check_circle_rounded
                        : Icons.pending_rounded,
                  ),
                ],
              ),
            ],
          ),
          if (status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _updateStatus(order, 'cancelled'),
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: AppTheme.error),
                    label: const Text('Decline',
                        style: TextStyle(color: AppTheme.error, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppTheme.error.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateStatus(order, 'confirmed'),
                    icon: const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white),
                    label: const Text('Accept',
                        style:
                            TextStyle(color: Colors.white, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (status == 'confirmed' || status == 'shipped') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _updateStatus(
                    order, status == 'confirmed' ? 'shipped' : 'delivered'),
                icon: Icon(
                    status == 'confirmed'
                        ? Icons.local_shipping_rounded
                        : Icons.check_circle_rounded,
                    size: 16,
                    color: AppTheme.primary),
                label: Text(
                  status == 'confirmed'
                      ? 'Mark as Shipped'
                      : 'Mark as Delivered',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Chats tab ───────────────────────────────

class _DealerChatList extends StatefulWidget {
  const _DealerChatList();

  @override
  State<_DealerChatList> createState() => _DealerChatListState();
}

class _DealerChatListState extends State<_DealerChatList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversations = chatProvider.conversations;
    final unreadTotal =
        conversations.fold<int>(0, (sum, c) => sum + (c.unread));

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DealerHeader(
            title: 'Chats',
            subtitle: unreadTotal > 0
                ? '$unreadTotal unread conversation(s)'
                : 'Talk to farmers buying your products',
            leading:
                const Icon(Icons.chat_rounded, color: Colors.white, size: 22),
            trailing: [
              IconButton(
                onPressed: () => chatProvider.loadConversations(),
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 22),
              ),
            ],
          ),
          Expanded(
            child: chatProvider.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : conversations.isEmpty
                    ? DealerEmptyState(
                        icon: Icons.forum_rounded,
                        title: 'No conversations yet',
                        subtitle:
                            'Farmers who order your products can chat with you here.',
                      )
                    : RefreshIndicator(
                        onRefresh: () => chatProvider.loadConversations(),
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          itemCount: conversations.length,
                          itemBuilder: (context, index) => _buildChatItem(
                              conversations[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(dynamic chat) {
    final unread = chat.unread > 0;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
              conversationId: chat.id, conversationName: chat.name),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: DealerTheme.cardDecoration,
        child: Row(
          children: [
            Stack(
              children: [
                DealerAvatar(
                  name: chat.name,
                  radius: 24,
                  tint: DealerTheme.grape,
                ),
                if (chat.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.name,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (chat.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified,
                            color: AppTheme.info, size: 16),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chat.lastMessage.isEmpty
                        ? 'No messages yet'
                        : chat.lastMessage,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (unread)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                    color: AppTheme.primary, shape: BoxShape.circle),
                child: Text('${chat.unread}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Profile tab ─────────────────────────────

class _DealerProfile extends StatelessWidget {
  const _DealerProfile();

  Future<void> _showEditProfileDialog(BuildContext context) async {
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
                            ? const Icon(Icons.store_rounded,
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
                    style: DealerTheme.smallMuted()),
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
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Update failed: $e'),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final isPremium = user?.isPremiumActive == true;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // Profile header
            Container(
              width: double.infinity,
              decoration: DealerTheme.headerGradient,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'My Profile',
                        style: GoogleFonts.poppins(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showEditProfileDialog(context),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => _showEditProfileDialog(context),
                    child: DealerAvatar(
                      photoUrl: user?.profilePhoto,
                      name: user?.fullName,
                      radius: 42,
                      tint: const Color(0xFFFFB74D),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.fullName ?? 'Store Owner',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email ?? '',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.store_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              'Dealer',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isPremium
                              ? const Color(0xFFFFB300)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isPremium
                                    ? Icons.workspace_premium_rounded
                                    : Icons.star_outline_rounded,
                                size: 13,
                                color: isPremium
                                    ? Colors.black87
                                    : Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              isPremium ? 'Premium' : 'Standard',
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: isPremium
                                    ? Colors.black87
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Menu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Text('Store', style: DealerTheme.sectionTitle()),
                  const SizedBox(height: 10),
                  _menuItem(
                    context,
                    icon: Icons.edit_rounded,
                    color: AppTheme.primary,
                    title: 'Edit Profile',
                    subtitle: 'Name, phone & photo',
                    onTap: () => _showEditProfileDialog(context),
                  ),
                  _menuItem(
                    context,
                    icon: Icons.star_rounded,
                    color: DealerTheme.sun,
                    title: 'Premium Upgrade',
                    subtitle: isPremium
                        ? 'Manage your premium subscription'
                        : '3x visibility & analytics',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PremiumScreen()),
                    ),
                  ),
                  _menuItem(
                    context,
                    icon: Icons.inventory_2_rounded,
                    color: AppTheme.primary,
                    title: 'My Products',
                    subtitle: 'Manage listings & stock',
                    onTap: () {
                      final state = context
                          .findAncestorStateOfType<_DealerDashboardState>();
                      state?._onItemTapped(1);
                    },
                  ),
                  _menuItem(
                    context,
                    icon: Icons.receipt_long_rounded,
                    color: DealerTheme.sky,
                    title: 'Order History',
                    subtitle: 'Track sales & deliveries',
                    onTap: () {
                      final state = context
                          .findAncestorStateOfType<_DealerDashboardState>();
                      state?._onItemTapped(2);
                    },
                  ),
                  _menuItem(
                    context,
                    icon: Icons.analytics_rounded,
                    color: AppTheme.success,
                    title: 'Sales Analytics',
                    subtitle: 'Revenue, top products & trends',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DealerAnalyticsScreen()),
                    ),
                  ),
                  _menuItem(
                    context,
                    icon: Icons.chat_rounded,
                    color: DealerTheme.grape,
                    title: 'Customer Chats',
                    subtitle: 'Conversations with farmers',
                    onTap: () {
                      final state = context
                          .findAncestorStateOfType<_DealerDashboardState>();
                      state?._onItemTapped(3);
                    },
                  ),
                  _menuItem(
                    context,
                    icon: Icons.notifications_rounded,
                    color: AppTheme.info,
                    title: 'Notifications',
                    subtitle: 'Orders, payments & broadcasts',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationsListScreen()),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Support', style: DealerTheme.sectionTitle()),
                  const SizedBox(height: 10),
                  _menuItem(
                    context,
                    icon: Icons.help_outline_rounded,
                    color: const Color(0xFF42A5F5),
                    title: 'Help & Support',
                    subtitle: 'Contact the AgriSense team',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const _HelpSupportScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await context.read<AuthProvider>().logout();
                        if (context.mounted) {
                          Navigator.of(context)
                              .pushNamedAndRemoveUntil('/', (route) => false);
                        }
                      },
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: Text(
                        'Logout',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade400,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Help & Support ──────────────────────────

class _HelpSupportScreen extends StatelessWidget {
  const _HelpSupportScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DealerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DealerHeader(
              title: 'Help & Support',
              subtitle: 'We are here to help you sell more',
              showBack: true,
              leading: const Icon(Icons.help_outline_rounded,
                  color: Colors.white, size: 22),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  DealerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How can we help?',
                            style: DealerTheme.sectionTitle()),
                        const SizedBox(height: 12),
                        _faqTile(
                          icon: Icons.inventory_2_rounded,
                          title: 'Managing products',
                          body: 'Add products from the Products tab, toggle '
                              'availability with the switch, and watch your '
                              'stock levels — products marked "Low stock" are '
                              'worth restocking.',
                        ),
                        _faqTile(
                          icon: Icons.receipt_long_rounded,
                          title: 'Processing orders',
                          body: 'New orders appear in the Orders tab with a '
                              'pending badge. Accept to confirm, then mark as '
                              'shipped and delivered as you fulfil them.',
                        ),
                        _faqTile(
                          icon: Icons.star_rounded,
                          title: 'Premium benefits',
                          body: 'Premium dealers rank first in the '
                              'marketplace, get a verified badge and analytics. '
                              'Upgrade from the Home tab or Profile.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DealerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Contact us', style: DealerTheme.sectionTitle()),
                        const SizedBox(height: 12),
                        const _contactRow(
                            Icons.email_rounded,
                            'support@agrisense.cm'),
                        const SizedBox(height: 8),
                        const _contactRow(
                            Icons.phone_rounded, '+237 6XX XX XX XX'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faqTile({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _contactRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _contactRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12.5)),
      ],
    );
  }
}
