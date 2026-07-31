import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/diagnosis_provider.dart';
import 'diagnosis_result_screen.dart';

class DiagnosisHistoryScreen extends StatefulWidget {
  const DiagnosisHistoryScreen({super.key});

  @override
  State<DiagnosisHistoryScreen> createState() => _DiagnosisHistoryScreenState();
}

class _DiagnosisHistoryScreenState extends State<DiagnosisHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiagnosisProvider>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagnosisProvider = context.watch<DiagnosisProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE8F5E9), Color(0xFFF5F5F5)])),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2)))),
                child: Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded)),
                  const SizedBox(width: 8),
                  const Icon(Icons.history_rounded, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Diagnosis History', style: AppTheme.headlineSmall)),
                ]),
              ),
              Expanded(
                child: diagnosisProvider.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : diagnosisProvider.history.isEmpty
                        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.history_rounded, size: 64, color: AppTheme.textMuted.withOpacity(0.3)), const SizedBox(height: 16), Text('No diagnoses yet', style: AppTheme.bodyLarge.copyWith(color: AppTheme.textMuted)), const SizedBox(height: 8), Text('Scan a plant to get started', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textMuted))]))
                        : RefreshIndicator(
                            onRefresh: () => diagnosisProvider.loadHistory(),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: diagnosisProvider.history.length,
                              itemBuilder: (context, index) {
                                final diagnosis = diagnosisProvider.history[index];
                                final isHigh = diagnosis.severity.toLowerCase() == 'high';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GestureDetector(
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DiagnosisResultScreen(diagnosis: diagnosis))),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                        child: Container(
                                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.5))),
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              Container(width: 56, height: 56, decoration: BoxDecoration(gradient: LinearGradient(colors: isHigh ? [AppTheme.error.withOpacity(0.2), AppTheme.error.withOpacity(0.1)] : [AppTheme.warning.withOpacity(0.2), AppTheme.warning.withOpacity(0.1)]), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.bug_report_rounded, color: isHigh ? AppTheme.error : AppTheme.warning, size: 28)),
                                              const SizedBox(width: 16),
                                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Text(diagnosis.diseaseName, style: AppTheme.titleMedium.copyWith(color: isHigh ? AppTheme.error : AppTheme.textPrimary)),
                                                const SizedBox(height: 4),
                                                Row(children: [
                                                  Icon(Icons.eco_rounded, size: 12, color: AppTheme.textMuted),
                                                  const SizedBox(width: 4),
                                                  Text('${diagnosis.cropType} - ${_timeAgo(diagnosis.createdAt)}', style: AppTheme.bodySmall.copyWith(color: AppTheme.textMuted)),
                                                ]),
                                              ])),
                                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text('${diagnosis.confidence.toInt()}%', style: AppTheme.bodySmall.copyWith(color: AppTheme.success, fontWeight: FontWeight.w600))),
                                                const SizedBox(height: 4),
                                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: isHigh ? AppTheme.error.withOpacity(0.1) : AppTheme.warning.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(isHigh ? Icons.warning : Icons.info_outline, size: 10, color: isHigh ? AppTheme.error : AppTheme.warning), const SizedBox(width: 3), Text(diagnosis.severity, style: AppTheme.bodySmall.copyWith(color: isHigh ? AppTheme.error : AppTheme.warning, fontWeight: FontWeight.w600, fontSize: 10))])),
                                              ]),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}
