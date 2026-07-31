import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final String conversationName;

  const ChatScreen({super.key, required this.conversationId, required this.conversationName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  late final ChatProvider _chatProvider;

  int get _currentUserId => context.read<AuthProvider>().currentUser?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _chatProvider = context.read<ChatProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatProvider.openConversation(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _chatProvider.closeConversation(widget.conversationId);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      try {
        await _chatProvider.sendImageMessage(widget.conversationId, image);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send image: $e'), backgroundColor: AppTheme.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages = _chatProvider.getMessages(widget.conversationId);

    return Scaffold(
      backgroundColor: const Color(0xFFEAF4EA),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, left: 8, right: 16, bottom: 12),
            decoration: const BoxDecoration(color: Colors.white),
            child: Row(
              children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20)),
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight]), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.person, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(widget.conversationName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14), overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, color: AppTheme.info, size: 16),
                      ]),
                      Row(children: [
                        Icon(Icons.circle, color: AppTheme.success, size: 8),
                        const SizedBox(width: 4),
                        Text('Online', style: TextStyle(color: AppTheme.success, fontSize: 11)),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.phone_rounded, color: AppTheme.primary, size: 22),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty && chatProvider.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : messages.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.chat_rounded, size: 64, color: Colors.grey.shade300), const SizedBox(height: 12), Text('No messages yet', style: AppTheme.bodyMedium)]))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return _buildMessageBubble(message, message.isMine(_currentUserId));
                        },
                      ),
          ),
          _buildInputBar(chatProvider),
        ],
      ),
    );
  }

  Widget _buildInputBar(ChatProvider chatProvider) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom, left: 16, right: 16, top: 12),
      decoration: const BoxDecoration(color: Colors.white),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: const Icon(Icons.attach_file_rounded, color: AppTheme.textMuted, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(30)),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(hintText: 'Type message...', hintStyle: TextStyle(color: Colors.grey.shade400), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final text = _messageController.text.trim();
              if (text.isNotEmpty) {
                _messageController.clear();
                try {
                  await _chatProvider.sendMessage(widget.conversationId, text);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to send: $e'), backgroundColor: AppTheme.error),
                    );
                  }
                }
              }
            },
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.2), blurRadius: 8)],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 6),
                      bottomRight: Radius.circular(isMe ? 6 : 20),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: message.imageUrl != null && message.imageUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: message.imageUrl!,
                            width: 220,
                            height: 160,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              width: 220, height: 160,
                              color: Colors.white.withOpacity(0.2),
                              child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            ),
                            errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white70, size: 40),
                          ),
                        )
                      : Text(message.text.isEmpty ? '📷' : message.text,
                          style: TextStyle(color: isMe ? Colors.white : AppTheme.textPrimary, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 4),
                Text(message.timeLabel, style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.2), blurRadius: 8)],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}
