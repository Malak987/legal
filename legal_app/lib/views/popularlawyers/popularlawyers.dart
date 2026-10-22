import 'package:legalserviceapp/widgets/customapp_bar.dart';
import 'package:legalserviceapp/views/messages/chat_screen.dart';
import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../models/product_model.dart';
import '../../services/api_client.dart';
import '../../state/session_scope.dart';
import '../../widgets/detailstext1.dart';
import '../home/details.dart';

/// The lawyer directory, read from the public `GET /api/lawyers` endpoint.
///
/// Public on purpose: the backend serves this list without a token, so the
/// screen works before sign-in as well. The lawyer detail screen is still a
/// static mock — tapping a card does not pass the loaded document to it yet.
///
/// The same widget serves two menu entries: "Popular Lawyers"
/// (`onlyTop: false`, `isPopular=true`) and "Top Lawyers" (`onlyTop: true`,
/// `isTop=true`). The second one used to be a separate screen rendering
/// sample products; both now read the same real endpoint with a different
/// server-side filter.
class PopularLawyersScreen extends StatefulWidget {
  const PopularLawyersScreen({
    super.key,
    this.onlyTop = false,
    this.title = 'Popular Lawyers',
  });

  /// When true, lists `isTop` lawyers instead of `isPopular` ones.
  final bool onlyTop;

  /// Header text, so one screen can serve both menu entries.
  final String title;

  @override
  State<PopularLawyersScreen> createState() => _PopularLawyersScreenState();
}

class _PopularLawyersScreenState extends State<PopularLawyersScreen> {
  late Future<List<Product>> _lawyers;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _lawyers = Future.value(const <Product>[]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _reload();
  }

  Future<void> _reload() {
    final future = SessionScope.read(context).repository.fetchLawyers(
      isPopular: widget.onlyTop ? null : true,
      isTop: widget.onlyTop ? true : null,
    );
    setState(() {
      _lawyers = future;
    });
    return future.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            children: [
              const SizedBox(height: 12),

              CustomAppBar(text: widget.title, text1: ''),
              const SizedBox(height: 12),

              Expanded(
                child: FutureBuilder<List<Product>>(
                  future: _lawyers,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _Status(
                        icon: Icons.error_outline,
                        title: 'Could not load lawyers',
                        detail: snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'Please try again.',
                        onRetry: () => _reload(),
                      );
                    }
                    final lawyers = snapshot.data ?? const <Product>[];
                    if (lawyers.isEmpty) {
                      return _Status(
                        icon: Icons.search_off,
                        title: widget.onlyTop
                            ? 'No top-rated lawyers yet'
                            : 'No lawyers listed yet',
                        detail: widget.onlyTop
                            ? 'Lawyers marked as top-rated by an administrator '
                                'will appear here.'
                            : 'Lawyers added by an administrator will appear '
                                'here.',
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: lawyers.length,
                        itemBuilder: (context, index) {
                          final lawyer = lawyers[index];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const LegalServiceDetailsScreen(),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 6,
                              shadowColor: Colors.black12,
                              color: Colors.white,
                              margin: const EdgeInsets.only(bottom: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: SizedBox(
                                        height: 80,
                                        width: 110,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: _LawyerPhoto(
                                              path: lawyer.imagePath),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text1(
                                            text1: lawyer.name.isEmpty
                                                ? 'Lawyer'
                                                : lawyer.name,
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                                size: 18,
                                              ),
                                              Text(
                                                (lawyer.rating ?? 0) > 0
                                                    ? lawyer.rating!
                                                        .toStringAsFixed(1)
                                                    : 'New',
                                                style:
                                                    const TextStyle(fontSize: 14),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                color: Colors.grey.shade600,
                                                size: 18,
                                              ),
                                              Expanded(
                                                child: Text(
                                                  (lawyer.location ?? '')
                                                          .isEmpty
                                                      ? 'Location not set'
                                                      : lawyer.location!,
                                                  style: TextStyle(
                                                    color: Colors.grey.shade600,
                                                    fontSize: 13,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text1(
                                          text1: lawyer.price.isEmpty
                                              ? 'Contact for pricing'
                                              : lawyer.price,
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  Colors.purple.shade50,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.message,
                                                  color: Colors.purple,
                                                ),
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const ChatScreen(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            CircleAvatar(
                                              backgroundColor:
                                                  Colors.green.shade50,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.phone,
                                                  color: Colors.green,
                                                ),
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const ChatScreen(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lawyer photo with a bundled fallback.
///
/// The `image` field is a remote URL for real records and a bundled path for
/// the older seeded data, so both forms are accepted.
class _LawyerPhoto extends StatelessWidget {
  const _LawyerPhoto({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      'images/lawyer2.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.bgColor,
        child: const Icon(Icons.person, color: AppColors.text3Color),
      ),
    );
    if (path.isEmpty) return fallback;
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.text3Color),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.text2Color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
