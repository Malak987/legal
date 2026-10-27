import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

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
      cases: paginatedOf(results[0], (json) => json).total,
      bookings: paginatedOf(results[1], (json) => json).total,
      slots: paginatedOf(results[2], (json) => json).total,
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

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
          return ErrorBanner(
            message: reportError(snapshot.error!, context: 'load lawyer overview'),
            onRetry: _reload,
          );
        }
        final totals = snapshot.data!;
        final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;
        final pad = compact ? AppSpacing.lg : AppSpacing.xl;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.xxl),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact) ...[
                      const RecordAvatar(icon: Icons.gavel),
                      const SizedBox(width: AppSpacing.lg),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName.isEmpty ? 'Lawyer workspace' : 'Welcome, $displayName',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Review only the cases and appointments assigned to your verified lawyer profile. This workspace does not provide client or case editing.',
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ResponsiveGrid(
              minItemWidth: 150,
              maxColumns: 3,
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
    return StatCard(
      label: label,
      value: value,
      icon: icon,
      color: AppTheme.secondary,
      onTap: () => widget.onNavigate(destination),
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
  late Future<Paginated<CaseItem>> _future;
  int _page = 1;
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

  Future<Paginated<CaseItem>> _fetch() {
    final api = AuthProvider.of(context).api;
    final search = _search.trim();
    return loadPaginated<CaseItem>(
      page: _page,
      fromJson: CaseItem.fromJson,
      request: (page) => api.get('cases', query: {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListToolbar(
          search: SearchField(
            hint: 'Search assigned cases...',
            onChanged: (value) {
              _search = value;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 350),
                () => _reload(resetPage: true),
              );
            },
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh assigned cases',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: PagedFutureView<CaseItem>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load caseitem list',
            empty: const EmptyState(
                  icon: Icons.folder_copy_outlined,
                  message: 'No cases are assigned to your profile',
                ),
            itemsBuilder: (context, cases) {
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
                  return RecordTile(
                    title: item.title,
                    details: detailLines.isEmpty ? const ['No case details'] : detailLines,
                    badges: [
                      StatusChip(status: item.status),
                      PriorityChip(priority: item.priority),
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

/// Assigned booking list. Lawyers can inspect appointment details but cannot
/// change status, cancel, create, or delete bookings from the panel.
class LawyerBookingsScreen extends StatefulWidget {
  const LawyerBookingsScreen({super.key});

  @override
  State<LawyerBookingsScreen> createState() => _LawyerBookingsScreenState();
}

class _LawyerBookingsScreenState extends State<LawyerBookingsScreen> {
  late Future<Paginated<Booking>> _future;
  int _page = 1;
  String? _status;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Booking>> _fetch() {
    final api = AuthProvider.of(context).api;
    final status = _status;
    return loadPaginated<Booking>(
      page: _page,
      fromJson: Booking.fromJson,
      request: (page) => api.get('bookings', query: {
        'page': '$page',
        'limit': '$kMaxPageSize',
        'status': ?status,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListToolbar(
          filters: [
            FilterDropdown<String>(
              label: 'Status',
              value: _status ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Active', child: Text('Active')),
                DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
              ],
              onChanged: (value) {
                _status = value == null || value.isEmpty ? null : value;
                _reload(resetPage: true);
              },
            ),
          ],
          actions: [
            IconButton(
              tooltip: 'Refresh assigned bookings',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: PagedFutureView<Booking>(
            future: _future,
            onRetry: _reload,
            onPageChanged: _goToPage,
            errorContext: 'load booking list',
            empty: const EmptyState(
                  icon: Icons.event_available_outlined,
                  message: 'No appointments are assigned to your profile',
                ),
            itemsBuilder: (context, bookings) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: bookings.length,
                itemBuilder: (context, index) {
                  final booking = bookings[index];
                  return RecordTile(
                    leading: const RecordAvatar(icon: Icons.event_outlined),
                    title: booking.lawyerName.isEmpty ? 'Appointment' : booking.lawyerName,
                    details: [booking.date, booking.time, '${booking.hours}h'],
                    badges: [StatusChip(status: booking.status)],
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
/// `rpc_lawyer_my_availability`. No schedule editing is exposed here.
class LawyerAvailabilityScreen extends StatefulWidget {
  const LawyerAvailabilityScreen({super.key});

  @override
  State<LawyerAvailabilityScreen> createState() => _LawyerAvailabilityScreenState();
}

class _LawyerAvailabilityScreenState extends State<LawyerAvailabilityScreen> {
  late Future<Paginated<Map<String, dynamic>>> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Map<String, dynamic>>> _fetch() {
    final api = AuthProvider.of(context).api;
    return loadPaginated<Map<String, dynamic>>(
      page: _page,
      fromJson: (json) => json,
      request: (page) => api.get('availability/mine', query: {
        'page': '$page',
        'limit': '$kMaxPageSize',
      }),
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _fetch();
    });
  }

  void _goToPage(int page) {
    setState(() {
      _page = page;
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PagedFutureView<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      onPageChanged: _goToPage,
      errorContext: 'load availability',
      empty: const EmptyState(
        icon: Icons.schedule_outlined,
        message: 'No availability entries found',
      ),
      itemsBuilder: (context, slots) {
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          itemCount: slots.length,
          itemBuilder: (context, index) {
            final slot = slots[index];
            final values = slot['slots'] is List
                ? (slot['slots'] as List).map((value) => value.toString()).toList()
                : const <String>[];
            return RecordTile(
              leading: const RecordAvatar(icon: Icons.calendar_month_outlined, color: AppTheme.secondary),
              title: slot['date']?.toString() ?? 'Date not provided',
              details: values.isEmpty ? const ['No time slots listed'] : values,
            );
          },
        );
      },
    );
  }
}
