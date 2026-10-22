import 'package:flutter/material.dart';

import '../../../constants/colors.dart';
import '../../../widgets/custombtn.dart';
import '../../../widgets/detailstext1.dart';
import '../../../widgets/detailstext2.dart';
import '../../../widgets/text11.dart';
import '../../../commonwidgets/product_data.dart' show ProductData;
import '../../../widgets/custom_outline_button.dart';
import '../../../widgets/customapp_bar.dart';
import '../../../models/product_model.dart';
import '../../checkout/trackmyorder.dart';
import 'active_orders.dart';
import 'cancelled_orders.dart';
import 'completed_orders.dart';

class OrdersHistory extends StatefulWidget {
  const OrdersHistory({super.key});

  @override
  OrdersHistoryState createState() => OrdersHistoryState();
}

class OrdersHistoryState extends State<OrdersHistory>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideFromLeftAnimation;
  late Animation<Offset> _slideFromRightAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _slideFromLeftAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _slideFromRightAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  final List<Product> products = ProductData().products;
  final List<Product> products1 = ProductData().products;
  final List<Product> products3 = ProductData().products;





  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return FadeTransition(
                opacity: _opacityAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CustomAppBar(text: 'My Bookings', text1: ''),
                    const SizedBox(height: 34),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const ActiveOrders()));
                      },
                      child: SlideTransition(
                        position: _slideFromLeftAnimation,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text1(
                              text1: 'Active Bookings',
                              size: 14,
                            ),
                            Text11(
                              text2: 'See All',
                              color: AppColors.text3Color,
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SlideTransition(
                      position: _slideFromLeftAnimation,
                      child: SizedBox(
                        height: 185,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 250,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
                                      spreadRadius: 2,
                                      blurRadius: 5,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: SizedBox(
                                            height: 80, // Adjusted height for visibility
                                            width: 110, // Adjusted width for visibility
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.asset(
                                                products[index].imagePath,
                                                fit: BoxFit.cover,  // You can change to BoxFit.contain or BoxFit.fill if needed
                                                errorBuilder: (context, error, stackTrace) {
                                                  // Handle image loading errors gracefully
                                                  return Center(child: Icon(Icons.error, color: Colors.red));
                                                },
                                              ),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text1(
                                                text1: products[index].name,
                                              ),
                                              const Text2(text2: 'May 23, 4.3PM'),

                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: CustomOutlinedButton(
                                                text: 'Cancel', onTap: () {}),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: CustomButton(
                                                text: 'Track', onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => const TrackLegalServiceScreen(),
                                                ),
                                              );

                                            }),
                                          )
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const CompletedOrders()));
                      },
                      child: SlideTransition(
                        position: _slideFromRightAnimation,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text1(
                              text1: 'Completed Bookings',
                              size: 14,
                            ),
                            Text11(
                              text2: 'See All',
                              color: AppColors.text3Color,
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SlideTransition(
                      position: _slideFromRightAnimation,
                      child: SizedBox(
                        height: 185,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          itemCount: products1.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 250,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
                                      spreadRadius: 2,
                                      blurRadius: 5,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: SizedBox(
                                            height: 80, // Adjusted height for visibility
                                            width: 110, // Adjusted width for visibility
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.asset(
                                                products[index].imagePath,
                                                fit: BoxFit.cover,  // You can change to BoxFit.contain or BoxFit.fill if needed
                                                errorBuilder: (context, error, stackTrace) {
                                                  // Handle image loading errors gracefully
                                                  return Center(child: Icon(Icons.error, color: Colors.red));
                                                },
                                              ),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text1(
                                                text1: products1[index].name,
                                              ),
                                              const Text2(text2: 'May 23, 4.3PM'),

                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: CustomOutlinedButton(
                                                text: 'Cancel ', onTap: () {}),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: CustomButton(
                                                text: 'Track ', onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => const TrackLegalServiceScreen(),
                                                ),
                                              );
                                            }),
                                          )
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const CancelledOrders()));
                      },
                      child: SlideTransition(
                        position: _slideFromLeftAnimation,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text1(
                              text1: 'Cancelled Bookings',
                              size: 14,
                            ),
                            Text11(
                              text2: 'See All',
                              color: AppColors.text3Color,
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SlideTransition(
                      position: _slideFromLeftAnimation,
                      child: SizedBox(
                        height: 185,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          shrinkWrap: true,
                          itemCount: products3.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 250,
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
                                      spreadRadius: 2,
                                      blurRadius: 5,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: SizedBox(
                                            height: 80, // Adjusted height for visibility
                                            width: 110, // Adjusted width for visibility
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.asset(
                                                products[index].imagePath,
                                                fit: BoxFit.cover,  // You can change to BoxFit.contain or BoxFit.fill if needed
                                                errorBuilder: (context, error, stackTrace) {
                                                  // Handle image loading errors gracefully
                                                  return Center(child: Icon(Icons.error, color: Colors.red));
                                                },
                                              ),
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text1(
                                                text1: products3[index].name,
                                              ),
                                              const Text2(text2: 'May 23, 4.3PM'),

                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          Flexible(
                                            child: CustomOutlinedButton(
                                                text: 'Cancel', onTap: () {}),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: CustomButton(
                                                text: 'Track ', onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => const TrackLegalServiceScreen(),
                                                ),
                                              );
                                            }),
                                          )
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
