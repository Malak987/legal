import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Manage subscription plans.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<List<Plan>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Plan>> _fetch() async {
    final res = await AuthProvider.of(context)
        .api
        .get('plans', query: {'page': '1', 'limit': '$kMaxPageSize'});
    return itemsOf(res).map(Plan.fromJson).toList();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _openForm({Plan? plan}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => PlanDialog(plan: plan),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Plan p) async {
    final api = AuthProvider.of(context).api;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete plan'),
        content: Text('Delete plan "${p.title}"?'),
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
      await api.delete('plans/${p.id}');
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Color _parseColor(String hex) {
    final v = hex.replaceAll('#', '');
    if (v.length == 6) {
      return Color(int.parse('FF$v', radix: 16));
    }
    return AppTheme.secondary;
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
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add Plan'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Plan>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
              }
              final plans = snapshot.data ?? [];
              if (plans.isEmpty) {
                return const EmptyState(
                  icon: Icons.subscriptions,
                  message: 'No plans found',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.95,
                ),
                itemCount: plans.length,
                itemBuilder: (context, i) {
                  final p = plans[i];
                  final color = _parseColor(p.color);
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (p.isPopular)
                                const Chip(
                                  label: Text('Popular',
                                      style: TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              p.price,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final f in p.features)
                                    Padding(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.check_circle,
                                              size: 16,
                                              color: AppTheme.success),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: Text(f,
                                                  style:
                                                      const TextStyle(fontSize: 13))),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: AppTheme.secondary),
                                onPressed: () => _openForm(plan: p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: AppTheme.danger),
                                onPressed: () => _delete(p),
                              ),
                            ],
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

class PlanDialog extends StatefulWidget {
  const PlanDialog({super.key, this.plan});
  final Plan? plan;

  @override
  State<PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<PlanDialog> {
  late final TextEditingController _title;
  late final TextEditingController _price;
  late final TextEditingController _features;
  late String _color;
  bool _popular = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _title = TextEditingController(text: p?.title ?? '');
    _price = TextEditingController(text: p?.price ?? '');
    _features = TextEditingController(text: p?.features.join('\n') ?? '');
    _color = p?.color ?? '#3498DB';
    _popular = p?.isPopular ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _features.dispose();
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
      'price': _price.text.trim(),
      'color': _color,
      'isPopular': _popular,
      'features': _features.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    };
    try {
      final api = AuthProvider.of(context).api;
      if (widget.plan == null) {
        await api.post('plans', body: body);
      } else {
        await api.put('plans/${widget.plan!.id}', body: body);
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
      title: Text(widget.plan == null ? 'Add Plan' : 'Edit Plan'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 12),
              TextField(controller: _price, decoration: const InputDecoration(labelText: 'Price')),
              const SizedBox(height: 12),
              TextField(
                controller: _features,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Features (one per line)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _color,
                decoration: const InputDecoration(labelText: 'Color'),
                items: const [
                  DropdownMenuItem(value: '#3498DB', child: Text('Blue')),
                  DropdownMenuItem(value: '#E74C3C', child: Text('Red')),
                  DropdownMenuItem(value: '#27AE60', child: Text('Green')),
                  DropdownMenuItem(value: '#F39C12', child: Text('Orange')),
                  DropdownMenuItem(value: '#8E44AD', child: Text('Purple')),
                ],
                onChanged: (v) => setState(() => _color = v ?? '#3498DB'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Popular'),
                value: _popular,
                onChanged: (v) => setState(() => _popular = v),
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
