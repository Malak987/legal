import 'dart:async';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
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

  /// Debounces search input so one keystroke does not equal one request.
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Lawyer>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('lawyers', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
      if (_search.isNotEmpty) 'search': _search,
    });
    return itemsOf(res).map(Lawyer.fromJson).toList();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  Future<void> _openForm({Lawyer? lawyer}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => LawyerDialog(lawyer: lawyer),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Lawyer lawyer) async {
    final api = AuthProvider.of(context).api;
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
      await api.delete('lawyers/${lawyer.id}');
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
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
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
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 350), _reload);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh lawyers',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
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
                  final experience = l.experience.trim().isEmpty
                      ? 'Experience not set'
                      : l.experience.trim();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.person, color: AppTheme.primary),
                      ),
                      title: Text(l.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${l.specialty}  •  $experience  •  '
                        '${l.price}  •  ⭐ ${l.rating}',
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
  late final TextEditingController _price;
  late final TextEditingController _priceValue;
  late final TextEditingController _experience;
  late final TextEditingController _location;
  late final TextEditingController _image;
  late double _rating;
  bool _isPopular = false;
  bool _isTop = false;
  bool _saving = false;
  bool _categoriesStarted = false;
  bool _categoryChanged = false;
  String? _categoryId;
  late Future<List<LegalCategory>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    final l = widget.lawyer;
    _name = TextEditingController(text: l?.name ?? '');
    _price = TextEditingController(text: l?.price ?? '');
    _categoryId = l?.categoryId.isNotEmpty == true ? l!.categoryId : null;
    _priceValue = TextEditingController(text: _formatRate(l?.priceValue));
    _experience = TextEditingController(text: l?.experience ?? '');
    _location = TextEditingController(text: l?.location ?? '');
    _image = TextEditingController(text: l?.image ?? '');
    _rating = l?.rating ?? 4.5;
    _isPopular = l?.isPopular ?? false;
    _isTop = l?.isTop ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _priceValue.dispose();
    _experience.dispose();
    _location.dispose();
    _image.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categoriesStarted) return;
    _categoriesStarted = true;
    _categoriesFuture = _fetchCategories();
  }

  Future<List<LegalCategory>> _fetchCategories() async {
    final response = await AuthProvider.of(context).api.get('categories', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
    });
    return itemsOf(response)
        .map(LegalCategory.fromJson)
        .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Shows a rate without a pointless trailing `.0`.
  static String _formatRate(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }
    if (widget.lawyer == null && (_categoryId == null || _categoryId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a legal category for this lawyer')),
      );
      return;
    }

    // The booking API prices a booking as `priceValue * hours`. A lawyer with
    // no rate cannot be booked, so a new lawyer must have one. On edit an
    // empty field means "keep the stored rate" — omitting the key is what
    // stops this dialog from erasing a price that is already configured.
    final rateText = _priceValue.text.trim();
    double? rate;
    if (rateText.isNotEmpty) {
      rate = double.tryParse(rateText);
      if (rate == null || !rate.isFinite || rate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hourly rate must be a positive number (e.g. 150)'),
          ),
        );
        return;
      }
    } else if (widget.lawyer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hourly rate is required so clients can book this lawyer'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'experience': _experience.text.trim(),
      'price': _price.text.trim(),
      'location': _location.text.trim(),
      'image': _image.text.trim(),
      'rating': _rating,
      'isPopular': _isPopular,
      'isTop': _isTop,
    };
    // Keep the category relation unchanged unless selected on this form; the
    // backend derives the legacy specialty label from the category name.
    if (widget.lawyer == null || _categoryChanged) {
      body['categoryId'] = _categoryId ?? '';
    }
    // Added after the literal instead of with a collection-`if`: the stored
    // rate must simply be absent when the field was left empty on edit.
    if (rate != null) body['priceValue'] = rate;
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
              FutureBuilder<List<LegalCategory>>(
                future: _categoriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _categoriesFuture = _fetchCategories();
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Could not load categories. Retry'),
                      ),
                    );
                  }
                  final categories = snapshot.data ?? const <LegalCategory>[];
                  if (categories.isEmpty) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No legal categories are available. Add a category before assigning one to a new lawyer.',
                        ),
                      ),
                    );
                  }
                  final currentId = categories.any((category) => category.id == _categoryId)
                      ? _categoryId
                      : null;
                  return DropdownButtonFormField<String>(
                    initialValue: currentId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Legal category'),
                    items: [
                      DropdownMenuItem<String>(
                        value: '',
                        child: Text(widget.lawyer == null
                            ? 'Select a category'
                            : 'No category (legacy profile)'),
                      ),
                      ...categories.map(
                        (category) => DropdownMenuItem<String>(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _categoryId = value == null || value.isEmpty ? null : value;
                      _categoryChanged = true;
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _experience,
                decoration: const InputDecoration(
                  labelText: 'Experience',
                  hintText: 'e.g. 8 years or Senior counsel',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Price (e.g. \$150/hr)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceValue,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Hourly rate (number only, e.g. 150)',
                  helperText: widget.lawyer == null
                      ? 'Required: bookings are priced as rate x hours'
                      : 'Leave empty to keep the current rate',
                ),
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
