import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Manage subscription plans.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late Future<Paginated<Plan>> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Plan>> _fetch() {
    final api = AuthProvider.of(context).api;
    return loadPaginated<Plan>(
      page: _page,
      fromJson: Plan.fromJson,
      request: (page) => api.get('plans', query: {'page': '$page', 'limit': '$kMaxPageSize'}),
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
            style: AppTheme.destructiveButtonStyle,
            child: const Text('Delete'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
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
        ListToolbar(
          leading: Text(
            'Subscription plans offered to clients.',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary),
          ),
          primary: ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Plan'),
          ),
        ),
        Expanded(
          child: PagedFutureView<Plan>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load plan list',
            empty: const EmptyState(
                  icon: Icons.subscriptions,
                  message: 'No plans found',
                ),
            itemsBuilder: (context, plans) {
              final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;
              final theme = Theme.of(context);
              // Cards size to their content (no fixed aspect ratio), so long
              // feature lists can never overflow the card.
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? AppSpacing.lg : AppSpacing.xl,
                  AppSpacing.xs,
                  compact ? AppSpacing.lg : AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: ResponsiveGrid(
                  minItemWidth: 250,
                  spacing: AppSpacing.lg,
                  children: [
                    for (final p in plans)
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(height: 4, color: _parseColor(p.color)),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(p.title, style: theme.textTheme.titleMedium!.copyWith(fontSize: 17)),
                                      ),
                                      if (p.isPopular)
                                        const StatusBadge(label: 'Popular', color: AppTheme.accent, icon: Icons.trending_up),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(p.price, style: theme.textTheme.headlineSmall),
                                  const SizedBox(height: AppSpacing.md),
                                  if (p.features.isEmpty)
                                    Text('No features listed', style: theme.textTheme.bodySmall)
                                  else
                                    for (final f in p.features)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding: EdgeInsets.only(top: 2),
                                              child: Icon(Icons.check, size: 16, color: AppTheme.success),
                                            ),
                                            const SizedBox(width: AppSpacing.sm),
                                            Expanded(child: Text(f, style: theme.textTheme.bodyMedium!.copyWith(fontSize: 13.5))),
                                          ],
                                        ),
                                      ),
                                ],
                              ),
                            ),
                            const Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  RowAction(
                                    icon: Icons.edit,
                                    tooltip: 'Edit plan',
                                    onPressed: () => _openForm(plan: p),
                                  ),
                                  RowAction(
                                    icon: Icons.delete,
                                    tooltip: 'Delete plan',
                                    destructive: true,
                                    onPressed: () => _delete(p),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
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
  late final TextEditingController _priceValue;
  late final TextEditingController _features;
  late String _color;

  static const Map<String, String> _palette = {
    '#3498DB': 'Blue',
    '#E74C3C': 'Red',
    '#27AE60': 'Green',
    '#F39C12': 'Orange',
    '#8E44AD': 'Purple',
  };
  bool _popular = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _title = TextEditingController(text: p?.title ?? '');
    _price = TextEditingController(text: p?.price ?? '');
    final value = p?.priceValue ?? 0;
    _priceValue = TextEditingController(
      text: p == null
          ? ''
          : (value == value.roundToDouble()
              ? value.toStringAsFixed(0)
              : value.toString()),
    );
    _features = TextEditingController(text: p?.features.join('\n') ?? '');
    _color = p?.color ?? '#3498DB';
    _popular = p?.isPopular ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _priceValue.dispose();
    _features.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // plans.title CHECK requires at least 2 non-space characters.
    if (_title.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title must be at least 2 characters')),
      );
      return;
    }
    // plans.price_value is NUMERIC(12,2) NOT NULL CHECK (>= 0).
    final valueText = _priceValue.text.trim();
    final priceValue = valueText.isEmpty ? 0.0 : double.tryParse(valueText);
    if (priceValue == null ||
        !priceValue.isFinite ||
        priceValue < 0 ||
        priceValue >= 10000000000 ||
        priceValue != double.parse(priceValue.toStringAsFixed(2))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numeric price must be 0 or more, with at most 2 decimals'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final body = {
      'title': _title.text.trim(),
      'price': _price.text.trim(),
      'priceValue': priceValue,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
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
              TextField(
                controller: _price,
                decoration: const InputDecoration(
                  labelText: 'Price label',
                  hintText: r'e.g. $29 / month',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceValue,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Numeric price (e.g. 29)',
                  helperText: 'Used to order plans in the app and admin panel',
                ),
              ),
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
                // A stored colour outside the palette (e.g. the DB default
                // #3A86FF) is kept as its own entry; otherwise the dropdown
                // has no item matching its value and fails to build.
                items: [
                  for (final entry in _palette.entries)
                    DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                  if (!_palette.containsKey(_color))
                    DropdownMenuItem(
                      value: _color,
                      child: Text('Current ($_color)'),
                    ),
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
