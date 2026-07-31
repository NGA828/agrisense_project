import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class TreatmentPlanScreen extends StatelessWidget {
  final String diseaseName;
  final double severity;

  const TreatmentPlanScreen({super.key, required this.diseaseName, required this.severity});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20)),
                const Icon(Icons.medical_services_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('Treatment Plan - $diseaseName', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15))),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(Icons.format_list_numbered_rounded, 'Treatment Steps'),
                    const SizedBox(height: 8),
                    _buildStep(Icons.content_cut_rounded, 'Step 1: Remove infected leaves', 'Prune affected foliage immediately and destroy'),
                    _buildStep(Icons.science_rounded, 'Step 2: Apply Fungicide', 'Apply protectant fungicide thoroughly'),
                    _buildStep(Icons.water_drop_rounded, 'Step 3: Improve drainage', 'Ensure proper soil drainage'),

                    const SizedBox(height: 20),
                    _buildSectionTitle(Icons.shopping_bag_rounded, 'Recommended Products'),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildProductCard('Pesticide Mancozeb 80%', Icons.science_rounded, const Color(0xFFE3F2FD)),
                          const SizedBox(width: 10),
                          _buildProductCard('Copper Fungicide', Icons.healing_rounded, const Color(0xFFE8F5E9)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    _buildSectionTitle(Icons.tips_and_updates_rounded, 'Prevention Tips'),
                    const SizedBox(height: 8),
                    _buildTip('Use resistant crop varieties'),
                    _buildTip('Crop rotation'),
                    _buildTip('Adequate plant spacing'),
                    _buildTip('Water at the base'),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.chat_rounded, color: Colors.white),
                        label: Text('Chat with Verified Dealer', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                      ),
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

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(children: [Icon(icon, size: 18, color: AppTheme.primary), const SizedBox(width: 8), Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14))]);
  }

  Widget _buildStep(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle), child: Icon(icon, color: AppTheme.primary, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12)), Text(subtitle, style: AppTheme.bodySmall)])),
      ]),
    );
  }

  Widget _buildProductCard(String name, IconData icon, Color bgColor) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 40, decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: AppTheme.primary, size: 20)),
          const SizedBox(height: 8),
          Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 10)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shopping_cart, size: 10, color: Colors.white), SizedBox(width: 4), Text('Buy Now', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600))]),
          ),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success), const SizedBox(width: 8), Text(text, style: AppTheme.bodySmall.copyWith(fontSize: 13))]),
    );
  }
}
