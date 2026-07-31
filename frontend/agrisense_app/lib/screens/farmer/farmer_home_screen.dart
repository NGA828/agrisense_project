import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../providers/weather_provider.dart';
import '../../providers/diagnosis_provider.dart';
import '../../providers/announcement_provider.dart';
import '../../theme/app_theme.dart';
import '../ai_scan/camera_screen.dart';
import '../weather/weather_screen.dart';
import '../marketplace/marketplace_screen.dart';
import '../diagnosis/diagnosis_history_screen.dart';
import '../chat/chat_list_screen.dart';
import '../notifications/notifications_screen.dart';

class FarmerHomeScreen extends StatefulWidget {
  const FarmerHomeScreen({super.key});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen>
    with TickerProviderStateMixin {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WeatherProvider>().loadWeather();
      context.read<DiagnosisProvider>().loadHistory();
      context.read<AnnouncementProvider>().loadAnnouncements();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final weather = context.watch<WeatherProvider>().weather;
    final diagnosisProvider = context.watch<DiagnosisProvider>();
    final announcementProvider = context.watch<AnnouncementProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: Colors.white,
          displacement: 40,
          onRefresh: () async {
            context.read<WeatherProvider>().loadWeather();
            context.read<DiagnosisProvider>().loadHistory();
            context.read<AnnouncementProvider>().loadAnnouncements();
          },
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                _buildHeader(user),

                // ── Greeting ──
                _buildGreeting(user),

                // ── Weather Mini-Card ──
                _buildWeatherMiniCard(weather),

                const SizedBox(height: 20),

                // ── Quick Scan Hero ──
                _buildQuickScanHero(),

                const SizedBox(height: 24),

                // ── Quick Access Grid ──
                _buildQuickAccessSection(),

                const SizedBox(height: 24),

                // ── Announcement Banner ──
                if (announcementProvider.announcements.isNotEmpty)
                  _buildAnnouncementBanner(announcementProvider.announcements.first),

                const SizedBox(height: 24),

                // ── Recent Diagnosis ──
                if (diagnosisProvider.history.isNotEmpty)
                  _buildRecentDiagnosis(diagnosisProvider),

                const SizedBox(height: 24),

                // ── Farming Tip ──
                _buildFarmingTip(),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  GREETING (time-of-day aware)
  // ─────────────────────────────────────────────
  Widget _buildGreeting(user) {
    final hour = DateTime.now().hour;
    final String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    final name = (user?.firstName?.isNotEmpty ?? false) ? user!.firstName : (user?.username ?? 'Farmer');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting, $name 👋',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Here is what your farm needs today',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  HEADER
  // ─────────────────────────────────────────────
  Widget _buildHeader(user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // Logo
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary,
                  AppTheme.primary.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.eco_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AgriSense AI',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryDark,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Smart Farming Assistant',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Notification bell (live unread badge)
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: NotificationBell(color: AppTheme.primary, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          GestureDetector(
            onTap: () {
              // Navigate to profile tab
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryLight,
                    AppTheme.primary.withOpacity(0.3),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.2),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '${(user?.firstName ?? 'F')[0].toUpperCase()}',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    int badge = 0,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(icon, color: AppTheme.textPrimary, size: 22),
            ),
            if (badge > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '$badge',
                      style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  WEATHER MINI-CARD
  // ─────────────────────────────────────────────
  Widget _buildWeatherMiniCard(weather) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WeatherScreen()),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFE3F2FD),
                Color(0xFFBBDEFB),
                Color(0xFFE1F5FE),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF90CAF9).withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              // Weather icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.wb_sunny_rounded,
                  color: Color(0xFFFF9800),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weather != null ? '${weather.temperature}°C' : '28°C',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0),
                      ),
                    ),
                    Text(
                      weather != null ? weather.condition : 'Partly Cloudy',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFF42A5F5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Mini stats
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Icon(Icons.water_drop_rounded,
                          size: 14, color: const Color(0xFF42A5F5)),
                      const SizedBox(width: 4),
                      Text(
                        weather != null ? '${weather.humidity}%' : '65%',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.air_rounded,
                          size: 14, color: const Color(0xFF42A5F5)),
                      const SizedBox(width: 4),
                      Text(
                        weather != null ? '${weather.windSpeed} km/h' : '12 km/h',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1565C0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: const Color(0xFF42A5F5),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  QUICK SCAN HERO
  // ─────────────────────────────────────────────
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
                Color(0xFF1B5E20),
                Color(0xFF2E7D32),
                Color(0xFF43A047),
                Color(0xFF66BB6A),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2E7D32).withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: -10,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04),
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
                        // Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF76FF03),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'AI Powered',
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Scan Your Crop',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Detect diseases instantly and get\nAI-powered treatment plans',
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // CTA Button
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_rounded,
                                  color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Start Scanning',
                                style: GoogleFonts.poppins(
                                  color: AppTheme.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Camera icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Container(
                      width: 56,
                      height: 56,
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: AppTheme.primary,
                        size: 28,
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

  // ─────────────────────────────────────────────
  //  QUICK ACCESS SECTION
  // ─────────────────────────────────────────────
  Widget _buildQuickAccessSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quick Access',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                'See all features',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 165,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _buildQuickAccessCard(
                title: 'Disease\nDetection',
                subtitle: 'AI scan',
                icon: Icons.eco_rounded,
                gradientColors: [
                  const Color(0xFFE8F5E9),
                  const Color(0xFFC8E6C9),
                ],
                iconColor: AppTheme.primary,
                iconBgColor: AppTheme.primary.withOpacity(0.12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraScreen()),
                ),
              ),
              const SizedBox(width: 12),
              _buildQuickAccessCard(
                title: 'Weather\nForecast',
                subtitle: 'Localized',
                icon: Icons.wb_cloudy_rounded,
                gradientColors: [
                  const Color(0xFFE3F2FD),
                  const Color(0xFFBBDEFB),
                ],
                iconColor: const Color(0xFF1565C0),
                iconBgColor: const Color(0xFF1565C0).withOpacity(0.12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WeatherScreen()),
                ),
              ),
              const SizedBox(width: 12),
              _buildQuickAccessCard(
                title: 'Farm\nMarketplace',
                subtitle: 'Shop now',
                icon: Icons.shopping_bag_rounded,
                gradientColors: [
                  const Color(0xFFFFF3E0),
                  const Color(0xFFFFE0B2),
                ],
                iconColor: const Color(0xFFE65100),
                iconBgColor: const Color(0xFFE65100).withOpacity(0.12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
                ),
              ),
              const SizedBox(width: 12),
              _buildQuickAccessCard(
                title: 'Chat with\nDealers',
                subtitle: 'Connect',
                icon: Icons.chat_rounded,
                gradientColors: [
                  const Color(0xFFF3E5F5),
                  const Color(0xFFE1BEE7),
                ],
                iconColor: const Color(0xFF7B1FA2),
                iconBgColor: const Color(0xFF7B1FA2).withOpacity(0.12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatListScreen()),
                ),
              ),
              const SizedBox(width: 12),
              _buildQuickAccessCard(
                title: 'Diagnosis\nHistory',
                subtitle: 'Past scans',
                icon: Icons.history_rounded,
                gradientColors: [
                  const Color(0xFFFFEBEE),
                  const Color(0xFFFFCDD2),
                ],
                iconColor: const Color(0xFFC62828),
                iconBgColor: const Color(0xFFC62828).withOpacity(0.12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiagnosisHistoryScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAccessCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required Color iconColor,
    required Color iconBgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  ANNOUNCEMENT BANNER
  // ─────────────────────────────────────────────
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
            colors: [
              Color(0xFFFFF8E1),
              Color(0xFFFFECB3),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFFB300).withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: Color(0xFFFF8F00),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Announcement',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: const Color(0xFFE65100),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    announcement.title ?? 'New AI model update available!',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
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
            Icon(
              Icons.chevron_right_rounded,
              color: const Color(0xFFFF8F00),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  RECENT DIAGNOSIS
  // ─────────────────────────────────────────────
  Widget _buildRecentDiagnosis(DiagnosisProvider provider) {
    final history = provider.history;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Diagnosis',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiagnosisHistoryScreen()),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: GoogleFonts.poppins(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.primary,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Latest diagnosis card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Main diagnosis row
                Row(
                  children: [
                    // Disease icon
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.error.withOpacity(0.1),
                            AppTheme.error.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.bug_report_rounded,
                        color: AppTheme.error,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            history.first.diseaseName,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${history.first.cropType} · ${history.first.confidence.toInt()}% confidence',
                            style: GoogleFonts.poppins(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Confidence badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getConfidenceColor(
                                history.first.confidence.toInt())
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${history.first.confidence.toInt()}%',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _getConfidenceColor(
                              history.first.confidence.toInt()),
                        ),
                      ),
                    ),
                  ],
                ),
                // Second diagnosis preview if exists
                if (history.length > 1) ...[
                  const SizedBox(height: 14),
                  Divider(color: Colors.grey.shade100, thickness: 1),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFF9800),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              history[1].diseaseName,
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${history[1].cropType} · ${history[1].confidence.toInt()}%',
                              style: GoogleFonts.poppins(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(int confidence) {
    if (confidence >= 80) return const Color(0xFF4CAF50);
    if (confidence >= 60) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  // ─────────────────────────────────────────────
  //  FARMING TIP
  // ─────────────────────────────────────────────
  Widget _buildFarmingTip() {
    final tips = [
      {
        'icon': Icons.lightbulb_rounded,
        'title': 'Farming Tip',
        'tip': 'Apply fungicide early morning for best absorption and reduced evaporation loss.',
        'bgColor': Color(0xFFE8F5E9),
        'iconColor': AppTheme.primary,
        'accentColor': AppTheme.primary,
      },
      {
        'icon': Icons.water_drop_rounded,
        'title': 'Watering Tip',
        'tip': 'Water your crops at dawn or dusk to minimize water loss through evaporation.',
        'bgColor': Color(0xFFE3F2FD),
        'iconColor': Color(0xFF1565C0),
        'accentColor': Color(0xFF1565C0),
      },
      {
        'icon': Icons.compost_rounded,
        'title': 'Soil Tip',
        'tip': 'Adding organic compost improves soil structure and boosts nutrient retention.',
        'bgColor': Color(0xFFF3E5F5),
        'iconColor': Color(0xFF7B1FA2),
        'accentColor': Color(0xFF7B1FA2),
      },
    ];

    final tip = tips[DateTime.now().millisecond % tips.length];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tip['bgColor'] as Color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (tip['accentColor'] as Color).withOpacity(0.15),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon with animated pulse
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (tip['iconColor'] as Color).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                tip['icon'] as IconData,
                color: tip['iconColor'] as Color,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tip['title'] as String,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: tip['accentColor'] as Color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (tip['accentColor'] as Color)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Daily',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: tip['accentColor'] as Color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tip['tip'] as String,
                    style: GoogleFonts.poppins(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.5,
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
}
