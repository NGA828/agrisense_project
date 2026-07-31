import 'package:flutter/foundation.dart';
import '../services/api/api_service.dart';

class Announcement {
  final int id;
  final String title;
  final String content;
  final String targetAudience;
  final String createdBy;
  final String createdAt;

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.targetAudience,
    required this.createdBy,
    required this.createdAt,
  });

  factory Announcement.fromApi(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      targetAudience: json['target_audience'],
      createdBy: json['created_by_name'] ?? 'Admin',
      createdAt: _formatDate(json['created_at']),
    );
  }

  static String _formatDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoString;
    }
  }
}

class AnnouncementProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<Announcement> _announcements = [];
  bool _isLoading = false;
  String? _error;

  List<Announcement> get announcements => _announcements;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadAnnouncements() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getAnnouncements();
      _announcements = (data as List).map((j) => Announcement.fromApi(j)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
