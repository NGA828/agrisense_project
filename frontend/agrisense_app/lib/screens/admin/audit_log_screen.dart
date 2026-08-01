import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

/// Immutable admin action audit log, fed by GET /api/audit_logs/.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final ApiService _api = ApiService();
  List<dynamic> _logs = [];
  bool _isLoading = true;
  String? _error;
  String? _category;

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
      final logs = await _api.getAuditLogs(category: _category);
      if (mounted) {
        setState(() {
          _logs = logs;
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

  IconData _iconFor(String category) {
    switch (category) {
      case 'user':
        return Icons.person_rounded;
      case 'product':
        return Icons.inventory_2_rounded;
      case 'payment':
        return Icons.payments_rounded;
      case 'content':
        return Icons.article_rounded;
      case 'order':
        return Icons.receipt_rounded;
      default:
        return Icons.history_rounded;
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
              title: 'Audit Log',
              subtitle: 'Immutable record of privileged actions',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            // Category filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  _chip(null, 'All'),
                  _chip('user', 'Users'),
                  _chip('product', 'Products'),
                  _chip('payment', 'Payments'),
                  _chip('content', 'Content'),
                  _chip('order', 'Orders'),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _logs.isEmpty
                          ? const _EmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _logs.length,
                              itemBuilder: (context, index) =>
                                  _logCard(_logs[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String? value, String label) {
    final selected = _category == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _category = value);
        _load();
      },
      selectedColor: AppTheme.primary,
      labelStyle: GoogleFonts.poppins(
          fontSize: 12, color: selected ? Colors.white : Colors.black87),
      backgroundColor: Colors.white,
    );
  }

  Widget _logCard(dynamic log) {
    final category = (log['category'] ?? 'system').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
            child: Icon(_iconFor(category), color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (log['description'] ?? 'Action').toString(),
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${log['actor_username'] ?? 'system'} · ${log['action']}',
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  (log['created_at']?.toString() ?? '').replaceFirst('T', ' '),
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade400, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppTheme.error)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
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
          const Icon(Icons.history_rounded, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text('No audit entries yet',
              style: GoogleFonts.poppins(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
