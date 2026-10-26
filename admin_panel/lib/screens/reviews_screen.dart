import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_errors.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import '../widgets/pagination.dart';

/// Manage reviews submitted by clients.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late Future<Paginated<Review>> _future;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Paginated<Review>> _fetch() {
    final api = AuthProvider.of(context).api;
    return loadPaginated<Review>(
      page: _page,
      fromJson: Review.fromJson,
      request: (page) =>
          api.get('reviews', query: {'page': '$page', 'limit': '$kMaxPageSize'}),
    );
  }

  /// Re-fetches; [resetPage] returns to page 1.
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

  Future<void> _moderate(Review r) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ReviewModerationDialog(review: r),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Review updated')));
      _reload();
    }
  }

  Future<void> _delete(Review r) async {
    final api = AuthProvider.of(context).api;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete review'),
        content: Text('Delete review by "${r.userName}"?'),
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
      await api.delete('reviews/${r.id}');
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reportError(e, context: 'delete review'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PagedFutureView<Review>(
      future: _future,
      onRetry: _reload,
      onPageChanged: _goToPage,
      errorContext: 'load reviews',
      empty: const EmptyState(icon: Icons.star, message: 'No reviews found'),
      itemsBuilder: (context, reviews) => ListView.builder(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xl),
        itemCount: reviews.length,
        itemBuilder: (context, i) {
          final r = reviews[i];
          final lawyer = r.lawyerName.isNotEmpty
              ? r.lawyerName
              : (r.lawyerId.isEmpty ? 'Unknown lawyer' : 'Lawyer ${r.lawyerId}');
          return RecordTile(
            leading: const RecordAvatar(icon: Icons.star_outline, color: AppTheme.warning),
            title: r.userName,
            subtitle: 'For $lawyer',
            extra: r.comment.trim().isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      r.comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
                    ),
                  ),
            badges: [
              StatusBadge(
                label: '${r.rating.toStringAsFixed(1)} / 5',
                color: AppTheme.warning,
                icon: Icons.star,
              ),
            ],
            actions: [
              RowAction(
                icon: Icons.edit,
                tooltip: 'Moderate review',
                onPressed: () => _moderate(r),
              ),
              RowAction(
                icon: Icons.delete,
                tooltip: 'Delete review',
                destructive: true,
                onPressed: () => _delete(r),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Edits a review's rating/comment via `PUT reviews/:id`
/// (`rpc_admin_review_moderate`). Only changed fields are sent; the RPC
/// leaves omitted (null) fields untouched. Reviewer identity is never shown
/// beyond the public `user_name`.
class ReviewModerationDialog extends StatefulWidget {
  const ReviewModerationDialog({super.key, required this.review});

  final Review review;

  static const int maxCommentLength = 4000;

  @override
  State<ReviewModerationDialog> createState() => _ReviewModerationDialogState();
}

class _ReviewModerationDialogState extends State<ReviewModerationDialog> {
  late double _rating;
  late final double _initialRating;
  late final TextEditingController _comment;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Snap to the slider's 0.5 grid within the 1–5 range the RPC accepts.
    _initialRating = ((widget.review.rating.clamp(1, 5)) * 2).round() / 2;
    _rating = _initialRating;
    _comment = TextEditingController(text: widget.review.comment)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  bool get _ratingChanged => (_rating - _initialRating).abs() > 0.001;
  bool get _commentChanged => _comment.text != widget.review.comment;
  bool get _commentTooLong =>
      _comment.text.length > ReviewModerationDialog.maxCommentLength;

  Future<void> _save() async {
    if (!_ratingChanged && !_commentChanged) return;
    if (_commentTooLong) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthProvider.of(context).api.put('reviews/${widget.review.id}', body: {
        if (_ratingChanged) 'rating': _rating,
        if (_commentChanged) 'comment': _comment.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final missingRpc = e is ApiException && (e.code == 'PGRST202' || e.code == '42883');
      setState(() {
        _saving = false;
        _error = missingRpc
            ? 'Review moderation needs rpc_admin_review_moderate (migration '
                '20261025142000), which is not deployed on this project yet. '
                'No change was made.'
            : reportError(e, context: 'moderate review');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final canSave = (_ratingChanged || _commentChanged) && !_commentTooLong && !_saving;
    return AlertDialog(
      title: const Text('Moderate review'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'By ${r.userName.isEmpty ? 'a client' : r.userName}'
                '${r.lawyerName.isEmpty ? '' : ' for ${r.lawyerName}'}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text('Rating: ${_rating.toStringAsFixed(1)} ★'),
              Slider(
                key: const Key('review-rating'),
                value: _rating,
                min: 1,
                max: 5,
                divisions: 8,
                label: _rating.toStringAsFixed(1),
                onChanged: _saving ? null : (v) => setState(() => _rating = v),
              ),
              TextField(
                key: const Key('review-comment'),
                controller: _comment,
                enabled: !_saving,
                minLines: 3,
                maxLines: 6,
                maxLength: ReviewModerationDialog.maxCommentLength,
                maxLengthEnforcement: MaxLengthEnforcement.none,
                decoration: InputDecoration(
                  labelText: 'Comment',
                  errorText: _commentTooLong
                      ? 'At most ${ReviewModerationDialog.maxCommentLength} characters'
                      : null,
                ),
              ),
              Text(
                'Only the fields you change are saved. The lawyer\'s displayed '
                'rating is stored separately and is not recalculated '
                'automatically.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    key: const Key('review-moderation-error'),
                    style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('review-moderation-save'),
          onPressed: canSave ? _save : null,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
