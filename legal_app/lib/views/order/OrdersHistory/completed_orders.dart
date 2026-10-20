import 'package:legalserviceapp/views/booking/booking.dart';
import 'package:flutter/material.dart';


import '../../../commonwidgets/product_data.dart';
import '../../../constants/colors.dart';
import '../../../widgets/custom_outline_button.dart';
import '../../../widgets/customapp_bar.dart';
import '../../../widgets/custombtn.dart';
import '../../../widgets/customtextfield.dart';
import '../../../widgets/detailstext1.dart';
import '../../../widgets/detailstext2.dart';
import '../../../models/product_model.dart';

class CompletedOrders extends StatefulWidget {
  const CompletedOrders({super.key});

  @override
  CompletedOrdersState createState() => CompletedOrdersState();
}

class CompletedOrdersState extends State<CompletedOrders> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideFromRightAnimation;

  final List<Product> products = ProductData().products;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

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
  void _showRatingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.bgColor,
          title: const Text1(
            text1: 'Rate Care',
            size: 16,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text1(text1: 'Please rate your care:'),
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomAppBar(text: 'Completed Bookings', text1: ''),
              const SizedBox(height: 20),
              Expanded(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        return SlideTransition(
                          position: _slideFromRightAnimation,
                          child: Padding(
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
                                              const Text2(text2: 'May 23, 4.3PM Delivered'),
                                              Text1(
                                                text1: products[index].price,
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
                                          Flexible(
                                            child: CustomOutlinedButton(
                                              text: 'Rate ',
                                              onTap: () {
                                                _showRatingDialog(context);

                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: CustomButton(
                                              text: 'Re Booking',
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => const BookingScreen(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
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
