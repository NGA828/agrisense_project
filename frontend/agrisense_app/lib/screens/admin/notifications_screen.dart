import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api/api_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

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
  String? _error;

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
      final list = await ApiService().getAllAnnouncements();
      if (mounted) {
        setState(() {
          _announcements = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _delete(dynamic announcement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text(
            '"${announcement['title']}" will be removed permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AdminHeader(
              title: 'Broadcast Center',
              subtitle:
                  '${_announcements.length} announcement(s) · active broadcasts reach users instantly',
              showBack: true,
              trailing: [
                IconButton(
                  onPressed: _openComposer,
                  icon:
                      const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  tooltip: 'New broadcast',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : _error != null
                      ? AdminErrorState(message: _error!, onRetry: _load)
                      : _announcements.isEmpty
                          ? AdminEmptyState(
                              icon: Icons.campaign_rounded,
                              title: 'No announcements yet',
                              subtitle:
                                  'Reach farmers and dealers with your first broadcast.',
                              action: ElevatedButton.icon(
                                onPressed: _openComposer,
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: const Text('Send the first broadcast'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppTheme.primary,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: _announcements.length,
                                itemBuilder: (context, index) =>
                                    _announcementCard(
                                        _announcements[index]),
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
      decoration: AdminTheme.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.primary.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.campaign_rounded,
                    color: active ? AppTheme.primary : AppTheme.textMuted,
                    size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement['title'] ?? '',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('Target: $audienceLabel',
                        style: AdminTheme.smallMuted()),
                  ],
                ),
              ),
              Switch(
                value: active,
                onChanged: (_) => _toggle(announcement),
                activeTrackColor: AppTheme.primary.withValues(alpha: 0.5),
                thumbColor: WidgetStateProperty.all(AppTheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement['content'] ?? '',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.5),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AdminPill(
                label: active ? 'Live' : 'Paused',
                color: active ? AppTheme.success : AppTheme.textMuted,
                icon: active ? Icons.circle : Icons.pause_rounded,
              ),
              Text(
                announcement['created_at']?.toString().substring(0, 10) ?? '',
                style: AdminTheme.smallMuted(),
              ),
              TextButton.icon(
                onPressed: () => _delete(announcement),
                icon: const Icon(Icons.delete_rounded,
                    size: 16, color: AppTheme.error),
                label: const Text('Delete',
                    style: TextStyle(color: AppTheme.error)),
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
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.canvas,
      appBar: AppBar(
        title: Text('New Broadcast',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: AppTheme.primary,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AdminCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Title is required' : null,
                    decoration: _decoration(
                        'Title', 'e.g. Locust alert — northern region'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _contentController,
                    maxLines: 5,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Content is required'
                        : null,
                    decoration: _decoration('Message',
                        'Write the announcement content...'),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Target audience',
                        style: AdminTheme.sectionTitle()),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _target,
                    decoration: _decoration('Audience', ''),
                    items: const [
                      DropdownMenuItem(
                          value: 'all', child: Text('All users')),
                      DropdownMenuItem(
                          value: 'farmers', child: Text('Farmers only')),
                      DropdownMenuItem(
                          value: 'dealers', child: Text('Dealers only')),
                    ],
                    onChanged: (v) => setState(() => _target = v ?? 'all'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSending ? null : _send,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(
                    _isSending ? 'Sending...' : 'Broadcast Now',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
