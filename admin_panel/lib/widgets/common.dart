import 'package:flutter/material.dart';
import '../config/theme.dart';

/// A compact KPI card used on the dashboards.
///
/// Sizes itself to its parent's width, so callers place it in a responsive
/// grid instead of giving it a fixed width.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppTheme.primary,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  /// Optional short line under the value (e.g. a derived breakdown).
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(builder: (context, constraints) {
          // On very narrow cards the label gets the full width.
          final showIcon = constraints.maxWidth >= 150;
          return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge!.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (showIcon) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.tint(color),
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall!.copyWith(fontSize: 26),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
        }),
      ),
    );
  }
}

/// Lays [children] out in equal-width columns. The column count is derived
/// from the available width ([minItemWidth]) and capped at [maxColumns], so
/// cards never get a fixed pixel width.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 136,
    this.maxColumns = 4,
    this.spacing = AppSpacing.md,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = ((width + spacing) / (minItemWidth + spacing)).floor().clamp(1, maxColumns);
      final itemWidth = (width - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: itemWidth, child: child)],
      );
    });
  }
}

/// Small rounded badge with a colored dot and a text label, so state is never
/// conveyed by color alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.tint(color, 0.08),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: AppTheme.tint(color, 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 13, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status badge (bookings, cases, subscriptions...).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  Color get _color {
    switch (status.toLowerCase()) {
      case 'active':
      case 'confirmed':
      case 'completed':
      case 'open':
      case 'in progress':
      case 'done':
        return AppTheme.success;
      case 'pending':
      case 'to do':
        return AppTheme.warning;
      case 'cancelled':
      case 'closed':
      case 'expired':
        return AppTheme.danger;
      default:
        return AppTheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) => StatusBadge(label: status, color: _color);
}

/// Priority badge; the arrow icon repeats the level for color-blind users.
class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (priority.toLowerCase()) {
      'high' => (AppTheme.danger, Icons.keyboard_double_arrow_up),
      'medium' => (AppTheme.warning, Icons.drag_handle),
      'low' => (AppTheme.success, Icons.keyboard_double_arrow_down),
      _ => (AppTheme.secondary, Icons.remove),
    };
    return StatusBadge(label: priority, color: color, icon: icon);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'Loading...'});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: message,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(message, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Centered placeholder for an empty list. [message] is the primary line.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.description,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: Color(0xFFEEF2F7), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: AppTheme.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium!.copyWith(color: AppTheme.textMuted),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: AppSpacing.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// Search box used by the list screens, with a clear button once text is
/// entered. Clearing reports an empty string through [onChanged].
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search...',
  });

  final ValueChanged<String> onChanged;
  final String hint;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value);
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _clear,
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// Labelled dropdown used for list filters. [dropdownKey] is placed on the
/// inner [DropdownButton] so tests and automation can target it.
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.dropdownKey,
    this.hint,
    this.width = 200,
    this.disabledReason,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Key? dropdownKey;
  final Widget? hint;

  /// Preferred width; [ListToolbar] may override it on narrow screens.
  final double width;

  /// When non-null the filter is disabled and this is shown as a tooltip.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final enabled = disabledReason == null;
    final field = InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        enabled: enabled,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: dropdownKey,
          isExpanded: true,
          isDense: true,
          value: value,
          hint: hint,
          borderRadius: AppRadius.mdAll,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          style: Theme.of(context).textTheme.bodyMedium,
          items: items,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
    return enabled ? field : Tooltip(message: disabledReason, child: field);
  }
}

/// Responsive toolbar above a list: search, filters, icon actions and a
/// primary action.
///
/// * wide: `[search][filters…][actions][primary]` when it fits, otherwise
///   filters wrap onto a second row;
/// * compact (< 600 px wide): search + icon actions on the first row, then
///   filters (two per row) and the primary action.
class ListToolbar extends StatelessWidget {
  const ListToolbar({
    super.key,
    this.search,
    this.filters = const [],
    this.actions = const [],
    this.primary,
    this.leading,
  });

  final Widget? search;
  final List<Widget> filters;
  final List<Widget> actions;
  final Widget? primary;

  /// Optional widget shown at the start (e.g. a short description).
  final Widget? leading;

  static const double _filterWidth = 200;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final compact = width < AppBreakpoints.medium;
      final pad = compact ? AppSpacing.lg : AppSpacing.xl;
      final inner = width - pad * 2;

      // Only dropdown filters get a fixed width; buttons keep their own size.
      Widget sized(Widget filter, double w) =>
          filter is FilterDropdown ? SizedBox(width: w, child: filter) : filter;

      final searchWidth = search == null ? 0.0 : 360.0;
      final inlineWidth = searchWidth +
          filters.length * (_filterWidth + AppSpacing.md) +
          actions.length * 44 +
          (primary == null ? 0 : 170) +
          (leading == null ? 0 : 200);
      final inline = !compact && inlineWidth <= inner;

      final List<Widget> rows;
      if (inline) {
        rows = [
          Row(
            children: [
              if (leading != null) Expanded(child: leading!),
              if (search != null)
                leading == null
                    ? Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: search,
                          ),
                        ),
                      )
                    : SizedBox(width: searchWidth, child: search),
              if (search == null && leading == null) const Spacer(),
              for (final f in filters) ...[
                const SizedBox(width: AppSpacing.md),
                sized(f, _filterWidth),
              ],
              if (actions.isNotEmpty) const SizedBox(width: AppSpacing.sm),
              ...actions,
              if (primary != null) ...[const SizedBox(width: AppSpacing.md), primary!],
            ],
          ),
        ];
      } else {
        final filterW = compact
            ? (filters.length == 1 ? inner : (inner - AppSpacing.md) / 2)
            : _filterWidth;
        final firstRow = <Widget>[
          if (leading != null && search == null) Expanded(child: leading!),
          if (search != null) Expanded(child: search!),
          if (search == null && leading == null) const Spacer(),
          if (actions.isNotEmpty) const SizedBox(width: AppSpacing.xs),
          ...actions,
          if (!compact && primary != null) ...[const SizedBox(width: AppSpacing.md), primary!],
        ];
        final showPrimaryBelow = compact && primary != null;
        rows = [
          if (leading != null && search != null) ...[leading!, const SizedBox(height: AppSpacing.md)],
          if (firstRow.length > 1 || search != null || leading != null) Row(children: firstRow),
          if (filters.isNotEmpty || showPrimaryBelow) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final f in filters) sized(f, filterW),
                if (showPrimaryBelow) primary!,
              ],
            ),
          ],
        ];
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(pad, compact ? AppSpacing.md : AppSpacing.lg, pad, AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      );
    });
  }
}

/// Card with an optional header row (title, subtitle, trailing action).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text(title!, style: theme.textTheme.titleMedium)),
                        if (subtitle != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(subtitle!, style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Standard error view with an optional retry button.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry, this.title});
  final String message;
  final VoidCallback? onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppTheme.tint(AppTheme.danger, 0.08), shape: BoxShape.circle),
                child: const Icon(Icons.error_outline, color: AppTheme.danger, size: 28),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (title != null) ...[
                Text(title!, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(color: AppTheme.textSecondary),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline status message for forms and dialogs (error / warning / info /
/// success) with an icon, so meaning is not carried by color alone.
class InlineMessage extends StatelessWidget {
  const InlineMessage({
    super.key,
    required this.message,
    this.tone = InlineMessageTone.error,
  });

  final String message;
  final InlineMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      InlineMessageTone.error => (AppTheme.danger, Icons.error_outline),
      InlineMessageTone.warning => (AppTheme.warning, Icons.warning_amber_rounded),
      InlineMessageTone.info => (AppTheme.info, Icons.info_outline),
      InlineMessageTone.success => (AppTheme.success, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppTheme.tint(color, 0.06),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppTheme.tint(color, 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }
}

enum InlineMessageTone { error, warning, info, success }

/// Standard list row: optional leading avatar, title, secondary lines,
/// status badges and trailing actions.
///
/// On wide rows the badges sit before the actions; on narrow rows they move
/// under the text, so the title is never squeezed into a sliver.
class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.details = const [],
    this.extra,
    this.badges = const [],
    this.actions = const [],
    this.onTap,
  });

  final String title;
  final Widget? leading;

  /// First secondary line (for example `Client: …`).
  final String? subtitle;

  /// Short facts joined with a middle dot; wraps as needed.
  final List<String> details;

  /// Additional content under the text (for example a comment preview).
  final Widget? extra;
  final List<Widget> badges;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactScreen = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;
    final facts = details.where((d) => d.trim().isNotEmpty).join('  ·  ');
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: compactScreen ? AppSpacing.lg : AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, actions.isEmpty ? AppSpacing.lg : AppSpacing.xs, AppSpacing.md),
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall!.copyWith(fontSize: 14.5),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall!.copyWith(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(facts, style: theme.textTheme.bodySmall!.copyWith(fontSize: 13)),
                ],
                ?extra,
                if (!wide && badges.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(spacing: 6, runSpacing: 6, children: badges),
                ],
              ],
            );
            return Row(
              crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.md)],
                Expanded(child: text),
                if (wide && badges.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: badges),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs),
                  ...actions,
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Circular icon avatar used as a [RecordTile] leading widget.
class RecordAvatar extends StatelessWidget {
  const RecordAvatar({super.key, required this.icon, this.color = AppTheme.primary});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: AppTheme.tint(color, 0.08), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

/// Edit / delete style icon actions with tooltips and consistent colors.
class RowAction extends StatelessWidget {
  const RowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: onPressed == null ? null : (destructive ? AppTheme.danger : AppTheme.textSecondary)),
    );
  }
}
