import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Shared building blocks for the redesigned farmer experience.
///
/// Every farmer-facing screen (dashboard tabs + sub-pages) is built from these
/// components so the app keeps one coherent, field-friendly visual language:
/// a soft green-grey canvas, white rounded cards, gradient headers, pill
/// badges, big touch targets and consistent empty/error states.
class FarmerTheme {
  FarmerTheme._();

  // Canvas + surfaces
  static const Color canvas = Color(0xFFF4F7F2);
  static const Color card = Colors.white;
  static const Color headerTop = Color(0xFF155724);
  static const Color headerBottom = Color(0xFF2F7D32);

  // Domain accents
  static const Color sky = Color(0xFF0288D1); // weather
  static const Color sun = Color(0xFFFF8F00); // market / warnings
  static const Color earth = Color(0xFF8D6E63); // soil / tips
  static const Color grape = Color(0xFF7B1FA2); // chat / community

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

/// Full-width gradient header used by every farmer sub-page.
class FarmerHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final bool showBack;

  const FarmerHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing = const [],
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: FarmerTheme.headerGradient,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                const SizedBox(width: 2),
              ],
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 19,
                  ),
                ),
              ),
              ...trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// White rounded card with optional padding.
class FarmerCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const FarmerCard({
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
        color: FarmerTheme.card,
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
class FarmerSectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const FarmerSectionTitle({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: FarmerTheme.sectionTitle()),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Pill badge for statuses / severity / roles.
class FarmerPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const FarmerPill({
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

/// KPI metric tile — the primary data-visualization unit on farmer screens.
class FarmerStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final String? footnote;

  const FarmerStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: color.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (footnote != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up_rounded, size: 12, color: color),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              style: GoogleFonts.poppins(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular avatar showing a profile photo, falling back to initials/icon.
class FarmerAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? name;
  final double radius;
  final Color? tint;

  const FarmerAvatar({
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
                  width: radius * 0.6,
                  height: radius * 0.6,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: color),
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

/// Product thumbnail with a fallback icon.
class FarmerProductThumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;

  const FarmerProductThumb({
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
          : Icon(fallbackIcon, color: AppTheme.primaryLight, size: size * 0.45),
    );
  }
}

/// Empty-state illustration block.
class FarmerEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const FarmerEmptyState({
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
                textAlign: TextAlign.center, style: FarmerTheme.title(context)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
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
class FarmerErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const FarmerErrorState(
      {super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FarmerEmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Could not load data',
      subtitle: message,
      action: ElevatedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Menu descriptor for the farmer navigation drawer.
class FarmerNavItem {
  final int id;
  final IconData icon;
  final String label;
  final bool isTab; // true → switches the bottom tab; false → opens a page
  const FarmerNavItem(this.id, this.icon, this.label, {this.isTab = false});
}

/// Slide-out navigation drawer for the farmer dashboard.
class FarmerDrawer extends StatelessWidget {
  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onLogout;
  final String? name;
  final String? email;
  final String? photo;

  const FarmerDrawer({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onPageSelected,
    required this.onLogout,
    this.name,
    this.email,
    this.photo,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: FarmerTheme.headerTop,
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
                        'AgriSense AI',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Smart Farming Assistant',
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
                  _group('MY FARM'),
                  _item(context, 0, Icons.home_rounded, 'Home', tab: true),
                  _item(context, 1, Icons.camera_alt_rounded, 'AI Crop Scan',
                      tab: true),
                  _page(context, Icons.wb_cloudy_rounded, 'Weather Forecast',
                      100),
                  _item(context, 2, Icons.shopping_bag_rounded, 'Marketplace',
                      tab: true),
                  _group('ACTIVITY'),
                  _page(
                      context, Icons.history_rounded, 'Diagnosis History', 101),
                  _page(context, Icons.receipt_long_rounded, 'My Orders', 102),
                  _page(context, Icons.notifications_rounded, 'Notifications',
                      103),
                  _item(context, 3, Icons.chat_rounded, 'Messages', tab: true),
                  _group('ACCOUNT'),
                  _item(context, 4, Icons.person_rounded, 'My Profile',
                      tab: true),
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
                  FarmerAvatar(
                    photoUrl: photo,
                    name: name,
                    radius: 18,
                    tint: const Color(0xFF8BC34A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name ?? 'Farmer',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email ?? '',
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

  Widget _item(BuildContext context, int id, IconData icon, String label,
      {bool tab = false}) {
    final selected = tab && selectedTab == id;
    return ListTile(
      dense: true,
      leading: Icon(icon,
          color: selected ? const Color(0xFF8BC34A) : Colors.white70, size: 20),
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
        onTabSelected(id);
      },
    );
  }

  Widget _page(BuildContext context, IconData icon, String label, int id) {
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
      trailing: const Icon(Icons.chevron_right_rounded,
          color: Colors.white38, size: 18),
      onTap: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        onPageSelected(id);
      },
    );
  }
}
