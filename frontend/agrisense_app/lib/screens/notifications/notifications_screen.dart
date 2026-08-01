import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/notification.dart';
import '../../providers/notification_provider.dart';
import '../../theme/app_theme.dart';
import '../farmer/farmer_widgets.dart';

/// User-facing in-app notifications: order updates, payment confirmations,
/// premium subscription events and system broadcasts.
class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() =>
      _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FarmerHeader(
              title: 'Notifications',
              subtitle: provider.unreadCount > 0
                  ? '${provider.unreadCount} unread update(s)'
                  : 'You are all caught up',
              showBack: true,
              leading: const Icon(Icons.notifications_rounded,
                  color: Colors.white, size: 22),
              trailing: [
                if (provider.unreadCount > 0)
                  TextButton(
                    onPressed: () => provider.markAllRead(),
                    child: const Text('Mark all read',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
              ],
            ),
            Expanded(
              child: provider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : provider.notifications.isEmpty
                      ? FarmerEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'No notifications yet',
                          subtitle: 'Order and payment updates will appear here',
                        )
                      : RefreshIndicator(
                          onRefresh: provider.loadNotifications,
                          color: AppTheme.primary,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: provider.notifications.length,
                            itemBuilder: (context, index) => _notificationCard(
                                provider, provider.notifications[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationCard(NotificationProvider provider, AppNotification n) {
    final IconData icon;
    final Color color;
    switch (n.type) {
      case 'order':
        icon = Icons.shopping_bag_rounded;
        color = AppTheme.info;
        break;
      case 'payment':
        icon = Icons.payments_rounded;
        color = AppTheme.success;
        break;
      case 'premium':
        icon = Icons.workspace_premium_rounded;
        color = AppTheme.accent;
        break;
      case 'chat':
        icon = Icons.chat_rounded;
        color = AppTheme.info;
        break;
      default:
        icon = Icons.campaign_rounded;
        color = AppTheme.warning;
    }

    return GestureDetector(
      onTap: () => provider.markRead(n),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: n.isRead ? Colors.white : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: n.isRead
                ? Colors.grey.shade200
                : AppTheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 21),
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
                          n.title,
                          style: GoogleFonts.poppins(
                            fontWeight:
                                n.isRead ? FontWeight.w500 : FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                              color: AppTheme.primary, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    n.message,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4),
                  ),
                  const SizedBox(height: 5),
                  Text(n.timeAgo,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bell icon with unread-count badge, used in app bar headers.
class NotificationBell extends StatelessWidget {
  final Color color;
  final double size;

  const NotificationBell({super.key, this.color = Colors.white, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadUnreadCount();
    });

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsListScreen()),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_none_rounded, color: color, size: size),
          if (provider.unreadCount > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  '${provider.unreadCount > 99 ? '99+' : provider.unreadCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
