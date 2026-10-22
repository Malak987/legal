import 'package:flutter/material.dart';

import '../../commonwidgets/home_widget.dart';
import '../../commonwidgets/product_card.dart';
import '../../constants/colors.dart';
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
  late Future<List<Product>> _future;
  String? _error;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load once, through the app-wide session repository so every screen
    // shares one ApiClient (base URL and token handling in one place).
    if (_loaded) return;
    _loaded = true;
    _load();
  }

  Future<void> _load() async {
    final repository = SessionScope.read(context).repository;
    setState(() {
      _error = null;
      _future = repository.fetchLawyers();
    });

    try {
      await _future;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
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
              LegalServiceCategories(),
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
                child: FutureBuilder<List<Product>>(
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

                    final products = snapshot.data ?? [];
                    if (products.isEmpty) {
                      return const Center(
                        child: Text(
                          'No services available yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];
                        return ProductCard(
                          imagePath: p.imagePath,
                          name: p.name,
                          price: p.price,
                          lawyer: p,
                          rating: p.rating,
                        );
                      },
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