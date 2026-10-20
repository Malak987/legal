import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class LegalServiceCategories extends StatelessWidget {
  final List<Map<String, dynamic>> categories = [
    {'icon': FontAwesomeIcons.gavel, 'label': 'Family', 'color': Colors.blue},
    {'icon': FontAwesomeIcons.userTie, 'label': 'Business', 'color': Colors.green},
    {'icon': FontAwesomeIcons.scaleBalanced, 'label': 'Criminal', 'color': Colors.red},
    {'icon': FontAwesomeIcons.fileContract, 'label': 'Contract', 'color': Colors.orange},
    {'icon': FontAwesomeIcons.handshake, 'label': 'Immigration', 'color': Colors.purple},
    {'icon': FontAwesomeIcons.moneyBill, 'label': 'Financial', 'color': Colors.teal},
    {'icon': FontAwesomeIcons.users, 'label': 'Employment', 'color': Colors.amber},
    {'icon': FontAwesomeIcons.gears, 'label': 'Intellectual', 'color': Colors.deepOrange},
    {'icon': FontAwesomeIcons.buildingColumns, 'label': 'Estate', 'color': Colors.brown},
    {'icon': FontAwesomeIcons.building, 'label': 'Real Estate', 'color': Colors.blueGrey},
  ];

  LegalServiceCategories({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 85,
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: categories.map((category) => _buildCategoryItem(category)).toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryItem(Map<String, dynamic> category) {
    return Padding(
      padding: const EdgeInsets.only(left: 7,right: 7,top: 7),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [category['color'].withOpacity(0.8), category['color'].withOpacity(0.4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: category['color'].withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(2, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 27,
              backgroundColor: Colors.transparent,
              child: FaIcon(
                category['icon'],
                size: 24,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            category['label'],
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}