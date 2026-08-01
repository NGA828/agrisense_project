import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/diagnosis_provider.dart';
import '../../services/api/api_service.dart';
import 'farmer_home_screen.dart';
import '../ai_scan/camera_screen.dart';
import '../weather/weather_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../diagnosis/diagnosis_history_screen.dart';
import '../chat/chat_list_screen.dart';
import 'order_history_screen.dart';

class FarmerDashboard extends StatefulWidget {
  const FarmerDashboard({super.key});

  @override
  State<FarmerDashboard> createState() => _FarmerDashboardState();
}

class _FarmerDashboardState extends State<FarmerDashboard>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late final AnimationController _navController;
  late final List<Animation<double>> _navAnimations;

  final List<Widget> _screens = [
    const FarmerHomeScreen(),
    const CameraScreen(),
    const WeatherScreen(),
    const MarketplaceScreen(),
    const _ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _navController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _navAnimations = List.generate(5, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _navController,
          curve: Curves.easeOutBack,
        ),
      );
    });
    _navController.forward();
  }

  @override
  void dispose() {
    _navController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    _navController.reset();
    setState(() => _selectedIndex = index);
    _navController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.06),
              blurRadius: 0,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ColorFilter.mode(
              Colors.white.withOpacity(0.9),
              BlendMode.srcOver,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.home_rounded, Icons.home, 'Home'),
                    _buildNavItem(
                        1, Icons.camera_alt_rounded, Icons.camera_alt, 'Scan'),
                    _buildNavItem(2, Icons.wb_cloudy_rounded, Icons.wb_cloudy,
                        'Weather'),
                    _buildNavItem(3, Icons.shopping_bag_rounded,
                        Icons.shopping_bag_outlined, 'Market'),
                    _buildNavItem(
                        4, Icons.person_rounded, Icons.person_outline, 'Profile'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isSelected = index == _selectedIndex;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 8,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(
                isSelected ? activeIcon : inactiveIcon,
                key: ValueKey(isSelected),
                size: isSelected ? 24 : 22,
                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              style: GoogleFonts.poppins(
                fontSize: isSelected ? 11 : 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                letterSpacing: isSelected ? 0.2 : 0,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PROFILE SCREEN
// ─────────────────────────────────────────────

/// Live counters for the farmer profile (scans, orders, chats).
class _ProfileStats extends StatefulWidget {
  const _ProfileStats();

  @override
  State<_ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<_ProfileStats> {
  int _scans = 0;
  int _orders = 0;
  int _chats = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final diagnosisProvider = context.read<DiagnosisProvider>();
    _scans = diagnosisProvider.history.length;
    if (_scans == 0) {
      await diagnosisProvider.loadHistory();
      _scans = diagnosisProvider.history.length;
    }
    try {
      final api = ApiService();
      final orders = await api.getOrders();
      final chats = await api.getChatRooms();
      if (mounted) {
        setState(() {
          _orders = orders is List ? orders.length : 0;
          _chats = chats is List ? chats.length : 0;
        });
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildItem(context, '$_scans', 'Scans', Icons.search),
        _buildDivider(),
        _buildItem(context, '$_orders', 'Orders', Icons.shopping_bag_outlined),
        _buildDivider(),
        _buildItem(context, '$_chats', 'Chats', Icons.chat_bubble_outline),
      ],
    );
  }

  Widget _buildItem(BuildContext context, String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          Text(label,
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildDivider() => Container(width: 1, height: 34, color: Colors.grey.shade200);
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  void _showSettingsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('App Settings'),
        content: const Text(
          '• Notifications are delivered in-app — check the bell icon.\n'
          '• Weather uses your device location with a fallback to Yaoundé.\n'
          '• Your session stays active until you log out.\n\n'
          'More preferences will be added in future releases.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSupportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Help & Support'),
        content: const Text(
          'Need help? Here is what you can do:\n\n'
          '• Chat with a verified dealer directly from a product page.\n'
          '• Review your treatment plans under Diagnosis History.\n'
          '• For account issues, contact support at support@agrisense.cm '
          'or call +237 6XX XX XX XX.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About AgriSense AI'),
        content: const Text(
          'AgriSense AI v1.0.0\n\n'
          'Your plant doctor, weather forecaster and farm-supply marketplace '
          'in one app. Built to remove agricultural guesswork for farmers '
          'in Cameroon and beyond.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

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
                    final picked = await picker.pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      setStateDialog(() => profilePhoto = File(picked.path));
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppTheme.primary.withOpacity(0.1),
                        backgroundImage: profilePhoto != null
                            ? FileImage(profilePhoto!) as ImageProvider
                            : (user.profilePhoto != null && user.profilePhoto!.isNotEmpty
                                ? CachedNetworkImageProvider(ApiService.resolveMedia(user.profilePhoto))
                                : null),
                        child: (profilePhoto == null && (user.profilePhoto == null || user.profilePhoto!.isEmpty))
                            ? const Icon(Icons.person, size: 40, color: AppTheme.primary)
                            : null,
                      ),
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.3)),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 24),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: firstName,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: lastName,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
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
            const SnackBar(content: Text('Profile updated successfully'), backgroundColor: AppTheme.success),
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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              // ── Profile Header ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                      const Color(0xFF2E7D32),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    // Top row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Profile',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.edit_rounded,
                                color: Colors.white, size: 20),
                            onPressed: () => _showEditProfileDialog(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Avatar
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.2),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${(user?.firstName ?? 'F')[0].toUpperCase()}${(user?.lastName?.isNotEmpty == true ? user!.lastName[0].toUpperCase() : '')}',
                          style: GoogleFonts.poppins(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${user?.firstName ?? 'Farmer'} ${user?.lastName ?? ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.eco_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            'Verified Farmer',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Stats Row ──
              Transform.translate(
                offset: const Offset(0, -20),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(
                      vertical: 18, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const _ProfileStats(),
                ),
              ),

              const SizedBox(height: 4),

              // ── Menu Section ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildSectionTitle('Activity'),
                    const SizedBox(height: 8),
                    _buildMenuItem(
                      context,
                      icon: Icons.history_rounded,
                      iconColor: const Color(0xFF6C63FF),
                      iconBg: const Color(0xFFEEEDFF),
                      title: 'Diagnosis History',
                      subtitle: 'View your past crop scans',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DiagnosisHistoryScreen()),
                      ),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.receipt_long_rounded,
                      iconColor: const Color(0xFFFF9800),
                      iconBg: const Color(0xFFFFF3E0),
                      title: 'My Orders',
                      subtitle: 'Track purchases & deliveries',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const OrderHistoryScreen()),
                      ),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.chat_bubble_outline_rounded,
                      iconColor: const Color(0xFF00BFA5),
                      iconBg: const Color(0xFFE0F2F1),
                      title: 'Chat History',
                      subtitle: 'Dealer conversations',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChatListScreen()),
                      ),
                    ),

                    const SizedBox(height: 20),
                    _buildSectionTitle('Support'),
                    const SizedBox(height: 8),
                    _buildMenuItem(
                      context,
                      icon: Icons.settings_rounded,
                      iconColor: const Color(0xFF78909C),
                      iconBg: const Color(0xFFECEFF1),
                      title: 'Settings',
                      subtitle: 'App preferences & account',
                      onTap: () => _showSettingsDialog(context),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.help_outline_rounded,
                      iconColor: const Color(0xFF42A5F5),
                      iconBg: const Color(0xFFE3F2FD),
                      title: 'Help & Support',
                      subtitle: 'FAQs & contact us',
                      onTap: () => _showSupportDialog(context),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.info_outline_rounded,
                      iconColor: const Color(0xFFAB47BC),
                      iconBg: const Color(0xFFF3E5F5),
                      title: 'About AgriSense AI',
                      subtitle: 'Version 1.0.0',
                      onTap: () => _showAboutDialog(context),
                    ),

                    const SizedBox(height: 24),

                    // ── Logout Button ──
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.error.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              title: Text('Logout?',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600)),
                              content: Text(
                                  'Are you sure you want to logout of AgriSense AI?',
                                  style: GoogleFonts.poppins(fontSize: 14)),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: Text('Cancel',
                                      style: GoogleFonts.poppins(
                                          color: AppTheme.textMuted)),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.error,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: Text('Logout',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await context.read<AuthProvider>().logout();
                            if (context.mounted) {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/', (route) => false);
                            }
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
      ),
    );
  }

  // ── Helper: Section Title ──
  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Helper: Menu Item ──
  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
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
          splashColor: iconColor.withOpacity(0.06),
          highlightColor: iconColor.withOpacity(0.03),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon with colored background
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 22, color: iconColor),
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
                          color: const Color(0xFF1A1A2E),
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