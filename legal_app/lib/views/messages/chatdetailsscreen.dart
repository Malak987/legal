import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../services/api_client.dart';
import '../../state/session_scope.dart';
import '../../widgets/detailstext1.dart';
import '../../widgets/detailstext2.dart';

/// Conversation thread backed by `GET /api/chats/:id` and
/// `POST /api/chats/:id/messages`.
class ChatDetailsScreen extends StatefulWidget {
  final String chatId;
  final String userName;
  final String avatarUrl;

  const ChatDetailsScreen({
    super.key,
    this.chatId = '',
    this.userName = 'Conversation',
    this.avatarUrl = 'images/c3.png',
  });

  @override
  State<ChatDetailsScreen> createState() => _ChatDetailsScreenState();
}

class _ChatDetailsScreenState extends State<ChatDetailsScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = const <Map<String, dynamic>>[];
  String _resolvedTitle = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _resolvedTitle = widget.userName;
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (widget.chatId.isEmpty) {
      setState(() {
        _loading = false;
        _messages = const <Map<String, dynamic>>[];
        _error = 'Select a conversation from Messages to view and send replies.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final repo = SessionScope.read(context).repository;
    final currentUid = repo.currentUid;

    try {
      final data = await repo.fetchChatMessages(widget.chatId);
      if (!mounted) return;
      final rawMessages = data['messages'];
      final list = rawMessages is List
          ? rawMessages
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList()
          : const <Map<String, dynamic>>[];

      var title = widget.userName;
      final names = data['participantNames'];
      if (names is Map) {
        for (final entry in names.entries) {
          if (entry.key.toString() != currentUid &&
              entry.value != null &&
              entry.value.toString().trim().isNotEmpty) {
            title = entry.value.toString().trim();
            break;
          }
        }
      }

      setState(() {
        _messages = list;
        _resolvedTitle = title;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load messages. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending || widget.chatId.isEmpty) return;

    setState(() => _sending = true);
    final repo = SessionScope.read(context).repository;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await repo.sendMessage(chatId: widget.chatId, text: text);
      if (!mounted) return;
      _messageController.clear();
      await _loadMessages();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to send message.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatTimestamp(dynamic raw) {
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
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody(currentUid)),
            if (widget.chatId.isNotEmpty) _buildMessageInputField(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      color: AppColors.buttonColor,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 22,
            backgroundImage: AssetImage(widget.avatarUrl),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text1(
                  text1: _resolvedTitle.isEmpty
                      ? 'Conversation'
                      : _resolvedTitle,
                  color: Colors.white,
                  size: 18,
                ),
                const Text2(
                  text2: 'Direct Message',
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _loadMessages,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh messages',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String? currentUid) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 46,
                color: AppColors.text3Color,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.text2Color,
                ),
              ),
              if (widget.chatId.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loadMessages,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'No messages yet. Send a message below to start the conversation.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.text2Color),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final senderId = msg['senderId']?.toString() ?? '';
        final isSentByMe = currentUid != null && senderId == currentUid;
        final text = msg['text']?.toString() ?? '';
        final time = _formatTimestamp(msg['timestamp'] ?? msg['createdAt']);

        return isSentByMe
            ? _buildSentMessage(text, time)
            : _buildReceivedMessage(text, time);
      },
    );
  }

  Widget _buildReceivedMessage(String message, String time) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text1(text1: message, size: 15),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.bottomRight,
                child: Text2(text2: time, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSentMessage(String message, String time) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: const BoxDecoration(
          color: AppColors.buttonColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text1(text1: message, color: Colors.white, size: 15),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.bottomRight,
                child: Text2(text2: time, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _messageController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _sendMessage,
            child: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.buttonColor,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
