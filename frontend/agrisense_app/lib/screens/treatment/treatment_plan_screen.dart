import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/diagnosis.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_list_screen.dart';

/// Full treatment plan for a confirmed diagnosis: recommended products,
/// application instructions, duration and prevention reminders.
class TreatmentPlanScreen extends StatelessWidget {
  final Diagnosis diagnosis;

  const TreatmentPlanScreen({super.key, required this.diagnosis});

  @override
  Widget build(BuildContext context) {
    final plan = diagnosis.treatmentPlan;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20)),
                const Icon(Icons.medical_services_rounded, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Treatment Plan — ${diagnosis.diseaseName}',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(Icons.science_rounded, 'Recommended Treatment'),
                    const SizedBox(height: 8),
                    _infoTile(
                      icon: Icons.healing_rounded,
                      title: plan?.medication.isNotEmpty == true ? 'Use this product' : 'No chemical treatment',
                      subtitle: plan?.medication.isNotEmpty == true
                          ? plan!.medication
                          : 'Cultural management is recommended for this disease.',
                    ),
                    const SizedBox(height: 12),
                    _infoTile(
                      icon: Icons.construction_rounded,
                      title: 'Application instructions',
                      subtitle: plan?.instructions ?? 'Follow integrated pest management practices.',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _infoTile(
                            icon: Icons.calendar_today_rounded,
                            title: 'Duration',
                            subtitle: plan != null ? '${plan.duration} days' : '—',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _infoTile(
                            icon: Icons.event_available_rounded,
                            title: 'Follow-up',
                            subtitle: plan?.followUpDate != null
                                ? '${plan!.followUpDate.day}/${plan.followUpDate.month}/${plan.followUpDate.year}'
                                : '—',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    _sectionTitle(Icons.tips_and_updates_rounded, 'Prevention Tips'),
                    const SizedBox(height: 8),
                    ..._bulletTips(diagnosis.prevention),

                    const SizedBox(height: 20),
                    _sectionTitle(Icons.shopping_bag_rounded, 'Buy Treatment'),
                    const SizedBox(height: 8),
                    Text(
                      'Find the recommended products from verified dealers in the marketplace.',
                      style: AppTheme.bodySmall,
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChatListScreen()),
                        ),
                        icon: const Icon(Icons.chat_rounded, color: Colors.white),
                        label: Text('Ask a Dealer',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
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

  Widget _sectionTitle(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 18, color: AppTheme.primary),
      const SizedBox(width: 8),
      Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
    ]);
  }

  Widget _infoTile({required IconData icon, required String title, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 3),
                Text(subtitle, style: AppTheme.bodySmall.copyWith(height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _bulletTips(String prevention) {
    final tips = prevention
        .split(RegExp(r'[.;]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .take(6)
        .toList();
    if (tips.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
            const SizedBox(width: 8),
            Expanded(child: Text('Monitor your crops regularly', style: AppTheme.bodySmall.copyWith(fontSize: 13))),
          ]),
        ),
      ];
    }
    return tips
        .map((tip) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
                const SizedBox(width: 8),
                Expanded(child: Text(tip, style: AppTheme.bodySmall.copyWith(fontSize: 13))),
              ]),
            ))
        .toList();
  }
}
