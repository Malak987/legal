import 'dart:async';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Browse users and edit profile fields that do not change Auth identity.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<Paginated<AppUser>> _future;
  String _search = '';
  int _page = 1;

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

  Future<Paginated<AppUser>> _fetch() {
    final api = AuthProvider.of(context).api;
    final search = _search;
    final role = _roleFilter;
    return loadPaginated<AppUser>(
      page: _page,
      fromJson: AppUser.fromJson,
      request: (page) => api.get('users', query: {
        'page': '$page',
        'limit': '$kMaxPageSize',
        if (search.isNotEmpty) 'search': search,
        if (role != null && role.isNotEmpty) 'role': role,
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

  Future<void> _openRoleChange(AppUser user) async {
    final changed = await showDialog<AppUser>(
      context: context,
      builder: (_) => UserRoleDialog(user: user),
    );
    if (changed != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${changed.name.isEmpty ? 'User' : changed.name} is now '
            '${UserRoleDialog.roleLabel(changed.role)}',
          ),
        ),
      );
      // Re-fetch so the row reflects the server-confirmed role.
      _reload();
    }
  }

  Future<void> _openEdit(AppUser user) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => UserEditDialog(user: user),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User updated')));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListToolbar(
          search: SearchField(
            hint: 'Search by name, email or phone...',
            onChanged: (v) {
              _search = v;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), () => _reload(resetPage: true));
            },
          ),
          filters: [
            FilterDropdown<String>(
              label: 'Role',
              value: _roleFilter ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('All roles')),
                DropdownMenuItem(value: 'owner', child: Text('Owner')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'lawyer', child: Text('Lawyer')),
                DropdownMenuItem(value: 'client', child: Text('Client')),
              ],
              onChanged: (v) {
                _roleFilter = (v == null || v.isEmpty) ? null : v;
                _reload(resetPage: true);
              },
            ),
          ],
          actions: [
            IconButton(
              tooltip: 'Refresh users',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: PagedFutureView<AppUser>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load users',
            empty: const EmptyState(icon: Icons.people, message: 'No users found'),
            itemsBuilder: (context, users) {
              final currentUserId = AuthProvider.of(context).session?.uid ?? '';
              return LayoutBuilder(builder: (context, constraints) {
                // Cards on narrow screens; a full-width table otherwise.
                if (constraints.maxWidth < 720) {
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    itemCount: users.length,
                    itemBuilder: (context, i) {
                      final u = users[i];
                      return RecordTile(
                        leading: _avatar(u.name),
                        title: u.name,
                        subtitle: u.email,
                        details: [u.phone],
                        badges: [_roleChip(u.role)],
                        actions: _userActions(u, currentUserId),
                      );
                    },
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, AppSpacing.xl),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: LayoutBuilder(builder: (context, inner) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: inner.maxWidth),
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
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _avatar(u.name, radius: 16),
                                      const SizedBox(width: AppSpacing.md),
                                      Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ],
                                  )),
                                  DataCell(Text(u.email)),
                                  DataCell(Text(u.phone.isEmpty ? '—' : u.phone)),
                                  DataCell(_roleChip(u.role)),
                                  DataCell(Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _userActions(u, currentUserId),
                                  )),
                                ]),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                );
              });
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _userActions(AppUser u, String currentUserId) {
    return [
      RowAction(
        icon: Icons.edit,
        tooltip: 'Edit user',
        onPressed: () => _openEdit(u),
      ),
      IconButton(
        key: ValueKey('change-role-${u.id}'),
        icon: const Icon(Icons.manage_accounts, size: 20),
        tooltip: u.role == 'owner'
            ? 'The owner role cannot be changed from the panel'
            : u.id == currentUserId
                ? 'You cannot change your own role'
                : 'Change role',
        onPressed: u.role == 'owner' || u.id == currentUserId
            ? null
            : () => _openRoleChange(u),
      ),
    ];
  }

  Widget _avatar(String name, {double radius = 20}) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE6ECF7),
      child: Text(
        initials,
        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: radius * 0.7),
      ),
    );
  }

  Widget _roleChip(String role) {
    final color = switch (role) {
      'owner' || 'admin' => AppTheme.accent,
      'lawyer' => AppTheme.secondary,
      _ => AppTheme.success,
    };
    final icon = switch (role) {
      'owner' => Icons.verified_user_outlined,
      'admin' => Icons.admin_panel_settings_outlined,
      'lawyer' => Icons.gavel,
      _ => Icons.person_outline,
    };
    return StatusBadge(
      key: ValueKey('role-chip-$role'),
      label: role,
      color: color,
      icon: icon,
    );
  }
}

/// Dialog for editing a user's profile (`PUT /api/users/:id`).
class UserEditDialog extends StatefulWidget {
  const UserEditDialog({super.key, required this.user});
  final AppUser user;

  @override
  State<UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<UserEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.name);
    _email = TextEditingController(text: widget.user.email);
    _phone = TextEditingController(text: widget.user.phone);
    _address = TextEditingController(text: widget.user.address);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name must be at least two characters')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await AuthProvider.of(context).api.put('users/${widget.user.id}', body: {
        'name': name,
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reportError(e, context: 'save user'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit User'),
      content: SizedBox(
        width: 440,
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
                controller: _email,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  helperText: 'Managed by Supabase Auth; change requires verification.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address'),
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

/// Confirms a role change through `PUT users/:id/role`
/// (`rpc_admin_set_user_role`). Only client, lawyer and admin can be chosen;
/// the owner role is never offered. Pops with the server-confirmed user.
class UserRoleDialog extends StatefulWidget {
  const UserRoleDialog({super.key, required this.user});

  final AppUser user;

  /// Roles this action may assign. `owner` is intentionally absent.
  static const List<String> assignableRoles = <String>['client', 'lawyer', 'admin'];

  static String roleLabel(String role) => switch (role) {
        'client' => 'a client',
        'lawyer' => 'a lawyer',
        'admin' => 'an administrator',
        'owner' => 'the owner',
        _ => role,
      };

  /// What the new role means in practice, shown before confirming.
  static String effectOf(String role) => switch (role) {
        'client' =>
          'Uses the mobile app as a client. Loses any admin panel or lawyer '
              'workspace access.',
        'lawyer' =>
          'Can sign in to the read-only lawyer workspace once this account is '
              'linked to a lawyer profile (Lawyers → Edit → Linked account). '
              'Loses admin access.',
        'admin' =>
          'Gets full administrative access to every screen and record in this '
              'panel, including other users\' roles.',
        _ => '',
      };

  @override
  State<UserRoleDialog> createState() => _UserRoleDialogState();
}

class _UserRoleDialogState extends State<UserRoleDialog> {
  String? _selected;
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    final role = _selected;
    if (role == null || role == widget.user.role) return;
    if (!UserRoleDialog.assignableRoles.contains(role)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await AuthProvider.of(context)
          .api
          .put('users/${widget.user.id}/role', body: {'role': role});
      AppUser updated;
      try {
        updated = AppUser.fromJson(objectDataOf(res));
      } catch (_) {
        updated = AppUser(
          id: widget.user.id,
          name: widget.user.name,
          email: widget.user.email,
          role: role,
        );
      }
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      final missingRpc = e is ApiException &&
          (e.code == 'PGRST202' || e.code == '42883');
      setState(() {
        _saving = false;
        _error = missingRpc
            ? 'Role changes need the database function rpc_admin_set_user_role '
                '(migration 20261025142000), which is not deployed on this '
                'project yet. No change was made.'
            : reportError(e, context: 'change user role');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final selected = _selected;
    final changed = selected != null && selected != user.role;
    return AlertDialog(
      title: const Text('Change role'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${user.name.isEmpty ? user.id : user.name}'
                '${user.email.isEmpty ? '' : ' (${user.email})'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('Current role: ${user.role.isEmpty ? 'unknown' : user.role}'),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: selected ?? user.role,
                onChanged: (v) {
                  if (!_saving) setState(() => _selected = v);
                },
                child: Column(
                  children: [
                    for (final role in UserRoleDialog.assignableRoles)
                      RadioListTile<String>(
                        key: ValueKey('role-option-$role'),
                        contentPadding: EdgeInsets.zero,
                        value: role,
                        enabled: !_saving,
                        title: Text(role[0].toUpperCase() + role.substring(1)),
                        subtitle: Text(UserRoleDialog.effectOf(role)),
                      ),
                  ],
                ),
              ),
              if (changed && (user.role == 'admin' || selected == 'admin'))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    selected == 'admin'
                        ? 'Warning: this grants full administrative access.'
                        : 'Warning: this removes administrative access. The '
                            'last administrator cannot be demoted.',
                    style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('role-change-error'),
                    style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: !changed || _saving ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(changed
                  ? 'Change to ${selected[0].toUpperCase()}${selected.substring(1)}'
                  : 'Change role'),
        ),
      ],
    );
  }
}
