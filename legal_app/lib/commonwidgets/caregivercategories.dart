import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/legal_category.dart';

/// Horizontal category catalogue backed by the legal-categories API.
class LegalServiceCategories extends StatelessWidget {
  const LegalServiceCategories({
    super.key,
    required this.categories,
    required this.onSelected,
    this.selectedCategoryId,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  final List<LegalCategory> categories;
  final String? selectedCategoryId;
  final ValueChanged<LegalCategory?> onSelected;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  static const List<Color> _colors = <Color>[
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.amber,
    Colors.deepOrange,
    Colors.brown,
    Colors.blueGrey,
  ];

  FaIconData _iconFor(LegalCategory category) {
    final label = '${category.slug} ${category.name}'.toLowerCase();
    if (label.contains('family') || label.contains('divorce')) {
      return FontAwesomeIcons.users;
    }
    if (label.contains('business') || label.contains('corporate')) {
      return FontAwesomeIcons.building;
    }
    if (label.contains('criminal')) return FontAwesomeIcons.scaleBalanced;
    if (label.contains('contract')) return FontAwesomeIcons.fileContract;
    if (label.contains('immigration')) return FontAwesomeIcons.handshake;
    if (label.contains('financial') || label.contains('tax')) {
      return FontAwesomeIcons.moneyBill;
    }
    if (label.contains('employment') || label.contains('labor')) {
      return FontAwesomeIcons.userTie;
    }
    if (label.contains('intellectual') || label.contains('property')) {
      return FontAwesomeIcons.gears;
    }
    if (label.contains('estate') || label.contains('inheritance')) {
      return FontAwesomeIcons.buildingColumns;
    }
    if (label.contains('real')) return FontAwesomeIcons.house;
    return FontAwesomeIcons.gavel;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 85,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (error != null) {
      return SizedBox(
        height: 85,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text('Categories unavailable: $error', maxLines: 2)),
            if (onRetry != null)
              IconButton(
                tooltip: 'Retry categories',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      );
    }
    if (categories.isEmpty) {
      return const SizedBox(
        height: 85,
        child: Center(child: Text('No legal categories available yet.')),
      );
    }

    return SizedBox(
      height: 85,
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < categories.length; index++)
              _buildCategoryItem(categories[index], index),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(LegalCategory category, int index) {
    final color = _colors[index % _colors.length];
    final selected = category.id == selectedCategoryId;
    return Padding(
      padding: const EdgeInsets.only(left: 7, right: 7, top: 7),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Filter lawyers by ${category.name}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onSelected(selected ? null : category),
          child: SizedBox(
            width: 78,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [color.withOpacity(0.8), color.withOpacity(0.4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: selected
                        ? Border.all(color: Colors.black87, width: 2)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(2, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 27,
                    backgroundColor: Colors.transparent,
                    child: FaIcon(
                      _iconFor(category),
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.bold,
                    color: selected ? Colors.black : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
