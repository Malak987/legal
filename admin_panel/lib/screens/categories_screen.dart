import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Administrator CRUD for the public legal-category catalogue.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<LegalCategory>> _future;
  String _search = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<LegalCategory>> _fetch() async {
    final response = await AuthProvider.of(context).api.get('categories', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
      if (_search.trim().isNotEmpty) 'search': _search.trim(),
    });
    return itemsOf(response)
        .map(LegalCategory.fromJson)
        .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
        .toList(growable: false);
  }

  void _reload() {
    if (mounted) setState(() => _future = _fetch());
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
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
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
        SnackBar(content: Text('$error')),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  hint: 'Search categories...',
                  onChanged: (value) {
                    _search = value;
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 350), _reload);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh categories',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add Category'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<LegalCategory>>(
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
              final categories = snapshot.data ?? const <LegalCategory>[];
              if (categories.isEmpty) {
                return const EmptyState(
                  icon: Icons.category_outlined,
                  message: 'No legal categories found',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8EEF6),
                        child: Icon(Icons.category, color: AppTheme.primary),
                      ),
                      title: Text(
                        category.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(category.slug),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit category',
                            icon: const Icon(Icons.edit, color: AppTheme.secondary),
                            onPressed: () => _openForm(category: category),
                          ),
                          IconButton(
                            tooltip: 'Delete category',
                            icon: const Icon(Icons.delete, color: AppTheme.danger),
                            onPressed: () => _delete(category),
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
        SnackBar(content: Text('$error')),
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
