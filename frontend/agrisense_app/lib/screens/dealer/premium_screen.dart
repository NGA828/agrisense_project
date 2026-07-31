import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';

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
        if (mounted) _showResult('Premium activated! Your products now rank higher.', isSuccess: true);
      } else {
        if (mounted) {
          _showResult(
            'Payment ${payment['status'] ?? 'failed'}. Check your mobile money number and try again.',
            isSuccess: false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upgrade failed: $e'), backgroundColor: AppTheme.error),
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
      ),
    );
    if (isSuccess) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20)),
                const Icon(Icons.star_rounded, color: AppTheme.accent, size: 20),
                const SizedBox(width: 8),
                Text('Premium Analytics', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.primary, AppTheme.primaryDark]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(12)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star, size: 12, color: Colors.black87), SizedBox(width: 4), Text('PREMIUM DEALER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black87))]),
                          ),
                          const SizedBox(height: 12),
                          Text('Grow Faster with Premium', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                          Text('3x more visibility', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                          const SizedBox(height: 16),
                          Row(children: [
                            _buildStat(Icons.visibility_rounded, '2.4k', 'Views'),
                            const SizedBox(width: 12),
                            _buildStat(Icons.touch_app_rounded, '186', 'Clicks'),
                            const SizedBox(width: 12),
                            _buildStat(Icons.thumb_up_rounded, '94%', 'Positive'),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.cardDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Premium Benefits', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 12),
                          _buildBenefit(Icons.push_pin_rounded, 'Featured Top'),
                          _buildBenefit(Icons.chat_rounded, 'Chat Priority'),
                          _buildBenefit(Icons.analytics_rounded, 'Analytics'),
                          _buildBenefit(Icons.verified_rounded, 'Verified Badge'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.cardDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select Duration', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildDurationChip(1, '1 Month', '${(premiumPricePerMonth * 1).toInt()}'),
                              const SizedBox(width: 8),
                              _buildDurationChip(3, '3 Months', '${(premiumPricePerMonth * 3).toInt()}'),
                              const SizedBox(width: 8),
                              _buildDurationChip(6, '6 Months', '${(premiumPricePerMonth * 6).toInt()}'),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'Mobile money number',
                              hintText: 'e.g. +237 6XX XX XX XX',
                              prefixIcon: const Icon(Icons.phone_android_rounded, size: 18),
                              filled: true,
                              fillColor: const Color(0xFFFAFAFA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Premium activates instantly after payment is confirmed.',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFFFFFDE7), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.accentSoft)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [Text('${(premiumPricePerMonth * _selectedMonths).toInt()} Fcfa', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)), Text('/${_selectedMonths == 1 ? 'mo' : '${_selectedMonths} months'}', style: AppTheme.bodySmall)]),
                            Text('${premiumPricePerMonth.toInt()} Fcfa per month', style: AppTheme.bodySmall),
                          ]),
                          ElevatedButton.icon(
                            onPressed: _isUpgrading ? null : _handleUpgrade,
                            icon: _isUpgrading 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.star_rounded, color: Colors.white),
                            label: Text(_isUpgrading ? 'Processing...' : 'Upgrade Now', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Icon(icon, size: 16, color: AppTheme.success), const SizedBox(width: 8), Text(text, style: AppTheme.bodyMedium.copyWith(fontSize: 13))]),
    );
  }

  Widget _buildDurationChip(int months, String label, String price) {
    final isSelected = _selectedMonths == months;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMonths = months),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppTheme.primary : Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text('$price Fcfa', style: TextStyle(fontSize: 11, color: isSelected ? Colors.white.withValues(alpha: 0.9) : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
