import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/api/api_service.dart';

class ChatMessage {
  final String id;
  final String text;
  final int senderId;
  final String senderName;
  final String? imageUrl;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    this.imageUrl,
    required this.createdAt,
  });

  bool isMine(int currentUserId) => senderId == currentUserId;

  factory ChatMessage.fromApi(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'].toString(),
      text: json['message'] ?? json['content'] ?? '',
      senderId: (json['sender'] ?? 0) is String
          ? int.tryParse(json['sender'].toString()) ?? 0
          : (json['sender'] ?? 0) as int,
      senderName: json['sender_name'] ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  factory ChatMessage.fromWebSocket(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? 0).toString(),
      text: json['message'] ?? '',
      senderId: (json['sender_id'] ?? 0) is String
          ? int.tryParse(json['sender_id'].toString()) ?? 0
          : (json['sender_id'] ?? 0) as int,
      senderName: json['sender_name'] ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String get timeLabel {
    final h = createdAt.hour.toString().padLeft(2, '0');
    final m = createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class ChatConversation {
  final int id;
  final int? otherUserId;
  final String name;
  final String role;
  final String phone;
  final bool isVerified;
  final bool isOnline;
  final String lastMessage;
  final int unread;

  ChatConversation({
    required this.id,
    this.otherUserId,
    required this.name,
    this.role = '',
    this.phone = '',
    this.isVerified = false,
    this.isOnline = false,
    this.lastMessage = '',
    this.unread = 0,
  });

  factory ChatConversation.fromApi(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] ?? 0,
      otherUserId: json['other_user_id'] as int?,
      name: json['other_user_name'] ?? 'Unknown',
      role: json['other_user_role'] ?? '',
      phone: json['other_user_phone'] ?? '',
      isVerified: json['other_is_verified'] ?? false,
      isOnline: json['is_online'] ?? json['other_is_online'] ?? false,
      lastMessage: json['last_message'] ?? '',
      unread: json['unread_count'] ?? 0,
    );
  }
}

class ChatProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<ChatConversation> _conversations = [];
  final Map<int, List<ChatMessage>> _messages = {};
  final Map<int, WebSocketChannel> _channels = {};
  final Set<int> _connectedRooms = {};
  bool _isLoading = false;
  String? _error;

  List<ChatConversation> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ChatMessage> getMessages(int conversationId) =>
      _messages[conversationId] ?? [];

  Future<void> loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getChatRooms();
      _conversations = (data as List)
          .map((j) => ChatConversation.fromApi(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load history over REST (marks incoming messages read server-side),
  /// then opens a live WebSocket for real-time delivery.
  Future<void> openConversation(int conversationId) async {
    try {
      final data = await _api.getChatMessages(conversationId);
      _messages[conversationId] = (data as List)
          .map((j) => ChatMessage.fromApi(j as Map<String, dynamic>))
          .toList();
      notifyListeners();
      _connectSocket(conversationId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadMessages(int conversationId) =>
      openConversation(conversationId);

  Future<void> _connectSocket(int roomId) async {
    if (_connectedRooms.contains(roomId)) return;
    try {
      final token = await _api.getAccessToken();
      if (token == null) return;
      final uri =
          Uri.parse('${ApiService.chatWebSocketUrl(roomId)}?token=$token');
      final channel = WebSocketChannel.connect(uri);
      _channels[roomId] = channel;
      _connectedRooms.add(roomId);
      channel.stream.listen(
        (raw) {
          try {
            final event = jsonDecode(raw as String) as Map<String, dynamic>;
            if (event['type'] == 'chat_message') {
              _appendIncoming(roomId, ChatMessage.fromWebSocket(event));
            }
          } catch (_) {}
        },
        onDone: () {
          _channels.remove(roomId);
          _connectedRooms.remove(roomId);
        },
        onError: (_) {
          _channels.remove(roomId);
          _connectedRooms.remove(roomId);
        },
      );
    } catch (e) {
      // REST fallback remains available; real-time will simply not push.
    }
  }

  void _appendIncoming(int roomId, ChatMessage message) {
    final list = _messages[roomId] ?? [];
    final exists = list.any((m) => m.id == message.id);
    if (!exists) {
      list.add(message);
      _messages[roomId] = list;
      _bumpConversation(roomId, message);
      notifyListeners();
    }
  }

  void _bumpConversation(int roomId, ChatMessage message) {
    final index = _conversations.indexWhere((c) => c.id == roomId);
    if (index >= 0) {
      final c = _conversations[index];
      _conversations[index] = ChatConversation(
        id: c.id,
        otherUserId: c.otherUserId,
        name: c.name,
        role: c.role,
        phone: c.phone,
        isVerified: c.isVerified,
        isOnline: c.isOnline,
        lastMessage:
            '${message.senderName.isNotEmpty ? '${message.senderName}: ' : ''}${message.text}',
        unread: c.unread,
      );
    }
  }

  Future<void> sendMessage(int conversationId, String text) async {
    final channel = _channels[conversationId];
    if (channel != null) {
      // Real-time path: send over WebSocket; the echo updates the UI.
      channel.sink.add(jsonEncode({'message': text}));
      return;
    }
    // REST fallback path.
    try {
      final msg = await _api.sendMessage(conversationId, text);
      final messages = _messages[conversationId] ?? [];
      messages.add(ChatMessage.fromApi(msg));
      _messages[conversationId] = messages;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendImageMessage(int conversationId, XFile image) async {
    try {
      final msg = await _api.sendImageMessage(conversationId, image);
      final messages = _messages[conversationId] ?? [];
      messages.add(ChatMessage.fromApi(msg));
      _messages[conversationId] = messages;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<ChatConversation?> startConversation(
      {int? dealerId, int? farmerId}) async {
    try {
      final room =
          await _api.createChatRoom(dealerId: dealerId, farmerId: farmerId);
      final conv = ChatConversation.fromApi(room);
      if (!_conversations.any((c) => c.id == conv.id)) {
        _conversations.insert(0, conv);
        notifyListeners();
      }
      return conv;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> closeConversation(int conversationId) async {
    final channel = _channels.remove(conversationId);
    _connectedRooms.remove(conversationId);
    try {
      await channel?.sink.close();
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final channel in _channels.values) {
      try {
        channel.sink.close();
      } catch (_) {}
    }
    _channels.clear();
    super.dispose();
  }
}
