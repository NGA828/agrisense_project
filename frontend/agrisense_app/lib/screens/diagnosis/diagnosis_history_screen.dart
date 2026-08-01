import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/diagnosis_provider.dart';
import '../../theme/app_theme.dart';
import '../farmer/farmer_widgets.dart';
import 'diagnosis_result_screen.dart';

/// Farmer diagnosis history: past crop scans with severity and confidence.
class DiagnosisHistoryScreen extends StatefulWidget {
  const DiagnosisHistoryScreen({super.key});

  @override
  State<DiagnosisHistoryScreen> createState() =>
      _DiagnosisHistoryScreenState();
}

class _DiagnosisHistoryScreenState extends State<DiagnosisHistoryScreen> {
  String _severityFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiagnosisProvider>().loadHistory();
    });
  }

  Color _severityColor(String severity) {
    return switch (severity.toLowerCase()) {
      'high' => AppTheme.error,
      'medium' => AppTheme.warning,
      _ => AppTheme.success,
    };
  }

  @override
  Widget build(BuildContext context) {
    final diagnosisProvider = context.watch<DiagnosisProvider>();
    final history = diagnosisProvider.history;

    final highCount =
        history.where((d) => d.severity.toLowerCase() == 'high').length;
    final mediumCount =
        history.where((d) => d.severity.toLowerCase() == 'medium').length;

    final filtered = _severityFilter == 'all'
        ? history
        : history
            .where((d) => d.severity.toLowerCase() == _severityFilter)
            .toList();

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FarmerHeader(
              title: 'Diagnosis History',
              subtitle: 'Your past crop scans & treatments',
              showBack: true,
              leading:
                  const Icon(Icons.history_rounded, color: Colors.white, size: 22),
              trailing: [
                IconButton(
                  onPressed: () => diagnosisProvider.loadHistory(),
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            // Stats row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  _countChip('${history.length}', 'Total', AppTheme.primary),
                  const SizedBox(width: 10),
                  _countChip('$highCount', 'High risk', AppTheme.error),
                  const SizedBox(width: 10),
                  _countChip('$mediumCount', 'Moderate', AppTheme.warning),
                ],
              ),
            ),
            // Severity filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'High', 'Medium', 'Low'].map((t) {
                    final f = t.toLowerCase();
                    final selected = _severityFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _severityFilter = f),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color:
                                  selected ? AppTheme.primary : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: diagnosisProvider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : history.isEmpty
                      ? FarmerEmptyState(
                          icon: Icons.eco_rounded,
                          title: 'No diagnoses yet',
                          subtitle: 'Scan a plant to get started',
                          action: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: const Text('Go scan a crop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        )
                      : filtered.isEmpty
                          ? FarmerEmptyState(
                              icon: Icons.filter_alt_off_rounded,
                              title: 'No ${_severityFilter} risk scans',
                              subtitle: 'Try a different severity filter.',
                            )
                          : RefreshIndicator(
                              onRefresh: () => diagnosisProvider.loadHistory(),
                              color: AppTheme.primary,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) =>
                                    _diagnosisCard(filtered[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800, fontSize: 17, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _diagnosisCard(dynamic diagnosis) {
    final isHigh = diagnosis.severity.toLowerCase() == 'high';
    final severityColor = _severityColor(diagnosis.severity);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => DiagnosisResultScreen(diagnosis: diagnosis)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: FarmerTheme.cardDecoration,
        child: Row(
          children: [
            // Crop photo thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 60,
                height: 60,
                color: severityColor.withValues(alpha: 0.08),
                child: diagnosis.imageUrl.isNotEmpty
                    ? Image.network(
                        diagnosis.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            isHigh ? Icons.bug_report_rounded : Icons.eco_rounded,
                            color: severityColor,
                            size: 28),
                      )
                    : Icon(
                        isHigh ? Icons.bug_report_rounded : Icons.eco_rounded,
                        color: severityColor,
                        size: 28),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diagnosis.diseaseName,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.eco_rounded,
                        size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${diagnosis.cropType} · ${_timeAgo(diagnosis.createdAt)}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11.5),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${diagnosis.confidence.toInt()}%',
                    style: GoogleFonts.poppins(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 5),
                FarmerPill(
                  label: diagnosis.severity,
                  color: severityColor,
                  icon: isHigh ? Icons.warning_rounded : Icons.info_outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }
}
