import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../providers/chat_provider.dart';
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

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Colors.white),
              child: Row(
                children: [
                  Icon(Icons.chat_rounded, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text('Messages', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: chatProvider.isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: () => chatProvider.loadConversations(),
                      child: chatProvider.conversations.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 160),
                                Icon(Icons.chat_rounded, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Center(child: Text('No conversations yet', style: AppTheme.bodyMedium)),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(16),
                              itemCount: chatProvider.conversations.length,
                              itemBuilder: (context, index) => _buildChatItem(context, chatProvider.conversations[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(BuildContext context, ChatConversation chat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: chat.id, conversationName: chat.name))),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.cardDecoration,
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight]), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.person, color: Colors.white, size: 24),
                  ),
                  if (chat.isOnline)
                    Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: AppTheme.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(chat.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (chat.isVerified) const Icon(Icons.verified, color: AppTheme.info, size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(chat.lastMessage.isEmpty ? 'No messages yet' : chat.lastMessage, style: AppTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (chat.unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                  child: Text('${chat.unread}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
