import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A3A1A), Color(0xFF2D5016)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
                      Text('Notifications', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 22)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Manage platform-wide notifications and alerts', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Send notification button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  label: Text('Send New Notification', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Recent notifications
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Recent Notifications', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildNotificationCard(
                    'System Maintenance Scheduled',
                    'Platform will be down for maintenance on July 26, 2026 from 2:00 AM to 4:00 AM',
                    '2 hours ago',
                    AppTheme.info,
                    Icons.build_rounded,
                    true,
                  ),
                  const SizedBox(height: 12),
                  _buildNotificationCard(
                    'New Payment Method Added',
                    'Orange Money is now available as a payment option for all users',
                    '1 day ago',
                    AppTheme.success,
                    Icons.payment_rounded,
                    true,
                  ),
                  const SizedBox(height: 12),
                  _buildNotificationCard(
                    'AI Model Update',
                    'Disease detection AI model has been updated to version 3.2 with improved accuracy',
                    '3 days ago',
                    AppTheme.primary,
                    Icons.smart_toy_rounded,
                    false,
                  ),
                  const SizedBox(height: 12),
                  _buildNotificationCard(
                    'Security Alert',
                    'Please update your password for enhanced security',
                    '5 days ago',
                    AppTheme.error,
                    Icons.security_rounded,
                    false,
                  ),
                  const SizedBox(height: 12),
                  _buildNotificationCard(
                    'Feature Announcement',
                    'New chat feature now available for farmers and dealers',
                    '1 week ago',
                    AppTheme.accent,
                    Icons.chat_rounded,
                    false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(String title, String message, String time, Color color, IconData icon, bool isUnread) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        border: isUnread ? Border.all(color: AppTheme.primary, width: 2) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                    ),
                    if (isUnread)
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(message, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(time, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
