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

/// Manage legal cases.
class CasesScreen extends StatefulWidget {
  const CasesScreen({super.key});

  @override
  State<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends State<CasesScreen> {
  late Future<Paginated<CaseItem>> _future;
  int _page = 1;
  String _search = '';
  String? _status;
  String? _priority;
  String? _categoryId;
  String? _lawyerId;
  List<LegalCategory> _filterCategories = const <LegalCategory>[];
  List<Lawyer> _filterLawyers = const <Lawyer>[];
  String? _categoryFilterError;
  String? _lawyerFilterError;

  /// Debounces search input so one keystroke does not equal one request.
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    _loadFilterOptions();
  }

  @override
  void dispose() {
    // The timer lives on this State, so it is cancelled here — a pending
    // debounce must not fire a request after the screen is gone.
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<Paginated<CaseItem>> _fetch() {
    final api = AuthProvider.of(context).api;
    final query = <String, String>{
      'limit': '$kMaxPageSize',
      if (_search.isNotEmpty) 'search': _search,
      'status': ?_status,
      'priority': ?_priority,
      'categoryId': ?_categoryId,
      'lawyerId': ?_lawyerId,
    };
    return loadPaginated<CaseItem>(
      page: _page,
      fromJson: CaseItem.fromJson,
      request: (page) => api.get('cases', query: {'page': '$page', ...query}),
    );
  }

  static const List<String> _statusOptions = <String>['Open', 'In Progress', 'Pending', 'Closed'];
  static const List<String> _priorityOptions = <String>['High', 'Medium', 'Low'];

  bool get _hasFilters =>
      _status != null || _priority != null || _categoryId != null || _lawyerId != null;

  /// Loads category/lawyer filter options once. A failure disables only that
  /// filter (with the reason as tooltip); the case list keeps working.
  Future<void> _loadFilterOptions() async {
    final api = AuthProvider.of(context).api;
    try {
      final response = await api.get('categories', query: {'page': '1', 'limit': '$kMaxPageSize'});
      final categories = itemsOf(response)
          .map(LegalCategory.fromJson)
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
          .toList(growable: false);
      if (mounted) setState(() => _filterCategories = categories);
    } catch (error) {
      if (mounted) {
        setState(() => _categoryFilterError =
            'Category filter unavailable: ${reportError(error, context: 'case category filter')}');
      }
    }
    try {
      final response = await api.get('lawyers', query: {'page': '1', 'limit': '$kMaxPageSize'});
      final lawyers = itemsOf(response)
          .map(Lawyer.fromJson)
          .where((l) => l.id.isNotEmpty)
          .toList(growable: false);
      if (mounted) setState(() => _filterLawyers = lawyers);
    } catch (error) {
      if (mounted) {
        setState(() => _lawyerFilterError =
            'Lawyer filter unavailable: ${reportError(error, context: 'case lawyer filter')}');
      }
    }
  }

  Widget _filterDropdown({
    required String id,
    required String label,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
    String? disabledReason,
  }) {
    // Keep a selected value visible even if it is not among the loaded options.
    final entries = <String, String>{
      if (value != null && !options.containsKey(value)) value: value,
      ...options,
    };
    return FilterDropdown<String?>(
      label: label,
      value: value,
      dropdownKey: Key('case-filter-$id'),
      disabledReason: disabledReason,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text('All', style: TextStyle(color: Colors.grey.shade700)),
        ),
        for (final entry in entries.entries)
          DropdownMenuItem<String?>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  List<Widget> _buildFilters() {
    return [
          _filterDropdown(
            id: 'status',
            label: 'Status',
            value: _status,
            options: {for (final s in _statusOptions) s: s},
            onChanged: (v) {
              _status = v;
              _reload(resetPage: true);
            },
          ),
          _filterDropdown(
            id: 'priority',
            label: 'Priority',
            value: _priority,
            options: {for (final p in _priorityOptions) p: p},
            onChanged: (v) {
              _priority = v;
              _reload(resetPage: true);
            },
          ),
          _filterDropdown(
            id: 'category',
            label: 'Category',
            value: _categoryId,
            options: {for (final c in _filterCategories) c.id: c.name},
            disabledReason: _categoryFilterError,
            onChanged: (v) {
              _categoryId = v;
              _reload(resetPage: true);
            },
          ),
          _filterDropdown(
            id: 'lawyer',
            label: 'Lawyer',
            value: _lawyerId,
            options: {for (final l in _filterLawyers) l.id: l.name.isEmpty ? l.id : l.name},
            disabledReason: _lawyerFilterError,
            onChanged: (v) {
              _lawyerId = v;
              _reload(resetPage: true);
            },
          ),
          if (_hasFilters)
            TextButton.icon(
              key: const Key('case-filter-clear'),
              onPressed: () {
                _status = null;
                _priority = null;
                _categoryId = null;
                _lawyerId = null;
                _reload(resetPage: true);
              },
              icon: const Icon(Icons.filter_alt_off, size: 18),
              label: const Text('Clear filters'),
            ),
    ];
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

  Future<void> _openForm({CaseItem? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CaseDialog(item: item),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(CaseItem item) async {
    final api = AuthProvider.of(context).api;
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
            style: AppTheme.destructiveButtonStyle,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.delete('cases/${item.id}');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Case deleted')));
        _reload();
      }
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
          search: SearchField(
            hint: 'Search cases...',
            onChanged: (v) {
              _search = v;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () => _reload(resetPage: true));
            },
          ),
          filters: _buildFilters(),
          actions: [
            IconButton(
              tooltip: 'Refresh cases',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          primary: ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Case'),
          ),
        ),
        Expanded(
          child: PagedFutureView<CaseItem>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load caseitem list',
            empty: const EmptyState(icon: Icons.folder_copy, message: 'No cases found'),
            itemsBuilder: (context, cases) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: cases.length,
                itemBuilder: (context, i) {
                  final c = cases[i];
                  final category = c.categoryName.trim().isNotEmpty
                      ? c.categoryName.trim()
                      : c.caseType.trim();
                  final details = <String>[
                    if (c.clientName.trim().isNotEmpty) c.clientName.trim(),
                    if (category.isNotEmpty) category,
                    if (c.lawyerName.trim().isNotEmpty)
                      'Lawyer: ${c.lawyerName.trim()}',
                    if (c.dueDate.trim().isNotEmpty) 'Due ${c.dueDate.trim()}',
                  ];
                  return RecordTile(
                    title: c.title,
                    details: details.isEmpty ? const ['No case details'] : details,
                    badges: [
                      PriorityChip(priority: c.priority),
                      StatusChip(status: c.status),
                    ],
                    actions: [
                      RowAction(
                        icon: Icons.edit,
                        tooltip: 'Edit case',
                        onPressed: () => _openForm(item: c),
                      ),
                      RowAction(
                        icon: Icons.delete,
                        tooltip: 'Delete case',
                        destructive: true,
                        onPressed: () => _delete(c),
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

  /// The client the case will be owned by, or `null` when none is selected.
  /// Kept separate from [_client] (the display/legacy `clientName`).
  AppUser? _selectedClient;

  /// True while an existing case's stored owner is being looked up.
  bool _resolvingOwner = false;

  /// Explains why the stored owner could not be used, so the administrator is
  /// never quietly re-pointed at a different account.
  String? _ownerWarning;

  /// Inline validation message shown when a create is attempted without a
  /// client.
  String? _clientError;
  bool _lookupsStarted = false;
  bool _categoriesLoading = true;
  bool _lawyersLoading = false;
  bool _assignmentTouched = false;
  List<LegalCategory> _categories = const <LegalCategory>[];
  List<Lawyer> _categoryLawyers = const <Lawyer>[];
  String? _lookupError;
  String? _assignmentError;
  String? _selectedCategoryId;
  String? _selectedLawyerId;

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
    _selectedCategoryId = c?.categoryId.isNotEmpty == true ? c!.categoryId : null;
    _selectedLawyerId = c?.lawyerId.isNotEmpty == true ? c!.lawyerId : null;

    // Editing: resolve the stored owner, so that a legacy record owned by an
    // administrator (or by nobody) is visible rather than becoming a silent
    // reassignment on save. Deferred to after the first frame because
    // `_resolveOwner` calls `setState`, which must not run while `initState`
    // is still on the stack.
    if (c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveOwner(c.userId);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lookupsStarted) return;
    _lookupsStarted = true;
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _lookupError = null;
    });
    try {
      final response = await AuthProvider.of(context).api.get('categories', query: {
        'page': '1',
        'limit': '$kMaxPageSize',
      });
      final categories = itemsOf(response)
          .map(LegalCategory.fromJson)
          .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoriesLoading = false;
      });
      final selected = _selectedCategoryId;
      if (selected != null) await _loadLawyers(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _lookupError = friendlyError(error);
      });
    }
  }

  Future<void> _loadLawyers(String categoryId) async {
    setState(() {
      _lawyersLoading = true;
      _lookupError = null;
      _categoryLawyers = const <Lawyer>[];
    });
    try {
      final response = await AuthProvider.of(context).api.get('lawyers', query: {
        'page': '1',
        'limit': '$kMaxPageSize',
        'categoryId': categoryId,
      });
      final lawyers = itemsOf(response)
          .map(Lawyer.fromJson)
          .where((lawyer) => lawyer.id.isNotEmpty)
          .toList(growable: false);
      if (!mounted || _selectedCategoryId != categoryId) return;
      setState(() {
        _categoryLawyers = lawyers;
        _lawyersLoading = false;
      });
    } catch (error) {
      if (!mounted || _selectedCategoryId != categoryId) return;
      setState(() {
        _lawyersLoading = false;
        _lookupError = friendlyError(error);
      });
    }
  }

  void _onCategoryChanged(String? categoryId) {
    final selected = categoryId == null || categoryId.isEmpty ? null : categoryId;
    setState(() {
      _selectedCategoryId = selected;
      _selectedLawyerId = null;
      _assignmentTouched = true;
      _assignmentError = null;
      _lookupError = null;
      _categoryLawyers = const <Lawyer>[];
      _lawyersLoading = selected != null;
    });
    if (selected != null) _loadLawyers(selected);
  }

  void _onLawyerChanged(String? lawyerId) {
    setState(() {
      _selectedLawyerId = lawyerId;
      _assignmentTouched = true;
      _assignmentError = null;
    });
  }

  /// Looks up the case's stored owner and preselects it only when the account
  /// really is a client.
  ///
  /// The stored `userId` is the authorization owner, and older admin-created
  /// cases were saved against the administrator's own account because the
  /// form had no client field at all. Those records must keep their owner
  /// until an administrator explicitly picks a replacement.
  Future<void> _resolveOwner(String ownerId) async {
    if (ownerId.isEmpty) {
      setState(() {
        _ownerWarning = 'This case has no client stored (legacy record). '
            'Its owner stays unchanged unless you select a client.';
      });
      return;
    }

    setState(() => _resolvingOwner = true);
    final api = AuthProvider.of(context).api;

    try {
      final res = await api.get('users/$ownerId');
      final owner = AppUser.fromJson(objectDataOf(res));
      if (!mounted) return;
      setState(() {
        _resolvingOwner = false;
        if (owner.isClient) {
          // Preselected. `_client` keeps the stored display name untouched.
          _selectedClient = owner;
        } else {
          _ownerWarning =
              'The stored owner "${owner.name.isEmpty ? owner.id : owner.name}" '
              'is not a client account. Select a client to replace them, or '
              'leave the owner unchanged.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      final missing = e is ApiException && e.statusCode == 404;
      setState(() {
        _resolvingOwner = false;
        _ownerWarning = missing
            ? 'The stored owner no longer exists. Select a client to replace '
                'them, or leave the owner unchanged.'
            : 'The stored owner could not be verified. Select a client to '
                'replace them, or leave the owner unchanged.';
      });
    }
  }

  /// Handles an explicit pick from the list. Only this path changes ownership.
  void _onClientSelected(AppUser user) {
    setState(() {
      _selectedClient = user;
      _clientError = null;
      // The display field follows an explicit pick; a preselected existing
      // client leaves the stored name alone.
      if (user.name.isNotEmpty) _client.text = user.name;
    });
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

  /// Opens a calendar and writes the date as `yyyy-MM-dd`, the format the
  /// mobile app uses for due dates. The text field stays editable so legacy
  /// free-text values are preserved unless the administrator changes them.
  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_due.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    setState(() {
      _due.text = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    });
  }

  Future<void> _save() async {
    // Mirrors the database contract: cases.title must contain at least two
    // non-space characters (and at most 200 in rpc_admin_case_update).
    final title = _title.text.trim();
    if (title.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title must be at least 2 characters')),
      );
      return;
    }

    // A typed name is not an owner. Without a real client id the backend would
    // fall back to the administrator's own account (`CASE_WITHOUT_CLIENT`), so
    // a new case is simply not submitted.
    final creating = widget.item == null;
    if (creating && _selectedClient == null) {
      setState(() => _clientError = 'Select a client for this case.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a client for this case')),
      );
      return;
    }

    if ((creating || _assignmentTouched) &&
        (_selectedCategoryId == null || _selectedLawyerId == null)) {
      setState(() => _assignmentError = 'Select both a category and a lawyer.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select both a category and a lawyer')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _clientError = null;
      _assignmentError = null;
    });

    // `clientName` stays the display/legacy field; `userId` is the owner.
    var clientName = _client.text.trim();
    if (clientName.isEmpty) clientName = _selectedClient?.name ?? '';

    // A categorized case carries the category name as its legacy case type,
    // which the mobile app displays. rpc_admin_case_update and the category
    // rename trigger keep the same invariant; a direct insert must set it.
    var caseType = _type.text.trim();
    if (creating || _assignmentTouched) {
      for (final category in _categories) {
        if (category.id == _selectedCategoryId) {
          caseType = category.name;
          break;
        }
      }
    }

    final body = <String, dynamic>{
      'title': title,
      'clientName': clientName,
      'caseType': caseType,
      'dueDate': _due.text.trim(),
      'description': _desc.text.trim(),
      'priority': _priority,
      'status': _status,
    };

    if (creating || _assignmentTouched) {
      body['categoryId'] = _selectedCategoryId ?? '';
      body['lawyerId'] = _selectedLawyerId ?? '';
    }

    // Sent only for an explicit selection. On edit the key is omitted unless
    // the administrator picked somebody, and `PUT` merges only the fields it
    // receives — so an unresolved legacy owner is preserved, never reassigned.
    final selectedId = _selectedClient?.id ?? '';
    if (selectedId.isNotEmpty) body['userId'] = selectedId;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
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
              TextField(
                controller: _title,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              if (_resolvingOwner)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: const [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Checking the current owner…',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                )
              else if (_ownerWarning != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OwnerWarning(message: _ownerWarning!),
                ),
              ClientPickerField(
                selectedUserId: _selectedClient?.id,
                onSelected: _onClientSelected,
              ),
              if (_selectedClient != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: AppTheme.success),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Owner: ${_selectedClient!.name} '
                          '(${_selectedClient!.id})',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_clientError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _clientError!,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.danger),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _client,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Client name'),
              ),
              const SizedBox(height: 12),
              if (widget.item != null && widget.item!.categoryId.isEmpty) ...[
                TextField(
                  controller: _type,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Legacy case type (uncategorized record)',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_categoriesLoading)
                const LinearProgressIndicator()
              else if (_lookupError != null && _categories.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _loadCategories,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Could not load categories. Retry'),
                  ),
                )
              else if (_categories.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No legal categories exist yet. Add a category before creating assigned cases.'),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _categories.any((item) => item.id == _selectedCategoryId)
                      ? _selectedCategoryId
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Legal category'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Select a legal category'),
                    ),
                    ..._categories.map(
                      (category) => DropdownMenuItem<String>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    ),
                  ],
                  onChanged: _onCategoryChanged,
                ),
              if (_selectedCategoryId != null) ...[
                const SizedBox(height: 12),
                if (_lawyersLoading)
                  const LinearProgressIndicator()
                else if (_lookupError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _loadLawyers(_selectedCategoryId!),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Could not load lawyers. Retry'),
                    ),
                  )
                else if (_categoryLawyers.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No lawyers are assigned to this category yet.'),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _categoryLawyers.any((lawyer) => lawyer.id == _selectedLawyerId)
                        ? _selectedLawyerId
                        : '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Assigned lawyer'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Select a lawyer'),
                      ),
                      ..._categoryLawyers.map(
                        (lawyer) => DropdownMenuItem<String>(
                          value: lawyer.id,
                          child: Text(lawyer.name),
                        ),
                      ),
                    ],
                    onChanged: _onLawyerChanged,
                  ),
              ],
              if (_assignmentError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _assignmentError!,
                      style: const TextStyle(fontSize: 12, color: AppTheme.danger),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _due,
                decoration: InputDecoration(
                  labelText: 'Due date',
                  hintText: 'YYYY-MM-DD',
                  suffixIcon: IconButton(
                    tooltip: 'Pick due date',
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _pickDueDate,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                maxLines: 3,
                maxLength: 4000,
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

/// Amber notice about a case whose stored owner cannot be used as a client.
class _OwnerWarning extends StatelessWidget {
  const _OwnerWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
