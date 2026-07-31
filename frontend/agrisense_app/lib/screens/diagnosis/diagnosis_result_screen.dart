import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/diagnosis.dart';
import '../../models/product.dart';
import '../../providers/marketplace_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../marketplace/marketplace_screen.dart';
import '../marketplace/product_detail_screen.dart';

/// Full AI diagnosis result: disease, confidence, causes, prevention and the
/// treatment plan, plus recommended marketplace products.
class DiagnosisResultScreen extends StatefulWidget {
  final Diagnosis diagnosis;

  const DiagnosisResultScreen({super.key, required this.diagnosis});

  @override
  State<DiagnosisResultScreen> createState() => _DiagnosisResultScreenState();
}

class _DiagnosisResultScreenState extends State<DiagnosisResultScreen> {
  List<Product> _recommended = [];
  bool _loadingProducts = true;

  Diagnosis get d => widget.diagnosis;

  @override
  void initState() {
    super.initState();
    _loadRecommended();
  }

  Future<void> _loadRecommended() async {
    try {
      final provider = context.read<MarketplaceProvider>();
      await provider.loadProducts(category: 'fungicide');
      var list = provider.products;
      if (list.isEmpty) {
        await provider.loadProducts(category: 'pesticide');
        list = provider.products;
      }
      if (mounted) {
        setState(() {
          _recommended = list.take(4).toList();
          _loadingProducts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  Color get _severityColor {
    switch (d.severity) {
      case 'high': return AppTheme.error;
      case 'medium': return AppTheme.warning;
      default: return AppTheme.success;
    }
  }

  String get _severityLabel {
    switch (d.severity) {
      case 'high': return 'High';
      case 'medium': return 'Moderate';
      default: return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      body: Column(
        children: [
          _header(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _imageCard(),
                  const SizedBox(height: 16),
                  _diagnosisCard(),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.info_outline_rounded,
                    title: 'What caused it',
                    body: d.causes,
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.health_and_safety_rounded,
                    title: 'How to prevent it',
                    body: d.prevention,
                  ),
                  const SizedBox(height: 16),
                  _treatmentCard(),
                  const SizedBox(height: 16),
                  _recommendedCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 8, right: 8, bottom: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D5016), Color(0xFF4A7C28)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
          ),
          const Icon(Icons.eco_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AgriSense AI', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                Text('Disease Diagnosis', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('${d.confidence.toInt()}% match', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _imageCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 200,
        width: double.infinity,
        color: AppTheme.primary.withOpacity(0.08),
        child: d.imageUrl.isNotEmpty
            ? Image.network(d.imageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imagePlaceholder())
            : _imagePlaceholder(),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.eco_rounded, size: 56, color: AppTheme.primary.withOpacity(0.4)),
          const SizedBox(height: 8),
          Text('Leaf sample — ${d.cropType}', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _diagnosisCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disease Name', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(Icons.bug_report_rounded, color: _severityColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(d.diseaseName, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textPrimary)),
              ),
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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _severityProgress,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(_severityColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confidence', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                    child: Text('${d.confidence.toInt()}%',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 20, color: AppTheme.primary)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  double get _severityProgress {
    switch (d.severity) {
      case 'high': return 0.85;
      case 'medium': return 0.55;
      default: return 0.25;
    }
  }

  Widget _sectionCard({required IconData icon, required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          Text(body.isEmpty ? 'Information coming from your agricultural advisor.' : body,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }

  Widget _treatmentCard() {
    final plan = d.treatmentPlan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.medical_services_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Treatment Plan', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          const SizedBox(height: 12),
          if (plan != null) ...[
            _treatmentRow(Icons.science_rounded, 'Recommended product', plan.medication),
            _treatmentRow(Icons.construction_rounded, 'How to apply', plan.instructions),
            _treatmentRow(Icons.calendar_today_rounded, 'Duration', '${plan.duration} days'),
            _treatmentRow(Icons.event_available_rounded, 'Follow-up', _formatDate(plan.followUpDate)),
          ] else ...[
            Text('Your treatment plan is being prepared.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _treatmentRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? '—' : value, style: TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.shopping_bag_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Recommended Products', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
                ),
                child: Text('View All >', style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingProducts)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)))
          else if (_recommended.isEmpty)
            Text('No treatment products available right now — check the marketplace.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12))
          else
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommended.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _productCard(_recommended[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _productCard(Product product) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(
            productId: product.idProduct,
            name: product.name,
            price: product.price.toInt().toString(),
            rating: 4.5,
            category: product.category,
          ),
        ),
      ),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: product.image.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(product.image, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.eco_rounded, color: AppTheme.primary, size: 26)),
                    )
                  : const Icon(Icons.eco_rounded, color: AppTheme.primary, size: 26),
            ),
            const SizedBox(height: 8),
            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 11)),
            const SizedBox(height: 4),
            Text('${product.price.toInt()} FCFA', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primary)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.day}/${date.month}/${date.year}';
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      );
}
