import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api/api_service.dart';
import 'premium_screen.dart';
import 'add_product_screen.dart';

class DealerDashboard extends StatefulWidget {
  const DealerDashboard({super.key});

  @override
  State<DealerDashboard> createState() => _DealerDashboardState();
}

class _DealerDashboardState extends State<DealerDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: IndexedStack(
        index: _selectedIndex,
        children: [const _DealerHome(), const _DealerProducts(), const _DealerOrders(), const _DealerChatList(), const _DealerProfile()],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -4))]),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_rounded, 'Dashboard'),
                _buildNavItem(1, Icons.inventory_2_rounded, 'Products'),
                _buildNavItem(2, Icons.receipt_long_rounded, 'Orders'),
                _buildNavItem(3, Icons.chat_rounded, 'Chats'),
                _buildNavItem(4, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = index == _selectedIndex;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 22, color: isSelected ? AppTheme.primary : AppTheme.textMuted),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400, color: isSelected ? AppTheme.primary : AppTheme.textMuted)),
        if (isSelected) Container(width: 20, height: 3, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
      ]),
    );
  }
}

class _DealerHome extends StatelessWidget {
  const _DealerHome();

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Green Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2D5016), Color(0xFF4A7C28), Color(0xFF6B9B37)]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [Icon(Icons.eco_rounded, color: Colors.white, size: 28), const SizedBox(width: 8), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('AgriSense AI', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)), Text('Dealer Dashboard', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11))])]),
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)),
                      child: Icon(Icons.store_rounded, color: Colors.white, size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Welcome back,', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                const SizedBox(height: 4),
                Text('${user?.firstName ?? 'Dealer'}\'s Store', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildStatCard(Icons.inventory_2_rounded, 'Products', '24', Colors.white.withOpacity(0.15), Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(Icons.receipt_long_rounded, 'Orders', '18', Colors.white.withOpacity(0.15), Colors.white)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(Icons.attach_money_rounded, 'Revenue', '245K', Colors.white.withOpacity(0.15), Colors.white)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Recent Orders
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Orders', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
                Text('View All >', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              _buildOrderItem('Urea Fertilizer 50kg', 'Jean Koffi', '25,000 FCFA', 'Pending', AppTheme.warning),
              _buildOrderItem('Pesticide - Cypermethrin', 'Adama Traore', '15,000 FCFA', 'Delivered', AppTheme.success),
              _buildOrderItem('NPK 20-10-10 50kg', 'Mariam Diallo', '27,500 FCFA', 'Completed', AppTheme.info),
            ]),
          ),
          const SizedBox(height: 20),
          // Quick Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Quick Actions', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _buildActionCard(Icons.add_circle_rounded, 'Add Product', AppTheme.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())))),
                const SizedBox(width: 12),
                Expanded(child: _buildActionCard(Icons.chat_rounded, 'Messages', AppTheme.info, () {})),
                const SizedBox(width: 12),
                Expanded(child: _buildActionCard(Icons.inventory_rounded, 'Stock', AppTheme.accent, () {})),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Premium Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFA726), Color(0xFFFF6F00)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12)]),
                      child: const Icon(Icons.star_rounded, color: AppTheme.accent, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Upgrade to Premium', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Get featured listings & analytics', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(children: [Icon(Icons.check_circle_rounded, color: Colors.white, size: 14), const SizedBox(width: 4), Text('3x More Visibility', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))]),
                    ])),
                    Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Column(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle), child: Icon(icon, color: iconColor, size: 20)),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 22)),
        Text(title, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildOrderItem(String product, String farmer, String price, String status, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(
        children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.inventory_2_rounded, color: AppTheme.primary, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(farmer, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(price, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.primary)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildActionCard(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: Column(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _DealerProducts extends StatefulWidget {
  const _DealerProducts();
  @override
  State<_DealerProducts> createState() => _DealerProductsState();
}

class _DealerProductsState extends State<_DealerProducts> {
  List<dynamic> _products = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadProducts(); }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try { final api = ApiService(); final response = await api.getMarketplaceProducts(); setState(() { _products = response; _isLoading = false; }); }
    catch (e) { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('My Products', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)), Text('Manage your product listings', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))]),
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  child: IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())), icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _products.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300), const SizedBox(height: 12), Text('No products yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14))]))
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _products.length,
                          itemBuilder: (context, index) => _buildProductItem(_products[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(dynamic product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 72, height: 72, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12)), child: Icon(_categoryIcon(product.category), color: AppTheme.primary, size: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.eco_rounded, size: 10, color: AppTheme.primary), const SizedBox(width: 3), Text(product.category, style: TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w600))])),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.attach_money_rounded, size: 12, color: AppTheme.primary),
                      Text('${product.price.toInt()} FCFA', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(width: 8),
                      Icon(Icons.inventory_2_rounded, size: 12, color: AppTheme.textMuted),
                      Text('${product.stockQuantity} units', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ]),
                  ],
                ),
              ),
              Row(children: [
                IconButton(onPressed: () {}, icon: Icon(Icons.edit_rounded, color: AppTheme.primary, size: 18)),
                IconButton(onPressed: () {}, icon: Icon(Icons.delete_rounded, color: AppTheme.error, size: 18)),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text('Status: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                Text(product.isAvailable ? 'Active' : 'Inactive', style: TextStyle(color: product.isAvailable ? AppTheme.success : AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
              Switch(value: product.isAvailable, onChanged: (v) {}, activeColor: AppTheme.primary),
            ],
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'seed': return Icons.eco_rounded;
      case 'fertilizer': return Icons.science_rounded;
      case 'pesticide': return Icons.bug_report_rounded;
      case 'fungicide': return Icons.healing_rounded;
      case 'equipment': return Icons.build_rounded;
      default: return Icons.inventory_2_rounded;
    }
  }
}

class _DealerOrders extends StatelessWidget {
  const _DealerOrders();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Orders', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: ['New (3)', 'Processing', 'Completed', 'Cancelled'].map((tab) {
                final isFirst = tab == 'New (3)';
                return Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isFirst ? AppTheme.primary : Colors.transparent, width: 3))),
                    child: Text(tab, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: isFirst ? FontWeight.w700 : FontWeight.w500, color: isFirst ? AppTheme.primary : AppTheme.textMuted)),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildOrderCard('Jean-Paul M.', '2x Hybrid Maize Seeds 10kg, 1x Urea', '16,000 FCFA', 'Paid via MTN MoMo', AppTheme.warning),
                _buildOrderCard('Amina F.', '1x NPK Fertilizer 50kg', '12,500 FCFA', 'Paid via Orange Money', AppTheme.accent),
                _buildOrderCard('Samuel T.', 'Knapsack Sprayer (16L)', '18,000 FCFA', 'Pending payment', AppTheme.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(String farmer, String items, String price, String payment, Color paymentColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.person_rounded, color: AppTheme.primary, size: 18)),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(farmer, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('10 min ago', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
              ]),
              Icon(Icons.more_vert_rounded, color: Colors.grey.shade400),
            ],
          ),
          const SizedBox(height: 10),
          Text(items, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(price, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.primary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: paymentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(payment, style: TextStyle(fontSize: 10, color: paymentColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text('Decline', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text('Accept', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
            ],
          ),
        ],
      ),
    );
  }
}

class _DealerChatList extends StatelessWidget {
  const _DealerChatList();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Chats', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildChatItem('Jean-Paul M.', 'My maize leaves have these brown spots...', true),
                _buildChatItem('Amina F.', 'Is the NPK fertilizer available?', true),
                _buildChatItem('Samuel T.', 'Thanks for the quick delivery!', false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(String name, String lastMessage, bool unread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(
        children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.person_rounded, color: AppTheme.primary, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            Text(lastMessage, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (unread) Container(width: 10, height: 10, decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

class _DealerProfile extends StatelessWidget {
  const _DealerProfile();

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
              child: Column(children: [
                Container(width: 80, height: 80, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle, border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 3)), child: Icon(Icons.store_rounded, color: AppTheme.primary, size: 40)),
                const SizedBox(height: 12),
                Text('${user?.firstName ?? 'Store'} ${user?.lastName ?? ''}', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(user?.email ?? '', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.store_rounded, size: 14, color: AppTheme.info), const SizedBox(width: 4), Text('Dealer', style: TextStyle(fontSize: 12, color: AppTheme.info, fontWeight: FontWeight.w600))])),
              ]),
            ),
            const SizedBox(height: 16),
            _buildMenuItem(context, Icons.inventory_2_rounded, 'My Products', () {}),
            _buildMenuItem(context, Icons.receipt_long_rounded, 'Order History', () {}),
            _buildMenuItem(context, Icons.chat_rounded, 'Customer Chats', () {}),
            _buildMenuItem(context, Icons.star_rounded, 'Premium Upgrade', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()))),
            _buildMenuItem(context, Icons.settings_rounded, 'Settings', () {}),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async { await context.read<AuthProvider>().logout(); if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false); },
                icon: const Icon(Icons.logout_rounded, color: AppTheme.error),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error.withOpacity(0.1), foregroundColor: AppTheme.error, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: InkWell(onTap: onTap, child: Row(children: [Icon(icon, size: 20, color: AppTheme.primary), const SizedBox(width: 14), Expanded(child: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w500, fontSize: 14))), Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20)])),
      ),
    );
  }
}
