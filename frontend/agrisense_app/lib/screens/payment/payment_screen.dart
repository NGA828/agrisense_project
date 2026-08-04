import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api/api_service.dart';

class PaymentScreen extends StatefulWidget {
  final int? orderId;
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
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    this.totalAmount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> with SingleTickerProviderStateMixin {
  String _selectedPayment = 'mtn';
  bool _isProcessing = false;
  final TextEditingController _phoneController = TextEditingController();
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // Local theme fallback colors
  Color get _primaryColor => const Color(0xFF2E7D32); // Forest Green
  Color get _mtnYellow => const Color(0xFFFFC107);    // MTN MoMo Yellow
  Color get _orangeMoney => const Color(0xFFFF5722);  // Orange Money Orange
  Color get _creditCardColor => const Color(0xFF1E241E); // Slate / Charcoal
  Color get _successColor => const Color(0xFF4CAF50);

  /// Amount to charge: the server-computed order total when the order was
  /// created online (authoritative — the backend rejects any other amount),
  /// otherwise unitPrice × quantity as an offline fallback.
  double get _orderTotal {
    final serverTotal = widget.totalAmount;
    if (serverTotal != null) return serverTotal;
    final money = widget.unitPrice.replaceAll(RegExp(r'[,\s]'), '');
    final unit = double.tryParse(money) ?? 0;
    return unit * widget.quantity;
  }

  /// Format a numeric FCFA amount as a whole number with thousands separators.
  String _formatAmount(double value) {
    final whole = value.round().toString();
    return whole.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Formatting variables
    final unitPrice = int.tryParse(widget.unitPrice.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // A. Order Summary Card (Fintech Theme)
                    _buildOrderSummaryCard(unitPrice, totalFormatted),
                    const SizedBox(height: 16),

                    // B. Delivery Address Details
                    _buildDeliveryAddressCard(),
                    const SizedBox(height: 16),

                    // C. Interactive Payment Methods Card
                    _buildPaymentMethodsCard(),
                    const SizedBox(height: 24),

                    // D. Primary Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _processPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonColor,
                          foregroundColor: buttonTextColor,
                          disabledBackgroundColor: buttonColor.withValues(alpha: 0.5),
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
                                  Icon(Icons.lock_outline_rounded, size: 18, color: buttonTextColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Secure Pay: $totalFormatted FCFA',
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
                        Icon(Icons.verified_user_outlined, size: 14, color: Colors.grey.shade600),
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF1E241E)),
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
  Widget _buildOrderSummaryCard(int unitPrice, String totalFormatted) {
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
                child: Icon(Icons.receipt_long_rounded, size: 18, color: _primaryColor),
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
          _buildSummaryRow(widget.productName, '${widget.unitPrice} FCFA'),
          _buildSummaryRow('Quantity Ordered', 'x${widget.quantity}'),

          // Dashed Separator
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: List.generate(
                30,
                (index) => Expanded(
                  child: Container(
                    color: index % 2 == 0 ? Colors.grey.shade200 : Colors.transparent,
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
                Icon(Icons.local_shipping_rounded, size: 12, color: _successColor),
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
  Widget _buildDeliveryAddressCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.location_on_rounded, size: 18, color: Colors.blue),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Delivery Location',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: const Color(0xFF1E241E),
                    ),
                  ),
                ],
              ),
              Text(
                'Change',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Rue 1.056, Quartier Bastos, Yaoundé, Cameroon',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF555F55),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // Interactive Payment Options Builder
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
                child: const Icon(Icons.payment_rounded, size: 18, color: Colors.orange),
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
            subtitle: 'Pay instantly via MoMo Wallet',
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
            subtitle: 'Secure Orange Money checkout',
            bgColor: const Color(0xFFFBE9E7),
            textColor: Colors.black,
            icon: Icons.phonelink_ring_rounded,
            accentColor: _orangeMoney,
          ),
          const SizedBox(height: 10),

          // Visa / Credit Card
          _buildPaymentOption(
            id: 'card',
            title: 'Credit Card',
            subtitle: 'Visa • Mastercard **** 4242',
            bgColor: const Color(0xFFECEFF1),
            textColor: Colors.black,
            icon: Icons.credit_card_rounded,
            accentColor: _creditCardColor,
          ),
          if (_selectedPayment != 'card') ...[
            const SizedBox(height: 14),
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
            const SizedBox(height: 4),
            Text(
              'Payment is sent to this mobile money number',
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

    return GestureDetector(
      onTap: () => setState(() => _selectedPayment = id),
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
                  color: isSelected ? accentColor.withValues(alpha: 0.3) : Colors.transparent,
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
                      color: isSelected ? Colors.grey.shade800 : const Color(0xFF757575),
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

  // Payment execution flow
  void _processPayment() async {
    if (widget.orderId == null) {
      _showSuccessDialog();
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final api = ApiService();

      // Map dynamic naming for backend API expectations
      final apiPaymentType = _selectedPayment == 'mtn'
          ? 'MTN_MOMO'
          : _selectedPayment == 'orange'
              ? 'ORANGE_MONEY'
              : 'CARD';

      final phone = _phoneController.text.trim();
      if (apiPaymentType != 'CARD' && phone.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter your mobile money number'),
              backgroundColor: Color(0xFFC62828),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final payment = await api.createPayment(
        widget.orderId!,
        apiPaymentType,
        phone.isEmpty ? '+237600000000' : phone,
        _orderTotal,
      );

      final result = await api.processPayment(payment['id']);

      if (!mounted) return;
      if (result['status'] == 'completed') {
        _showSuccessDialog();
      } else {
        // The provider rejected or could not confirm the transaction.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payment ${result['status'] ?? 'failed'}. Please check your mobile money '
              'number and try again, or choose another payment method.',
            ),
            backgroundColor: const Color(0xFFC62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: const Color(0xFFC62828),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                'Your payment has been secure-processed. Your order will be dispatched to Bastos, Yaoundé shortly.',
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
                  icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 18),
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
