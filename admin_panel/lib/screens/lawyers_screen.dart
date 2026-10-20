import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Manage lawyers (list, create, update, delete).
class LawyersScreen extends StatefulWidget {
  const LawyersScreen({super.key});

  @override
  State<LawyersScreen> createState() => _LawyersScreenState();
}

class _LawyersScreenState extends State<LawyersScreen> {
  late Future<List<Lawyer>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Lawyer>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('lawyers', query: {
      'page': '1',
      'limit': '200',
      if (_search.isNotEmpty) 'search': _search,
    });
    final data = res['data'] as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Lawyer.fromJson).toList();
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _openForm({Lawyer? lawyer}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LawyerDialog(lawyer: lawyer),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Lawyer lawyer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete lawyer'),
        content: Text('Delete "${lawyer.name}"? This cannot be undone.'),
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
      await AuthProvider.of(context).api.delete('lawyers/${lawyer.id}');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Lawyer deleted')));
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
                  hint: 'Search lawyers...',
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
                label: const Text('Add Lawyer'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Lawyer>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(
                  message: '${snapshot.error}',
                  onRetry: _reload,
                );
              }
              final lawyers = snapshot.data ?? [];
              if (lawyers.isEmpty) {
                return const EmptyState(
                  icon: Icons.gavel,
                  message: 'No lawyers found',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: lawyers.length,
                itemBuilder: (context, i) {
                  final l = lawyers[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.person, color: AppTheme.primary),
                      ),
                      title: Text(l.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${l.specialty}  •  ${l.price}  •  ⭐ ${l.rating}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (l.isPopular)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Chip(
                                label: Text('Popular', style: TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          if (l.isTop)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Chip(
                                label: Text('Top', style: TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppTheme.secondary),
                            onPressed: () => _openForm(lawyer: l),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: AppTheme.danger),
                            onPressed: () => _delete(l),
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

/// Create / edit dialog for a lawyer.
class LawyerDialog extends StatefulWidget {
  const LawyerDialog({super.key, this.lawyer});
  final Lawyer? lawyer;

  @override
  State<LawyerDialog> createState() => _LawyerDialogState();
}

class _LawyerDialogState extends State<LawyerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _specialty;
  late final TextEditingController _price;
  late final TextEditingController _location;
  late final TextEditingController _image;
  late double _rating;
  bool _isPopular = false;
  bool _isTop = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.lawyer;
    _name = TextEditingController(text: l?.name ?? '');
    _specialty = TextEditingController(text: l?.specialty ?? '');
    _price = TextEditingController(text: l?.price ?? '');
    _location = TextEditingController(text: l?.location ?? '');
    _image = TextEditingController(text: l?.image ?? '');
    _rating = l?.rating ?? 4.5;
    _isPopular = l?.isPopular ?? false;
    _isTop = l?.isTop ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _specialty.dispose();
    _price.dispose();
    _location.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    setState(() => _saving = true);
    final body = {
      'name': _name.text.trim(),
      'specialty': _specialty.text.trim(),
      'price': _price.text.trim(),
      'location': _location.text.trim(),
      'image': _image.text.trim(),
      'rating': _rating,
      'isPopular': _isPopular,
      'isTop': _isTop,
    };
    try {
      final api = AuthProvider.of(context).api;
      if (widget.lawyer == null) {
        await api.post('lawyers', body: body);
      } else {
        await api.put('lawyers/${widget.lawyer!.id}', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.lawyer == null ? 'Add Lawyer' : 'Edit Lawyer'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _specialty,
                decoration: const InputDecoration(labelText: 'Specialty'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Price (e.g. \$150/hr)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _image,
                decoration: const InputDecoration(labelText: 'Image path (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Rating: ${_rating.toStringAsFixed(1)}'),
                  Expanded(
                    child: Slider(
                      value: _rating,
                      min: 0,
                      max: 5,
                      divisions: 50,
                      label: _rating.toStringAsFixed(1),
                      onChanged: (v) => setState(() => _rating = v),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                title: const Text('Popular'),
                value: _isPopular,
                onChanged: (v) => setState(() => _isPopular = v),
              ),
              SwitchListTile(
                title: const Text('Top lawyer'),
                value: _isTop,
                onChanged: (v) => setState(() => _isTop = v),
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
