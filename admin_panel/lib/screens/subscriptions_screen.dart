import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Inspect subscriptions and allow cancellation; payment-state transitions
/// remain unavailable until they are driven by a verified provider workflow.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late Future<List<Subscription>> _future;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Subscription>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('subscriptions', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
      if (_statusFilter != null && _statusFilter!.isNotEmpty)
        'status': _statusFilter!,
    });
    return itemsOf(res).map(Subscription.fromJson).toList();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
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
              const Text('Filter by status:'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _statusFilter,
                hint: const Text('All'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                  DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                ],
                onChanged: (v) {
                  _statusFilter = (v == null || v.isEmpty) ? null : v;
                  _reload();
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Reload',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Subscription>>(
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
              final subscriptions = snapshot.data ?? [];
              if (subscriptions.isEmpty) {
                return const EmptyState(
                  icon: Icons.subscriptions,
                  message: 'No subscriptions found',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: subscriptions.length,
                itemBuilder: (context, i) {
                  final s = subscriptions[i];
                  final actions = _allowedActions(s.status);
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.primary,
                        child: Icon(Icons.subscriptions, color: Colors.white),
                      ),
                      title: Text(
                        s.displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        s.userId.isEmpty ? 'Unknown user' : 'User: ${s.userId}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusChip(status: s.status),
                          if (actions.isNotEmpty)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (v) => _setStatus(s, v),
                              itemBuilder: (_) => [
                                for (final action in actions)
                                  PopupMenuItem(
                                    value: action,
                                    child: Text('Cancel subscription'),
                                  ),
                              ],
                            )
                          else
                            const SizedBox(width: 48),
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
