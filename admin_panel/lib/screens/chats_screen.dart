import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../models/models.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Simple chat log viewer (read-only messages list).
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late Future<Paginated<Map<String, dynamic>>> _future;
  String? _selectedChatId;
  String _selectedTitle = 'Conversation';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Map<String, dynamic>>> _fetch() {
    final api = AuthProvider.of(context).api;
    return loadPaginated<Map<String, dynamic>>(
      page: _page,
      fromJson: (json) => json,
      request: (page) =>
          api.get('chats', query: {'page': '$page', 'limit': '$kMaxPageSize'}),
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  void _goToPage(int page) {
    setState(() {
      _page = page;
      _future = _fetch();
    });
  }

  Future<void> _openChat(Map<String, dynamic> chat, String title) async {
    setState(() {
      _selectedChatId = chat['id'];
      _selectedTitle = title;
    });
  }

  void _closeChat() => setState(() => _selectedChatId = null);

  Widget _conversationList({required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? AppSpacing.lg : AppSpacing.xl, AppSpacing.lg, AppSpacing.sm, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text('Conversations', style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'Refresh conversations',
                onPressed: _reload,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: PagedFutureView<Map<String, dynamic>>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load chats',
            empty: const EmptyState(icon: Icons.chat_bubble_outline, message: 'No conversations'),
            itemsBuilder: (context, chats) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: chats.length,
                itemBuilder: (context, i) {
                  final c = chats[i];
                  final names = (c['participantNames'] as Map?) ?? {};
                  final title = (names.values.isNotEmpty
                      ? names.values.first.toString()
                      : 'Chat');
                  final selected = c['id'] == _selectedChatId;
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? AppSpacing.sm : AppSpacing.md,
                      vertical: 1,
                    ),
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: const Color(0xFFE6ECF7),
                      selectedColor: AppTheme.primary,
                      leading: const RecordAvatar(icon: Icons.person_outline),
                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${c['lastMessage'] ?? 'No messages'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openChat(c, title),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Master/detail: list and messages side by side when there is room,
      // otherwise one pane at a time with a back button.
      final wide = constraints.maxWidth >= 760;
      if (!wide) {
        if (_selectedChatId == null) return _conversationList(compact: true);
        return _MessagesPane(
          chatId: _selectedChatId!,
          title: _selectedTitle,
          onBack: _closeChat,
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: constraints.maxWidth >= 1100 ? 360 : 300,
            child: Material(color: AppTheme.surface, child: _conversationList(compact: false)),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedChatId == null
                ? const EmptyState(
                    icon: Icons.chat_bubble_outline,
                    message: 'Select a conversation to view messages',
                  )
                : _MessagesPane(chatId: _selectedChatId!, title: _selectedTitle),
          ),
        ],
      );
    });
  }
}

class _MessagesPane extends StatefulWidget {
  const _MessagesPane({required this.chatId, required this.title, this.onBack});

  final String chatId;
  final String title;

  /// Shown as a back button on narrow layouts.
  final VoidCallback? onBack;

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

    Widget header(int? count) => Container(
        width: double.infinity,
        height: 56,
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        padding: EdgeInsets.only(left: widget.onBack == null ? AppSpacing.xl : AppSpacing.xs, right: AppSpacing.lg),
        child: Row(
          children: [
            if (widget.onBack != null)
              IconButton(
                tooltip: 'Back to conversations',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (count != null)
              Text('$count messages', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );

    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = const LoadingView(message: 'Loading messages...');
        } else if (snapshot.hasError) {
          content = ErrorBanner(
            message: reportError(snapshot.error!, context: 'load chat messages'),
            onRetry: _reload,
          );
        } else {
          final data = snapshot.data ?? const <String, dynamic>{};
          final messages = (data['messages'] as List? ?? const [])
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
          if (messages.isEmpty) {
            content = const EmptyState(icon: Icons.chat_bubble_outline, message: 'No messages yet');
          } else {
            return Column(
              children: [
                header(messages.length),
                Expanded(child: _messageList(messages, myUid)),
              ],
            );
          }
        }
        return Column(children: [header(null), Expanded(child: content)]);
      },
    );
  }

  Widget _messageList(List<Map<String, dynamic>> messages, String? myUid) {
    return ListView.builder(
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
              color: mine ? const Color(0xFFE6ECF7) : Colors.white,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: AppTheme.border),
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
              );
  }
}
