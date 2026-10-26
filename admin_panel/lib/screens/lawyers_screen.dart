import 'dart:async';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/client_picker.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Manage lawyers (list, create, update, delete).
class LawyersScreen extends StatefulWidget {
  const LawyersScreen({super.key});

  @override
  State<LawyersScreen> createState() => _LawyersScreenState();
}

class _LawyersScreenState extends State<LawyersScreen> {
  late Future<Paginated<Lawyer>> _future;
  int _page = 1;
  String _search = '';

  /// Debounces search input so one keystroke does not equal one request.
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Lawyer>> _fetch() {
    final api = AuthProvider.of(context).api;
    final search = _search;
    return loadPaginated<Lawyer>(
      page: _page,
      fromJson: Lawyer.fromJson,
      request: (page) => api.get('lawyers', query: {
        'page': '$page',
        'limit': '$kMaxPageSize',
        if (search.isNotEmpty) 'search': search,
      }),
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
            style: AppTheme.destructiveButtonStyle,
            child: const Text('Delete'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
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
        ListToolbar(
          search: SearchField(
            hint: 'Search lawyers...',
            onChanged: (v) {
              _search = v;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () => _reload(resetPage: true));
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh lawyers',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          primary: ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Lawyer'),
          ),
        ),
        Expanded(
          child: PagedFutureView<Lawyer>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load lawyer list',
            empty: const EmptyState(
                  icon: Icons.gavel,
                  message: 'No lawyers found',
                ),
            itemsBuilder: (context, lawyers) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: lawyers.length,
                itemBuilder: (context, i) {
                  final l = lawyers[i];
                  final experience = l.experience.trim().isEmpty
                      ? 'Experience not set'
                      : l.experience.trim();
                  return RecordTile(
                    leading: const RecordAvatar(icon: Icons.person_outline),
                    title: l.name,
                    details: [l.specialty, experience, l.price, '★ ${l.rating}'],
                    badges: [
                      if (l.isPopular)
                        const StatusBadge(label: 'Popular', color: AppTheme.accent, icon: Icons.trending_up),
                      if (l.isTop)
                        const StatusBadge(label: 'Top', color: AppTheme.secondary, icon: Icons.workspace_premium_outlined),
                    ],
                    actions: [
                      RowAction(
                        icon: Icons.edit,
                        tooltip: 'Edit lawyer',
                        onPressed: () => _openForm(lawyer: l),
                      ),
                      RowAction(
                        icon: Icons.delete,
                        tooltip: 'Delete lawyer',
                        destructive: true,
                        onPressed: () => _delete(l),
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
  late final TextEditingController _bio;
  late double _rating;

  /// The linked `lawyer`-role account (`lawyers.user_id`). The lawyer
  /// workspace and assigned-case access depend on this link.
  String? _linkedUserId;
  String _linkedUserLabel = '';

  /// True only after an explicit pick or unlink. The `userId` key is sent
  /// only then, so an untouched form never changes the stored link.
  bool _linkChanged = false;
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
    _bio = TextEditingController(text: l?.bio ?? '');
    _linkedUserId = l?.userId.isNotEmpty == true ? l!.userId : null;
    _linkedUserLabel = _linkedUserId ?? '';
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
    _bio.dispose();
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
    // rpc_admin_lawyer_save rejects names shorter than 2 characters.
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least 2 characters')),
      );
      return;
    }
    // The save RPC requires a category on create and on edit
    // (CATEGORY_REQUIRED); an empty selection never clears a stored one.
    if (_categoryId == null || _categoryId!.isEmpty) {
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
    } else if (widget.lawyer == null || (widget.lawyer!.priceValue ?? 0) <= 0) {
      // A stored rate of 0 is rejected by the save RPC, so "keep the current
      // rate" is only possible when a positive rate is already stored.
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
      'bio': _bio.text.trim(),
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
    // An empty string unlinks (the RPC stores NULL); absent keeps the link.
    if (_linkChanged) body['userId'] = _linkedUserId ?? '';
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
            .showSnackBar(SnackBar(content: Text(reportError(e))));
      }
    }
  }

  /// Linked lawyer-account section: shows the current link, offers an
  /// explicit unlink, and a picker restricted to `lawyer`-role profiles.
  Widget _buildAccountLink() {
    final linked = _linkedUserId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              linked == null ? Icons.link_off : Icons.link,
              size: 16,
              color: linked == null ? Colors.grey : AppTheme.success,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                linked == null
                    ? 'No lawyer account linked (the lawyer cannot sign in to '
                        'their workspace).'
                    : 'Linked account: $_linkedUserLabel'
                        '${_linkedUserLabel == linked ? '' : ' ($linked)'}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
            if (linked != null)
              TextButton(
                onPressed: () => setState(() {
                  _linkedUserId = null;
                  _linkedUserLabel = '';
                  _linkChanged = true;
                }),
                child: const Text('Unlink'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClientPickerField(
          selectedUserId: _linkedUserId,
          requiredRole: 'lawyer',
          roleLabel: 'lawyer account',
          onSelected: (user) => setState(() {
            _linkedUserId = user.id;
            _linkedUserLabel = user.name.isEmpty ? user.id : user.name;
            _linkChanged = true;
          }),
        ),
      ],
    );
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
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              _buildAccountLink(),
              const SizedBox(height: 12),
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
                            : 'Select a category (required)'),
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
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Experience',
                  hintText: 'e.g. 8 years or Senior counsel',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                maxLength: 80,
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
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bio,
                maxLines: 4,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _image,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Image path (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Tooltip(
                    message: 'Recalculated automatically when clients add or '
                        'change reviews.',
                    child: Text('Rating: ${_rating.toStringAsFixed(1)}'),
                  ),
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
