import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../farmer/farmer_widgets.dart';

/// Farmer order history: track purchases and deliveries with live status.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ApiService();
      final response = await api.getOrders();
      if (mounted) {
        setState(() {
          _orders = response is List ? response : [];
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

  List<dynamic> get _filtered => _statusFilter == 'all'
      ? _orders
      : _orders.where((o) => o['status'] == _statusFilter).toList();

  Color _statusColor(String status) {
    return switch (status) {
      'pending' => AppTheme.warning,
      'confirmed' => AppTheme.info,
      'shipped' => AppTheme.primary,
      'delivered' => AppTheme.success,
      'cancelled' => AppTheme.error,
      _ => AppTheme.textMuted,
    };
  }

  IconData _statusIcon(String status) {
    return switch (status) {
      'pending' => Icons.hourglass_empty_rounded,
      'confirmed' => Icons.check_circle_outline_rounded,
      'shipped' => Icons.local_shipping_rounded,
      'delivered' => Icons.check_circle_rounded,
      'cancelled' => Icons.cancel_rounded,
      _ => Icons.receipt_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = _orders
        .where((o) =>
            o['status'] == 'pending' ||
            o['status'] == 'confirmed' ||
            o['status'] == 'shipped')
        .length;
    final delivered =
        _orders.where((o) => o['status'] == 'delivered').length;

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FarmerHeader(
              title: 'My Orders',
              subtitle: 'Track your purchases & deliveries',
              showBack: true,
              leading: const Icon(Icons.receipt_long_rounded,
                  color: Colors.white, size: 22),
              trailing: [
                IconButton(
                  onPressed: _loadOrders,
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            // Stats row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  _countChip('${_orders.length}', 'Total', AppTheme.primary),
                  const SizedBox(width: 10),
                  _countChip('$active', 'Active', AppTheme.info),
                  const SizedBox(width: 10),
                  _countChip('$delivered', 'Delivered', AppTheme.success),
                ],
              ),
            ),
            // Status filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'All', 'Pending', 'Confirmed', 'Shipped', 'Delivered',
                    'Cancelled'
                  ].map((t) {
                    final f = t.toLowerCase();
                    final selected = _statusFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _statusFilter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  selected ? AppTheme.primary : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? FarmerErrorState(
                          message: _error!, onRetry: _loadOrders)
                      : _filtered.isEmpty
                          ? FarmerEmptyState(
                              icon: Icons.receipt_long_outlined,
                              title: _orders.isEmpty
                                  ? 'No orders yet'
                                  : 'No orders in this status',
                              subtitle: _orders.isEmpty
                                  ? 'Products you buy will appear here'
                                  : 'Try a different status filter.',
                            )
                          : RefreshIndicator(
                              onRefresh: _loadOrders,
                              color: AppTheme.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 8, 20, 24),
                                itemCount: _filtered.length,
                                itemBuilder: (context, index) =>
                                    _buildOrderCard(_filtered[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800, fontSize: 17, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final status = order['status'] ?? 'pending';
    final statusColor = _statusColor(status);
    final paymentStatus = order['payment_status'] ?? 'unpaid';
    final paid = paymentStatus == 'paid' || paymentStatus == 'completed';
    final total = order['total_price'] ?? 0;
    final productName = order['product_name'] ?? 'Product';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: FarmerTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Order #${order['id']}',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              FarmerPill(
                label: status,
                color: statusColor,
                icon: _statusIcon(status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FarmerProductThumb(
                imageUrl: order['product_image'],
                size: 52,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(productName,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                            color: AppTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.shopping_cart_rounded,
                          size: 12, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text('Qty: ${order['quantity']}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ]),
                  ],
                ),
              ),
              Text(
                '$total FCFA',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(
                  paid ? Icons.check_circle_rounded : Icons.pending_rounded,
                  size: 14,
                  color: paid ? AppTheme.success : AppTheme.warning,
                ),
                const SizedBox(width: 4),
                Text(
                  'Payment: $paymentStatus',
                  style: TextStyle(
                    fontSize: 11,
                    color: paid ? AppTheme.success : AppTheme.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
              Row(children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 12, color: AppTheme.textMuted),
                const SizedBox(width: 4),
                Text(_dateLabel(order['created_at']),
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  String _dateLabel(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) return '';
    return DateFormat('d MMM yyyy').format(date);
  }
}
