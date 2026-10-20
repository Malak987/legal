import 'package:flutter/material.dart';


import '../../../constants/colors.dart';
import '../../../models/product_model.dart';
import '../../../widgets/custom_outline_button.dart';
import '../../../widgets/customapp_bar.dart';
import '../../../widgets/custombtn.dart';
import '../../../widgets/customtextfield.dart';
import '../../../widgets/detailstext1.dart';
import '../../../widgets/detailstext2.dart';
import '../cartscreen/cart_screen.dart';

class PastOrders extends StatefulWidget {
  const PastOrders({super.key});

  @override
  PastOrdersState createState() => PastOrdersState();
}

class PastOrdersState extends State<PastOrders> {
  List<Product> cancelledProducts = [
    Product(imagePath: 'images/oil.png', name: 'Oil', price: '\$4.30'),
    Product(imagePath: 'images/lamb_meat.png', name: 'Lamb Meat', price: '\$4.30'),
    Product(imagePath: 'images/banana.png', name: 'Banana', price: '\$4.30'),
  ];

  List<Product> activeProducts = [
    Product(imagePath: 'images/ginger.png', name: 'Ginger', price: '\$4.30'),
    Product(imagePath: 'images/carrot.png', name: 'Carrot', price: '\$1.25'),
    Product(imagePath: 'images/beef.png', name: 'Beef', price: '\$5.50'),
  ];

  List<Product> completedProducts = [
    Product(imagePath: 'images/apple.png', name: 'Apple', price: '\$2.00'),
    Product(imagePath: 'images/fruit.png', name: 'Fruits', price: '\$1.75'),
    Product(imagePath: 'images/chicken.png', name: 'Chicken', price: '\$4.30'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CustomAppBar(text: 'My Orders', text1: ''),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('Cancelled Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ...cancelledProducts.map((product) => buildOrderItem(context, product, 'Cancelled')),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('Active Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ...activeProducts.map((product) => buildOrderItem(context, product, 'Active')),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 7),
                  child: Text('Completed Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ...completedProducts.map((product) => buildOrderItem(context, product, 'Completed')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildOrderItem(BuildContext context, Product product, String status) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: Colors.white,
        elevation: 3,

        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    product.imagePath,
                    width: 80,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text1(
                          text1: product.name,
                        ),
                        const Text2(text2: 'May 23, 4.3PM Delivered'),
                        Text1(
                          text1: product.price,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (status == 'Cancelled') ...[
                      Flexible(
                        child: CustomOutlinedButton(
                          text: 'Rate Courier',
                          onTap: () {
                            _showRatingDialog(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: CustomButton(
                          text: 'Re Order',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CartScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else if (status == 'Active') ...[
                      Flexible(
                        child: CustomOutlinedButton(
                          text: 'Cancel Order',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: CustomButton(
                          text: 'Track Order',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CartScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else if (status == 'Completed') ...[
                      Flexible(
                        child: CustomOutlinedButton(
                          text: 'Rate Courier',
                          onTap: () {
                            _showRatingDialog(context);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: CustomButton(
                          text: 'Re Order',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const CartScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRatingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.bgColor,
          title: const Text1(
            text1: 'Rate Courier',
            size: 16,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text1(text1: 'Please rate your courier:'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(5, (index) {
                  return const Icon(
                    Icons.star_border,
                    size: 30,
                    color: Colors.orange,
                  );
                }),
              ),
              const SizedBox(height: 20),
              const CustomTextField(
                label: 'Leave a comment',
                icon: Icons.comment,
              ),
              Row(
                children: [
                  Flexible(
                      child: CustomOutlinedButton(
                          text: 'Cancel',
                          onTap: () {
                            Navigator.pop(context);
                          })),
                  const SizedBox(
                    width: 10,
                  ),
                  Flexible(
                      child: CustomButton(
                          text: 'Submit',
                          onTap: () {
                            Navigator.pop(context);
                          })),
                ],
              )
            ],
          ),
        );
      },
    );
  }
}
