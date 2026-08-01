import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/diagnosis.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_list_screen.dart';
import '../farmer/farmer_widgets.dart';

/// Full treatment plan for a confirmed diagnosis: recommended products,
/// application instructions, duration and prevention reminders.
class TreatmentPlanScreen extends StatelessWidget {
  final Diagnosis diagnosis;

  const TreatmentPlanScreen({super.key, required this.diagnosis});

  @override
  Widget build(BuildContext context) {
    final plan = diagnosis.treatmentPlan;

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FarmerHeader(
              title: 'Treatment Plan',
              subtitle: diagnosis.diseaseName,
              showBack: true,
              leading: const Icon(Icons.medical_services_rounded,
                  color: Colors.white, size: 22),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  Text('Recommended Treatment',
                      style: FarmerTheme.sectionTitle()),
                  const SizedBox(height: 10),
                  _infoTile(
                    icon: Icons.healing_rounded,
                    title: plan?.medication.isNotEmpty == true
                        ? 'Use this product'
                        : 'No chemical treatment',
                    subtitle: plan?.medication.isNotEmpty == true
                        ? plan!.medication
                        : 'Cultural management is recommended for this disease.',
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    icon: Icons.construction_rounded,
                    title: 'Application instructions',
                    subtitle: plan?.instructions ??
                        'Follow integrated pest management practices.',
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

                  const SizedBox(height: 22),
                  Text('Prevention Tips', style: FarmerTheme.sectionTitle()),
                  const SizedBox(height: 10),
                  FarmerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _bulletTips(diagnosis.prevention),
                    ),
                  ),

                  const SizedBox(height: 22),
                  Text('Buy Treatment', style: FarmerTheme.sectionTitle()),
                  const SizedBox(height: 8),
                  const Text(
                    'Find the recommended products from verified dealers in the marketplace.',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12.5),
                  ),

                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChatListScreen()),
                      ),
                      icon: const Icon(Icons.chat_rounded,
                          color: Colors.white, size: 20),
                      label: Text('Ask a Dealer',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return FarmerCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 12.5)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.5)),
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
      tips.add('Monitor your crops regularly');
    }
    return tips
        .map((tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 17, color: AppTheme.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: GoogleFonts.poppins(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ))
        .toList();
  }
}
