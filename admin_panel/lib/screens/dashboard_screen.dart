import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
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
      final data = (res is Map && res['data'] is Map)
          ? res['data'] as Map<String, dynamic>
          : (res as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _stats = DashboardStats.fromJson(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView(message: 'Loading dashboard...');
    if (_error != null) return ErrorBanner(message: _error!, onRetry: _load);

    final s = _stats!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric('Users', '${s.users}', Icons.people, AppTheme.primary),
              _metric('Lawyers', '${s.lawyers}', Icons.gavel, AppTheme.secondary),
              _metric('Cases', '${s.cases}', Icons.folder_copy, AppTheme.accent),
              _metric('Bookings', '${s.bookings}', Icons.event_available,
                  AppTheme.success),
              _metric('Reviews', '${s.reviews}', Icons.star, AppTheme.warning),
              _metric('Subscriptions', '${s.subscriptions}', Icons.subscriptions,
                  AppTheme.primary),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bookings by status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 240,
                          child: BarChart(_barData(s)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Overview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _overviewRow('Active', s.activeBookings, AppTheme.success),
                        _overviewRow(
                            'Completed', s.completedBookings, AppTheme.secondary),
                        _overviewRow(
                            'Cancelled', s.cancelledBookings, AppTheme.danger),
                        const Divider(height: 32),
                        const Text('Total wallet balance'),
                        const SizedBox(height: 4),
                        Text(
                          '\$${_formatMoney(s.totalWalletBalance)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _quickAction('Manage Lawyers', Icons.gavel, 'Lawyers'),
                      _quickAction('Manage Users', Icons.people, 'Users'),
                      _quickAction('View Bookings', Icons.event_available, 'Bookings'),
                      _quickAction('View Cases', Icons.folder_copy, 'Cases'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) {
    return SizedBox(
      width: 180,
      child: StatCard(label: label, value: value, icon: icon, color: color),
    );
  }

  Widget _overviewRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
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
    final groups = [
      BarChartGroupData(
        x: 0,
        barRods: [
          BarChartRodData(
            toY: s.activeBookings.toDouble(),
            color: AppTheme.success,
            width: 22,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barRods: [
          BarChartRodData(
            toY: s.completedBookings.toDouble(),
            color: AppTheme.secondary,
            width: 22,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barRods: [
          BarChartRodData(
            toY: s.cancelledBookings.toDouble(),
            color: AppTheme.danger,
            width: 22,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    ];

    return BarChartData(
      barGroups: groups,
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 30),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              const labels = ['Active', 'Completed', 'Cancelled'];
              final i = value.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(labels[i], style: const TextStyle(fontSize: 11)),
              );
            },
          ),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
    );
  }
}

String _formatMoney(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}
