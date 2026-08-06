import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/diagnosis_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../ai_scan/camera_screen.dart';
import '../chat/chat_list_screen.dart';
import '../diagnosis/diagnosis_history_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../notifications/notifications_screen.dart';
import '../weather/weather_screen.dart';
import 'farmer_home_screen.dart';
import 'farmer_widgets.dart';
import 'order_history_screen.dart';

/// AgriSense farmer app shell.
///
/// Information architecture (redesigned around the farmer's daily workflow):
///
///   Bottom tabs   Home · Scan · Market · Chat · Profile
///   Drawer        My Farm (Home / Scan / Weather / Market)
///                 Activity (Diagnosis History / Orders / Notifications /
///                            Messages)
///                 Account (Profile)
///
/// Weather moved from a dedicated tab into the drawer + Home weather card,
/// because chat (buying inputs) is a higher-frequency workflow.
class FarmerDashboard extends StatefulWidget {
  const FarmerDashboard({super.key});

  @override
  State<FarmerDashboard> createState() => _FarmerDashboardState();
}

class _FarmerDashboardState extends State<FarmerDashboard> {
  int _selectedIndex = 0;

  /// Key of the outer [Scaffold] that owns the [FarmerDrawer]. The home tab
  /// renders its own nested Scaffold, so the hamburger button must open the
  /// drawer through this key instead of `Scaffold.of(context)` (which would
  /// resolve to the nested, drawer-less Scaffold).
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget> _screens = [
    FarmerHomeScreen(
      onOpenProfile: () => _onItemTapped(4),
      onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
    ),
    const CameraScreen(),
    const MarketplaceScreen(),
    const ChatListScreen(),
    const _ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  void _openPage(int id) {
    final Widget page = switch (id) {
      100 => const WeatherScreen(),
      101 => const DiagnosisHistoryScreen(),
      102 => const OrderHistoryScreen(),
      103 => const NotificationsListScreen(),
      _ => const WeatherScreen(),
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
      key: _scaffoldKey,
      backgroundColor: FarmerTheme.canvas,
      resizeToAvoidBottomInset: false,
      drawer: FarmerDrawer(
        selectedTab: _selectedIndex,
        onTabSelected: _onItemTapped,
        onPageSelected: _openPage,
        onLogout: _logout,
        name: user?.fullName,
        email: user?.email,
        photo: user?.profilePhoto,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(
                      0, Icons.home_rounded, 'Home', Icons.home_outlined),
                  _buildNavItem(1, Icons.camera_alt_rounded, 'Scan',
                      Icons.camera_alt_outlined),
                  _buildNavItem(2, Icons.shopping_bag_rounded, 'Market',
                      Icons.shopping_bag_outlined),
                  _buildNavItem(
                      3, Icons.chat_rounded, 'Chat', Icons.chat_outlined),
                  _buildNavItem(
                      4, Icons.person_rounded, 'Profile', Icons.person_outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData activeIcon, String label, IconData inactiveIcon) {
    final isSelected = index == _selectedIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? activeIcon : inactiveIcon,
                  key: ValueKey('$index-$isSelected'),
                  size: isSelected ? 26 : 24,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.poppins(
                  fontSize: isSelected ? 11 : 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                ),
                child: Text(label),
              ),
              const SizedBox(height: 4),
              Opacity(
                opacity: isSelected ? 1 : 0,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<int> _loadHistoryCount(DiagnosisProvider diagnosisProvider) async {
    if (diagnosisProvider.history.isNotEmpty)
      return diagnosisProvider.history.length;
    try {
      await diagnosisProvider.loadHistory();
    } catch (_) {}
    return diagnosisProvider.history.length;
  }

  Future<int> _loadListCount(Future<dynamic> Function() loader) async {
    try {
      final value = await loader();
      return value is List ? value.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _load() async {
    if (_loaded) {
      return;
    }
    final diagnosisProvider = context.read<DiagnosisProvider>();
    final api = ApiService();

    final counts = await Future.wait([
      _loadHistoryCount(diagnosisProvider),
      _loadListCount(() => api.getOrders()),
      _loadListCount(() => api.getChatRooms()),
    ]);

    if (mounted) {
      setState(() {
        _scans = counts[0];
        _orders = counts[1];
        _chats = counts[2];
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildItem('$_scans', 'Scans', Icons.eco_rounded, AppTheme.primary),
        _buildDivider(),
        _buildItem(
            '$_orders', 'Orders', Icons.shopping_bag_rounded, FarmerTheme.sun),
        _buildDivider(),
        _buildItem('$_chats', 'Chats', Icons.chat_rounded, FarmerTheme.grape),
      ],
    );
  }

  Widget _buildItem(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 6),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      Container(width: 1, height: 40, color: Colors.grey.shade200);
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
    XFile? profilePhoto;
    Uint8List? profilePhotoBytes;

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
                      final bytes = await picked.readAsBytes();
                      setStateDialog(() {
                        profilePhoto = picked;
                        profilePhotoBytes = bytes;
                      });
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor:
                            AppTheme.primary.withValues(alpha: 0.1),
                        backgroundImage: profilePhotoBytes != null
                            ? MemoryImage(profilePhotoBytes!) as ImageProvider
                            : (user.profilePhoto != null &&
                                    user.profilePhoto!.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    ApiService.resolveMedia(user.profilePhoto))
                                : null),
                        child: (profilePhotoBytes == null &&
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
                    style: FarmerTheme.smallMuted()),
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

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              // ── Profile header ──
              Container(
                width: double.infinity,
                decoration: FarmerTheme.headerGradient,
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
                      child: FarmerAvatar(
                        photoUrl: user?.profilePhoto,
                        name: user?.fullName,
                        radius: 44,
                        tint: const Color(0xFF8BC34A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.fullName ?? 'Farmer',
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
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

              // ── Stats ──
              Transform.translate(
                offset: const Offset(0, -22),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding:
                      const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
                  decoration: FarmerTheme.cardDecoration,
                  child: const _ProfileStats(),
                ),
              ),

              const SizedBox(height: 4),

              // ── Menu ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text('Activity', style: FarmerTheme.sectionTitle()),
                    const SizedBox(height: 10),
                    _buildMenuItem(
                      context,
                      icon: Icons.history_rounded,
                      iconColor: AppTheme.primary,
                      iconBg: const Color(0xFFE8F5E9),
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
                      iconColor: FarmerTheme.sun,
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
                      iconColor: FarmerTheme.grape,
                      iconBg: const Color(0xFFF3E5F5),
                      title: 'Chat History',
                      subtitle: 'Dealer conversations',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChatListScreen()),
                      ),
                    ),
                    _buildMenuItem(
                      context,
                      icon: Icons.notifications_rounded,
                      iconColor: FarmerTheme.sky,
                      iconBg: const Color(0xFFE3F2FD),
                      title: 'Notifications',
                      subtitle: 'Orders, payments & broadcasts',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsListScreen()),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Support', style: FarmerTheme.sectionTitle()),
                    const SizedBox(height: 10),
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
                    SizedBox(
                      width: double.infinity,
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
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text('Cancel',
                                      style: GoogleFonts.poppins(
                                          color: AppTheme.textMuted)),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
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
                            final authProvider = context.read<AuthProvider>();
                            await authProvider.logout();
                            if (!context.mounted) return;
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
      ),
    );
  }

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
          splashColor: iconColor.withValues(alpha: 0.06),
          highlightColor: iconColor.withValues(alpha: 0.03),
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
