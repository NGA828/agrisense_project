import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

/// Predictive outbreak console: detected, growing disease clusters (Phase F #4).
class OutbreaksScreen extends StatefulWidget {
  const OutbreaksScreen({super.key});

  @override
  State<OutbreaksScreen> createState() => _OutbreaksScreenState();
}

class _OutbreaksScreenState extends State<OutbreaksScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _alerts = [];
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
      final data = await _api.getOutbreaks();
      if (mounted) {
        setState(() {
          _alerts = data['alerts'] ?? [];
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
    return Scaffold(
      backgroundColor: AdminTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AdminHeader(
              title: 'Outbreak Alerts',
              subtitle: 'Growing disease clusters detected by the AI',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? _buildError()
                      : _alerts.isEmpty
                          ? const _EmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: _alerts.length,
                              itemBuilder: (context, index) =>
                                  _alertCard(_alerts[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(color: AppTheme.error)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _alertCard(dynamic alert) {
    final disease = (alert['disease_name'] ?? 'Unknown').toString();
    final crop = (alert['crop_name'] ?? '').toString();
    final clusterSize = alert['cluster_size'] ?? 0;
    final previous = alert['previous_size'] ?? 0;
    final notified = alert['notified_users'] ?? 0;
    final status = (alert['status'] ?? 'active').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.error.withValues(alpha: 0.12),
            child: const Icon(Icons.warning_amber_rounded,
                color: AppTheme.error, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$disease${crop.isNotEmpty ? ' ($crop)' : ''}',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  'Cluster: ${alert['latitude']?.toStringAsFixed(2)}, '
                  '${alert['longitude']?.toStringAsFixed(2)} · '
                  '${alert['radius_km'] ?? 50} km',
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text('$clusterSize cases (was $previous) · $notified notified',
                    style: GoogleFonts.poppins(
                        color: AppTheme.primary, fontSize: 11)),
                const SizedBox(height: 4),
                Text('Status: $status',
                    style: GoogleFonts.poppins(
                        color: Colors.grey.shade400, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user_rounded,
              size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text('No outbreak alerts detected',
              style: GoogleFonts.poppins(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
