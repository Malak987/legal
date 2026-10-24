import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Manage notifications: view, create, mark as read, delete.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<NotificationItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<NotificationItem>> _fetch() async {
    final res = await AuthProvider.of(context)
        .api
        .get('notifications', query: {'page': '1', 'limit': '$kMaxPageSize'});
    return itemsOf(res).map(NotificationItem.fromJson).toList();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _openForm() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const NotificationDialog(),
    );
    if (saved == true) _reload();
  }

  Future<void> _markRead(NotificationItem n) async {
    try {
      await AuthProvider.of(context)
          .api
          .put('notifications/${n.id}/read', body: {'read': !n.read});
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _delete(NotificationItem n) async {
    try {
      await AuthProvider.of(context).api.delete('notifications/${n.id}');
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _openForm,
                icon: const Icon(Icons.add),
                label: const Text('New Notification'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<NotificationItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.notifications,
                  message: 'No notifications found',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final n = items[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: n.read
                            ? Colors.grey.shade300
                            : AppTheme.primary.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.notifications,
                          color: n.read ? Colors.grey : AppTheme.primary,
                        ),
                      ),
                      title: Text(
                        n.title,
                        style: TextStyle(
                          fontWeight: n.read ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(n.content, maxLines: 2),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              n.read
                                  ? Icons.mark_email_unread
                                  : Icons.mark_email_read,
                              color: AppTheme.secondary,
                            ),
                            tooltip: n.read ? 'Mark unread' : 'Mark read',
                            onPressed: () => _markRead(n),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: AppTheme.danger),
                            onPressed: () => _delete(n),
                          ),
                        ],
                      ),
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
}

class NotificationDialog extends StatefulWidget {
  const NotificationDialog({super.key});

  @override
  State<NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends State<NotificationDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _userId = TextEditingController();
  final _type = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _userId.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthProvider.of(context).api.post('notifications', body: {
        'title': _title.text.trim(),
        'content': _content.text.trim(),
        'type': _type.text.trim(),
        if (_userId.text.trim().isNotEmpty) 'userId': _userId.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Notification'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(
                controller: _content,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Content'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userId,
                decoration: const InputDecoration(
                  labelText: 'User ID (optional — leave empty for all)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _type,
                decoration: const InputDecoration(labelText: 'Type (booking, payment...)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Send'),
        ),
      ],
    );
  }
}
