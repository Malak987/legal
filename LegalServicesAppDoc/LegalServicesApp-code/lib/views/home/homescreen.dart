import 'package:flutter/material.dart';
import '../../CommonWidgets/home_widget.dart';
import '../../CommonWidgets/product_card.dart';
import '../../CommonWidgets/product_data.dart';
import '../../Constants/colors.dart';

import '../../commonwidgets/caregivercategories.dart';
import '../../models/product_model.dart';
import '../../widgets/drawer_widget.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final List<Product> products = ProductData().products;

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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const HomeWidgte(), const SizedBox(height: 6)],
                ),
              ),
              Container(
                margin: EdgeInsets.only(top: 6),
                padding: EdgeInsets.only(left: 15, top: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFF8CA32),
                      Color(0xFFE5B003),
                    ], // Gradient colors
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26, // Shadow color
                      blurRadius: 8, // Blur effect
                      spreadRadius: 2, // Spread of shadow
                      offset: Offset(0, 4), // Shadow position
                    ),
                  ],
                ),
                width: double.infinity,
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween, // Space text and image
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 35),
                      child: Row(
                        children: [
                          Container(
                            height: 20,
                            width: 3,
                            margin: EdgeInsets.only(top: 8, right: 3),
                            decoration: BoxDecoration(color: Colors.white),
                          ),

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
              SizedBox(height: 5,),

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
                    onPressed: () {
                      // Action for 'View All'
                    },
                    child: const Text(
                      'View All',
                      style: TextStyle(color: AppColors.buttonColor),
                    ),
                  ),
                ],
              ),

              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    return ProductCard(
                      imagePath: products[index].imagePath,
                      name: products[index].name,
                      price: products[index].price.toString(),
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
