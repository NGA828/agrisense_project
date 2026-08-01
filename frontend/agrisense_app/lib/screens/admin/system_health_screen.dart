import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

/// Live system health: API/database/AI-engine checks from GET /api/health/.
class SystemHealthScreen extends StatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  State<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends State<SystemHealthScreen> {
  Map<String, dynamic>? _health;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final health = await ApiService().getHealth();
      if (mounted) {
        setState(() {
          _health = health;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _health?['status'];
    final allOk = status == 'ok';

    return Scaffold(
      backgroundColor: AdminTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AdminHeader(
              title: 'System Health',
              subtitle: allOk
                  ? 'All systems operational'
                  : 'Service degraded — review the checks below',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _load,
                  icon:
                      const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                  tooltip: 'Re-check',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? AdminErrorState(message: _error!, onRetry: _load)
                      : ListView(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            // Overall status banner
                            AdminCard(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: (allOk
                                              ? AppTheme.success
                                              : AppTheme.warning)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      allOk
                                          ? Icons.check_circle_rounded
                                          : Icons.warning_rounded,
                                      color: allOk
                                          ? AppTheme.success
                                          : AppTheme.warning,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          allOk
                                              ? 'All systems operational'
                                              : 'Service degraded',
                                          style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'API version ${_health?['version'] ?? '—'}',
                                          style: AdminTheme.smallMuted(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AdminPill(
                                    label: allOk ? 'Healthy' : 'Attention',
                                    color: allOk
                                        ? AppTheme.success
                                        : AppTheme.warning,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _serviceCard(
                              title: 'API Gateway',
                              subtitle:
                                  'API version ${_health?['version'] ?? '—'}',
                              healthy: allOk,
                              icon: Icons.cloud_done_rounded,
                            ),
                            _serviceCard(
                              title: 'Database',
                              subtitle: _statusDetail('database'),
                              healthy: _statusDetail('database') == 'ok',
                              icon: Icons.storage_rounded,
                            ),
                            _serviceCard(
                              title: 'AI Engine',
                              subtitle: _aiDetail(),
                              healthy: _statusDetail('ai_engine') == 'ok',
                              icon: Icons.smart_toy_rounded,
                            ),
                            const SizedBox(height: 8),
                            AdminCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const Icon(Icons.schedule_rounded,
                                      color: AppTheme.textMuted, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Last checked: ${_timestamp()}',
                                      style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
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

  String _statusDetail(String key) {
    final checks = _health?['checks'] as Map<String, dynamic>?;
    final detail = checks?[key]?['detail'] ?? '';
    final status = checks?[key]?['status'] ?? 'unknown';
    return status == 'ok' ? 'Operational' : '$status — $detail';
  }

  String _aiDetail() {
    final checks = _health?['checks'] as Map<String, dynamic>?;
    final status = checks?['ai_engine']?['status'] ?? 'unknown';
    final detail = checks?['ai_engine']?['detail'] ?? '';
    return status == 'ok'
        ? (detail.toString().isNotEmpty ? detail.toString() : 'Operational')
        : 'degraded — $detail';
  }

  String _timestamp() {
    final raw = _health?['timestamp'];
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '—';
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _serviceCard({
    required String title,
    required String subtitle,
    required bool healthy,
    required IconData icon,
  }) {
    final color = healthy ? AppTheme.success : AppTheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AdminTheme.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          AdminPill(
            label: healthy ? 'Up' : 'Down',
            color: color,
            icon: healthy ? Icons.check_rounded : Icons.close_rounded,
          ),
        ],
      ),
    );
  }
}
