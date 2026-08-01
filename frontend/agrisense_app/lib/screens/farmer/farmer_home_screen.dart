import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/announcement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/diagnosis_provider.dart';
import '../../providers/weather_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../ai_scan/camera_screen.dart';
import '../chat/chat_list_screen.dart';
import '../diagnosis/diagnosis_history_screen.dart';
import '../diagnosis/diagnosis_result_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../notifications/notifications_screen.dart';
import '../weather/weather_screen.dart';
import '../irrigation/irrigation_screen.dart';
import 'farmer_widgets.dart';
import 'order_history_screen.dart';

/// Farmer home — the command center of the app.
/// Redesigned with premium UI/UX following reference screen patterns.
class FarmerHomeScreen extends StatefulWidget {
  /// Called when the header avatar is tapped (switches to the Profile tab).
  final VoidCallback? onOpenProfile;

  const FarmerHomeScreen({super.key, this.onOpenProfile});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeSlideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeSlideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WeatherProvider>().loadWeather();
      context.read<DiagnosisProvider>().loadHistory();
      context.read<AnnouncementProvider>().loadAnnouncements();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final weather = context.watch<WeatherProvider>().weather;
    final diagnosisProvider = context.watch<DiagnosisProvider>();
    final announcementProvider = context.watch<AnnouncementProvider>();

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: Colors.white,
          displacement: 40,
          onRefresh: () async {
            context.read<WeatherProvider>().loadWeather();
            context.read<DiagnosisProvider>().loadHistory();
            context.read<AnnouncementProvider>().loadAnnouncements();
          },
          child: AnimatedBuilder(
            animation: _fadeSlideAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeSlideAnimation.value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - _fadeSlideAnimation.value)),
                  child: child,
                ),
              );
            },
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _buildHeader(user),
                _buildGreeting(user),
                const SizedBox(height: 20),
                _buildWeatherMiniCard(weather),
                const SizedBox(height: 24),
                _buildFarmSnapshot(),
                const SizedBox(height: 24),
                _buildQuickScanHero(),
                const SizedBox(height: 28),
                _buildQuickAccessSection(),
                if (announcementProvider.announcements.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildAnnouncementBanner(
                      announcementProvider.announcements.first),
                ],
                if (diagnosisProvider.history.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildRecentDiagnosis(diagnosisProvider),
                ],
                const SizedBox(height: 24),
                _buildDailyTip(),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Premium Header ─────────────────────────────────────────────────────
  Widget _buildHeader(user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // Menu button
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primary, AppTheme.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Brand logo
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.eco_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AgriSense AI',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Smart Farming',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Notification bell
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: NotificationBell(color: AppTheme.primary, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          GestureDetector(
            onTap: widget.onOpenProfile,
            child: FarmerAvatar(
              photoUrl: user?.profilePhoto,
              name: user?.fullName,
              radius: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ── Time-aware Greeting ──────────────────────────────────────────────
  Widget _buildGreeting(user) {
    final hour = DateTime.now().hour;
    final String greeting;
    final String emoji;
    if (hour < 12) {
      greeting = 'Good morning';
      emoji = '🌅';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
      emoji = '☀️';
    } else {
      greeting = 'Good evening';
      emoji = '🌙';
    }
    final name = (user?.firstName?.isNotEmpty ?? false)
        ? user!.firstName
        : (user?.username ?? 'Farmer');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting,',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 12, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('EEEE, MMMM d').format(DateTime.now()),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(emoji, style: const TextStyle(fontSize: 36)),
        ],
      ),
    );
  }

  // ── Premium Weather Card ───────────────────────────────────────────────
  Widget _buildWeatherMiniCard(weather) {
    final isGood = weather?.condition?.toLowerCase().contains('sun') ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WeatherScreen()),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isGood
                  ? [const Color(0xFFE3F2FD), const Color(0xFFBBDEFB)]
                  : [const Color(0xFFE8EAF6), const Color(0xFFC5CAE9)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: (isGood ? Colors.blue : Colors.indigo).withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Weather icon with glow
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: (isGood ? Colors.orange : Colors.indigo).withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  isGood ? Icons.wb_sunny_rounded : Icons.cloud_rounded,
                  color: isGood ? const Color(0xFFFF9800) : const Color(0xFF5C6BC0),
                  size: 34,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          weather != null ? '${weather.temperature}°C' : '28°C',
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: isGood ? const Color(0xFF1565C0) : const Color(0xFF303F9F),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isGood ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isGood ? Icons.thumb_up_rounded : Icons.warning_rounded,
                                size: 12,
                                color: isGood ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isGood ? 'Good' : 'Fair',
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isGood ? Colors.green : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      weather != null ? weather.condition : 'Partly Cloudy',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: isGood ? const Color(0xFF42A5F5) : const Color(0xFF5C6BC0),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _weatherChip(Icons.water_drop_rounded,
                            weather != null ? '${weather.humidity}%' : '65%'),
                        const SizedBox(width: 8),
                        _weatherChip(Icons.air_rounded,
                            weather != null ? '${weather.windSpeed} km/h' : '12 km/h'),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF42A5F5), size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weatherChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF42A5F5)),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1565C0),
            ),
          ),
        ],
      ),
    );
  }

  // ── Farm snapshot: key metrics ──────────────────────────────────────
  Widget _buildFarmSnapshot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your farm at a glance', style: FarmerTheme.sectionTitle()),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _FarmSnapshot(),
        ],
      ),
    );
  }

  // ── Premium Quick Scan Hero ───────────────────────────────────────────
  Widget _buildQuickScanHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CameraScreen()),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D3B0F),
                Color(0xFF1B5E20),
                Color(0xFF2E7D32),
                Color(0xFF43A047),
              ],
              stops: [0.0, 0.3, 0.6, 1.0],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative elements
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              // Content
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // AI badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF76FF03),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'AI Powered Detection',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Scan Your Crop',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Detect diseases instantly and get\nAI-powered treatment plans',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // CTA Button
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_rounded,
                                  color: AppTheme.primary, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                'Start Scanning',
                                style: GoogleFonts.poppins(
                                  color: AppTheme.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: AppTheme.primary, size: 18),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Camera icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: Container(
                      width: 70,
                      height: 70,
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: AppTheme.primary,
                        size: 34,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick Access Grid ────────────────────────────────────────────────
  Widget _buildQuickAccessSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Access', style: FarmerTheme.sectionTitle()),
          const SizedBox(height: 14),
          // First row
          Row(
            children: [
              Expanded(
                child: _quickTile(
                  title: 'Weather',
                  subtitle: 'Forecast & advice',
                  icon: Icons.wb_cloudy_rounded,
                  color: const Color(0xFF0288D1),
                  bg: const Color(0xFFE3F2FD),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WeatherScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _quickTile(
                  title: 'Marketplace',
                  subtitle: 'Shop inputs',
                  icon: Icons.shopping_bag_rounded,
                  color: const Color(0xFFFF8F00),
                  bg: const Color(0xFFFFF3E0),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Second row
          Row(
            children: [
              Expanded(
                child: _quickTile(
                  title: 'Chat',
                  subtitle: 'Talk to dealers',
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF7B1FA2),
                  bg: const Color(0xFFF3E5F5),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatListScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _quickTile(
                  title: 'History',
                  subtitle: 'Past diagnoses',
                  icon: Icons.history_rounded,
                  color: AppTheme.primary,
                  bg: const Color(0xFFE8F5E9),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DiagnosisHistoryScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Third row — irrigation
          Row(
            children: [
              Expanded(
                child: _quickTile(
                  title: 'Irrigation',
                  subtitle: 'Field sensors & advice',
                  icon: Icons.water_drop_rounded,
                  color: const Color(0xFF00897B),
                  bg: const Color(0xFFE0F2F1),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const IrrigationScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                      color: color,
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

  // ── Announcement Banner ────────────────────────────────────────────────
  Widget _buildAnnouncementBanner(announcement) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB300).withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: Color(0xFFFF8F00),
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Announcement',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: const Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    announcement.title ?? 'New update available!',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: const Color(0xFF795548),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFFF8F00), size: 22),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recent Diagnoses ─────────────────────────────────────────────────
  Widget _buildRecentDiagnosis(DiagnosisProvider provider) {
    final history = provider.history;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FarmerSectionTitle(
            title: 'Recent Diagnoses',
            action: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DiagnosisHistoryScreen()),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View All',
                      style: GoogleFonts.poppins(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded,
                      color: AppTheme.primary, size: 16),
                ],
              ),
            ),
          ),
          ...history.take(2).map((d) => _diagnosisRow(d)),
        ],
      ),
    );
  }

  Widget _diagnosisRow(dynamic d) {
    final isHigh = d.severity.toLowerCase() == 'high';
    final color = isHigh ? AppTheme.error : AppTheme.warning;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DiagnosisResultScreen(diagnosis: d)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Crop photo thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 60,
                height: 60,
                color: AppTheme.primary.withValues(alpha: 0.08),
                child: d.imageUrl.isNotEmpty
                    ? Image.network(
                        d.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.eco_rounded,
                            color: AppTheme.primary,
                            size: 28),
                      )
                    : const Icon(Icons.eco_rounded,
                        color: AppTheme.primary, size: 28),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.diseaseName,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        d.cropType,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.textMuted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        _timeAgo(d.createdAt),
                        style: const TextStyle(
                            color: AppTheme.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${d.confidence.toInt()}%',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Daily Farming Tip ────────────────────────────────────────────────
  Widget _buildDailyTip() {
    final tips = [
      {
        'icon': Icons.lightbulb_rounded,
        'title': 'Farming Tip',
        'tip': 'Apply fungicide early morning for best absorption and reduced evaporation loss.',
        'bgColor': const Color(0xFFE8F5E9),
        'iconColor': AppTheme.primary,
        'accentColor': AppTheme.primary,
      },
      {
        'icon': Icons.water_drop_rounded,
        'title': 'Watering Tip',
        'tip': 'Water your crops at dawn or dusk to minimize water loss through evaporation.',
        'bgColor': const Color(0xFFE3F2FD),
        'iconColor': const Color(0xFF1565C0),
        'accentColor': const Color(0xFF1565C0),
      },
      {
        'icon': Icons.compost_rounded,
        'title': 'Soil Tip',
        'tip': 'Adding organic compost improves soil structure and boosts nutrient retention.',
        'bgColor': const Color(0xFFF3E5F5),
        'iconColor': const Color(0xFF7B1FA2),
        'accentColor': const Color(0xFF7B1FA2),
      },
    ];

    final tip = tips[DateTime.now().day % tips.length];
    final accent = tip['accentColor'] as Color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tip['bgColor'] as Color,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (tip['iconColor'] as Color).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                tip['icon'] as IconData,
                color: tip['iconColor'] as Color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tip['title'] as String,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Daily',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tip['tip'] as String,
                    style: GoogleFonts.poppins(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                      fontWeight: FontWeight.w400,
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

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}

/// Live metric tiles for the farm snapshot (scans / orders / chats).
class _FarmSnapshot extends StatefulWidget {
  const _FarmSnapshot();

  @override
  State<_FarmSnapshot> createState() => _FarmSnapshotState();
}

class _FarmSnapshotState extends State<_FarmSnapshot> {
  int _scans = 0;
  int _orders = 0;
  int _chats = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loaded) return;
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
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FarmerStatCard(
            value: '$_scans',
            label: 'Crop scans',
            icon: Icons.eco_rounded,
            color: AppTheme.primary,
            footnote: 'Diagnoses done',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FarmerStatCard(
            value: '$_orders',
            label: 'Orders',
            icon: Icons.shopping_bag_rounded,
            color: const Color(0xFFFF8F00),
            footnote: 'Purchases made',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: FarmerStatCard(
            value: '$_chats',
            label: 'Chats',
            icon: Icons.chat_rounded,
            color: const Color(0xFF7B1FA2),
            footnote: 'Dealer talks',
          ),
        ),
      ],
    );
  }
}
