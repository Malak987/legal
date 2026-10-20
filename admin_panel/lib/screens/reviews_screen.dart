import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../widgets/common.dart';

/// Manage reviews submitted by clients.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late Future<List<Review>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<Review>> _fetch() async {
    final res = await AuthProvider.of(context)
        .api
        .get('reviews', query: {'page': '1', 'limit': '200'});
    final data = res['data'] as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Review.fromJson).toList();
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _delete(Review r) async {
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
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await AuthProvider.of(context).api.delete('reviews/${r.id}');
      if (mounted) _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Review>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView();
        }
        if (snapshot.hasError) {
          return ErrorBanner(message: '${snapshot.error}', onRetry: _reload);
        }
        final reviews = snapshot.data ?? [];
        if (reviews.isEmpty) {
          return const EmptyState(icon: Icons.star, message: 'No reviews found');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: reviews.length,
          itemBuilder: (context, i) {
            final r = reviews[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.warning,
                  child: Icon(Icons.star, color: Colors.white),
                ),
                title: Text(r.userName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${r.rating.toStringAsFixed(1)} ★\n${r.comment}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: AppTheme.danger),
                  onPressed: () => _delete(r),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
