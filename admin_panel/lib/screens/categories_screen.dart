import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Administrator CRUD for the public legal-category catalogue.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<Paginated<LegalCategory>> _future;
  String _search = '';
  int _page = 1;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<LegalCategory>> _fetch() {
    final api = AuthProvider.of(context).api;
    final search = _search.trim();
    return loadPaginated<LegalCategory>(
      page: _page,
      fromJson: LegalCategory.fromJson,
      request: (page) => api.get('categories', query: {
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

  Future<void> _openForm({LegalCategory? category}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CategoryDialog(category: category),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(LegalCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete legal category'),
        content: Text(
          'Delete "${category.name}"? Categories assigned to a lawyer or case cannot be deleted.',
        ),
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
    if (!mounted || confirmed != true) return;

    try {
      await AuthProvider.of(context).api.delete('categories/${category.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Legal category deleted')),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, context: 'delete category'))),
      );
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
            hint: 'Search categories...',
            onChanged: (v) {
              _search = v;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () => _reload(resetPage: true));
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh categories',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          primary: ElevatedButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Category'),
          ),
        ),
        Expanded(
          child: PagedFutureView<LegalCategory>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load categories',
            empty: const EmptyState(
              icon: Icons.category_outlined,
              message: 'No legal categories found',
            ),
            itemsBuilder: (context, items) {
              final categories = items
                  .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
                  .toList(growable: false);
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return RecordTile(
                    leading: const RecordAvatar(icon: Icons.category_outlined),
                    title: category.name,
                    subtitle: category.slug,
                    actions: [
                      RowAction(
                        icon: Icons.edit,
                        tooltip: 'Edit category',
                        onPressed: () => _openForm(category: category),
                      ),
                      RowAction(
                        icon: Icons.delete,
                        tooltip: 'Delete category',
                        destructive: true,
                        onPressed: () => _delete(category),
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

class CategoryDialog extends StatefulWidget {
  const CategoryDialog({super.key, this.category});

  final LegalCategory? category;

  @override
  State<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<CategoryDialog> {
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category name must be at least 2 characters')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = AuthProvider.of(context).api;
      final body = <String, dynamic>{'name': name};
      if (widget.category == null) {
        await api.post('categories', body: body);
      } else {
        await api.put('categories/${widget.category!.id}', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reportError(error, context: 'save category'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'Add Category' : 'Edit Category'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category name',
            helperText: 'The URL slug is generated from the name.',
          ),
          onSubmitted: (_) => _saving ? null : _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
