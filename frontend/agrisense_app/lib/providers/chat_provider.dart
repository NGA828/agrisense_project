import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../services/api/api_service.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final String time;
  final bool hasProduct;
  final String? productName;
  final String? productPrice;

  ChatMessage({
    required this.id, required this.text, required this.isMe,
    required this.time, this.hasProduct = false, this.productName, this.productPrice,
  });

  factory ChatMessage.fromApi(Map<String, dynamic> json, int currentUserId) {
    return ChatMessage(
      id: json['id'].toString(),
      text: json['content'] ?? '',
      isMe: json['sender'] == currentUserId,
      time: _formatTime(json['created_at']),
    );
  }

  static String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }
}

class ChatConversation {
  final int id;
  final String name;
  final String lastMessage;
  final String time;
  final bool isOnline;
  final bool isVerified;
  final int unread;

  ChatConversation({
    required this.id, required this.name, required this.lastMessage,
    required this.time, this.isOnline = false, this.isVerified = false, this.unread = 0,
  });

  factory ChatConversation.fromApi(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'],
      name: json['other_user_name'] ?? 'Unknown',
      lastMessage: json['last_message'] ?? '',
      time: '',
      isVerified: true,
      unread: json['unread_count'] ?? 0,
    );
  }
}

class ChatProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<ChatConversation> _conversations = [];
  Map<int, List<ChatMessage>> _messages = {};
  bool _isLoading = false;
  String? _error;

  List<ChatConversation> get conversations => _conversations;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ChatMessage> getMessages(int conversationId) => _messages[conversationId] ?? [];

  Future<void> loadConversations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.getChatRooms();
      _conversations = (data as List).map((j) => ChatConversation.fromApi(j)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(int conversationId) async {
    try {
      final data = await _api.getChatMessages(conversationId);
      _messages[conversationId] = (data as List).map((j) => ChatMessage.fromApi(j, 0)).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendMessage(int conversationId, String text) async {
    try {
      final msg = await _api.sendMessage(conversationId, text);
      final messages = _messages[conversationId] ?? [];
      messages.add(ChatMessage.fromApi(msg, 0));
      _messages[conversationId] = messages;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendImageMessage(int conversationId, XFile image) async {
    try {
      final msg = await _api.sendImageMessage(conversationId, image);
      final messages = _messages[conversationId] ?? [];
      messages.add(ChatMessage.fromApi(msg, 0));
      _messages[conversationId] = messages;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
