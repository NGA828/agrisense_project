import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../services/api/api_service.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<dynamic> _orders = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadOrders(); }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.getOrders();
      setState(() { _orders = response is List ? response : []; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20)),
                const Icon(Icons.receipt_long_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('My Orders', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _orders.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300), const SizedBox(height: 12), Text('No orders yet', style: AppTheme.bodyMedium), const SizedBox(height: 8), Text('Your orders will appear here', style: AppTheme.bodySmall)]))
                      : RefreshIndicator(
                          onRefresh: _loadOrders,
                          child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _orders.length, itemBuilder: (context, index) => _buildOrderCard(_orders[index])),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final statusColor = {'pending': AppTheme.warning, 'confirmed': AppTheme.info, 'shipped': AppTheme.primary, 'delivered': AppTheme.success, 'cancelled': AppTheme.error}[order.status] ?? AppTheme.textMuted;
    final statusIcon = {'pending': Icons.hourglass_empty_rounded, 'confirmed': Icons.check_circle_outline_rounded, 'shipped': Icons.local_shipping_rounded, 'delivered': Icons.check_circle_rounded, 'cancelled': Icons.cancel_rounded}[order.status] ?? Icons.receipt_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Order #${order.id}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(statusIcon, size: 14, color: statusColor), const SizedBox(width: 4), Text(order.status.toUpperCase(), style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w700))]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: AppTheme.bgLight, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 24)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(order.productName ?? 'Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 4), Row(children: [const Icon(Icons.shopping_cart_rounded, size: 12, color: AppTheme.textMuted), const SizedBox(width: 4), Text('Qty: ${order.quantity}', style: AppTheme.bodySmall)])])),
            Text('${order.totalPrice} Fcfa', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppTheme.primary)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Icon(order.paymentStatus == 'paid' ? Icons.check_circle_rounded : Icons.pending_rounded, size: 14, color: order.paymentStatus == 'paid' ? AppTheme.success : AppTheme.warning),
              const SizedBox(width: 4),
              Text('Payment: ${order.paymentStatus ?? "unpaid"}', style: TextStyle(fontSize: 11, color: order.paymentStatus == 'paid' ? AppTheme.success : AppTheme.warning, fontWeight: FontWeight.w600)),
            ]),
            Row(children: [const Icon(Icons.calendar_today_rounded, size: 12, color: AppTheme.textMuted), const SizedBox(width: 4), Text(order.createdAt?.toString()?.substring(0, 10) ?? '', style: AppTheme.bodySmall)]),
          ]),
        ],
      ),
    );
  }
}
