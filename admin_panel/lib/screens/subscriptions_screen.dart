import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Inspect subscriptions and allow cancellation; payment-state transitions
/// remain unavailable until they are driven by a verified provider workflow.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late Future<Paginated<Subscription>> _future;
  int _page = 1;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Subscription>> _fetch() {
    final api = AuthProvider.of(context).api;
    final status = _statusFilter;
    return loadPaginated<Subscription>(
      page: _page,
      fromJson: Subscription.fromJson,
      request: (page) => api.get('subscriptions', query: {
        'page': '$page',
        'limit': '$kMaxPageSize',
        if (status != null && status.isNotEmpty) 'status': status,
      }),
    );
  }

  static String _day(DateTime? value) {
    if (value == null) return '—';
    final d = value.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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

  /// Only cancellation is available from the panel. Activation/expiry must
  /// follow trusted payment and entitlement processing, never a manual toggle.
  static List<String> _allowedActions(String status) {
    return status == 'Pending' || status == 'Active'
        ? const ['Cancelled']
        : const [];
  }

  Future<void> _setStatus(Subscription s, String status) async {
    if (status != 'Cancelled') return;
    final api = AuthProvider.of(context).api;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel subscription'),
        content: Text(
          'Cancel "${s.displayTitle}"? A cancelled subscription cannot be '
          'reactivated from the panel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: AppTheme.destructiveButtonStyle,
            child: const Text('Cancel subscription'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await api.put('subscriptions/${s.id}', body: {'status': status});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription marked as $status')),
        );
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
          leading: Text(
            'Review plan subscriptions and their status.',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary),
          ),
          filters: [
            FilterDropdown<String>(
              label: 'Status',
              value: _statusFilter ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Active', child: Text('Active')),
                DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) {
                _statusFilter = (v == null || v.isEmpty) ? null : v;
                _reload(resetPage: true);
              },
            ),
          ],
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: PagedFutureView<Subscription>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load subscription list',
            empty: const EmptyState(
                  icon: Icons.subscriptions,
                  message: 'No subscriptions found',
                ),
            itemsBuilder: (context, subscriptions) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: subscriptions.length,
                itemBuilder: (context, i) {
                  final s = subscriptions[i];
                  final actions = _allowedActions(s.status);
                  return RecordTile(
                    leading: const RecordAvatar(icon: Icons.card_membership_outlined),
                    title: s.displayTitle,
                    subtitle: 'User: ${s.userLabel}',
                    details: ['Start: ${_day(s.startDate)}', 'End: ${_day(s.endDate)}'],
                    badges: [StatusChip(status: s.status)],
                    actions: [
                          if (actions.isNotEmpty)
                            PopupMenuButton<String>(
                              tooltip: 'Subscription actions',
                              icon: const Icon(Icons.more_vert),
                              onSelected: (v) => _setStatus(s, v),
                              itemBuilder: (_) => [
                                for (final action in actions)
                                  PopupMenuItem(
                                    value: action,
                                    child: Text('Cancel subscription'),
                                  ),
                              ],
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
