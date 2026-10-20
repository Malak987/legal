import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Manage bookings (appointments) and update their status.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late Future<List<Booking>> _future;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Booking>> _fetch() async {
    final res = await AuthProvider.of(context).api.get('bookings', query: {
      'page': '1',
      'limit': '200',
      if (_statusFilter != null && _statusFilter!.isNotEmpty)
        'status': _statusFilter!,
    });
    final data = res['data'] as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Booking.fromJson).toList();
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _setStatus(Booking b, String status) async {
    try {
      await AuthProvider.of(context)
          .api
          .put('bookings/${b.id}', body: {'status': status});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Booking marked as $status')));
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _delete(Booking b) async {
    final api = AuthProvider.of(context).api;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete booking'),
        content: Text('Delete booking for "${b.lawyerName}"?'),
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
      await api.delete('bookings/${b.id}');
      if (mounted) _reload();
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
                  DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                  DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                ],
                onChanged: (v) {
                  _statusFilter = (v == null || v.isEmpty) ? null : v;
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Booking>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
              }
              final bookings = snapshot.data ?? [];
              if (bookings.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_available,
                  message: 'No bookings found',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: bookings.length,
                itemBuilder: (context, i) {
                  final b = bookings[i];
                  return Card(
                    child: ListTile(
                      title: Text(b.lawyerName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${b.date}  •  ${b.time}  •  ${b.hours}h  •  \$${b.totalPrice.toStringAsFixed(0)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusChip(status: b.status),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'delete') {
                                _delete(b);
                              } else {
                                _setStatus(b, v);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'Active', child: Text('Mark Active')),
                              PopupMenuItem(
                                  value: 'Completed', child: Text('Mark Completed')),
                              PopupMenuItem(
                                  value: 'Cancelled', child: Text('Mark Cancelled')),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete',
                                      style: TextStyle(color: AppTheme.danger))),
                            ],
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
