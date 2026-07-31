import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../treatment/treatment_plan_screen.dart';
import '../ai_scan/camera_screen.dart';

class DiagnosisResultScreen extends StatelessWidget {
  final String diseaseName;
  final double confidence;
  final double severity;
  final String cropType;

  const DiagnosisResultScreen({super.key, required this.diseaseName, required this.confidence, required this.severity, required this.cropType});

  Color get _severityColor => severity >= 70 ? AppTheme.error : severity >= 40 ? AppTheme.warning : AppTheme.success;
  String get _severityLabel => severity >= 70 ? 'High' : severity >= 40 ? 'Moderate' : 'Low';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: Column(
        children: [
          // Green Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 16, right: 16, bottom: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2D5016), Color(0xFF4A7C28)]),
            ),
            child: Row(
              children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white)),
                Icon(Icons.eco_rounded, color: Colors.white.withOpacity(0.9), size: 22),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('AgriSense AI', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)), Text('Disease Diagnosis', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11))])),
                Icon(Icons.share_rounded, color: Colors.white, size: 22),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image placeholder
                  Container(
                    width: double.infinity,
                    height: 200,
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      image: DecorationImage(image: NetworkImage('https://images.unsplash.com/photo-1574323347407-f5e1ad6d020b?w=600'), fit: BoxFit.cover, opacity: 0.6),
                    ),
                  ),
                  // Disease Name Card
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Disease Name', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(width: 36, height: 36, decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.shield_rounded, color: AppTheme.primary, size: 18)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(diseaseName, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary))),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Severity', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    Text(_severityLabel, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: _severityColor)),
                                    const SizedBox(height: 6),
                                    ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: severity / 100, minHeight: 6, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation<Color>(_severityColor))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Confidence Level', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                                    child: Text('${confidence.toInt()}%', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.primary)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Treatment Plan
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [Icon(Icons.article_rounded, color: AppTheme.primary, size: 20), const SizedBox(width: 8), Text('Treatment Plan', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15))]),
                          const SizedBox(height: 16),
                          _buildStep(1, 'Remove affected leaves'),
                          _buildStep(2, 'Apply copper-based fungicide'),
                          _buildStep(3, 'Improve air circulation'),
                        ],
                      ),
                    ),
                  ),
                  // Recommended Products
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [Icon(Icons.shopping_bag_rounded, color: AppTheme.primary, size: 20), const SizedBox(width: 8), Text('Recommended Products', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15))]),
                              Text('View All >', style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(child: _buildProductCard('Copper Oxychloride', 'Fungicide', '500 g', '249')),
                              const SizedBox(width: 12),
                              Expanded(child: _buildProductCard('NPK 19:19:19', 'Water Soluble Fertilizer', '1 kg', '199')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Prevention Tips
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
                      child: Row(
                        children: [
                          Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE8F5E9), shape: BoxShape.circle), child: Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Prevention Tips', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
                                Text('Follow these tips to prevent future outbreaks', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(Icons.expand_more_rounded, color: Colors.grey.shade400, size: 24),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Scan Another Plant
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const CameraScreen())),
                        icon: const Icon(Icons.home_rounded, color: Colors.white, size: 18),
                        label: Text('Scan Another Plant', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(color: const Color(0xFFE8F5E9), shape: BoxShape.circle), child: Center(child: Text('$number', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary)))),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 14, color: AppTheme.textPrimary))),
        ],
      ),
    );
  }

  Widget _buildProductCard(String name, String type, String weight, String price) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F9F8), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 60,
            width: double.infinity,
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.science_rounded, color: AppTheme.primary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12)),
          Text(type, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
          Text(weight, style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          Text('\$$price', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primary)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.shopping_cart_rounded, color: Colors.white, size: 12),
              label: Text('Buy Now', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ),
        ],
      ),
    );
  }
}
