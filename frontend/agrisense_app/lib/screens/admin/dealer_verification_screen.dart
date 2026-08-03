import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

/// Admin moderation queue: approve or reject pending dealer applications.
class DealerVerificationScreen extends StatefulWidget {
  const DealerVerificationScreen({super.key});

  @override
  State<DealerVerificationScreen> createState() =>
      _DealerVerificationScreenState();
}

class _DealerVerificationScreenState extends State<DealerVerificationScreen> {
  List<dynamic> _dealers = [];
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
      final dealers = await ApiService().getPendingDealers();
      if (mounted) {
        setState(() {
          _dealers = dealers;
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

  Future<void> _decide(dynamic dealer, bool approve) async {
    try {
      await ApiService().verifyDealer(dealer['id'], approve);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? '${dealer['first_name']} ${dealer['last_name']} approved ✅'
                : 'Application rejected'),
            backgroundColor: approve ? AppTheme.success : AppTheme.warning,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        setState(() => _dealers.removeWhere((d) => d['id'] == dealer['id']));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action failed: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
              title: 'Dealer Verification',
              subtitle:
                  '${_dealers.length} application(s) awaiting your review',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? AdminErrorState(message: _error!, onRetry: _load)
                      : _dealers.isEmpty
                          ? AdminEmptyState(
                              icon: Icons.verified_rounded,
                              title: 'All caught up!',
                              subtitle: 'No pending dealer applications',
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppTheme.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _dealers.length,
                                itemBuilder: (context, index) =>
                                    _dealerCard(_dealers[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dealerCard(dynamic dealer) {
    final name =
        '${dealer['first_name'] ?? ''} ${dealer['last_name'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminUserAvatar(
                photoUrl: dealer['profile_photo'],
                name: name.isEmpty ? dealer['username'] : name,
                radius: 24,
                tint: AppTheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '@${dealer['username']}' : name,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text('@${dealer['username'] ?? ''}',
                        style: AdminTheme.smallMuted()),
                  ],
                ),
              ),
              AdminPill(
                label: 'Pending',
                color: AppTheme.warning,
                icon: Icons.hourglass_top_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.storefront_rounded,
              '${dealer['first_name'] ?? ''} ${dealer['last_name'] ?? ''}'.trim()),
          _infoRow(Icons.phone_rounded, dealer['phone_number'] ?? '—'),
          _infoRow(Icons.email_rounded, dealer['email'] ?? '—'),
          _infoRow(
              Icons.calendar_today_rounded,
              _short(dealer['date_joined']?.toString()),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _decide(dealer, false),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.error),
                  label: const Text('Reject',
                      style: TextStyle(color: AppTheme.error)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: AppTheme.error.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _decide(dealer, true),
                  icon: const Icon(Icons.check_rounded,
                      size: 16, color: Colors.white),
                  label: const Text('Approve',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _short(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value.length > 10 ? value.substring(0, 10) : value;
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
