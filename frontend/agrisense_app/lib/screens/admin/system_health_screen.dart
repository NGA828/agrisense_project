import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class SystemHealthScreen extends StatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  State<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends State<SystemHealthScreen> {
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
                      Text('System Health', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                      IconButton(onPressed: () {}, icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 16),
                            const SizedBox(width: 6),
                            Text('All Systems Operational', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Overall health score
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
                ),
                child: Column(
                  children: [
                    Text('Overall Health Score', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textSecondary)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('98', style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 56, color: AppTheme.success)),
                        const SizedBox(width: 4),
                        Text('/ 100', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 24, color: AppTheme.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text('Excellent', style: TextStyle(color: AppTheme.success, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // System metrics
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('System Metrics', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.3,
                children: [
                  _buildMetricCard('API Response', '45ms', Icons.speed_rounded, AppTheme.success, 'Fast'),
                  _buildMetricCard('Server Uptime', '99.9%', Icons.dns_rounded, AppTheme.success, 'Stable'),
                  _buildMetricCard('Database', 'Active', Icons.storage_rounded, AppTheme.success, 'Healthy'),
                  _buildMetricCard('Error Rate', '0.02%', Icons.bug_report_rounded, AppTheme.success, 'Low'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Service status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Service Status', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
                ),
                child: Column(
                  children: [
                    _buildServiceItem('Authentication Service', 'Running', AppTheme.success),
                    const Divider(height: 24),
                    _buildServiceItem('AI Diagnosis Service', 'Running', AppTheme.success),
                    const Divider(height: 24),
                    _buildServiceItem('Payment Gateway', 'Running', AppTheme.success),
                    const Divider(height: 24),
                    _buildServiceItem('Notification Service', 'Running', AppTheme.success),
                    const Divider(height: 24),
                    _buildServiceItem('Weather API', 'Running', AppTheme.success),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Recent logs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Recent Logs', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildLogItem('INFO', 'User login successful', '2 min ago', AppTheme.info),
                  const SizedBox(height: 8),
                  _buildLogItem('SUCCESS', 'Payment processed successfully', '5 min ago', AppTheme.success),
                  const SizedBox(height: 8),
                  _buildLogItem('INFO', 'AI diagnosis completed', '8 min ago', AppTheme.info),
                  const SizedBox(height: 8),
                  _buildLogItem('WARNING', 'High API latency detected', '15 min ago', AppTheme.warning),
                  const SizedBox(height: 8),
                  _buildLogItem('INFO', 'New dealer registration', '20 min ago', AppTheme.info),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color, String status) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 22, color: AppTheme.textPrimary)),
          Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceItem(String service, String status, Color statusColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(service, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
        Row(
          children: [
            Icon(Icons.circle, size: 8, color: statusColor),
            const SizedBox(width: 8),
            Text(status, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildLogItem(String level, String message, String time, Color levelColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: levelColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(level, style: TextStyle(color: levelColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
          Text(time, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
