import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Shared building blocks for the redesigned AgriSense dealer console.
///
/// Every dealer-facing screen (dashboard tabs + product/premium pages) is built
/// from these components so the console keeps one coherent, store-friendly
/// visual language: a warm green-teal canvas, white rounded cards, gradient
/// headers, pill badges, KPI tiles and consistent empty/error states.
class DealerTheme {
  DealerTheme._();

  // Canvas + surfaces
  static const Color canvas = Color(0xFFF3F7F4);
  static const Color card = Colors.white;
  static const Color headerTop = Color(0xFF14421E);
  static const Color headerBottom = Color(0xFF2E6B28);

  // Domain accents
  static const Color sky = Color(0xFF0288D1); // info / orders
  static const Color sun = Color(0xFFFF8F00); // premium / warnings
  static const Color grape = Color(0xFF7B1FA2); // chat / customers
  static const Color teal = Color(0xFF00897B); // revenue / money

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

/// Full-width gradient header used by every dealer page.
class DealerHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;
  final bool showBack;

  const DealerHeader({
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
      decoration: DealerTheme.headerGradient,
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
class DealerCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const DealerCard({
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
        color: DealerTheme.card,
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
class DealerSectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const DealerSectionTitle({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: DealerTheme.sectionTitle()),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Pill badge for statuses / categories / stock levels.
class DealerPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const DealerPill({
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

/// KPI tile — the primary data-visualization unit on dealer screens.
class DealerStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final String? footnote;

  const DealerStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return DealerCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
              if (footnote != null)
                Icon(Icons.trending_up_rounded, size: 13, color: color),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          if (footnote != null) ...[
            const SizedBox(height: 3),
            Text(
              footnote!,
              style:
                  TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular avatar with photo / initials fallback.
class DealerAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? name;
  final double radius;
  final Color? tint;

  const DealerAvatar({
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
          : Icon(Icons.store_rounded, size: radius, color: color),
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
class DealerProductThumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final IconData fallbackIcon;

  const DealerProductThumb({
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

/// Empty-state illustration block.
class DealerEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const DealerEmptyState({
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
                textAlign: TextAlign.center, style: DealerTheme.title(context)),
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
class DealerErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const DealerErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return DealerEmptyState(
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

/// Menu item descriptor for the dealer navigation drawer.
class DealerNavItem {
  final int id;
  final IconData icon;
  final String label;
  final bool isTab; // true → switches the bottom tab; false → opens a page
  const DealerNavItem(this.id, this.icon, this.label, {this.isTab = false});
}

/// Slide-out navigation drawer for the dealer console.
class DealerDrawer extends StatelessWidget {
  final int selectedTab;
  final ValueChanged<int> onTabSelected;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onLogout;
  final String? storeName;
  final String? email;
  final String? photo;

  const DealerDrawer({
    super.key,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onPageSelected,
    required this.onLogout,
    this.storeName,
    this.email,
    this.photo,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: DealerTheme.headerTop,
      child: SafeArea(
        child: Column(
          children: [
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
                    child: const Icon(Icons.storefront_rounded,
                        color: Color(0xFFFFB74D), size: 26),
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
                        'Dealer Console',
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
                  _group('MY STORE'),
                  _item(0, Icons.space_dashboard_rounded, 'Dashboard', tab: true),
                  _item(1, Icons.inventory_2_rounded, 'Products', tab: true),
                  _item(2, Icons.receipt_long_rounded, 'Orders', tab: true),
                  _page(Icons.star_rounded, 'Premium Upgrade', 100),
                  _group('CUSTOMERS'),
                  _item(3, Icons.chat_rounded, 'Chats', tab: true),
                  _page(Icons.notifications_rounded, 'Notifications', 101),
                  _group('ACCOUNT'),
                  _item(4, Icons.person_rounded, 'My Profile', tab: true),
                  _page(Icons.help_outline_rounded, 'Help & Support', 102),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  DealerAvatar(
                    photoUrl: photo,
                    name: storeName,
                    radius: 18,
                    tint: const Color(0xFFFFB74D),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storeName ?? 'Dealer',
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

  Widget _item(int id, IconData icon, String label, {bool tab = false}) {
    final selected = tab && selectedTab == id;
    return ListTile(
      dense: true,
      leading: Icon(icon,
          color: selected ? const Color(0xFFFFB74D) : Colors.white70, size: 20),
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
                color: const Color(0xFFFFB74D),
                borderRadius: BorderRadius.circular(2),
              ),
            )
          : null,
      onTap: () {
        Navigator.pop(context);
        onTabSelected(id);
      },
    );
  }

  Widget _page(IconData icon, String label, int id) {
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
        Navigator.pop(context);
        onPageSelected(id);
      },
    );
  }
}
