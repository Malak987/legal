import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Manage legal cases.
class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  late Future<List<CaseItem>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<CaseItem>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('cases', query: {
      'page': '1',
      'limit': '200',
      if (_search.isNotEmpty) 'search': _search,
    });
    final data = res['data'] as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(CaseItem.fromJson).toList();
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _openForm({CaseItem? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CaseDialog(item: item),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(CaseItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete case'),
        content: Text('Delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await AuthProvider.of(context).api.delete('cases/${item.id}');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Case deleted')));
        _reload();
      }
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
              Expanded(
                child: SearchField(
                  hint: 'Search cases...',
                  onChanged: (v) {
                    _search = v;
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add Case'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<CaseItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
              }
              final cases = snapshot.data ?? [];
              if (cases.isEmpty) {
                return const EmptyState(icon: Icons.folder_copy, message: 'No cases found');
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: cases.length,
                itemBuilder: (context, i) {
                  final c = cases[i];
                  return Card(
                    child: ListTile(
                      title: Text(c.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${c.clientName}  •  ${c.caseType}  •  Due ${c.dueDate}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PriorityChip(priority: c.priority),
                          const SizedBox(width: 6),
                          StatusChip(status: c.status),
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppTheme.secondary),
                            onPressed: () => _openForm(item: c),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: AppTheme.danger),
                            onPressed: () => _delete(c),
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

class CaseDialog extends StatefulWidget {
  const CaseDialog({super.key, this.item});
  final CaseItem? item;

  @override
  State<CaseDialog> createState() => _CaseDialogState();
}

class _CaseDialogState extends State<CaseDialog> {
  late final TextEditingController _title;
  late final TextEditingController _client;
  late final TextEditingController _type;
  late final TextEditingController _due;
  late final TextEditingController _desc;
  late String _priority;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.item;
    _title = TextEditingController(text: c?.title ?? '');
    _client = TextEditingController(text: c?.clientName ?? '');
    _type = TextEditingController(text: c?.caseType ?? '');
    _due = TextEditingController(text: c?.dueDate ?? '');
    _desc = TextEditingController(text: c?.description ?? '');
    _priority = c?.priority ?? 'Medium';
    _status = c?.status ?? 'Open';
  }

  @override
  void dispose() {
    _title.dispose();
    _client.dispose();
    _type.dispose();
    _due.dispose();
    _desc.dispose();
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
    final body = {
      'title': _title.text.trim(),
      'clientName': _client.text.trim(),
      'caseType': _type.text.trim(),
      'dueDate': _due.text.trim(),
      'description': _desc.text.trim(),
      'priority': _priority,
      'status': _status,
    };
    try {
      final api = AuthProvider.of(context).api;
      if (widget.item == null) {
        await api.post('cases', body: body);
      } else {
        await api.put('cases/${widget.item!.id}', body: body);
      }
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
      title: Text(widget.item == null ? 'Add Case' : 'Edit Case'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(controller: _client, decoration: const InputDecoration(labelText: 'Client name')),
              const SizedBox(height: 12),
              TextField(controller: _type, decoration: const InputDecoration(labelText: 'Case type')),
              const SizedBox(height: 12),
              TextField(controller: _due, decoration: const InputDecoration(labelText: 'Due date')),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: const [
                  DropdownMenuItem(value: 'High', child: Text('High')),
                  DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'Low', child: Text('Low')),
                ],
                onChanged: (v) => setState(() => _priority = v ?? 'Medium'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Open', child: Text('Open')),
                  DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Closed', child: Text('Closed')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'Open'),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}
