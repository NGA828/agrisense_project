import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'dealer_widgets.dart';

class EditProductScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  String _selectedCategory = 'fertilizer';
  bool _isLoading = false;
  XFile? _imageFile;
  Uint8List? _imageBytes;
  String? _existingImageUrl;

  final List<Map<String, dynamic>> _categories = [
    {'value': 'fertilizer', 'label': 'Fertilizer', 'icon': Icons.science_rounded},
    {'value': 'seed', 'label': 'Seeds', 'icon': Icons.eco_rounded},
    {'value': 'pesticide', 'label': 'Pesticide', 'icon': Icons.bug_report_rounded},
    {'value': 'fungicide', 'label': 'Fungicide', 'icon': Icons.healing_rounded},
    {'value': 'herbicide', 'label': 'Herbicide', 'icon': Icons.grass_rounded},
    {'value': 'equipment', 'label': 'Equipment', 'icon': Icons.build_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.product['name'] ?? '';
    _descriptionController.text = widget.product['description'] ?? '';
    _priceController.text = widget.product['price']?.toString() ?? '';
    _stockController.text = widget.product['stock_quantity']?.toString() ?? '';
    _selectedCategory = widget.product['category'] ?? 'fertilizer';
    _existingImageUrl = widget.product['image'];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _imageFile = picked;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.updateProduct(
        widget.product['id_product'],
        name: _nameController.text,
        description: _descriptionController.text,
        category: _selectedCategory,
        price: double.parse(_priceController.text),
        stockQuantity: int.parse(_stockController.text),
        imageFile: _imageFile,
        isAvailable: widget.product['is_available'] == true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Product updated successfully'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update product: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DealerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DealerHeader(
              title: 'Edit Product',
              subtitle: 'Update your product listing',
              showBack: true,
              leading: const Icon(Icons.edit_rounded,
                  color: Colors.white, size: 22),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Image ──
                      Text('Product Photo', style: DealerTheme.sectionTitle()),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: double.infinity,
                          height: 190,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _imageFile != null
                                  ? AppTheme.primary
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: _imageFile != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Image.memory(
                                        _imageBytes!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      right: 10,
                                      top: 10,
                                      child: GestureDetector(
                                        onTap: () =>
                                             setState(() {
                                               _imageFile = null;
                                               _imageBytes = null;
                                             }),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.close_rounded,
                                              color: Colors.white,
                                              size: 16),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : _existingImageUrl != null &&
                                      _existingImageUrl!.isNotEmpty
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          child: CachedNetworkImage(
                                            imageUrl:
                                                ApiService.resolveMedia(
                                                    _existingImageUrl),
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => Center(
                                              child:
                                                  const CircularProgressIndicator(
                                                      color:
                                                          AppTheme.primary),
                                            ),
                                            errorWidget: (_, __, ___) =>
                                                const Icon(
                                                    Icons.broken_image,
                                                    size: 40,
                                                    color: Colors.grey),
                                          ),
                                        ),
                                        Positioned(
                                          right: 10,
                                          top: 10,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'CURRENT PHOTO',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight:
                                                      FontWeight.w700),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.add_a_photo_rounded,
                                              size: 32,
                                              color: AppTheme.primary),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Tap to add or change product photo',
                                          style: GoogleFonts.poppins(
                                            color: AppTheme.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── Name ──
                      Text('Product Name', style: DealerTheme.sectionTitle()),
                      const SizedBox(height: 8),
                      _buildTextField(
                        _nameController,
                        'Product Name',
                        'e.g., Organic NPK Fertilizer',
                        Icons.label_rounded,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      // ── Category ──
                      Text('Category', style: DealerTheme.sectionTitle()),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _categories.map((cat) {
                          final isSelected =
                              cat['value'] == _selectedCategory;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedCategory = cat['value']),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(cat['icon'],
                                      size: 17,
                                      color: isSelected
                                          ? Colors.white
                                          : AppTheme.textPrimary),
                                  const SizedBox(width: 7),
                                  Text(
                                    cat['label'],
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── Price + stock ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Price (FCFA)',
                                    style: DealerTheme.sectionTitle()),
                                const SizedBox(height: 8),
                                _buildTextField(
                                  _priceController,
                                  'Price (FCFA)',
                                  '15000',
                                  Icons.attach_money_rounded,
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    if (double.tryParse(v) == null) {
                                      return 'Invalid number';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Stock Quantity',
                                    style: DealerTheme.sectionTitle()),
                                const SizedBox(height: 8),
                                _buildTextField(
                                  _stockController,
                                  'Stock Quantity',
                                  '50',
                                  Icons.inventory_2_rounded,
                                  keyboardType: TextInputType.number,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'Required';
                                    }
                                    if (int.tryParse(v) == null) {
                                      return 'Invalid number';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // ── Description ──
                      Text('Description', style: DealerTheme.sectionTitle()),
                      const SizedBox(height: 8),
                      _buildTextField(
                        _descriptionController,
                        'Description',
                        'Describe your product features...',
                        Icons.description_rounded,
                        maxLines: 4,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 26),
                      // ── Save ──
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveProduct,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded,
                                  color: Colors.white, size: 20),
                          label: Text(
                            _isLoading ? 'Saving...' : 'Save Changes',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontSize: 15),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }
}
