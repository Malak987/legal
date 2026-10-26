import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/client_picker.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Manage notifications: view, create, mark as read, delete.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<Paginated<NotificationItem>> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<NotificationItem>> _fetch() {
    final api = AuthProvider.of(context).api;
    return loadPaginated<NotificationItem>(
      page: _page,
      fromJson: NotificationItem.fromJson,
      request: (page) => api.get('notifications', query: {'page': '$page', 'limit': '$kMaxPageSize'}),
    );
  }

  /// Re-fetches; [resetPage] returns to page 1 (search/filter changes).
  void _reload({bool resetPage = false}) {
    if (!mounted) return;
    setState(() {
      if (resetPage) _page = 1;
      _future = _fetch();
    });
  }

  void _goToPage(int page) {
    setState(() {
      _page = page;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
      }
    }
  }

  Future<void> _delete(NotificationItem n) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete notification'),
        content: Text('Delete "${n.title}"? The recipient will no longer see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: AppTheme.destructiveButtonStyle,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await AuthProvider.of(context).api.delete('notifications/${n.id}');
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListToolbar(
          primary: ElevatedButton.icon(
            onPressed: _openForm,
            icon: const Icon(Icons.add),
            label: const Text('New Notification'),
          ),
        ),
        Expanded(
          child: PagedFutureView<NotificationItem>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load notificationitem list',
            empty: const EmptyState(
                  icon: Icons.notifications,
                  message: 'No notifications found',
                ),
            itemsBuilder: (context, items) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final n = items[i];
                  return RecordTile(
                    leading: RecordAvatar(
                      icon: n.read ? Icons.notifications_none : Icons.notifications_active_outlined,
                      color: n.read ? AppTheme.textMuted : AppTheme.primary,
                    ),
                    title: n.title,
                    subtitle: 'To: ${n.recipientLabel}',
                    extra: n.content.trim().isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              n.content,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
                            ),
                          ),
                    badges: [
                      n.read
                          ? const StatusBadge(label: 'Read', color: AppTheme.textMuted, icon: Icons.done_all)
                          : const StatusBadge(label: 'Unread', color: AppTheme.secondary),
                    ],
                    actions: [
                      RowAction(
                        icon: n.read ? Icons.mark_email_unread : Icons.mark_email_read,
                        tooltip: n.read ? 'Mark unread' : 'Mark read',
                        onPressed: () => _markRead(n),
                      ),
                      RowAction(
                        icon: Icons.delete,
                        tooltip: 'Delete notification',
                        destructive: true,
                        onPressed: () => _delete(n),
                      ),
                    ],
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
  final _type = TextEditingController();
  bool _saving = false;

  /// notifications.user_id is NOT NULL and there is no broadcast contract, so
  /// every notification needs exactly one recipient chosen from the picker.
  String _recipientRole = 'client';
  AppUser? _recipient;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title must be at least 2 characters')),
      );
      return;
    }
    final recipient = _recipient;
    if (recipient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a recipient')),
      );
      return;
    }
    setState(() => _saving = true);
    final type = _type.text.trim();
    try {
      await AuthProvider.of(context).api.post('notifications', body: {
        'title': _title.text.trim(),
        'content': _content.text.trim(),
        // Omitted when empty so the column default ('general') applies.
        if (type.isNotEmpty) 'type': type,
        'userId': recipient.id,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
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
              DropdownButtonFormField<String>(
                initialValue: _recipientRole,
                decoration: const InputDecoration(labelText: 'Recipient role'),
                items: const [
                  DropdownMenuItem(value: 'client', child: Text('Client')),
                  DropdownMenuItem(value: 'lawyer', child: Text('Lawyer')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setState(() {
                  _recipientRole = v ?? 'client';
                  _recipient = null;
                }),
              ),
              const SizedBox(height: 12),
              ClientPickerField(
                // Re-created per role so the search restarts for that role.
                key: ValueKey('recipient-$_recipientRole'),
                selectedUserId: _recipient?.id,
                requiredRole: _recipientRole,
                roleLabel: _recipientRole,
                onSelected: (user) => setState(() => _recipient = user),
              ),
              if (_recipient != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Recipient: ${_recipient!.name} (${_recipient!.id})',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _type,
                decoration: const InputDecoration(
                  labelText: 'Type (optional, e.g. booking, payment)',
                  helperText: 'Defaults to "general"',
                ),
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
