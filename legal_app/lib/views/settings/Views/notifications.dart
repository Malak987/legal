import 'package:flutter/material.dart';


import '../../../constants/colors.dart';
import '../../../widgets/detailstext1.dart';
import '../../../widgets/detailstext2.dart';
import '../../../widgets/text11.dart';

class GroceryNotifications extends StatefulWidget {
  const GroceryNotifications({super.key});

  @override
  State<GroceryNotifications> createState() => _GroceryNotificationsState();
}

class _GroceryNotificationsState extends State<GroceryNotifications> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 5,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.text3Color)
                      ),
                      height: 30,
                      width: 30,
                      child: const Icon(
                        Icons.arrow_back,
                        size: 17,
                      ),
                    ),
                    const Spacer(),
                    const Text1(text1: 'Notification'),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                      decoration: BoxDecoration(
                          color: AppColors.buttonColor,
                          borderRadius: BorderRadius.circular(20)
                      ),
                      child: const Text11(text2: '2 New',color: Colors.white,),
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text1(text1: 'Today'),
                          Text11(text2: 'Mark all as read', color: AppColors.text3Color)
                        ],
                      ),
                    ),
                    // Notifications List
                    ..._buildNotifications(),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNotifications() {
    return List.generate(_notifications.length, (index) {
      final notification = _notifications[index];
      return Card(
        color: Colors.white,

        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: notification['iconBackgroundColor'],
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(
                  notification['icon'],
                  size: 24,
                  color: notification['iconColor'],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text1(text1: notification['title']),
                    Text2(text2: notification['content'])
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 22),
                child: CircleAvatar(
                  radius: 5,
                  backgroundColor: Colors.deepOrange,
                ),
              )
            ],
          ),
        ),
      );
    });
  }

  final List<Map<String, dynamic>> _notifications = [
    {
      'icon': Icons.check_circle,
      'iconColor': Colors.green,
      'iconBackgroundColor': Colors.green.shade100,
      'title': 'Order Confirmed',
      'content': 'Your order #12345 has been confirmed.'
    },
    {
      'icon': Icons.local_shipping,
      'iconColor': Colors.blue,
      'iconBackgroundColor': Colors.blue.shade100,
      'title': 'Order Shipped',
      'content': 'Your order #12345 has been shipped.'
    },
    {
      'icon': Icons.delivery_dining,
      'iconColor': Colors.orange,
      'iconBackgroundColor': Colors.orange.shade100,
      'title': 'Out for Delivery',
      'content': 'Your order #12345 is out for delivery.'
    },
    {
      'icon': Icons.home,
      'iconColor': Colors.purple,
      'iconBackgroundColor': Colors.purple.shade100,
      'title': 'Order Delivered',
      'content': 'Your order #12345 has been delivered.'
    },
    {
      'icon': Icons.cancel,
      'iconColor': Colors.red,
      'iconBackgroundColor': Colors.red.shade100,
      'title': 'Order Cancelled',
      'content': 'Your order #12345 has been cancelled.'
    },
    {
      'icon': Icons.payment,
      'iconColor': Colors.teal,
      'iconBackgroundColor': Colors.teal.shade100,
      'title': 'Payment Received',
      'content': 'Your payment for order #12345 has been received.'
    },
    {
      'icon': Icons.update,
      'iconColor': Colors.yellow,
      'iconBackgroundColor': Colors.yellow.shade100,
      'title': 'Order Update',
      'content': 'Your order #12345 has been updated.'
    },
    {
      'icon': Icons.support,
      'iconColor': Colors.brown,
      'iconBackgroundColor': Colors.brown.shade100,
      'title': 'Customer Support',
      'content': 'Customer support has responded to your query.'
    },
    {
      'icon': Icons.notifications,
      'iconColor': Colors.indigo,
      'iconBackgroundColor': Colors.indigo.shade100,
      'title': 'New Promotion',
      'content': 'Check out our new promotion on fresh produce!'
    },
    {
      'icon': Icons.star,
      'iconColor': Colors.amber,
      'iconBackgroundColor': Colors.amber.shade100,
      'title': 'Rate Us',
      'content': 'Please rate your recent purchase experience.'
    },
    {
      'icon': Icons.shopping_cart,
      'iconColor': Colors.green,
      'iconBackgroundColor': Colors.green.shade100,
      'title': 'Cart Reminder',
      'content': 'You have items in your cart. Don\'t forget to checkout!'
    },
    {
      'icon': Icons.new_releases,
      'iconColor': Colors.blue,
      'iconBackgroundColor': Colors.blue.shade100,
      'title': 'New Arrivals',
      'content': 'Check out the new arrivals in our store.'
    },
    {
      'icon': Icons.error,
      'iconColor': Colors.red,
      'iconBackgroundColor': Colors.red.shade100,
      'title': 'Payment Failed',
      'content': 'Your payment for order #12345 failed. Please try again.'
    },
    {
      'icon': Icons.card_giftcard,
      'iconColor': Colors.purple,
      'iconBackgroundColor': Colors.purple.shade100,
      'title': 'Gift Card Added',
      'content': 'A new gift card has been added to your account.'
    },
    {
      'icon': Icons.store,
      'iconColor': Colors.orange,
      'iconBackgroundColor': Colors.orange.shade100,
      'title': 'Store Update',
      'content': 'Our store timings have been updated.'
    },
    {
      'icon': Icons.feedback,
      'iconColor': Colors.teal,
      'iconBackgroundColor': Colors.teal.shade100,
      'title': 'Feedback Request',
      'content': 'We would love to hear your feedback on our service.'
    },
    {
      'icon': Icons.local_offer,
      'iconColor': Colors.yellow,
      'iconBackgroundColor': Colors.yellow.shade100,
      'title': 'Special Offer',
      'content': 'Don\'t miss our special offer on organic produce!'
    },
    {
      'icon': Icons.warning,
      'iconColor': Colors.brown,
      'iconBackgroundColor': Colors.brown.shade100,
      'title': 'Stock Alert',
      'content': 'An item in your wishlist is back in stock.'
    },
    {
      'icon': Icons.verified_user,
      'iconColor': Colors.indigo,
      'iconBackgroundColor': Colors.indigo.shade100,
      'title': 'Account Verified',
      'content': 'Your account has been successfully verified.'
    },
    {
      'icon': Icons.schedule,
      'iconColor': Colors.amber,
      'iconBackgroundColor': Colors.amber.shade100,
      'title': 'Delivery Rescheduled',
      'content': 'Your delivery for order #12345 has been rescheduled.'
    },
  ];
}
