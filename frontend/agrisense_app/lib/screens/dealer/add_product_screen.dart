import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'dealer_widgets.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  String _selectedCategory = 'fertilizer';
  bool _isAvailable = true;
  bool _isLoading = false;
  XFile? _imageFile;
  Uint8List? _imageBytes;

  final List<Map<String, dynamic>> _categories = [
    {'value': 'fertilizer', 'label': 'Fertilizer', 'icon': Icons.science_rounded},
    {'value': 'seed', 'label': 'Seeds', 'icon': Icons.eco_rounded},
    {'value': 'pesticide', 'label': 'Pesticide', 'icon': Icons.bug_report_rounded},
    {'value': 'fungicide', 'label': 'Fungicide', 'icon': Icons.healing_rounded},
    {'value': 'herbicide', 'label': 'Herbicide', 'icon': Icons.grass_rounded},
    {'value': 'equipment', 'label': 'Equipment', 'icon': Icons.build_rounded},
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
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
              title: 'Add New Product',
              subtitle: 'List a product for farmers to buy',
              showBack: true,
              leading: const Icon(Icons.add_box_rounded,
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
                      // ── Image upload ──
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
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                                      'Tap to add product photo',
                                      style: GoogleFonts.poppins(
                                        color: AppTheme.textSecondary,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Supports JPG, PNG — good photos sell faster',
                                      style: TextStyle(
                                          color: AppTheme.textMuted,
                                          fontSize: 11.5),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── Product name ──
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
                      const SizedBox(height: 20),
                      // ── Availability toggle ──
                      DealerCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                      Icons.visibility_rounded,
                                      size: 20,
                                      color: AppTheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Available for sale',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5),
                                    ),
                                    const Text(
                                      'Visible in the farmer marketplace',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11.5),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Switch(
                              value: _isAvailable,
                              onChanged: (v) =>
                                  setState(() => _isAvailable = v),
                              activeTrackColor: AppTheme.primary
                                  .withValues(alpha: 0.5),
                              thumbColor:
                                  WidgetStateProperty.all(AppTheme.primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                      // ── Submit ──
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _submitProduct,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 22),
                          label: Text(
                            _isLoading ? 'Adding...' : 'Add Product',
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

  void _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.addProduct(
        name: _nameController.text,
        description: _descriptionController.text,
        category: _selectedCategory,
        price: double.parse(_priceController.text),
        stockQuantity: int.parse(_stockController.text),
        imageFile: _imageFile,
        isAvailable: _isAvailable,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Product added successfully!'),
              ],
            ),
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
            content: Text('Failed: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
