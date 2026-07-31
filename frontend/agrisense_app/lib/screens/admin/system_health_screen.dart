import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

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
      if (mounted) setState(() {
        _health = health;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

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
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3A1A), Color(0xFF2D5016)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
                      Text('System Health',
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                      const Spacer(),
                      IconButton(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_health != null)
                    Row(
                      children: [
                        Icon(
                          _health!['status'] == 'ok' ? Icons.check_circle_rounded : Icons.warning_rounded,
                          color: _health!['status'] == 'ok' ? const Color(0xFF81C784) : const Color(0xFFFFB74D),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _health!['status'] == 'ok' ? 'All systems operational' : 'Service degraded',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text('Backend unreachable', style: AppTheme.titleMedium),
                                const SizedBox(height: 8),
                                Text(_error!, style: AppTheme.bodySmall, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(onPressed: _load, child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: [
                            _serviceCard('API Gateway', 'API version ${_health!['version'] ?? '—'}',
                                _health!['status'] == 'ok'),
                            _serviceCard('Database', _statusDetail('database'), _statusDetail('database') == 'ok'),
                            _serviceCard('AI Engine', _aiDetail(), _statusDetail('ai_engine') == 'ok'),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.schedule_rounded, color: AppTheme.textMuted, size: 18),
                                  const SizedBox(width: 10),
                                  Text('Last checked: ${_timestamp()}',
                                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
    return status == 'ok' ? 'ok' : '$status — $detail';
  }

  String _aiDetail() {
    final checks = _health?['checks'] as Map<String, dynamic>?;
    final status = checks?['ai_engine']?['status'] ?? 'unknown';
    final detail = checks?['ai_engine']?['detail'] ?? '';
    return status == 'ok' ? (detail.toString().isNotEmpty ? detail.toString() : 'ok') : 'degraded — $detail';
  }

  String _timestamp() {
    final raw = _health?['timestamp'];
    final date = DateTime.tryParse(raw?.toString() ?? '');
    if (date == null) return '—';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Widget _serviceCard(String title, String subtitle, bool healthy) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: (healthy ? AppTheme.success : AppTheme.error).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              healthy ? Icons.check_circle_rounded : Icons.error_rounded,
              color: healthy ? AppTheme.success : AppTheme.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(healthy ? 'UP' : 'DOWN',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: healthy ? AppTheme.success : AppTheme.error,
              )),
        ],
      ),
    );
  }
}
