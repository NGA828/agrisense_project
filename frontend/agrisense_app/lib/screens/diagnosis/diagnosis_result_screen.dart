import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/diagnosis.dart';
import '../../models/product.dart';
import '../../providers/marketplace_provider.dart';
import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../farmer/farmer_widgets.dart';
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
    // Never market chemicals for a healthy or uncertain diagnosis.
    if (!d.usesTrainedModel || d.isHealthy || d.isInconclusive) {
      _loadingProducts = false;
      return;
    }
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
      case 'high':
        return AppTheme.error;
      case 'medium':
        return AppTheme.warning;
      case 'unknown':
        return Colors.grey; // inconclusive result
      default:
        return AppTheme.success;
    }
  }

  String get _severityLabel {
    switch (d.severity) {
      case 'high':
        return 'High';
      case 'medium':
        return 'Moderate';
      case 'unknown':
        return 'Unknown';
      default:
        return 'Low';
    }
  }

  double get _severityProgress {
    switch (d.severity) {
      case 'high':
        return 0.85;
      case 'medium':
        return 0.55;
      case 'unknown':
        return 0.1; // indeterminate
      default:
        return 0.25;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: Column(
        children: [
          FarmerHeader(
            title: 'Diagnosis Result',
            subtitle: '${d.cropType} · ${_timeAgo(d.createdAt)}',
            showBack: true,
            leading:
                const Icon(Icons.eco_rounded, color: Colors.white, size: 22),
            trailing: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${d.confidence.toInt()}% match',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _imageCard(),
                if (d.lacksTrainedModelProvenance) ...[
                  const SizedBox(height: 14),
                  _fallbackNotice(),
                ],
                const SizedBox(height: 14),
                _diagnosisCard(),
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.info_outline_rounded,
                  title: 'What caused it',
                  body: d.causes,
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.health_and_safety_rounded,
                  title: 'How to prevent it',
                  body: d.prevention,
                ),
                const SizedBox(height: 14),
                _treatmentCard(),
                if (d.usesTrainedModel &&
                    !d.isHealthy &&
                    !d.isInconclusive) ...[
                  const SizedBox(height: 14),
                  _recommendedCard(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Image card ──────────────────────────────────────────────────────
  Widget _imageCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 200,
        width: double.infinity,
        color: AppTheme.primary.withValues(alpha: 0.08),
        child: d.imageUrl.isNotEmpty
            ? Image.network(d.imageUrl,
                fit: BoxFit.cover,
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
          Icon(Icons.eco_rounded,
              size: 56, color: AppTheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text('Leaf sample — ${d.cropType}',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _fallbackNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.warning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.science_outlined,
              color: AppTheme.warning, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    d.usesRuleFallback
                        ? 'Demo heuristic result'
                        : 'Unverified inference source',
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                const Text(
                  'No verified trained-model provenance is attached to this '
                  'result. Confirm it with an agronomist before treatment.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Diagnosis card ──────────────────────────────────────────────────
  Widget _diagnosisCard() {
    return FarmerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Disease Name',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              if (d.usesTrainedModel)
                FarmerPill(
                  label: d.modelVersion.isEmpty ? 'Trained model' : d.modelVersion,
                  color: AppTheme.info,
                  icon: Icons.auto_awesome_rounded,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _severityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(Icons.bug_report_rounded,
                    color: _severityColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  d.diseaseName,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: AppTheme.textPrimary),
                ),
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
                    Text('Severity',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(_severityLabel,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _severityColor)),
                        const SizedBox(width: 8),
                        FarmerPill(
                            label: d.severity, color: _severityColor),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _severityProgress,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_severityColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confidence',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${d.confidence.toInt()}%',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: AppTheme.primary)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section card ────────────────────────────────────────────────────
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return FarmerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 10),
          Text(
            body.isEmpty ? 'Information coming from your agricultural advisor.' : body,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── Treatment card ──────────────────────────────────────────────────
  Widget _treatmentCard() {
    final plan = d.treatmentPlan;
    return FarmerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.medical_services_rounded,
                color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Treatment Plan',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (plan != null)
              FarmerPill(
                label: plan.status,
                color: plan.status == 'active'
                    ? AppTheme.success
                    : AppTheme.info,
              ),
          ]),
          const SizedBox(height: 12),
          if (plan != null) ...[
            _treatmentRow(Icons.science_rounded, 'Recommended product',
                plan.medication),
            _treatmentRow(Icons.construction_rounded, 'How to apply',
                plan.instructions),
            Row(
              children: [
                Expanded(
                  child: _treatmentRow(Icons.calendar_today_rounded,
                      'Duration', '${plan.duration} days'),
                ),
                Expanded(
                  child: _treatmentRow(Icons.event_available_rounded,
                      'Follow-up', _formatDate(plan.followUpDate)),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'Your treatment plan is being prepared.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
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
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Recommended products ────────────────────────────────────────────
  Widget _recommendedCard() {
    return FarmerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.shopping_bag_rounded,
                    color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Recommended Products',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ]),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MarketplaceScreen()),
                ),
                child: Text('View All >',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loadingProducts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    color: AppTheme.primary, strokeWidth: 2),
              ),
            )
          else if (_recommended.isEmpty)
            const Text(
              'No treatment products available right now — check the marketplace.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            )
          else
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommended.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) =>
                    _productCard(_recommended[index]),
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 60,
                width: double.infinity,
                color: const Color(0xFFE8F5E9),
                child: product.image.isNotEmpty
                    ? Image.network(
                        product.image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.eco_rounded,
                            color: AppTheme.primary,
                            size: 26),
                      )
                    : const Icon(Icons.eco_rounded,
                        color: AppTheme.primary, size: 26),
              ),
            ),
            const SizedBox(height: 8),
            Text(product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 11)),
            const SizedBox(height: 4),
            Text('${product.price.toInt()} FCFA',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppTheme.primary)),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
