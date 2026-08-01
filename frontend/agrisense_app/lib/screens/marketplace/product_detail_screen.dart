import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// Importing original imports. Fallbacks are included to ensure seamless execution.
import '../../theme/app_theme.dart';
import '../../services/api/api_service.dart';
import '../../widgets/glass_card.dart';
import '../../providers/chat_provider.dart';
import '../chat/chat_screen.dart';
import '../chat/chat_list_screen.dart';
import '../payment/payment_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final int? productId;
  final String name;
  final String price;
  final double rating;
  final String category;

  const ProductDetailScreen({
    super.key,
    this.productId,
    required this.name,
    required this.price,
    required this.rating,
    required this.category,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> with SingleTickerProviderStateMixin {
  int quantity = 1;
  bool isAddingToCart = false;
  bool isFavorite = false;
  int? _dealerId;
  String _dealerName = '';
  String _productImage = '';
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadProduct();
  }

  Future<void> _loadProduct() async {
    final productId = widget.productId;
    if (productId == null) return;
    try {
      final product = await ApiService().getProduct(productId);
      if (mounted) {
        setState(() {
          _dealerId = product.dealerId;
          _dealerName = product.dealerName;
          _productImage = product.image;
        });
      }
    } catch (_) {
      // Keep the values passed via constructor; chat falls back to the list.
    }
  }

  Future<void> _openChatWithDealer() async {
    final chatProvider = context.read<ChatProvider>();
    if (_dealerId != null) {
      final conversation = await chatProvider.startConversation(dealerId: _dealerId);
      if (conversation != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conversation.id,
              conversationName: conversation.name,
            ),
          ),
        );
        return;
      }
    }
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen()));
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Define local theme attributes in case AppTheme properties are absent/different
  Color get _primaryColor => const Color(0xFF2E7D32); // Deep premium green
  Color get _accentColor => const Color(0xFFE65100);  // Deep orange
  Color get _bgLight => const Color(0xFFF4F6F4);

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'seed':
        return const Color(0xFF4CAF50);
      case 'fertilizer':
        return const Color(0xFF9C27B0);
      case 'pesticide':
        return const Color(0xFFFF5722);
      case 'fungicide':
        return const Color(0xFF009688);
      case 'equipment':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF607D8B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _getCategoryColor(widget.category);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Dynamic Layout
          Column(
            children: [
              // 1. Premium Header Banner
              _buildHeaderBanner(categoryColor),

              // 2. Scrollable Product Details Sheet
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 24,
                    bottom: 120, // Leave space for floating action bar
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category Badge & Stock Status Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: categoryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: categoryColor.withOpacity(0.2), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _categoryIcon(widget.category),
                                  size: 14,
                                  color: categoryColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.category.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: categoryColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Pulsing "In Stock" Badge
                          Row(
                            children: [
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  return Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF4CAF50),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF4CAF50).withOpacity(0.5),
                                          blurRadius: 4 + (_pulseController.value * 6),
                                          spreadRadius: _pulseController.value * 2,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'In Stock',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Product Name Text
                      Text(
                        widget.name,
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1E241E),
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Rating & Reviews row
                      Row(
                        children: [
                          Row(
                            children: List.generate(5, (index) {
                              final starVal = index + 1;
                              return Icon(
                                Icons.star_rounded,
                                color: widget.rating >= starVal
                                    ? const Color(0xFFFFB300)
                                    : const Color(0xFFE0E0E0),
                                size: 18,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.rating.toString(),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E241E),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(48 Reviews)',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF757575),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Price Display (With Currency Tag)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            widget.price,
                            style: GoogleFonts.poppins(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: _primaryColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'FCFA',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 3. Premium Agro-Dealer Glass Card
                      _buildDealerCard(),

                      const SizedBox(height: 24),

                      // Key Features Grid/Row (Farmers trust certified products)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildFeatureBadge(Icons.shield_outlined, '100% Certified'),
                          _buildFeatureBadge(Icons.local_shipping_outlined, 'Fast Delivery'),
                          _buildFeatureBadge(Icons.assignment_turned_in_outlined, 'Tested Quality'),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Description Section
                      Text(
                        'Description',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E241E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A premium quality, protective contact fungicide specifically formulated for smallholders. Ideal for controlling and preventing devastating crop diseases like Late Blight, Early Blight, and Downy Mildew.',
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          height: 1.5,
                          color: const Color(0xFF555F55),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Dosage & Usage Section (Crucial agricultural contextual value!)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FBF9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFEAEAEA), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Application Guideline',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E241E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '• Dosage: Mix 50g per 15L backpack sprayer.\n• Frequency: Apply every 10-14 days on signs of wet weather.\n• Pre-Harvest Interval (PHI): 7 Days.',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                height: 1.6,
                                color: const Color(0xFF424A42),
                              ),
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

          // 4. Floating Premium Bottom Sticky Action Bar
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  // Header banner widget with organic styling & smooth back buttons
  Widget _buildHeaderBanner(Color categoryColor) {
    return Container(
      height: 310,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            categoryColor.withOpacity(0.18),
            categoryColor.withOpacity(0.02),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background organic ambient decoration
          Positioned(
            right: -50,
            top: -20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: categoryColor.withOpacity(0.05),
              ),
            ),
          ),

          // Glowing Sphere with Floating Category Icon
          Center(
            child: _FloatingWidget(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: categoryColor.withOpacity(0.2),
                          blurRadius: 35,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                  ),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.8),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _productImage.isNotEmpty
                        ? Image.network(
                            _productImage,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(
                                _categoryIcon(widget.category),
                                size: 70,
                                color: categoryColor,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              _categoryIcon(widget.category),
                              size: 70,
                              color: categoryColor,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Navigation Overlay (Safely spaced with padding)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircularHeaderButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: () => Navigator.pop(context),
                ),
                _buildCircularHeaderButton(
                  icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: isFavorite ? Colors.red : const Color(0xFF1E241E),
                  onPressed: () {
                    setState(() {
                      isFavorite = !isFavorite;
                    });
                    // Elegant quick micro-feedback haptic trigger
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isFavorite ? 'Added to Wishlist' : 'Removed from Wishlist'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Circular glass-like header button builder
  Widget _buildCircularHeaderButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color iconColor = const Color(0xFF1E241E),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 18, color: iconColor),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ),
      ),
    );
  }

  // Premium Store Card Design
  Widget _buildDealerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2EBE2), width: 1),
      ),
      child: Row(
        children: [
          // Store avatar with subtle gradient rim
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_primaryColor, _primaryColor.withOpacity(0.4)],
              ),
              shape: BoxShape.circle,
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.store_rounded, color: _primaryColor, size: 24),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AgroShop Yaounde',
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E241E),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Color(0xFF2E7D32), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Verified Dealer',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Direct Dealer Shop Action Arrow
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chevron_right_rounded, color: Color(0xFF757575), size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF9F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDEDED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7A6B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF555F55),
            ),
          ),
        ],
      ),
    );
  }

  // Floating sticky actions sheet at the bottom of screen
  Widget _buildBottomActionBar() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              border: const Border(
                top: BorderSide(color: Color(0xFFECECEC), width: 1.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                )
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Modern Rounded Quantity Selector
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6F4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2EBE2)),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: quantity > 1 ? () => setState(() => quantity--) : null,
                              icon: const Icon(Icons.remove_rounded),
                              color: quantity > 1 ? const Color(0xFF1E241E) : Colors.grey,
                              iconSize: 20,
                            ),
                            Text(
                              '$quantity',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E241E),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => quantity++),
                              icon: const Icon(Icons.add_rounded),
                              color: const Color(0xFF1E241E),
                              iconSize: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Add to Cart / Instant Buy Button
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isAddingToCart ? null : _handleAddToCart,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isAddingToCart
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.shopping_cart_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Buy Now',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Direct Chat Action Button (Secondary Choice)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _openChatWithDealer,
                      icon: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: _primaryColor),
                      label: Text(
                        _dealerName.isEmpty ? 'Chat with Seller' : 'Chat with $_dealerName',
                        style: GoogleFonts.poppins(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryColor,
                        side: BorderSide(color: _primaryColor, width: 1.8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Handle shopping bag transaction
  Future<void> _handleAddToCart() async {
    if (widget.productId != null) {
      setState(() => isAddingToCart = true);
      try {
        final api = ApiService();
        final order = await api.createOrder(widget.productId!, quantity);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentScreen(
                orderId: order['id'],
                productName: widget.name,
                unitPrice: widget.price,
                quantity: quantity,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to process order: $e'),
              backgroundColor: const Color(0xFFC62828),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => isAddingToCart = false);
      }
    } else {
      // Offline / Local fallback transition
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            productName: widget.name,
            unitPrice: widget.price,
            quantity: quantity,
          ),
        ),
      );
    }
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'seed':
        return Icons.eco_rounded;
      case 'fertilizer':
        return Icons.science_rounded;
      case 'pesticide':
        return Icons.bug_report_rounded;
      case 'fungicide':
        return Icons.healing_rounded;
      case 'equipment':
        return Icons.build_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }
}

// Helper widget to implement a fluid floating transition
class _FloatingWidget extends StatefulWidget {
  final Widget child;
  const _FloatingWidget({required this.child});

  @override
  State<_FloatingWidget> createState() => _FloatingWidgetState();
}

class _FloatingWidgetState extends State<_FloatingWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
