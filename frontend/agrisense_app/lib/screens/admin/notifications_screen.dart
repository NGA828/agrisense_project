import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';

/// Admin broadcast center: compose announcements, target an audience and
/// toggle their visibility. Active announcements appear in farmers' homes.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService().getAllAnnouncements();
      if (mounted) setState(() {
        _announcements = list;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openComposer() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _ComposeScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _toggle(dynamic announcement) async {
    try {
      await ApiService().toggleAnnouncement(announcement['id']);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _delete(dynamic announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('"${announcement['title']}" will be removed permanently.'),
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
      await ApiService().deleteAnnouncement(announcement['id']);
      await _load();
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20)),
                  Text('Broadcast Center',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
                  IconButton(
                    onPressed: _openComposer,
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _announcements.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.campaign_rounded, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('No announcements yet', style: AppTheme.titleMedium),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _openComposer,
                                icon: const Icon(Icons.send_rounded),
                                label: const Text('Send the first broadcast'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppTheme.primary,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _announcements.length,
                            itemBuilder: (context, index) =>
                                _announcementCard(_announcements[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _announcementCard(dynamic announcement) {
    final audience = announcement['target_audience'] ?? 'all';
    final audienceLabel = audience == 'farmers'
        ? 'Farmers'
        : audience == 'dealers'
            ? 'Dealers'
            : 'All users';
    final active = announcement['is_active'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: active ? AppTheme.primary.withOpacity(0.1) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.campaign_rounded,
                    color: active ? AppTheme.primary : AppTheme.textMuted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(announcement['title'] ?? '',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text('Target: $audienceLabel',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: active,
                onChanged: (_) => _toggle(announcement),
                activeColor: AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(announcement['content'] ?? '',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.5),
              maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(announcement['created_at']?.toString().substring(0, 10) ?? '',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              TextButton.icon(
                onPressed: () => _delete(announcement),
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

class _ComposeScreen extends StatefulWidget {
  const _ComposeScreen();

  @override
  State<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<_ComposeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _target = 'all';
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);
    try {
      await ApiService().createAnnouncement(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        targetAudience: _target,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement broadcast successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F3),
      appBar: AppBar(
        title: Text('New Broadcast', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
              decoration: _decoration('Title', 'e.g. Locust alert — northern region'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _contentController,
              maxLines: 5,
              validator: (v) => v == null || v.trim().isEmpty ? 'Content is required' : null,
              decoration: _decoration('Message', 'Write the announcement content...'),
            ),
            const SizedBox(height: 14),
            Text('Target audience', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _target,
              decoration: _decoration('Audience', ''),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All users')),
                DropdownMenuItem(value: 'farmers', child: Text('Farmers only')),
                DropdownMenuItem(value: 'dealers', child: Text('Dealers only')),
              ],
              onChanged: (v) => setState(() => _target = v ?? 'all'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _send,
                icon: _isSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(_isSending ? 'Sending...' : 'Broadcast Now',
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

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
