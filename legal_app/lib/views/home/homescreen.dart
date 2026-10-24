import 'package:flutter/material.dart';

import '../../commonwidgets/home_widget.dart';
import '../../commonwidgets/product_card.dart';
import '../../constants/colors.dart';
import '../../models/legal_category.dart';
import '../../models/paginated_result.dart';
import '../../services/api_client.dart';
import '../../services/app_repository.dart';
import '../../state/session_scope.dart';

import '../../commonwidgets/caregivercategories.dart';
import '../../models/product_model.dart';
import '../../widgets/drawer_widget.dart';

/// Home screen. Loads the lawyer/service list from the backend REST API
/// and falls back to a friendly empty state when the API is unreachable.
class HomePage extends StatefulWidget {
  HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<PaginatedResult<Product>> _future;
  final List<Product> _additionalResults = <Product>[];
  List<LegalCategory> _categories = const <LegalCategory>[];
  String? _selectedCategoryId;
  String? _categoriesError;
  bool _categoriesLoading = true;
  final Set<String?> _seenLawyerIds = <String?>{};
  int _requestSeq = 0;
  String? _error;
  String? _loadMoreError;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load once, through the app-wide session repository so every screen
    // shares one ApiClient (base URL and token handling in one place).
    if (_loaded) return;
    _loaded = true;
    _load();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final repository = SessionScope.read(context).repository;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    try {
      final categories = await repository.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoriesLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categoriesError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
        _categoriesError = 'Could not load categories. Please try again.';
      });
    }
  }

  void _onCategorySelected(LegalCategory? category) {
    _selectedCategoryId = category?.id;
    _load();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    final repository = SessionScope.read(context).repository;
    final request = repository.fetchLawyerPage(
      categoryId: _selectedCategoryId,
      page: 1,
      limit: AppRepository.lawyerPageSize,
    );
    setState(() {
      _error = null;
      _loadMoreError = null;
      _additionalResults.clear();
      _seenLawyerIds.clear();
      _page = 1;
      _hasMore = false;
      _loadingMore = false;
      _future = request;
    });

    try {
      final result = await request;
      if (mounted && seq == _requestSeq) {
        setState(() {
          _seenLawyerIds.addAll(result.items.map((lawyer) => lawyer.id));
          _page = result.page;
          _hasMore = result.hasMore;
        });
      }
    } catch (e) {
      if (mounted && seq == _requestSeq) setState(() => _error = '$e');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final seq = _requestSeq;
    final repository = SessionScope.read(context).repository;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final result = await repository.fetchLawyerPage(
        categoryId: _selectedCategoryId,
        page: _page + 1,
        limit: AppRepository.lawyerPageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        for (final lawyer in result.items) {
          if (_seenLawyerIds.add(lawyer.id)) _additionalResults.add(lawyer);
        }
        _page = result.page;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (mounted && seq == _requestSeq) {
        setState(() {
          _loadMoreError = e.message;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted && seq == _requestSeq) {
        setState(() {
          _loadMoreError = 'Could not load more lawyers. Please try again.';
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: DrawerWidget(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.buttonColor, Colors.blueAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HomeWidgte(),
                    SizedBox(height: 6),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Promotional banner
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.only(left: 15, top: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8CA32), Color(0xFFE5B003)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 35),
                      child: Row(
                        children: [
                          SizedBox(
                            height: 20,
                            width: 3,
                            child: ColoredBox(color: Colors.white),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Find Best Lawyers with us',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Image.asset(
                      'images/banner2.png',
                      fit: BoxFit.cover,
                      scale: 1.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              const SizedBox(height: 5),
              LegalServiceCategories(
                categories: _categories,
                selectedCategoryId: _selectedCategoryId,
                onSelected: _onCategorySelected,
                isLoading: _categoriesLoading,
                error: _categoriesError,
                onRetry: _loadCategories,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Legal Services',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text(
                      'Refresh',
                      style: TextStyle(color: AppColors.buttonColor),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: FutureBuilder<PaginatedResult<Product>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return _ErrorState(
                        message: _error ?? 'Could not load services.',
                        onRetry: _load,
                      );
                    }

                    final firstPage = snapshot.data;
                    final products = <Product>[
                      ...(firstPage?.items ?? const <Product>[]),
                      ..._additionalResults,
                    ];
                    if (products.isEmpty) {
                      return const Center(
                        child: Text(
                          'No services available yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    final hasFooter =
                        _hasMore || _loadingMore || _loadMoreError != null;
                    return RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: products.length + (hasFooter ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == products.length) {
                            if (_loadingMore) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (_loadMoreError != null) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _loadMoreError!,
                                    textAlign: TextAlign.center,
                                  ),
                                  TextButton(
                                    onPressed: _loadMore,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              );
                            }
                            return Center(
                              child: TextButton.icon(
                                onPressed: _loadMore,
                                icon: const Icon(Icons.expand_more),
                                label: const Text('Load more'),
                              ),
                            );
                          }
                          final product = products[index];
                          return ProductCard(
                            imagePath: product.imagePath,
                            name: product.name,
                            price: product.price,
                            lawyer: product,
                            rating: product.rating,
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

/// Shown when the API call fails (no backend / no network).
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              'Unable to load services',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}