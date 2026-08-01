import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/api/api_service.dart';

/// Manages the single per-user realtime WebSocket push bus.
///
/// After login the app opens one persistent connection to ``/ws/push/`` which
/// delivers lightweight events: ``notification``, ``stock_update``, broadcast
/// announcements, etc. The provider exposes a broadcast stream that other
/// providers (notifications, marketplace) subscribe to, so a live app updates
/// instantly without polling.
///
/// Resilience: on connection drop the provider reconnects with exponential
/// backoff (1s → 30s cap) and resets on a successful connect.
class RealtimeProvider extends ChangeNotifier {
  RealtimeProvider._();

  /// Singleton so multiple providers can share one connection.
  static final RealtimeProvider instance = RealtimeProvider._();

  final ApiService _api = ApiService();
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _attempts = 0;
  bool _disposed = false;
  bool _connecting = false;

  final StreamController<Map<String, dynamic>> _controller =
      StreamController.broadcast();

  /// Broadcast stream of incoming realtime events: `{type, payload}`.
  Stream<Map<String, dynamic>> get events => _controller.stream;

  bool get isConnected => _channel != null;

  /// Open (or reopen) the push-bus connection for the current user.
  Future<void> connect() async {
    if (_connecting) return;
    _disposed = false;
    final token = await _api.getAccessToken();
    if (token == null) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    try {
      final uri = Uri.parse(
          '${ApiService.pushWebSocketUrl()}?token=$token');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub?.cancel();
      _sub = channel.stream.listen(
        (raw) {
          try {
            final event = jsonDecode(raw as String) as Map<String, dynamic>;
            if (event['type'] == 'connected') {
              _attempts = 0; // connected — reset backoff
              notifyListeners();
            } else if (event['type'] == 'pong') {
              // keepalive acknowledgement; nothing else to do
            } else {
              _controller.add(event);
            }
          } catch (_) {}
        },
        onDone: () => _scheduleReconnect(),
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      notifyListeners();
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    _teardown();
    if (_disposed) return;
    final delay = min(pow(2, _attempts).toInt(), 30) * 1000;
    _attempts += 1;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (!_disposed) connect();
    });
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  /// Send a lightweight message to the server (e.g. ping keepalive).
  void send(String type, [Map<String, dynamic>? data]) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode({'type': type, ...?data}));
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _teardown();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _teardown();
    _controller.close();
    super.dispose();
  }
}
