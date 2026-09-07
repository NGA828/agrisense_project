import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api/api_service.dart';

class PaymentScreen extends StatefulWidget {
  final int? orderId;
  final int? productId;
  final int? paymentId;
  final String? paymentStatus;
  final ApiService? api;
  final String productName;
  final String unitPrice;
  final int quantity;

  /// Server-computed order total (from the `createOrder` response). When
  /// present this is the authoritative amount the backend will accept;
  /// otherwise the screen falls back to unitPrice × quantity.
  final double? totalAmount;

  const PaymentScreen({
    super.key,
    this.orderId,
    this.productId,
    this.paymentId,
    this.paymentStatus,
    this.api,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.totalAmount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin {
  String _selectedPayment = 'mtn';
  bool _isProcessing = false;
  bool _loadingMethods = true;
  bool _successShown = false;
  String? _methodsError;
  String? _paymentMessage;
  String _paymentState = 'not_started';
  int? _orderId;
  int? _paymentId;
  double? _serverTotal;
  late final ApiService _api;
  late final String _checkoutKey;
  Map<String, Map<String, dynamic>> _methods = {};

  bool get _hasAttempt => _paymentId != null;
  String get _methodId => _selectedPayment == 'orange' ? 'ORANGE_MONEY' : 'MTN_MOMO';
  bool get _methodAvailable => _methods[_methodId]?['available'] == true;
  bool get _canPay => !_isProcessing && (_hasAttempt ||
      (!_loadingMethods && _methodAvailable && (widget.productId != null || _orderId != null)));
  final TextEditingController _phoneController = TextEditingController();
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiService();
    _orderId = widget.orderId;
    _paymentId = widget.paymentId;
    _paymentState = widget.paymentStatus ?? 'not_started';
    _serverTotal = widget.totalAmount;
    _checkoutKey = _newCheckoutKey();
    _loadMethods();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  static String _newCheckoutKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _loadMethods() async {
    setState(() { _loadingMethods = true; _methodsError = null; });
    try {
      final response = await _api.getPaymentMethods();
      if (!mounted) return;
      final methods = <String, Map<String, dynamic>>{};
      for (final item in (response['methods'] as List? ?? [])) {
        final method = Map<String, dynamic>.from(item as Map);
        methods[method['id'].toString()] = method;
      }
      setState(() {
        _methods = methods;
        if (!_methodAvailable && methods['ORANGE_MONEY']?['available'] == true) {
          _selectedPayment = 'orange';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _methodsError = 'Could not load payment options. Check your connection.');
    } finally {
      if (mounted) setState(() => _loadingMethods = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // Local theme fallback colors
  Color get _primaryColor => const Color(0xFF2E7D32); // Forest Green
  Color get _mtnYellow => const Color(0xFFFFC107); // MTN MoMo Yellow
  Color get _orangeMoney => const Color(0xFFFF5722); // Orange Money Orange
  Color get _successColor => const Color(0xFF4CAF50);

  /// Amount to charge: the server-computed order total when the order was
  /// created online (authoritative — the backend rejects any other amount),
  /// otherwise unitPrice × quantity is an estimate until the server reserves it.
  double get _orderTotal {
    final serverTotal = _serverTotal;
    if (serverTotal != null) return serverTotal;
    final money = widget.unitPrice.replaceAll(RegExp(r'[,\s]'), '');
    final unit = double.tryParse(money) ?? 0;
    return unit * widget.quantity;
  }

  /// Keep the amount shown to the farmer identical to the amount requested.
  String _formatAmount(double value) {
    final parts = value.toStringAsFixed(value == value.truncateToDouble() ? 0 : 2).split('.');
    final grouped = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return parts.length == 1 ? grouped : '$grouped.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    // Formatting variables
    final total = _orderTotal;
    final totalFormatted = _formatAmount(total);

    // Dynamic button styling depending on active choice
    Color buttonColor;
    Color buttonTextColor;
    if (_selectedPayment == 'mtn') {
      buttonColor = _mtnYellow;
      buttonTextColor = Colors.black;
    } else if (_selectedPayment == 'orange') {
      buttonColor = _orangeMoney;
      buttonTextColor = Colors.white;
    } else {
      buttonColor = _primaryColor;
      buttonTextColor = Colors.white;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAF9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Secure Header Section
            _buildSecureHeader(),

            // 2. Main Scrollable Payment Area
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // A. Order Summary Card (Fintech Theme)
                    _buildOrderSummaryCard(totalFormatted),
                    const SizedBox(height: 16),

                    // B. Delivery Address Details
                    _buildDeliveryAddressCard(),
                    const SizedBox(height: 16),

                    // C. Interactive Payment Methods Card
                    _buildPaymentMethodsCard(),
                    const SizedBox(height: 24),

                    if (_paymentMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(_paymentMessage!),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // D. Primary Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canPay ? _processPayment : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonColor,
                          foregroundColor: buttonTextColor,
                          disabledBackgroundColor:
                              buttonColor.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                          shadowColor: buttonColor.withValues(alpha: 0.3),
                        ),
                        child: _isProcessing
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: buttonTextColor,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.lock_outline_rounded,
                                      size: 18, color: buttonTextColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    _hasAttempt ? 'Check payment status' : 'Pay: $totalFormatted FCFA',
                                    style: GoogleFonts.poppins(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.bold,
                                      color: buttonTextColor,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Secure SSL Notice
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_outlined,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(
                          'SSL Secure Connection • 256-bit Encryption',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  // Secure customized Header UI
  Widget _buildSecureHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: Color(0xFF1E241E)),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Checkout Portal',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: const Color(0xFF1E241E),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _successColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'AgriSense Secure Gateway',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF555F55),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, color: _successColor, size: 14),
                const SizedBox(width: 4),
                Text(
                  'ENCRYPTED',
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: _successColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Premium Fintech styled Summary Card
  Widget _buildOrderSummaryCard(String totalFormatted) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.receipt_long_rounded,
                    size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 10),
              Text(
                'Order Details',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: const Color(0xFF1E241E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Detail Row
          _buildSummaryRow(widget.productName, '${_formatAmount(_orderTotal / widget.quantity)} FCFA / unit'),
          _buildSummaryRow('Quantity Ordered', 'x${widget.quantity}'),

          // Dashed Separator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: List.generate(
                30,
                (index) => Expanded(
                  child: Container(
                    color: index % 2 == 0
                        ? Colors.grey.shade200
                        : Colors.transparent,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Grand Total Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total:',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                  color: const Color(0xFF1E241E),
                ),
              ),
              Text(
                '$totalFormatted FCFA',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  color: _primaryColor,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Shipping Info Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _successColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping_rounded,
                    size: 12, color: _successColor),
                const SizedBox(width: 6),
                Text(
                  'Delivery Dispatch: Fast & Free',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: _successColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Delivery Address section
  Widget _buildDeliveryAddressCard() => _buildCard(
    child: const Row(children: [
      Icon(Icons.local_shipping_outlined), SizedBox(width: 12),
      Expanded(child: Text('Arrange delivery with the dealer. The dealer receives '
          'your order only after payment is confirmed.')),
    ]),
  );

  Widget _buildPaymentMethodsCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payment_rounded,
                    size: 18, color: Colors.orange),
              ),
              const SizedBox(width: 10),
              Text(
                'Select Payment Option',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: const Color(0xFF1E241E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // MTN MoMo
          _buildPaymentOption(
            id: 'mtn',
            title: 'MTN Mobile Money',
            subtitle: _methods['MTN_MOMO']?['message']?.toString() ?? 'Checking availability…',
            bgColor: const Color(0xFFFFFDE7),
            textColor: Colors.black,
            icon: Icons.phone_android_rounded,
            accentColor: _mtnYellow,
          ),
          const SizedBox(height: 10),

          // Orange Money
          _buildPaymentOption(
            id: 'orange',
            title: 'Orange Money',
            subtitle: _methods['ORANGE_MONEY']?['message']?.toString() ?? 'Not available',
            bgColor: const Color(0xFFFBE9E7),
            textColor: Colors.black,
            icon: Icons.phonelink_ring_rounded,
            accentColor: _orangeMoney,
          ),
          const SizedBox(height: 10),

          if (_loadingMethods) const LinearProgressIndicator(),
          if (_methodsError != null) ...[
            Text(_methodsError!),
            TextButton(onPressed: _isProcessing ? null : _loadMethods,
                child: const Text('Reload payment options')),
          ],
          if (!_hasAttempt) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              enabled: !_isProcessing && !_hasAttempt,
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
            const SizedBox(height: 4),
            Text(
              'Approve the collection on your phone. Never share your MoMo PIN.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // Generalized Card Layout wrapper
  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECECEC), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF6B7A6B),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF1E241E),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Interactive option widget with subtle scale animations
  Widget _buildPaymentOption({
    required String id,
    required String title,
    required String subtitle,
    required Color bgColor,
    required Color textColor,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _selectedPayment == id;
    final method = id == 'orange' ? 'ORANGE_MONEY' : 'MTN_MOMO';
    final enabled = !_isProcessing && !_hasAttempt && _methods[method]?['available'] == true;

    return GestureDetector(
      onTap: enabled ? () => setState(() => _selectedPayment = id) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : Colors.grey.shade200,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            // Styled Wallet Icon Base
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : const Color(0xFFF4F6F4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.3)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                color: isSelected ? accentColor : const Color(0xFF6B7A6B),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),

            // Text Block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: isSelected ? accentColor : const Color(0xFF1E241E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.grey.shade800
                          : const Color(0xFF757575),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Circular Radial Check Box Indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? accentColor : Colors.grey.shade300,
                  width: isSelected ? 6.5 : 1.5,
                ),
              ),
              child: isSelected
                  ? Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // Reserve/create only when the user actually presses Pay. A lost response
  // is retried with the same checkout token/attempt, never a second charge.
  Future<void> _processPayment() async {
    if (_isProcessing) return;
    if (!_hasAttempt && widget.productId == null && _orderId == null) {
      setState(() => _paymentMessage = 'This product is offline. Connect to the marketplace before paying.');
      return;
    }
    final phone = _phoneController.text.trim();
    if (!_hasAttempt && (phone.isEmpty || !_methodAvailable)) {
      setState(() => _paymentMessage = 'Choose an available payment method and enter your mobile money number.');
      return;
    }
    if (!_hasAttempt) {
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^00'), '');
      final valid = RegExp(r'^(?:237)?6[0-9]{8}$').hasMatch(digits) ||
          (_methods[_methodId]?['environment'] == 'sandbox' && RegExp(r'^4673312345[0-4]$').hasMatch(digits));
      if (!valid) {
        setState(() => _paymentMessage = 'Enter a valid Cameroon mobile number, for example +237 6XX XX XX XX.');
        return;
      }
    }
    setState(() { _isProcessing = true; _paymentMessage = null; });
    try {
      Map<String, dynamic> result;
      if (_hasAttempt) {
        result = await _api.verifyPayment(_paymentId!);
        if (!mounted) return;
        if (result['status'] == 'pending') {
          result = await _api.processPayment(_paymentId!, expectedAmount: _orderTotal);
        }
      } else {
        if (_orderId == null) {
          final displayedTotal = _orderTotal;
          final order = await _api.createOrder(widget.productId!, widget.quantity,
              checkoutKey: _checkoutKey, paymentMethod: _methodId);
          _orderId = order['id'] as int;
          _serverTotal = double.tryParse(order['total_price'].toString());
          if (_serverTotal == null || !_serverTotal!.isFinite || _serverTotal! <= 0) {
            throw ApiException('The server returned an invalid order amount. Contact support.');
          }
          if ((_serverTotal! - displayedTotal).abs() > 0.005) {
            if (mounted) setState(() => _paymentMessage = 'The current total is '
                '${_formatAmount(_serverTotal!)} FCFA. Review the updated price and '
                'press Pay again to confirm. No payment request has been sent.');
            return;
          }
        }
        if (!mounted) return;
        final payment = await _api.createPayment(_orderId!, _methodId, phone, _orderTotal);
        _paymentId = payment['id'] as int;
        _paymentState = payment['status']?.toString() ?? 'pending';
        if (!mounted) return;
        // Mark as unresolved locally BEFORE awaiting the external collection.
        result = _paymentState == 'pending'
            ? await _api.processPayment(_paymentId!, expectedAmount: _orderTotal) : payment;
      }
      if (!mounted) return;
      _applyPaymentResult(result);
      for (var attempt = 0; attempt < 10 && _paymentState == 'processing'; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        result = await _api.verifyPayment(_paymentId!);
        if (!mounted) return;
        _applyPaymentResult(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _paymentMessage = e is ApiException && e.code == 'invalid_payment_transition'
            ? e.message
            : _hasAttempt
            ? 'Confirmation is not available yet. Use Check payment status; do not '
                'pay again. You can also return here from My Orders.'
            : e is ApiException ? e.message
            : 'Could not connect to checkout. No payment was confirmed. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _applyPaymentResult(Map<String, dynamic> result) {
    final state = result['status']?.toString() ?? 'processing';
    setState(() {
      _paymentState = state;
      _paymentMessage = result['message']?.toString() ?? result['last_error']?.toString();
      if (_paymentMessage == null || _paymentMessage!.isEmpty) {
        _paymentMessage = state == 'processing'
            ? 'Approve on your phone. Awaiting confirmation; do not pay again.'
            : state == 'review_required'
                ? 'Funds received, but this order needs support review. Do not pay again.'
                : 'Payment status: $state';
      }
      if (state == 'failed') _paymentId = null; // definitive rejection only
    });
    if (state == 'completed' && !_successShown) {
      _successShown = true;
      _showSuccessDialog();
    }
  }

  // High-end Checkout Success Modal Dialog sheet
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Scales custom animated double-border check circle
              Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _successColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: _successColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title Header
              Text(
                'Payment Confirmed!',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: const Color(0xFF1E241E),
                ),
              ),
              const SizedBox(height: 8),

              // Sub-summary info
              Text(
                'Your payment is confirmed and the dealer has received your order. Track it in My Orders.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.45,
                  color: const Color(0xFF555F55),
                ),
              ),
              const SizedBox(height: 24),

              // Continue Shopping Primary Call to Action button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navigate cleanly back to local marketplace catalog
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.shopping_bag_rounded,
                      color: Colors.white, size: 18),
                  label: Text(
                    'Continue Shopping',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
