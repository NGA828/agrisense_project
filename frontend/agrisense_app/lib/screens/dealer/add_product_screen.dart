import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import '../../services/api/api_service.dart';

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
  File? _imageFile;

  final List<Map<String, dynamic>> _categories = [
    {'value': 'fertilizer', 'label': 'Fertilizer', 'icon': Icons.science_rounded},
    {'value': 'seed', 'label': 'Seeds', 'icon': Icons.eco_rounded},
    {'value': 'pesticide', 'label': 'Pesticide', 'icon': Icons.bug_report_rounded},
    {'value': 'fungicide', 'label': 'Fungicide', 'icon': Icons.healing_rounded},
    {'value': 'herbicide', 'label': 'Herbicide', 'icon': Icons.grass_rounded},
    {'value': 'equipment', 'label': 'Equipment', 'icon': Icons.build_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2D5016), Color(0xFF4A7C28)]),
              ),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
                  const SizedBox(width: 8),
                  Text('Add New Product', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Image Upload
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: double.infinity, height: 200,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade300, width: 2, style: BorderStyle.solid),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                          ),
                          child: _imageFile != null
                              ? ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(_imageFile!, fit: BoxFit.cover))
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 64, height: 64,
                                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                                      child: Icon(Icons.add_a_photo_rounded, size: 32, color: AppTheme.primary),
                                    ),
                                    const SizedBox(height: 12),
                                    Text('Tap to add product photo', style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Text('Supports JPG, PNG', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Product Name
                      Text('Product Name', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 8),
                      _buildTextField(_nameController, 'Product Name', 'e.g., Organic NPK Fertilizer', Icons.label_rounded),
                      const SizedBox(height: 20),
                      // Category
                      Text('Category', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10, runSpacing: 10,
                        children: _categories.map((cat) {
                          final isSelected = cat['value'] == _selectedCategory;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedCategory = cat['value']),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary : Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: isSelected ? AppTheme.primary : Colors.grey.shade300, width: 1.5),
                                boxShadow: isSelected ? [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 8)] : null,
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(cat['icon'], size: 18, color: isSelected ? Colors.white : AppTheme.textPrimary),
                                const SizedBox(width: 8),
                                Text(cat['label'], style: TextStyle(color: isSelected ? Colors.white : AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // Price and Stock
                      Row(
                        children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Price (FCFA)', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
                            const SizedBox(height: 8),
                            _buildTextField(_priceController, 'Price (FCFA)', '15000', Icons.attach_money_rounded, keyboardType: TextInputType.number),
                          ])),
                          const SizedBox(width: 16),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Stock Quantity', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
                            const SizedBox(height: 8),
                            _buildTextField(_stockController, 'Stock Quantity', '50', Icons.inventory_2_rounded, keyboardType: TextInputType.number),
                          ])),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Description
                      Text('Description', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
                      const SizedBox(height: 8),
                      _buildTextField(_descriptionController, 'Description', 'Describe your product features...', Icons.description_rounded, maxLines: 4),
                      const SizedBox(height: 20),
                      // Availability Toggle
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.primary)),
                            const SizedBox(width: 12),
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Available for sale', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textPrimary)),
                              Text('Product will be visible in marketplace', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            ]),
                          ]),
                          Switch(value: _isAvailable, onChanged: (v) => setState(() => _isAvailable = v), activeColor: AppTheme.primary),
                        ]),
                      ),
                      const SizedBox(height: 28),
                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _submitProduct,
                          icon: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                          label: Text('Add Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                        ),
                      ),
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

  Widget _buildTextField(TextEditingController controller, String label, String hint, IconData icon, {int maxLines = 1, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Icon(icon, size: 16, color: AppTheme.primary), const SizedBox(width: 6), Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13))]),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller, maxLines: maxLines, keyboardType: keyboardType,
          validator: (v) => v!.isEmpty ? 'Required' : null,
          decoration: InputDecoration(hintText: hint, filled: true, fillColor: Colors.white,
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _imageFile = File(picked.path));
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
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [Icon(Icons.check_circle, color: Colors.white, size: 16), SizedBox(width: 8), Text('Product added successfully!')]),
            backgroundColor: AppTheme.success
          )
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() { _nameController.dispose(); _descriptionController.dispose(); _priceController.dispose(); _stockController.dispose(); super.dispose(); }
}
