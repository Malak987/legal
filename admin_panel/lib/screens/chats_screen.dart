import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Simple chat log viewer (read-only messages list).
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late Future<List<dynamic>> _future;
  String? _selectedChatId;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<dynamic>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('chats');
    return listDataOf(res);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    setState(() => _selectedChatId = chat['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Chats list
        SizedBox(
          width: 340,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Conversations',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const LoadingView();
                    }
                    if (snapshot.hasError) {
                      return ErrorBanner(
                          message: '${snapshot.error}', onRetry: _reload);
                    }
                    final chats = snapshot.data ?? [];
                    if (chats.isEmpty) {
                      return const EmptyState(
                          icon: Icons.message, message: 'No conversations');
                    }
                    return ListView.builder(
                      itemCount: chats.length,
                      itemBuilder: (context, i) {
                        final c = chats[i] as Map<String, dynamic>;
                        final names = (c['participantNames'] as Map?) ?? {};
                        final title = (names.values.isNotEmpty
                            ? names.values.first.toString()
                            : 'Chat');
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: AppTheme.primary,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text(title),
                            subtitle: Text(
                              '${c['lastMessage'] ?? 'No messages'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _openChat(c),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Messages pane
        Expanded(
          child: _selectedChatId == null
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  message: 'Select a conversation to view messages',
                )
              : _MessagesPane(chatId: _selectedChatId!),
        ),
      ],
    );
  }
}

class _MessagesPane extends StatefulWidget {
  const _MessagesPane({required this.chatId});

  final String chatId;

  @override
  State<_MessagesPane> createState() => _MessagesPaneState();
}

class _MessagesPaneState extends State<_MessagesPane> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant _MessagesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-request only when the conversation actually changes. The future is
    // cached otherwise, so an unrelated rebuild (auth state, resize, parent
    // rebuild) cannot fire a duplicate HTTP request - previously the call was
    // created inline inside build() and re-issued on every single frame.
    if (oldWidget.chatId != widget.chatId) {
      _future = _fetch();
    }
  }

  Future<Map<String, dynamic>> _fetch() async {
    final res =
        await AuthProvider.of(context).api.get('chats/${widget.chatId}');
    return objectDataOf(res);
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Non-listening read: used to align the bubbles with the signed-in admin.
    final myUid = AuthProvider.of(context).session?.uid;

    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Loading messages...');
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final messages = (data['messages'] as List? ?? const [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();

        if (messages.isEmpty) {
          return const EmptyState(icon: Icons.chat, message: 'No messages yet');
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              color: AppTheme.primary,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Conversation',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, i) {
                  final m = messages[i];
                  // Compare against the signed-in admin's uid instead of a
                  // hardcoded demo id, so bubbles align for the real account.
                  final mine = myUid != null && m['senderId'] == myUid;
                  return Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 420),
                      decoration: BoxDecoration(
                        color: mine
                            ? AppTheme.primary.withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m['senderName'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('${m['text'] ?? ''}'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
