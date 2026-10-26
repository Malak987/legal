import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Manage bookings (appointments) and update their status.
class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  late Future<Paginated<Booking>> _future;
  int _page = 1;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Booking>> _fetch() {
    final api = AuthProvider.of(context).api;
    final status = _statusFilter;
    return loadPaginated<Booking>(
      page: _page,
      fromJson: Booking.fromJson,
      request: (page) => api.get('bookings', query: {
        'page': '$page',
        'limit': '$kMaxPageSize',
        if (status != null && status.isNotEmpty) 'status': status,
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

  /// Status changes rpc_admin_set_booking_status accepts from [current].
  /// Completed and Cancelled are terminal (BOOKING_STATUS_IS_TERMINAL), and
  /// the legacy 'Active' value is stored as 'Confirmed'.
  static List<String> _nextStatuses(String current) {
    final normalized = current == 'Active' ? 'Confirmed' : current;
    if (normalized == 'Completed' || normalized == 'Cancelled') {
      return const <String>[];
    }
    return const <String>['Confirmed', 'Completed', 'Cancelled']
        .where((status) => status != normalized)
        .toList(growable: false);
  }

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reportError(e))));
      }
    }
  }

  Future<void> _reschedule(Booking b) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => RescheduleBookingDialog(booking: b),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Booking rescheduled')));
      _reload();
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
            style: AppTheme.destructiveButtonStyle,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await api.delete('bookings/${b.id}');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Booking deleted')));
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
            'Appointments between clients and lawyers.',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary),
          ),
          filters: [
            FilterDropdown<String>(
              label: 'Status',
              value: _statusFilter ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                DropdownMenuItem(value: 'Confirmed', child: Text('Confirmed')),
                DropdownMenuItem(value: 'Completed', child: Text('Completed')),
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
              tooltip: 'Refresh bookings',
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
                  icon: Icons.event_available,
                  message: 'No bookings found',
                ),
            itemsBuilder: (context, bookings) {
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: bookings.length,
                itemBuilder: (context, i) {
                  final b = bookings[i];
                  return RecordTile(
                    title: b.lawyerName,
                    subtitle: 'Client: ${b.clientLabel}',
                    details: [b.date, b.time, '${b.hours}h', '\$${b.totalPrice.toStringAsFixed(0)}'],
                    badges: [StatusChip(status: b.status)],
                    actions: [
                          PopupMenuButton<String>(
                            tooltip: 'Booking actions',
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'delete') {
                                _delete(b);
                              } else if (v == 'reschedule') {
                                _reschedule(b);
                              } else {
                                _setStatus(b, v);
                              }
                            },
                            itemBuilder: (_) => [
                              for (final status in _nextStatuses(b.status))
                                PopupMenuItem(
                                    value: status, child: Text('Mark $status')),
                              if (_nextStatuses(b.status).isNotEmpty) ...[
                                const PopupMenuItem(
                                    value: 'reschedule', child: Text('Reschedule…')),
                                const PopupMenuDivider(),
                              ],
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete',
                                      style: TextStyle(color: AppTheme.danger))),
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

/// Reschedules a non-terminal booking through `PUT bookings/:id` with
/// date/time/hours (→ `rpc_admin_reschedule_booking`). The lawyer is kept;
/// the server re-checks availability, conflicts and recomputes the price.
class RescheduleBookingDialog extends StatefulWidget {
  const RescheduleBookingDialog({super.key, required this.booking});

  final Booking booking;

  static final RegExp timePattern = RegExp(r'^(\d{1,2}):(\d{2})$');

  /// Minutes after midnight for `H:MM`/`HH:MM`, or null when invalid.
  static int? minutesOf(String value) {
    final match = timePattern.firstMatch(value.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// Validation message for a start [time] lasting [hours], or null if valid.
  static String? validateTime(String time, int hours) {
    final start = minutesOf(time);
    if (start == null) return 'Enter a 24-hour time such as 09:30';
    if (start + hours * 60 > 24 * 60) return 'The appointment must end by midnight';
    return null;
  }

  @override
  State<RescheduleBookingDialog> createState() => _RescheduleBookingDialogState();
}

class _RescheduleBookingDialogState extends State<RescheduleBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _time;
  DateTime? _date;
  late int _hours;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _date = DateTime.tryParse(b.date);
    final existing = RescheduleBookingDialog.minutesOf(b.time);
    _time = TextEditingController(
      text: existing == null
          ? ''
          : '${(existing ~/ 60).toString().padLeft(2, '0')}:${(existing % 60).toString().padLeft(2, '0')}',
    );
    _hours = b.hours.clamp(1, 12);
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _date == null) {
      if (_date == null) setState(() => _error = 'Choose a date');
      return;
    }
    final minutes = RescheduleBookingDialog.minutesOf(_time.text)!;
    final time =
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    final b = widget.booking;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthProvider.of(context).api.put('bookings/${b.id}', body: {
        if (b.lawyerId.isNotEmpty) 'lawyerId': b.lawyerId,
        'date': _isoDate(_date!),
        'time': time,
        'hours': _hours,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final missingRpc = e is ApiException && (e.code == 'PGRST202' || e.code == '42883');
      setState(() {
        _saving = false;
        _error = missingRpc
            ? 'Rescheduling needs rpc_admin_reschedule_booking (migration '
                '20261025142000), which is not deployed on this project yet. '
                'No change was made.'
            : reportError(e, context: 'reschedule booking');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return AlertDialog(
      title: const Text('Reschedule booking'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b.lawyerName.isEmpty ? 'Lawyer' : b.lawyerName} • ${b.clientLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Currently: ${b.date} at ${b.time} for ${b.hours}h'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('reschedule-date'),
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_date == null ? 'Choose a date' : _isoDate(_date!)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('reschedule-time'),
                  controller: _time,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Start time (24-hour, HH:MM)',
                    hintText: '09:30',
                  ),
                  validator: (v) => RescheduleBookingDialog.validateTime(v ?? '', _hours),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('reschedule-hours'),
                  initialValue: _hours,
                  decoration: const InputDecoration(labelText: 'Duration'),
                  items: [
                    for (var h = 1; h <= 12; h++)
                      DropdownMenuItem(value: h, child: Text(h == 1 ? '1 hour' : '$h hours')),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _hours = v ?? _hours),
                ),
                const SizedBox(height: 12),
                Text(
                  'The new time must be inside the lawyer\'s published availability '
                  'for that date. The price is recalculated from the lawyer\'s rate.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      key: const Key('reschedule-error'),
                      style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Reschedule'),
        ),
      ],
    );
  }
}
