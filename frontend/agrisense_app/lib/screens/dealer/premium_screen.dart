import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'dealer_widgets.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isUpgrading = false;
  int _selectedMonths = 1;
  final TextEditingController _phoneController = TextEditingController();

  /// Must match the backend PREMIUM_PRICE_PER_MONTH (FCFA).
  static const double premiumPricePerMonth = 1000;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleUpgrade() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null || user.id == null) return;

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your mobile money number to pay for premium'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isUpgrading = true);
    try {
      final api = ApiService();
      // Creates a premium payment (payment_required) — premium activates only
      // once the mobile-money payment completes.
      final result = await api.upgradePremium(
        user.id!,
        durationMonths: _selectedMonths,
        phoneNumber: phone,
      );
      final paymentId = result['payment_id'];

      if (paymentId == null) {
        // Admin grant or already active.
        await context.read<AuthProvider>().loadCurrentUser();
        if (mounted) _showResult('Premium is active!', isSuccess: true);
        return;
      }

      final payment = await api.processPayment(paymentId);
      if (payment['status'] == 'completed') {
        await context.read<AuthProvider>().loadCurrentUser();
        if (mounted) {
          _showResult(
              'Premium activated! Your products now rank higher.',
              isSuccess: true);
        }
      } else {
        if (mounted) {
          _showResult(
            'Payment ${payment['status'] ?? 'failed'}. Check your mobile '
            'money number and try again.',
            isSuccess: false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upgrade failed: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isUpgrading = false);
    }
  }

  void _showResult(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (isSuccess) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    final isPremium = user?.isPremiumActive == true;
    final total = (premiumPricePerMonth * _selectedMonths).toInt();

    return Scaffold(
      backgroundColor: DealerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DealerHeader(
              title: 'Premium',
              subtitle: isPremium
                  ? 'Your products rank higher in the marketplace'
                  : 'Grow faster with premium visibility',
              showBack: true,
              leading: const Icon(Icons.star_rounded,
                  color: Colors.white, size: 22),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Hero card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFFFA726),
                          Color(0xFFFF6F00),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: DealerTheme.sun.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded,
                                  size: 13, color: DealerTheme.sun),
                              SizedBox(width: 4),
                              Text(
                                'PREMIUM DEALER',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFE65100)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Grow Faster with Premium',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '3x more visibility in the marketplace',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          _heroStat(Icons.visibility_rounded, '2.4k', 'Views'),
                          const SizedBox(width: 10),
                          _heroStat(Icons.touch_app_rounded, '186', 'Clicks'),
                          const SizedBox(width: 10),
                          _heroStat(
                              Icons.thumb_up_rounded, '94%', 'Positive'),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ── Benefits ──
                  DealerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Premium Benefits',
                            style: DealerTheme.sectionTitle()),
                        const SizedBox(height: 12),
                        _benefit(Icons.push_pin_rounded, 'Featured at the top '
                            'of search results'),
                        _benefit(Icons.analytics_rounded,
                            'Analytics on views & clicks'),
                        _benefit(Icons.verified_rounded,
                            'Verified badge on your store'),
                        _benefit(Icons.support_agent_rounded,
                            'Priority customer support'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ── Duration selection ──
                  DealerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select Duration',
                            style: DealerTheme.sectionTitle()),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _durationChip(
                                1, '1 Month', '${(premiumPricePerMonth * 1).toInt()}'),
                            const SizedBox(width: 8),
                            _durationChip(
                                3, '3 Months', '${(premiumPricePerMonth * 3).toInt()}'),
                            const SizedBox(width: 8),
                            _durationChip(
                                6, '6 Months', '${(premiumPricePerMonth * 6).toInt()}'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: 'Mobile money number',
                            hintText: 'e.g. +237 6XX XX XX XX',
                            prefixIcon:
                                const Icon(Icons.phone_android_rounded, size: 18),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Premium activates instantly after payment is confirmed.',
                          style: TextStyle(
                              color: AppTheme.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ── Summary + CTA ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFE082)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(
                                '$total FCFA',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w800, fontSize: 19),
                              ),
                              Text(
                                _selectedMonths == 1
                                    ? '/month'
                                    : '/${_selectedMonths} months',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12),
                              ),
                            ]),
                            Text('${premiumPricePerMonth.toInt()} FCFA per month',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11.5)),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _isUpgrading ? null : _handleUpgrade,
                          icon: _isUpgrading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.star_rounded,
                                  color: Colors.white, size: 18),
                          label: Text(
                            _isUpgrading ? 'Processing...' : 'Upgrade Now',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontSize: 12.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E241E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _benefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: AppTheme.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _durationChip(int months, String label, String price) {
    final isSelected = _selectedMonths == months;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMonths = months),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primary : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          isSelected ? Colors.white : Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text('$price FCFA',
                  style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
