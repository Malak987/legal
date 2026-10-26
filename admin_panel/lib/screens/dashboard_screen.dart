import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';

/// Dashboard with key metrics and a bookings chart.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onNavigate});
  final void Function(String title)? onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardStats? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AuthProvider.of(context).api.get('dashboard/stats');
      final data = objectDataOf(res);
      if (mounted) {
        setState(() {
          _stats = DashboardStats.fromJson(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _describeError(e);
          _loading = false;
        });
      }
    }
  }

  /// Turns a failure into an actionable message instead of a raw exception.
  ///
  /// Network failures, expired tokens and a missing admin role need completely
  /// different fixes, so they must not all render as the same sentence.
  String _describeError(Object e) {
    if (e is ApiException) {
      switch (e.statusCode) {
        case 0:
          return 'Could not reach Supabase. Check your connection and retry.';
        case 401:
          return 'Supabase rejected the request (401 Unauthorized). Your '
              'session may have expired — sign out and sign in again.';
        case 403:
          return 'The database denied this operation (403 Forbidden). Verify '
              'that the server-owned public.users role permits this workflow.';
        default:
          return 'Request failed (${e.statusCode}): ${e.message}';
      }
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView(message: 'Loading dashboard...');
    if (_error != null) {
      return ErrorBanner(
        title: 'Could not load the dashboard',
        message: _error!,
        onRetry: _load,
      );
    }

    final s = _stats!;
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;
    final pad = compact ? AppSpacing.lg : AppSpacing.xl;

    void go(String title) => widget.onNavigate?.call(title);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.xxl),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Platform activity at a glance',
                  style: theme.textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary),
                ),
              ),
              compact
                  ? IconButton(
                      tooltip: 'Refresh dashboard',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                    )
                  : OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ResponsiveGrid(
            children: [
              StatCard(label: 'Users', value: _count(s.users), icon: Icons.people_outline, color: AppTheme.primary, onTap: () => go('Users')),
              StatCard(label: 'Lawyers', value: _count(s.lawyers), icon: Icons.gavel, color: AppTheme.secondary, onTap: () => go('Lawyers')),
              StatCard(label: 'Cases', value: _count(s.cases), icon: Icons.folder_copy_outlined, color: AppTheme.accent, onTap: () => go('Cases')),
              StatCard(label: 'Bookings', value: _count(s.bookings), icon: Icons.event_available_outlined, color: AppTheme.success, onTap: () => go('Bookings')),
              StatCard(label: 'Reviews', value: _count(s.reviews), icon: Icons.star_outline, color: AppTheme.warning, onTap: () => go('Reviews')),
              StatCard(label: 'Plans', value: _count(s.plans), icon: Icons.workspace_premium_outlined, color: AppTheme.primary, onTap: () => go('Plans')),
              StatCard(label: 'Subscriptions', value: _count(s.subscriptions), icon: Icons.card_membership_outlined, color: AppTheme.secondary, onTap: () => go('Subscriptions')),
              StatCard(label: 'Wallet balance', value: _money(s.totalWalletBalance), icon: Icons.account_balance_wallet_outlined, color: AppTheme.success),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          // Side by side on wide layouts; stacked on narrow ones so the
          // chart and breakdown are not squeezed into unreadable columns.
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = SectionCard(
                title: 'Bookings by status',
                subtitle: 'Active, completed and cancelled bookings',
                child: SizedBox(height: 240, child: BarChart(_barData(s))),
              );
              final breakdown = SectionCard(
                title: 'Status breakdown',
                subtitle: 'Share of the bookings shown in the chart',
                child: _breakdown(s),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [chart, const SizedBox(height: AppSpacing.lg), breakdown],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: chart),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: breakdown),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionCard(
            title: 'Quick actions',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _quickAction('Manage Lawyers', Icons.gavel, 'Lawyers'),
                _quickAction('Manage Users', Icons.people_outline, 'Users'),
                _quickAction('View Bookings', Icons.event_available_outlined, 'Bookings'),
                _quickAction('View Cases', Icons.folder_copy_outlined, 'Cases'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdown(DashboardStats s) {
    final theme = Theme.of(context);
    final rows = [
      ('Active', s.activeBookings, AppTheme.success),
      ('Completed', s.completedBookings, AppTheme.secondary),
      ('Cancelled', s.cancelledBookings, AppTheme.danger),
    ];
    final total = rows.fold<int>(0, (sum, r) => sum + r.$2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value, color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.all(Radius.circular(3))),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                    Text(_count(value), style: theme.textTheme.titleSmall),
                    SizedBox(
                      width: 52,
                      child: Text(
                        total == 0 ? '—' : '${(value * 100 / total).round()}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : value / total,
                    minHeight: 6,
                    color: color,
                    backgroundColor: const Color(0xFFEEF2F7),
                  ),
                ),
              ],
            ),
          ),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: Text('Total', style: theme.textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary))),
            Text(_count(total), style: theme.textTheme.titleSmall),
            const SizedBox(width: 52),
          ],
        ),
      ],
    );
  }

  Widget _quickAction(String label, IconData icon, String navTitle) {
    return OutlinedButton.icon(
      onPressed: () => widget.onNavigate?.call(navTitle),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  BarChartData _barData(DashboardStats s) {
    final values = [s.activeBookings, s.completedBookings, s.cancelledBookings];
    const colors = [AppTheme.success, AppTheme.secondary, AppTheme.danger];
    const labels = ['Active', 'Completed', 'Cancelled'];
    final maxValue = values.fold<int>(0, (m, v) => v > m ? v : m);
    final interval = _niceInterval(maxValue / 4);
    final maxY = maxValue == 0 ? 4 * interval : (maxValue / interval).ceil() * interval;
    final axisStyle = Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11.5);
    // Reserve room for the longest y-axis label so it never wraps.
    final longest = NumberFormat.compact().format(maxY).length;

    return BarChartData(
      maxY: maxY,
      minY: 0,
      alignment: BarChartAlignment.spaceAround,
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i].toDouble(),
                color: colors[i],
                width: 32,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          ),
      ],
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppTheme.textPrimary,
          tooltipRoundedRadius: AppRadius.sm,
          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
            '${labels[group.x]}: ${_count(rod.toY.round())}',
            const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: interval,
            reservedSize: 14.0 + longest * 7.5,
            getTitlesWidget: (value, meta) {
              if (value > maxY) return const SizedBox.shrink();
              return SideTitleWidget(
                meta: meta,
                child: Text(NumberFormat.compact().format(value), style: axisStyle, maxLines: 1, softWrap: false),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
              return SideTitleWidget(
                meta: meta,
                child: Text(labels[i], style: axisStyle.copyWith(color: AppTheme.textSecondary)),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) => const FlLine(color: AppTheme.border, strokeWidth: 1),
      ),
      borderData: FlBorderData(
        show: true,
        border: const Border(bottom: BorderSide(color: AppTheme.borderStrong)),
      ),
    );
  }
}

/// A "nice" axis step (1, 2, 2.5 or 5 × 10ⁿ) at or above [raw].
double _niceInterval(double raw) {
  if (raw <= 1) return 1;
  final exponent = (math.log(raw) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  for (final step in [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (raw <= step * magnitude) return step * magnitude;
  }
  return 10 * magnitude;
}

String _count(int value) => NumberFormat.decimalPattern().format(value);

String _money(double value) => NumberFormat.currency(
      symbol: r'$',
      decimalDigits: value == value.roundToDouble() ? 0 : 2,
    ).format(value);
