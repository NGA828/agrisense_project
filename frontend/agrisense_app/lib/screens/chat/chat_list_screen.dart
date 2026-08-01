import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';
import '../farmer/farmer_widgets.dart';
import 'chat_screen.dart';

/// Observes navigation so the conversation list refreshes when the user
/// returns from a chat. Registered in `main.dart` navigatorObservers.
final RouteObserver<ModalRoute<void>> chatRouteObserver =
    RouteObserver<ModalRoute<void>>();

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadConversations();
    });
  }

  /// Refresh the list when returning from a conversation so last messages
  /// and unread badges are always current.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      chatRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (mounted) {
      context.read<ChatProvider>().loadConversations();
    }
  }

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversations = chatProvider.conversations;
    final unreadTotal =
        conversations.fold<int>(0, (sum, c) => sum + (c.unread));

    return Scaffold(
      backgroundColor: FarmerTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FarmerHeader(
              title: 'Messages',
              subtitle: unreadTotal > 0
                  ? '$unreadTotal unread conversation(s)'
                  : 'Chat with verified agro-input dealers',
              leading:
                  const Icon(Icons.chat_rounded, color: Colors.white, size: 22),
              trailing: [
                IconButton(
                  onPressed: () => chatProvider.loadConversations(),
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 22),
                ),
              ],
            ),
            Expanded(
              child: chatProvider.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: () => chatProvider.loadConversations(),
                      child: conversations.isEmpty
                          ? FarmerEmptyState(
                              icon: Icons.forum_rounded,
                              title: 'No conversations yet',
                              subtitle:
                                  'Start chatting with a dealer from any product page.',
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: conversations.length,
                              itemBuilder: (context, index) => _buildChatItem(
                                  context, conversations[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(ChatConversation chat) {
    final text = chat.lastMessage.isEmpty ? 'No messages yet' : chat.lastMessage;
    return text;
  }

  Widget _buildChatItem(BuildContext context, ChatConversation chat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
                conversationId: chat.id, conversationName: chat.name),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: FarmerTheme.cardDecoration,
          child: Row(
            children: [
              Stack(
                children: [
                  FarmerAvatar(
                    name: chat.name,
                    radius: 25,
                    tint: FarmerTheme.grape,
                  ),
                  if (chat.isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.name,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (chat.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              color: AppTheme.info, size: 16),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _timeLabel(chat),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (chat.unread > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                      color: AppTheme.primary, shape: BoxShape.circle),
                  child: Text('${chat.unread}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
