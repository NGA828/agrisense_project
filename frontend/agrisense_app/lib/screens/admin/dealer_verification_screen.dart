import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Admin moderation queue: approve or reject pending dealer applications.
class DealerVerificationScreen extends StatefulWidget {
  const DealerVerificationScreen({super.key});

  @override
  State<DealerVerificationScreen> createState() => _DealerVerificationScreenState();
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
      if (mounted) setState(() {
        _dealers = dealers;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
          ),
        );
        setState(() => _dealers.removeWhere((d) => d['id'] == dealer['id']));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e'), backgroundColor: AppTheme.error),
        );
      }
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
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
                      Text('Dealer Verification',
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${_dealers.length} application(s) awaiting review',
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(_error!, style: AppTheme.bodySmall, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _dealers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.verified_rounded, size: 64, color: Colors.green.shade200),
                                  const SizedBox(height: 12),
                                  Text('All caught up!', style: AppTheme.titleMedium),
                                  const SizedBox(height: 4),
                                  Text('No pending dealer applications',
                                      style: TextStyle(color: AppTheme.textMuted)),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppTheme.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _dealers.length,
                                itemBuilder: (context, index) => _dealerCard(_dealers[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dealerCard(dynamic dealer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.store_rounded, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${dealer['first_name'] ?? ''} ${dealer['last_name'] ?? ''}',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text('@${dealer['username'] ?? ''}',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.hourglass_top_rounded, size: 12, color: AppTheme.warning),
                  const SizedBox(width: 4),
                  Text('PENDING', style: TextStyle(fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.phone_rounded, dealer['phone_number'] ?? '—'),
          _infoRow(Icons.email_rounded, dealer['email'] ?? '—'),
          _infoRow(Icons.calendar_today_rounded,
              dealer['date_joined']?.toString().substring(0, 10) ?? '—'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _decide(dealer, false),
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.error),
                  label: const Text('Reject', style: TextStyle(color: AppTheme.error)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.error.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _decide(dealer, true),
                  icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  label: const Text('Approve', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
