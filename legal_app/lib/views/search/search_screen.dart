import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../models/product_model.dart';
import '../../services/api_client.dart';
import '../../state/session_scope.dart';
import '../../widgets/customapp_bar.dart';

/// Lawyer search, backed by `GET /api/lawyers?search=...`.
///
/// The previous version listed `ProductData().products` — sample rows — and the
/// text field was not wired to anything, so typing filtered nothing and the
/// results were never real lawyers. This screen asks the backend instead:
///
///  * the endpoint is public (`searchFields: name, specialty, location`), so it
///    works before sign-in as well;
///  * input is debounced, and a sequence counter drops responses that arrive
///    out of order, so a slow request cannot overwrite a newer one;
///  * loading, empty, error and retry states are all rendered.
///
/// Results are informational only: the lawyer detail screen is still a static
/// mock (`views/home/details.dart`), and opening it from a real row would show
/// somebody else's sample data. Tapping a result therefore does nothing yet —
/// see README section 7.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  /// Matches the debounce used by the admin panel's search box.
  static const Duration _debounceDelay = Duration(milliseconds: 350);

  Timer? _debounce;

  /// Guards against an older, slower response overwriting a newer one.
  int _requestSeq = 0;

  List<Product> _results = const <Product>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The first load runs without a rebuild: `_loading` already starts true and
    // the tree has not been built yet.
    _search('', initial: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () => _search(value));
    // Rebuild so the clear button appears/disappears with the text.
    setState(() {});
  }

  Future<void> _search(String query, {bool initial = false}) async {
    final seq = ++_requestSeq;
    if (!initial && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // Read the repository before the await: `context` must not be used after an
    // asynchronous gap.
    final repository = SessionScope.read(context).repository;

    try {
      final lawyers = await repository.fetchLawyers(search: query.trim());
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = lawyers;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = 'Could not search right now. Check your connection and retry.';
        _loading = false;
      });
    }
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    _search('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomAppBar(text: 'Search', text1: ''),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) {
                  _debounce?.cancel();
                  _search(value);
                },
                decoration: InputDecoration(
                  hintText: 'Search by name, specialty or city',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: _clear,
                        ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(child: _buildBody(query)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(String query) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _SearchStatus(
        icon: Icons.error_outline,
        title: 'Search failed',
        detail: _error!,
        onRetry: () => _search(query),
      );
    }

    if (_results.isEmpty) {
      return _SearchStatus(
        icon: Icons.search_off,
        title: query.isEmpty ? 'No lawyers listed yet' : 'No lawyers found',
        detail: query.isEmpty
            ? 'Lawyers added by an administrator will appear here.'
            : 'Nothing matches "$query". Try a different name or city.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) => _LawyerResultCard(
        lawyer: _results[index],
        // A search request is in flight: dim the stale rows instead of
        // flickering them out, which keeps the list readable while typing.
        dimmed: _loading,
      ),
    );
  }
}

class _LawyerResultCard extends StatelessWidget {
  const _LawyerResultCard({required this.lawyer, required this.dimmed});

  final Product lawyer;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final rating = lawyer.rating;
    final location = (lawyer.location ?? '').trim();
    final specialty = (lawyer.specialty ?? '').trim();
    final price = lawyer.price.trim();

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Card(
        elevation: 4,
        shadowColor: Colors.black12,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lawyer.name.trim().isEmpty ? 'Unnamed lawyer' : lawyer.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1Color,
                      ),
                    ),
                  ),
                  if (rating != null)
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (specialty.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  specialty,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text2Color,
                  ),
                ),
              ],
              if (location.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: AppColors.text3Color,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text2Color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (price.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.buttonColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading/empty/error placeholder with an optional retry action.
class _SearchStatus extends StatelessWidget {
  const _SearchStatus({
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.text3Color),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text1Color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.text2Color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
