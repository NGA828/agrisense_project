import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Admin console for the AI knowledge base: list, search, add, edit and
/// delete diseases. Changes here immediately affect diagnosis results.
class ContentManagementScreen extends StatefulWidget {
  const ContentManagementScreen({super.key});

  @override
  State<ContentManagementScreen> createState() => _ContentManagementScreenState();
}

class _ContentManagementScreenState extends State<ContentManagementScreen> {
  List<dynamic> _diseases = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final diseases = await ApiService().getDiseases();
      if (mounted) setState(() {
        _diseases = diseases;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filtered {
    if (_searchQuery.isEmpty) return _diseases;
    return _diseases
        .where((d) =>
            (d['disease_name'] ?? '').toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (d['crop_name'] ?? '').toString().toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> _openForm([dynamic disease]) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiseaseFormScreen(disease: disease),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(dynamic disease) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete disease?'),
        content: Text('"${disease['disease_name']}" will be removed from the AI knowledge base.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().deleteDisease(disease['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disease deleted'), backgroundColor: AppTheme.success),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A3A1A), Color(0xFF2D5016)]),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
                      Text('Disease Knowledge Base',
                          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                      IconButton(
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: const InputDecoration(
                              hintText: 'Search diseases or crops...',
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(_error!, style: AppTheme.bodySmall, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _load, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _filtered.isEmpty
                          ? Center(child: Text('No diseases found', style: TextStyle(color: AppTheme.textMuted)))
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppTheme.primary,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _filtered.length,
                                itemBuilder: (context, index) =>
                                    _diseaseCard(_filtered[index]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diseaseCard(dynamic disease) {
    final severity = disease['severity'] ?? 'low';
    final severityColor = severity == 'high'
        ? AppTheme.error
        : severity == 'medium'
            ? AppTheme.warning
            : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.bug_report_rounded, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(disease['disease_name'] ?? 'Unknown',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('${disease['crop_name'] ?? ''} · ${disease['pathogen'] ?? '—'}',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: severityColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(severity.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: severityColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(disease['medication']?.toString().isNotEmpty == true
                  ? '💊 ${disease['medication']}'
                  : 'Cultural management only',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _openForm(disease),
                icon: const Icon(Icons.edit_rounded, size: 16, color: AppTheme.primary),
                label: const Text('Edit', style: TextStyle(color: AppTheme.primary)),
              ),
              TextButton.icon(
                onPressed: () => _delete(disease),
                icon: const Icon(Icons.delete_rounded, size: 16, color: AppTheme.error),
                label: const Text('Delete', style: TextStyle(color: AppTheme.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DiseaseFormScreen extends StatefulWidget {
  final dynamic disease;

  const DiseaseFormScreen({super.key, this.disease});

  @override
  State<DiseaseFormScreen> createState() => _DiseaseFormScreenState();
}

class _DiseaseFormScreenState extends State<DiseaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cropController;
  late final TextEditingController _nameController;
  late final TextEditingController _pathogenController;
  late final TextEditingController _symptomsController;
  late final TextEditingController _causesController;
  late final TextEditingController _preventionController;
  late final TextEditingController _medicationController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _durationController;
  String _severity = 'medium';
  bool _isSaving = false;

  bool get _isEdit => widget.disease != null;

  @override
  void initState() {
    super.initState();
    final d = widget.disease;
    _cropController = TextEditingController(text: d?['crop_name'] ?? '');
    _nameController = TextEditingController(text: d?['disease_name'] ?? '');
    _pathogenController = TextEditingController(text: d?['pathogen'] ?? '');
    _symptomsController = TextEditingController(text: d?['symptoms'] ?? '');
    _causesController = TextEditingController(text: d?['causes'] ?? '');
    _preventionController = TextEditingController(text: d?['prevention'] ?? '');
    _medicationController = TextEditingController(text: d?['medication'] ?? '');
    _instructionsController = TextEditingController(text: d?['instructions'] ?? '');
    _durationController = TextEditingController(text: '${d?['duration'] ?? 14}');
    _severity = d?['severity'] ?? 'medium';
  }

  @override
  void dispose() {
    _cropController.dispose();
    _nameController.dispose();
    _pathogenController.dispose();
    _symptomsController.dispose();
    _causesController.dispose();
    _preventionController.dispose();
    _medicationController.dispose();
    _instructionsController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final api = ApiService();
      final duration = int.tryParse(_durationController.text) ?? 14;
      if (_isEdit) {
        await api.updateDisease(
          widget.disease['id'],
          cropName: _cropController.text.trim(),
          diseaseName: _nameController.text.trim(),
          pathogen: _pathogenController.text.trim(),
          symptoms: _symptomsController.text.trim(),
          causes: _causesController.text.trim(),
          severity: _severity,
          prevention: _preventionController.text.trim(),
          medication: _medicationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          treatmentType: 'Fungicide Application',
          duration: duration,
        );
      } else {
        await api.addDisease(
          cropName: _cropController.text.trim(),
          diseaseName: _nameController.text.trim(),
          pathogen: _pathogenController.text.trim(),
          symptoms: _symptomsController.text.trim(),
          causes: _causesController.text.trim(),
          severity: _severity,
          prevention: _preventionController.text.trim(),
          medication: _medicationController.text.trim(),
          instructions: _instructionsController.text.trim(),
          treatmentType: 'Fungicide Application',
          duration: duration,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Disease updated' : 'Disease added to the knowledge base'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Disease' : 'Add Disease',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_nameController, 'Disease name', 'e.g. Tomato Late Blight', validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
            _field(_cropController, 'Crop', 'e.g. Tomato', validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
            _field(_pathogenController, 'Pathogen (cause)', 'e.g. Phytophthora infestans'),
            _field(_symptomsController, 'Symptoms', 'Describe visible symptoms...', maxLines: 3),
            _field(_causesController, 'Causes & spread', 'What causes it...', maxLines: 2),
            _field(_preventionController, 'Prevention', 'How to prevent it...', maxLines: 3),
            _field(_medicationController, 'Recommended medication', 'e.g. Mancozeb 80% WP (50g/20L)', maxLines: 2),
            _field(_instructionsController, 'Application instructions', 'How to apply...', maxLines: 3),
            Row(
              children: [
                Expanded(child: _field(_durationController, 'Duration (days)', '14', keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _severity,
                    decoration: const InputDecoration(labelText: 'Severity'),
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('Low')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High')),
                    ],
                    onChanged: (v) => setState(() => _severity = v ?? 'medium'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded, color: Colors.white),
                label: Text(_isSaving ? 'Saving...' : 'Save Disease',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint,
      {int maxLines = 1, TextInputType? keyboardType, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
