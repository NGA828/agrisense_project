import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Shared building blocks for the redesigned AgriSense admin console.
///
/// Everything in the admin area (dashboard tabs + standalone screens) is built
/// from these components so the whole console keeps one coherent visual
/// language: a soft green-grey canvas, white rounded cards, gradient headers,
/// pill badges and consistent empty/error states.
class AdminTheme {
  AdminTheme._();

  // Canvas + surfaces
  static const Color canvas = Color(0xFFF2F6F0);
  static const Color card = Colors.white;
  static const Color headerTop = Color(0xFF123D1A);
  static const Color headerBottom = Color(0xFF2E6B28);

  // Semantic accents used across cards
  static const Color purple = Color(0xFF7B4FC0);
  static const Color teal = Color(0xFF00897B);

  static BoxDecoration get headerGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [headerTop, headerBottom],
        ),
      );

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static TextStyle title(BuildContext context) =>
      GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 20);

  static TextStyle sectionTitle() =>
      GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16);

  static TextStyle smallMuted() =>
      const TextStyle(color: AppTheme.textMuted, fontSize: 12);
}

/// Full-width gradient header used by every admin screen.
class AdminHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final bool showBack;

  const AdminHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    // Screens wrap this header in a SafeArea, so a fixed top padding keeps
    // the layout consistent without double-padding under the status bar.
    return Container(
      width: double.infinity,
      decoration: AdminTheme.headerGradient,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showBack) ...[
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 4),
              ],
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              ...trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// White rounded card with optional padding.
class AdminCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const AdminCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AdminTheme.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Section heading with an optional trailing action.
class AdminSectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const AdminSectionTitle({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AdminTheme.sectionTitle()),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// KPI tile used on the overview + analytics pages.
class AdminStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final String? footnote;

  const AdminStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (footnote != null)
                Icon(Icons.trending_up_rounded, size: 14, color: color),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                footnote!,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pill badge for statuses / roles / severity.
class AdminPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const AdminPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded search input used on list screens.
class AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  const AdminSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                hintStyle: const TextStyle(fontSize: 13),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (controller != null)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller!,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: () {
                        controller!.clear();
                        onChanged('');
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: AppTheme.textMuted),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Empty-state illustration block.
class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppTheme.primaryLight),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center, style: AdminTheme.title(context)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with retry.
class AdminErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const AdminErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AdminEmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Could not load data',
      subtitle: message,
      action: ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Circular avatar that shows a profile photo when available and falls back
/// to initials (or an icon) otherwise.
class AdminUserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? name;
  final double radius;
  final Color? tint;

  const AdminUserAvatar({
    super.key,
    this.photoUrl,
    this.name,
    this.radius = 24,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService.resolveMedia(photoUrl);
    final hasPhoto = resolved.isNotEmpty;
    final initials = _initials(name);
    final color = tint ?? AppTheme.primary;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: resolved,
              fit: BoxFit.cover,
              placeholder: (_, __) => Center(
                child: SizedBox(
                  width: radius * 0.7,
                  height: radius * 0.7,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color),
                ),
              ),
              errorWidget: (_, __, ___) => _fallback(color, initials),
            )
          : _fallback(color, initials),
    );
  }

  Widget _fallback(Color color, String initials) {
    return Center(
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.7,
                color: color,
              ),
            )
          : Icon(Icons.person_rounded, size: radius, color: color),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Product thumbnail with a category-coloured fallback.
class AdminProductThumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;

  const AdminProductThumb({
    super.key,
    this.imageUrl,
    this.size = 52,
    this.fallbackIcon = Icons.inventory_2_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = ApiService.resolveMedia(imageUrl);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: resolved.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: resolved,
              fit: BoxFit.cover,
              placeholder: (_, __) => Center(
                child: SizedBox(
                  width: size * 0.35,
                  height: size * 0.35,
                  child: const CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                ),
              ),
              errorWidget: (_, __, ___) => Icon(fallbackIcon,
                  color: AppTheme.primaryLight, size: size * 0.45),
            )
          : Icon(fallbackIcon,
              color: AppTheme.primaryLight, size: size * 0.45),
    );
  }
}

/// Lightweight vertical bar chart used on the overview + analytics pages.
class AdminBarChart extends StatelessWidget {
  final List<(String, double)> points;
  final Color color;
  final double height;

  const AdminBarChart({
    super.key,
    required this.points,
    this.color = AppTheme.primary,
    this.height = 130,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data for this period',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _AdminBarChartPainter(points, color),
      ),
    );
  }
}

class _AdminBarChartPainter extends CustomPainter {
  final List<(String, double)> points;
  final Color color;

  _AdminBarChartPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxValue = points.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;
    final barWidth = (size.width / points.length) * 0.52;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < points.length; i++) {
      final h = (points[i].$2 / safeMax) * (size.height - 8);
      final left =
          i * (size.width / points.length) + (size.width / points.length - barWidth) / 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - h, barWidth, h),
        const Radius.circular(4),
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.55)],
        ).createShader(rrect.outerRect);
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AdminBarChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

/// Menu item descriptor for the admin navigation drawer.
class AdminNavItem {
  final int id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isPage; // true → opens a standalone screen route
  const AdminNavItem(this.id, this.icon, this.activeIcon, this.label,
      {this.isPage = false});
}

/// Navigation drawer for the admin console.
class AdminDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  /// Fired when a standalone page item (isPage == true) is tapped.
  final ValueChanged<int> onPageSelected;
  /// Standalone page entries shown under the "Management" group.
  final List<AdminNavItem> pages;
  final VoidCallback onLogout;
  final String? adminName;
  final String? adminEmail;
  final String? adminPhoto;

  const AdminDrawer({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onPageSelected,
    this.pages = const [],
    required this.onLogout,
    this.adminName,
    this.adminEmail,
    this.adminPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AdminTheme.headerTop,
      child: SafeArea(
        child: Column(
          children: [
            // Brand block
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.eco_rounded,
                        color: Color(0xFF8BC34A), size: 26),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AgriSense',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Admin Console',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  _group('MAIN'),
                  _item(context, 0, Icons.space_dashboard_rounded,
                      Icons.space_dashboard_rounded, 'Overview'),
                  _item(context, 1, Icons.people_alt_rounded, Icons.people_alt_rounded,
                      'User Management'),
                  _item(context, 2, Icons.receipt_long_rounded,
                      Icons.receipt_long_rounded, 'Orders'),
                  if (pages.isNotEmpty) _group('MANAGEMENT'),
                  ...pages.map(
                    (p) => _pageItem(p.icon, p.label, () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                      onPageSelected(p.id);
                    }),
                  ),
                  _group('PLATFORM'),
                  _item(context, 3, Icons.settings_rounded, Icons.settings_rounded,
                      'Settings'),
                ],
              ),
            ),
            // Profile + logout
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  AdminUserAvatar(
                    photoUrl: adminPhoto,
                    name: adminName,
                    radius: 18,
                    tint: const Color(0xFF8BC34A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adminName ?? 'Administrator',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          adminEmail ?? '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded,
                        color: Color(0xFFFF8A80), size: 20),
                    tooltip: 'Sign out',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _item(BuildContext context, int id, IconData icon, IconData activeIcon, String label) {
    final selected = selectedIndex == id;
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? activeIcon : icon,
        color: selected ? const Color(0xFF8BC34A) : Colors.white70,
        size: 20,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          fontSize: 13.5,
        ),
      ),
      trailing: selected
          ? Container(
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF8BC34A),
                borderRadius: BorderRadius.circular(2),
              ),
            )
          : null,
      onTap: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        onSelect(id);
      },
    );
  }

  Widget _pageItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Colors.white70, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w400,
          fontSize: 13.5,
        ),
      ),
      trailing:
          const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
      onTap: onTap,
    );
  }
}
