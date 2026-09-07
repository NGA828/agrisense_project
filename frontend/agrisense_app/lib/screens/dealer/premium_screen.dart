import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'dealer_widgets.dart';

class PremiumScreen extends StatefulWidget {
  final ApiService? api;
  const PremiumScreen({super.key, this.api});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isUpgrading = false;
  int? _paymentId;
  int _selectedMonths = 1;
  bool _loadingMethod = true;
  bool _isTestPayment = false;
  bool _needsPriceConfirmation = false;
  String? _methodError;
  Map<String, dynamic> _method = {};
  late final ApiService _api;
  bool get _canSubmit => !_isUpgrading && (_paymentId != null ||
      (!_loadingMethod && _methodError == null && _method['available'] == true));
  final TextEditingController _phoneController = TextEditingController();

  double premiumPricePerMonth = 1000;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiService();
    _loadMethod();
  }

  Future<void> _loadMethod() async {
    setState(() { _loadingMethod = true; _methodError = null; });
    try {
      final response = await _api.getPaymentMethods();
      final price = double.tryParse('${response['premium_price_per_month']}');
      if (price == null || !price.isFinite || price <= 0) {
        throw ApiException('Premium pricing is unavailable. Ask the administrator to check the backend.');
      }
      Map<String, dynamic> method = {};
      for (final item in (response['methods'] as List? ?? [])) {
        if ((item as Map)['id'] == 'MTN_MOMO') method = Map<String, dynamic>.from(item);
      }
      if (!mounted) return;
      setState(() {
        _method = method;
        if (_paymentId == null) {
          premiumPricePerMonth = price;
          _isTestPayment = method['is_test'] == true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _methodError = 'Could not load premium payment options and pricing. Try again.');
    } finally {
      if (mounted) setState(() => _loadingMethod = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleUpgrade() async {
    if (!_canSubmit) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user?.id == null) return;
    final phone = _phoneController.text.trim();
    if (_paymentId == null && phone.isEmpty) {
      _showResult('Enter your mobile money number.', isSuccess: false);
      return;
    }
    setState(() => _isUpgrading = true);
    try {
      Map<String, dynamic> payment;
      if (_paymentId != null) {
        payment = await _api.verifyPayment(_paymentId!);
        if (!mounted) return;
        if (payment['status'] == 'pending') {
          final amount = double.tryParse('${payment['amount']}');
          if (amount == null || !amount.isFinite || amount <= 0) {
            throw ApiException('Could not verify the premium price.');
          }
          if ((amount - premiumPricePerMonth * _selectedMonths).abs() > 0.005) {
            setState(() {
              _selectedMonths = (payment['duration_months'] as num?)?.toInt() ?? _selectedMonths;
              premiumPricePerMonth = amount / _selectedMonths;
              _needsPriceConfirmation = true;
            });
            _showResult('The total is now $amount FCFA. Review and confirm again.', isSuccess: false);
            return;
          }
          _needsPriceConfirmation = false;
          payment = await _api.processPayment(_paymentId!,
              expectedAmount: premiumPricePerMonth * _selectedMonths);
        }
      } else {
        final displayedTotal = premiumPricePerMonth * _selectedMonths;
        final result = await _api.upgradePremium(user!.id!,
            durationMonths: _selectedMonths, phoneNumber: phone);
        _paymentId = result['payment_id'] as int?;
        if (_paymentId == null) throw ApiException('No payment reference was returned.');
        if (!mounted) return;
        final amount = double.tryParse('${result['amount']}');
        if (amount == null || !amount.isFinite || amount <= 0) {
          throw ApiException('Could not verify the premium payment amount.');
        }
        setState(() {
          _selectedMonths = (result['duration_months'] as num?)?.toInt() ?? _selectedMonths;
          premiumPricePerMonth = amount / _selectedMonths;
          _isTestPayment = result['is_test'] == true;
        });
        if (result['payment_status'] == 'pending' && (amount - displayedTotal).abs() > 0.005) {
          _needsPriceConfirmation = true;
          _showResult('The current premium total is $amount FCFA. Review the updated '
              'amount and confirm again. No payment request has been sent.', isSuccess: false);
          return;
        }
        payment = await _api.processPayment(_paymentId!,
            expectedAmount: premiumPricePerMonth * _selectedMonths);
      }
      for (var attempt = 0; attempt < 10 && payment['status'] == 'processing'; attempt++) {
        if (!mounted) return;
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        payment = await _api.verifyPayment(_paymentId!);
      }
      if (!mounted) return;
      if (payment['status'] == 'completed') {
        await context.read<AuthProvider>().loadCurrentUser();
        if (!mounted) return;
        _showResult(payment['is_test'] == true
            ? 'Test premium activation — no money was transferred.'
            : 'Premium activated!', isSuccess: true);
      } else {
        if (payment['status'] == 'failed') {
          _paymentId = null;
          _needsPriceConfirmation = false;
        }
        _showResult(payment['message']?.toString() ??
            'Awaiting confirmation. Check this payment again; do not pay twice.', isSuccess: false);
      }
    } catch (e) {
      if (mounted) _showResult(e is ApiException && e.code == 'invalid_payment_transition' ? e.message
          : _paymentId == null ? '$e'
          : 'Confirmation is unavailable. Check the same payment again; do not pay twice.',
          isSuccess: false);
    } finally {
      if (mounted) setState(() => _isUpgrading = false);
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
                          enabled: !_isUpgrading && _paymentId == null,
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
                  if (_loadingMethod)
                    const LinearProgressIndicator()
                  else if (_methodError != null || _method['available'] != true)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_methodError ?? _method['message']?.toString() ??
                          'MTN payments are not configured.',
                          style: const TextStyle(color: AppTheme.error)),
                      TextButton(onPressed: _isUpgrading ? null : _loadMethod,
                          child: const Text('Reload payment options')),
                    ])
                  else if (_isTestPayment)
                    const Padding(padding: EdgeInsets.only(bottom: 12), child: Text(
                        'TEST PAYMENT ONLY — no real money will be transferred.',
                        style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w700))),
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
                          onPressed: _canSubmit ? _handleUpgrade : null,
                          icon: _isUpgrading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.star_rounded,
                                  color: Colors.white, size: 18),
                          label: Text(
                            _isUpgrading ? 'Processing...' : _needsPriceConfirmation ? 'Confirm payment' : _paymentId != null ? 'Check payment status' : 'Upgrade Now',
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
        onTap: _isUpgrading || _paymentId != null ? null : () => setState(() => _selectedMonths = months),
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
