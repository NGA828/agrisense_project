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
import 'farmer_widgets.dart';
import 'order_history_screen.dart';

/// Farmer home — the command center of the app.
///
/// Information hierarchy (top → bottom):
///   1. Header          brand, notification bell, avatar → profile
///   2. Greeting        time-aware greeting + today's date
///   3. Weather card    live conditions → full weather screen
///   4. Farm snapshot   key metrics at a glance (scans / orders / chats)
///   5. Quick scan hero primary CTA → AI plant doctor
///   6. Quick access    2×2 grid: Weather · Market · Chat · History
///   7. Announcement    latest broadcast
///   8. Recent scans    latest diagnoses with thumbnails
///   9. Daily tip       rotating farming advice
class FarmerHomeScreen extends StatefulWidget {
  /// Called when the header avatar is tapped (switches to the Profile tab).
  final VoidCallback? onOpenProfile;

  const FarmerHomeScreen({super.key, this.onOpenProfile});

  @override
  State<FarmerHomeScreen> createState() => _FarmerHomeScreenState();
}

class _FarmerHomeScreenState extends State<FarmerHomeScreen> {
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
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(user),
              _buildGreeting(user),
              const SizedBox(height: 16),
              _buildWeatherMiniCard(weather),
              const SizedBox(height: 20),
              _buildFarmSnapshot(),
              const SizedBox(height: 20),
              _buildQuickScanHero(),
              const SizedBox(height: 24),
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
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────
  Widget _buildHeader(user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primary, AppTheme.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.menu_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AgriSense AI',
                  style: GoogleFonts.poppins(
                    fontSize: 17,
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
          ),
          // Notification bell (live unread badge)
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: NotificationBell(color: AppTheme.primary, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          // Avatar → profile tab
          GestureDetector(
            onTap: widget.onOpenProfile,
            child: FarmerAvatar(
              photoUrl: user?.profilePhoto,
              name: user?.fullName,
              radius: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ── Greeting ────────────────────────────────────────────────────────
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
    final name = (user?.firstName?.isNotEmpty ?? false)
        ? user!.firstName
        : (user?.username ?? 'Farmer');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
          const SizedBox(height: 3),
          Text(
            DateFormat('EEEE, MMMM d').format(DateTime.now()),
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Weather mini-card ───────────────────────────────────────────────
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
              colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFFE1F5FE)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF90CAF9).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              // Weather icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
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
                      const Icon(Icons.water_drop_rounded,
                          size: 14, color: Color(0xFF42A5F5)),
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
                      const Icon(Icons.air_rounded,
                          size: 14, color: Color(0xFF42A5F5)),
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
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF42A5F5), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  // ── Farm snapshot: key metrics at a glance ──────────────────────────
  Widget _buildFarmSnapshot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your farm at a glance', style: FarmerTheme.sectionTitle()),
          const SizedBox(height: 12),
          const _FarmSnapshot(),
        ],
      ),
    );
  }

  // ── Quick scan hero ─────────────────────────────────────────────────
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
          padding: const EdgeInsets.all(22),
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
                color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
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
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
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
                                  color: Colors.white.withValues(alpha: 0.9),
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
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
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
                            color: Colors.black.withValues(alpha: 0.1),
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

  // ── Quick access 2×2 grid ───────────────────────────────────────────
  Widget _buildQuickAccessSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Access', style: FarmerTheme.sectionTitle()),
          const SizedBox(height: 12),
          Row(
            children: [
              _quickTile(
                title: 'Weather',
                subtitle: 'Forecast & farm advice',
                icon: Icons.wb_cloudy_rounded,
                color: FarmerTheme.sky,
                bg: const Color(0xFFE3F2FD),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WeatherScreen()),
                ),
              ),
              const SizedBox(width: 12),
              _quickTile(
                title: 'Marketplace',
                subtitle: 'Shop inputs',
                icon: Icons.shopping_bag_rounded,
                color: FarmerTheme.sun,
                bg: const Color(0xFFFFF3E0),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _quickTile(
                title: 'Chat',
                subtitle: 'Talk to dealers',
                icon: Icons.chat_rounded,
                color: FarmerTheme.grape,
                bg: const Color(0xFFF3E5F5),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatListScreen()),
                ),
              ),
              const SizedBox(width: 12),
              _quickTile(
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 10.5,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Announcement banner ─────────────────────────────────────────────
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
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.15),
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
                    announcement.title ?? 'New update available!',
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
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFFF8F00), size: 22),
          ],
        ),
      ),
    );
  }

  // ── Recent diagnoses ────────────────────────────────────────────────
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
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('View All',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_forward_rounded,
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: FarmerTheme.cardDecoration,
        child: Row(
          children: [
            // Crop photo thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 56,
                height: 56,
                color: AppTheme.primary.withValues(alpha: 0.08),
                child: d.imageUrl.isNotEmpty
                    ? Image.network(
                        d.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.eco_rounded,
                            color: AppTheme.primary,
                            size: 26),
                      )
                    : const Icon(Icons.eco_rounded,
                        color: AppTheme.primary, size: 26),
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
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: AppTheme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${d.cropType} · ${_timeAgo(d.createdAt)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${d.confidence.toInt()}%',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Daily farming tip ───────────────────────────────────────────────
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

    final tip = tips[DateTime.now().millisecond % tips.length];
    final accent = tip['accentColor'] as Color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tip['bgColor'] as Color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: 0.15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (tip['iconColor'] as Color).withValues(alpha: 0.12),
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
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FarmerPill(label: 'Daily', color: accent),
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
        const SizedBox(width: 12),
        Expanded(
          child: FarmerStatCard(
            value: '$_orders',
            label: 'Orders',
            icon: Icons.shopping_bag_rounded,
            color: FarmerTheme.sun,
            footnote: 'Purchases made',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FarmerStatCard(
            value: '$_chats',
            label: 'Chats',
            icon: Icons.chat_rounded,
            color: FarmerTheme.grape,
            footnote: 'Dealer talks',
          ),
        ),
      ],
    );
  }
}
