import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import 'common.dart';

/// Parses a `{data: {items, total, page, limit, totalPages, hasMore?}}` page
/// envelope (from `_tablePage` and the paged RPCs).
///
/// If the server omits an exact total, a completely full page is treated as
/// "maybe more", so records after the first page are never silently hidden.
Paginated<T> paginatedOf<T>(
  dynamic response,
  T Function(Map<String, dynamic>) fromJson, {
  int page = 1,
  int limit = kMaxPageSize,
}) {
  final data = listPageOf(response);
  final items = itemsOf(response).map(fromJson).toList(growable: false);

  int? asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  final effectivePage = asInt(data['page']) ?? page;
  final effectiveLimit = (asInt(data['limit']) ?? limit).clamp(1, 1000000);
  final reportedTotal = asInt(data['total']);
  final total = reportedTotal ?? (effectivePage - 1) * effectiveLimit + items.length;
  final computedPages = total == 0 ? 1 : (total + effectiveLimit - 1) ~/ effectiveLimit;
  final reportedPages = asInt(data['totalPages']);
  final totalPages =
      (reportedPages == null || reportedPages < 1) ? computedPages : reportedPages;
  final hasMore = data['hasMore'] == true ||
      effectivePage < totalPages ||
      (reportedTotal == null && items.length >= effectiveLimit);

  return Paginated<T>(
    items: items,
    total: total,
    page: effectivePage,
    limit: effectiveLimit,
    totalPages: totalPages,
    hasMore: hasMore,
  );
}

/// Loads [page] and, if it came back empty while earlier pages still exist
/// (for example after deleting the last row on the last page), loads the last
/// non-empty page instead.
Future<Paginated<T>> loadPaginated<T>({
  required int page,
  required Future<dynamic> Function(int page) request,
  required T Function(Map<String, dynamic>) fromJson,
}) async {
  var result = paginatedOf(await request(page), fromJson, page: page);
  if (result.items.isEmpty && page > 1 && result.total > 0) {
    final last = result.totalPages.clamp(1, page - 1);
    result = paginatedOf(await request(last), fromJson, page: last);
  }
  return result;
}

/// Footer with record range, page position and previous/next controls.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.onPageChanged,
    this.loading = false,
  });

  final Paginated<dynamic> page;
  final ValueChanged<int> onPageChanged;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 400;
    final summary = page.total == 0
        ? 'No records'
        : narrow
            ? '${page.firstIndex}–${page.lastIndex} of ${page.total}'
            : 'Showing ${page.firstIndex}–${page.lastIndex} of ${page.total}';
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.medium;
    final pageButtonStyle = IconButton.styleFrom(
      minimumSize: const Size(36, 36),
      side: const BorderSide(color: AppTheme.border),
      foregroundColor: AppTheme.textPrimary,
      disabledForegroundColor: AppTheme.borderStrong,
    );
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.lg : AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              key: const Key('pagination-summary'),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            key: const Key('pagination-previous'),
            tooltip: 'Previous page',
            style: pageButtonStyle,
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: loading || !page.hasPrevious
                ? null
                : () => onPageChanged(page.page - 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              'Page ${page.page} of ${page.hasNext && page.page >= page.totalPages ? '${page.page}+' : page.totalPages}',
              key: const Key('pagination-position'),
              style: theme.textTheme.labelMedium!.copyWith(color: AppTheme.textPrimary),
            ),
          ),
          IconButton(
            key: const Key('pagination-next'),
            tooltip: 'Next page',
            style: pageButtonStyle,
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: loading || !page.hasNext
                ? null
                : () => onPageChanged(page.page + 1),
          ),
        ],
      ),
    );
  }
}

/// A paged result area: initial loading, friendly error with retry, empty
/// state, the results, and a [PaginationBar].
///
/// While a new page/filter is loading the previous rows stay visible under a
/// thin progress bar and the pager is disabled, so the layout does not jump.
class PagedFutureView<T> extends StatelessWidget {
  const PagedFutureView({
    super.key,
    required this.future,
    required this.itemsBuilder,
    required this.empty,
    required this.onRetry,
    required this.onPageChanged,
    this.errorContext,
  });

  final Future<Paginated<T>> future;
  final Widget Function(BuildContext context, List<T> items) itemsBuilder;
  final Widget empty;
  final VoidCallback onRetry;
  final ValueChanged<int> onPageChanged;

  /// Label used in debug diagnostics (for example 'load cases').
  final String? errorContext;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Paginated<T>>(
      future: future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final data = snapshot.data;
        if (!loading && snapshot.hasError) {
          return ErrorBanner(
            message: reportError(snapshot.error!, context: errorContext),
            onRetry: onRetry,
          );
        }
        if (data == null) return const LoadingView();
        if (data.items.isEmpty) {
          if (loading) return const LoadingView();
          if (data.page > 1) {
            // Defensive: a page beyond the end that loadPaginated could not
            // step back from (e.g. rows deleted concurrently).
            return Column(
              children: [
                const Expanded(
                  child: EmptyState(
                    icon: Icons.inbox_outlined,
                    message: 'No records on this page',
                  ),
                ),
                PaginationBar(page: data, onPageChanged: onPageChanged),
              ],
            );
          }
          return empty;
        }
        return Column(
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: itemsBuilder(context, data.items)),
            PaginationBar(
              page: data,
              loading: loading,
              onPageChanged: onPageChanged,
            ),
          ],
        );
      },
    );
  }
}
