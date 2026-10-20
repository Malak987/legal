import 'dart:async';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Manage users with a sortable data table.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<AppUser>> _future;
  String _search = '';

  /// Debounces search input so one keystroke does not equal one request.
  Timer? _searchDebounce;
  String? _roleFilter;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<List<AppUser>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('users', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
      if (_search.isNotEmpty) 'search': _search,
      if (_roleFilter != null && _roleFilter!.isNotEmpty) 'role': _roleFilter!,
    });
    return itemsOf(res).map(AppUser.fromJson).toList();
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _delete(AppUser user) async {
    final api = AuthProvider.of(context).api;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user'),
        content: Text('Delete "${user.name}" (${user.email})?'),
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
      await api.delete('users/${user.id}');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('User deleted')));
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
                  hint: 'Search by name, email or phone...',
                  onChanged: (v) {
                    _search = v;
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 350), _reload);
                  },
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _roleFilter,
                hint: const Text('All roles'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All roles')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'lawyer', child: Text('Lawyer')),
                  DropdownMenuItem(value: 'client', child: Text('Client')),
                ],
                onChanged: (v) {
                  _roleFilter = (v == null || v.isEmpty) ? null : v;
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AppUser>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
              }
              final users = snapshot.data ?? [];
              if (users.isEmpty) {
                return const EmptyState(icon: Icons.people, message: 'No users found');
              }

              return SingleChildScrollView(
                scrollDirection: Axis.vertical,
                padding: const EdgeInsets.only(bottom: 24),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Phone')),
                      DataColumn(label: Text('Role')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: [
                      for (final u in users)
                        DataRow(cells: [
                          DataCell(Text(u.name)),
                          DataCell(Text(u.email)),
                          DataCell(Text(u.phone)),
                          DataCell(_roleChip(u.role)),
                          DataCell(
                            IconButton(
                              icon: const Icon(Icons.delete, color: AppTheme.danger),
                              onPressed: () => _delete(u),
                            ),
                          ),
                        ]),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _roleChip(String role) {
    final color = switch (role) {
      'admin' => AppTheme.accent,
      'lawyer' => AppTheme.secondary,
      _ => AppTheme.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
