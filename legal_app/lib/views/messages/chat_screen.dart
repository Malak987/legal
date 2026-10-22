import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../services/api_client.dart';
import '../../state/session_scope.dart';
import '../../widgets/customapp_bar.dart';
import '../../widgets/detailstext1.dart';
import '../../widgets/detailstext2.dart';
import 'chatdetailsscreen.dart';

/// Conversation list backed by `GET /api/chats`.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _chats;
  bool _loaded = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _chats = Future.value(const <Map<String, dynamic>>[]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    final future = SessionScope.read(context).repository.fetchChats();
    setState(() {
      _chats = future;
    });
    return future.then((_) {}, onError: (_) {});
  }

  String _resolvePeerName(Map<String, dynamic> chat, String? currentUid) {
    final names = chat['participantNames'];
    if (names is Map) {
      for (final entry in names.entries) {
        final key = entry.key.toString();
        final value = entry.value?.toString().trim() ?? '';
        if (key != currentUid && value.isNotEmpty) {
          return value;
        }
      }
      for (final value in names.values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      }
    }
    return 'Legal Consultation';
  }

  String _formatTime(dynamic raw) {
    final value = raw?.toString() ?? '';
    if (value.isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = SessionScope.of(context).repository.currentUid;

    return Scaffold(
      backgroundColor: AppColors.bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomAppBar(text: 'Messages', text1: ''),
              const SizedBox(height: 15),
              _buildSearchBar(),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _chats,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ChatStatus(
                        icon: Icons.error_outline,
                        title: 'Could not load messages',
                        detail: snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'Please try again.',
                        onRetry: _reload,
                      );
                    }

                    final allChats =
                        snapshot.data ?? const <Map<String, dynamic>>[];
                    final query = _searchQuery.trim().toLowerCase();
                    final chats = query.isEmpty
                        ? allChats
                        : allChats.where((chat) {
                            final peer =
                                _resolvePeerName(chat, currentUid).toLowerCase();
                            final last = (chat['lastMessage']?.toString() ?? '')
                                .toLowerCase();
                            return peer.contains(query) || last.contains(query);
                          }).toList();

                    if (chats.isEmpty) {
                      return _ChatStatus(
                        icon: Icons.chat_bubble_outline,
                        title: query.isEmpty
                            ? 'No conversations yet'
                            : 'No matching conversations',
                        detail: query.isEmpty
                            ? 'Active conversations with your lawyer or client will appear here.'
                            : 'Nothing matches "$_searchQuery".',
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final chatId = chat['id']?.toString() ?? '';
                          final name = _resolvePeerName(chat, currentUid);
                          final lastMessage =
                              (chat['lastMessage']?.toString() ?? '').trim();
                          final time = _formatTime(
                            chat['lastMessageTime'] ?? chat['updatedAt'],
                          );

                          return GestureDetector(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatDetailsScreen(
                                    chatId: chatId,
                                    userName: name,
                                  ),
                                ),
                              );
                              if (mounted) _reload();
                            },
                            child: _buildChatTile(
                              name: name,
                              message: lastMessage.isEmpty
                                  ? 'Tap to open conversation'
                                  : lastMessage,
                              time: time,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search messages',
          border: InputBorder.none,
          icon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildChatTile({
    required String name,
    required String message,
    required String time,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundImage: AssetImage('images/c3.png'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text1(text1: name, size: 16),
                const SizedBox(height: 4),
                Text2(text2: message),
              ],
            ),
          ),
          if (time.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text2(text2: time),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChatStatus extends StatelessWidget {
  const _ChatStatus({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.text3Color),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.text2Color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
