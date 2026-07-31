import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import '../services/api/api_service.dart';

/// In-app notifications for the current user (order alerts, payment
/// confirmations, premium updates, system broadcasts).
class NotificationProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;
  DateTime _lastUnreadFetch = DateTime.fromMillisecondsSinceEpoch(0);

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Refresh the unread badge at most once per 20 seconds (called from the
  /// bell widget on rebuilds) — avoids hammering the API.
  Future<void> loadUnreadCount({bool force = false}) async {
    if (!force &&
        DateTime.now().difference(_lastUnreadFetch).inSeconds < 20) {
      return;
    }
    _lastUnreadFetch = DateTime.now();
    try {
      _unreadCount = await _api.getUnreadNotificationCount();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadNotifications() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getNotifications();
      _notifications = (data as List)
          .map((j) => AppNotification.fromJson(j as Map<String, dynamic>))
          .toList();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    try {
      await _api.markNotificationRead(notification.id);
      final index = _notifications.indexWhere((n) => n.id == notification.id);
      if (index >= 0) {
        _notifications[index] = AppNotification(
          id: notification.id,
          title: notification.title,
          message: notification.message,
          type: notification.type,
          referenceId: notification.referenceId,
          isRead: true,
          createdAt: notification.createdAt,
        );
      }
      if (_unreadCount > 0) _unreadCount -= 1;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _api.markAllNotificationsRead();
      _notifications = _notifications
          .map((n) => AppNotification(
                id: n.id,
                title: n.title,
                message: n.message,
                type: n.type,
                referenceId: n.referenceId,
                isRead: true,
                createdAt: n.createdAt,
              ))
          .toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (_) {}
  }
}
