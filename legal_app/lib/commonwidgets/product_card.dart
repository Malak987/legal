import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../models/product_model.dart';
import '../views/home/details.dart';

class ProductCard extends StatefulWidget {
  final String imagePath;
  final String name;
  final String price;
  final Product? lawyer;
  final double? rating;
  final VoidCallback? onTap;
  final bool isFavorited;
  final VoidCallback? onFavoriteTap;

  const ProductCard({
    super.key,
    required this.imagePath,
    required this.name,
    required this.price,
    this.lawyer,
    this.rating,
    this.onTap,
    this.isFavorited = false,
    this.onFavoriteTap,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  late bool _isFavorited;

  @override
  void initState() {
    super.initState();
    _isFavorited = widget.isFavorited;
  }

  @override
  Widget build(BuildContext context) {
    final displayRating = widget.rating ?? widget.lawyer?.rating ?? 4.0;

    return GestureDetector(
      onTap: widget.onTap ??
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LegalServiceDetailsScreen(
                  lawyer: widget.lawyer,
                  lawyerId: widget.lawyer?.id,
                ),
              ),
            );
          },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blueAccent.withAlpha((0.2 * 255).toInt()),
              spreadRadius: 2,
              blurRadius: 7,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildImageSection(),
            ),
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        displayRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.price,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.buttonColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final fallback = Image.asset(
      'images/lawyer2.png',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.bgColor,
        child: const Icon(Icons.person, color: AppColors.text3Color),
      ),
    );

    Widget imageWidget;
    if (widget.imagePath.isEmpty) {
      imageWidget = fallback;
    } else if (widget.imagePath.startsWith('http')) {
      imageWidget = Image.network(
        widget.imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else {
      imageWidget = Image.asset(
        widget.imagePath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: imageWidget,
        ),
        Positioned(
          top: 10,
          right: 10,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _isFavorited = !_isFavorited;
              });
              if (widget.onFavoriteTap != null) {
                widget.onFavoriteTap!();
              }
            },
            child: CircleAvatar(
              radius: 15,
              backgroundColor: Colors.white,
              child: Icon(
                _isFavorited ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
