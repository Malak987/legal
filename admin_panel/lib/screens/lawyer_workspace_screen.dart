import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Read-only landing page for a server-verified lawyer account.
class LawyerOverviewScreen extends StatefulWidget {
  const LawyerOverviewScreen({super.key, required this.onNavigate});

  final ValueChanged<String> onNavigate;

  @override
  State<LawyerOverviewScreen> createState() => _LawyerOverviewScreenState();
}

class _LawyerOverviewScreenState extends State<LawyerOverviewScreen> {
  late Future<_LawyerOverview> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_LawyerOverview> _fetch() async {
    final api = AuthProvider.of(context).api;
    final results = await Future.wait<dynamic>([
      api.get('cases', query: {'page': '1', 'limit': '$kMaxPageSize'}),
      api.get('bookings', query: {'page': '1', 'limit': '$kMaxPageSize'}),
      api.get('availability/mine', query: {'page': '1', 'limit': '$kMaxPageSize'}),
    ]);
    return _LawyerOverview(
      cases: itemsOf(results[0]).length,
      bookings: itemsOf(results[1]).length,
      slots: itemsOf(results[2]).length,
    );
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    final session = AuthProvider.watchOf(context).session;
    final displayName = (session?.name ?? '').trim();

    return FutureBuilder<_LawyerOverview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Loading your workspace...');
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
        }
        final totals = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              color: AppTheme.primary,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isEmpty ? 'Lawyer workspace' : 'Welcome, $displayName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Review only the cases and appointments assigned to your verified lawyer profile. This workspace does not provide client or case editing.',
                      style: TextStyle(color: Colors.white70, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _overviewCard(
                  context,
                  'My Cases',
                  '${totals.cases}',
                  Icons.folder_copy_outlined,
                  'My Cases',
                ),
                _overviewCard(
                  context,
                  'My Bookings',
                  '${totals.bookings}',
                  Icons.event_available_outlined,
                  'My Bookings',
                ),
                _overviewCard(
                  context,
                  'Availability entries',
                  '${totals.slots}',
                  Icons.schedule_outlined,
                  'My Availability',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _overviewCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    String destination,
  ) {
    return SizedBox(
      width: 260,
      child: StatCard(
        label: label,
        value: value,
        icon: icon,
        color: AppTheme.secondary,
        onTap: () => widget.onNavigate(destination),
      ),
    );
  }
}

class _LawyerOverview {
  const _LawyerOverview({required this.cases, required this.bookings, required this.slots});

  final int cases;
  final int bookings;
  final int slots;
}

/// Assigned case list. The API scopes this query by the verified lawyer row;
/// this screen intentionally has no create, edit, reassignment, or delete UI.
class LawyerCasesScreen extends StatefulWidget {
  const LawyerCasesScreen({super.key});

  @override
  State<LawyerCasesScreen> createState() => _LawyerCasesScreenState();
}

class _LawyerCasesScreenState extends State<LawyerCasesScreen> {
  late Future<List<CaseItem>> _future;
  Timer? _searchDebounce;
  String _search = '';

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

  Future<List<CaseItem>> _fetch() async {
    final response = await AuthProvider.of(context).api.get('cases', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
      if (_search.trim().isNotEmpty) 'search': _search.trim(),
    });
    return itemsOf(response).map(CaseItem.fromJson).toList(growable: false);
  }

  void _reload() => setState(() => _future = _fetch());

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
                  hint: 'Search assigned cases...',
                  onChanged: (value) {
                    _search = value;
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 350),
                      _reload,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh assigned cases',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<CaseItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingView();
              }
              if (snapshot.hasError) {
                return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
              }
              final cases = snapshot.data ?? const <CaseItem>[];
              if (cases.isEmpty) {
                return const EmptyState(
                  icon: Icons.folder_copy_outlined,
                  message: 'No cases are assigned to your profile',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: cases.length,
                itemBuilder: (context, index) {
                  final item = cases[index];
                  final category = item.categoryName.trim().isNotEmpty
                      ? item.categoryName.trim()
                      : item.caseType.trim();
                  final detailLines = <String>[
                    if (item.clientName.trim().isNotEmpty) 'Client: ${item.clientName.trim()}',
                    if (category.isNotEmpty) category,
                    if (item.dueDate.trim().isNotEmpty) 'Due ${item.dueDate.trim()}',
                    if (item.description.trim().isNotEmpty) item.description.trim(),
                  ];
                  return Card(
                    child: ListTile(
                      isThreeLine: detailLines.length > 1,
                      title: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        detailLines.isEmpty ? 'No case details' : detailLines.join('  •  '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusChip(status: item.status),
                          const SizedBox(height: 5),
                          PriorityChip(priority: item.priority),
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

/// Assigned booking list. Lawyers can inspect appointment details but cannot
/// change status, cancel, create, or delete bookings from the panel.
class LawyerBookingsScreen extends StatefulWidget {
  const LawyerBookingsScreen({super.key});

  @override
  State<LawyerBookingsScreen> createState() => _LawyerBookingsScreenState();
}

class _LawyerBookingsScreenState extends State<LawyerBookingsScreen> {
  late Future<List<Booking>> _future;
  String? _status;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Booking>> _fetch() async {
    final query = <String, String>{
      'page': '1',
      'limit': '$kMaxPageSize',
    };
    final status = _status;
    if (status != null) query['status'] = status;

    final response =
        await AuthProvider.of(context).api.get('bookings', query: query);
    return itemsOf(response).map(Booking.fromJson).toList(growable: false);
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Status:'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _status ?? '',
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Active', child: Text('Active')),
                  DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                  DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                ],
                onChanged: (value) {
                  setState(() => _status = value == null || value.isEmpty ? null : value);
                  _reload();
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh assigned bookings',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
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
              final bookings = snapshot.data ?? const <Booking>[];
              if (bookings.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_available_outlined,
                  message: 'No appointments are assigned to your profile',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: bookings.length,
                itemBuilder: (context, index) {
                  final booking = bookings[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        booking.lawyerName.isEmpty ? 'Appointment' : booking.lawyerName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${booking.date}  •  ${booking.time}  •  ${booking.hours}h',
                      ),
                      trailing: StatusChip(status: booking.status),
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

/// The lawyer's own availability schedule, loaded via the authenticated
/// `/api/availability/mine` endpoint. No schedule editing is exposed here.
class LawyerAvailabilityScreen extends StatefulWidget {
  const LawyerAvailabilityScreen({super.key});

  @override
  State<LawyerAvailabilityScreen> createState() => _LawyerAvailabilityScreenState();
}

class _LawyerAvailabilityScreenState extends State<LawyerAvailabilityScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final response = await AuthProvider.of(context).api.get('availability/mine', query: {
      'page': '1',
      'limit': '$kMaxPageSize',
    });
    return itemsOf(response);
  }

  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
        }
        final slots = snapshot.data ?? const <Map<String, dynamic>>[];
        if (slots.isEmpty) {
          return const EmptyState(
            icon: Icons.schedule_outlined,
            message: 'No availability entries found',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            final values = slot['slots'] is List
                ? (slot['slots'] as List).map((value) => value.toString()).toList()
                : const <String>[];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month_outlined, color: AppTheme.secondary),
                title: Text(slot['date']?.toString() ?? 'Date not provided'),
                subtitle: Text(values.isEmpty ? 'No time slots listed' : values.join('  •  ')),
              ),
            );
          },
        );
      },
    );
  }
}
