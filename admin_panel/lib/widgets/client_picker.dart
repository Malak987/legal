import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Searchable picker over users with one exact server-owned application role.
///
/// Backed by paginated, role-filtered Supabase reads. A result is eligible only
/// when the raw payload contains the requested role; client-side model defaults
/// are never treated as authorization evidence.
class ClientPickerField extends StatefulWidget {
  const ClientPickerField({
    super.key,
    required this.selectedUserId,
    required this.onSelected,
    this.enabled = true,
    this.requiredRole = 'client',
    this.roleLabel = 'client',
  });

  /// The id currently selected, or `null` when nothing is selected.
  ///
  /// Only used to tick the matching result — the picker never changes the
  /// selection by itself, so the administrator stays in control.
  final String? selectedUserId;

  /// Called with the chosen profile. Never called with `null` automatically.
  final ValueChanged<AppUser> onSelected;

  final bool enabled;
  final String requiredRole;
  final String roleLabel;

  @override
  State<ClientPickerField> createState() => _ClientPickerFieldState();
}

class _ClientPickerFieldState extends State<ClientPickerField> {
  final TextEditingController _search = TextEditingController();

  /// Matches the case-list debounce so the two search boxes feel the same.
  Timer? _debounce;

  /// Guards against an older, slower response overwriting a newer one.
  int _requestSeq = 0;

  List<AppUser> _results = const [];
  bool _loading = true;
  String? _error;

  /// Distinguishes "no matching profiles" from "no search matches".
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // No setState here: `_loading` already starts true, and calling setState
    // during initState is pointless work before the first build.
    _fetch(showLoading: false);
  }

  @override
  void dispose() {
    // The timer and controller belong to this State; cancelling here means a
    // pending debounce cannot fire after the dialog is gone.
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool showLoading = true}) async {
    final seq = ++_requestSeq;
    final query = _search.text.trim();

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // Read the client before the first await: `AuthProvider.of` uses
    // `context.read`, which must not run across an async gap.
    final api = AuthProvider.of(context).api;

    try {
      final res = await api.get('users', query: {
        'role': widget.requiredRole,
        'page': '1',
        // The endpoint caps `limit` at 100; asking for less would paginate
        // results the picker would then silently not show.
        'limit': '$kMaxPageSize',
        if (query.isNotEmpty) 'search': query,
      });

      // Only exact-role profiles are eligible; defaulted roles are ignored.
      final clients = itemsOf(res)
          .where((json) => json['role']?.toString() == widget.requiredRole)
          .map(AppUser.fromJson)
          .toList();

      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = clients;
        _lastQuery = query;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _fetch);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _search,
          enabled: widget.enabled,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            labelText: 'Search ${widget.roleLabel}s',
            hintText: 'Name, email or phone',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              tooltip: 'Refresh profiles',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: widget.enabled ? () => _fetch() : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 168,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load ${widget.roleLabel}s.\n$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.enabled ? () => _fetch() : null,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            _lastQuery.isEmpty
                ? 'No ${widget.roleLabel}s found.'
                : 'No ${widget.roleLabel}s match "$_lastQuery".',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final user = _results[i];
        final selected = user.id == widget.selectedUserId;
        // Name plus email/phone: two clients can share a name, and the id is
        // what actually gets stored.
        final details = [user.email, user.phone].where((s) => s.isNotEmpty);
        return ListTile(
          dense: true,
          selected: selected,
          leading: Icon(
            selected ? Icons.check_circle : Icons.person_outline,
            size: 20,
            color: selected ? AppTheme.secondary : Colors.grey.shade600,
          ),
          title: Text(user.name.isEmpty ? user.id : user.name),
          subtitle: details.isEmpty ? null : Text(details.join('  •  ')),
          onTap: widget.enabled ? () => widget.onSelected(user) : null,
        );
      },
    );
  }
}
