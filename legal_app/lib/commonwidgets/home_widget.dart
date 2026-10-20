import 'package:flutter/material.dart';

import '../widgets/detailstext1.dart';
import '../constants/colors.dart';
import '../views/settings/views/notifications.dart';

class HomeWidgte extends StatelessWidget {
  const HomeWidgte({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Builder(builder: (context) {
          return InkWell(
            onTap: () {
              Scaffold.of(context).openDrawer();
            },
            child: const Icon(
              Icons.menu_outlined,
              color: Colors.white,
            ),
          );
        }),
        const Text1(
          text1: 'Home',
          size: 16,
          color: Colors.white,
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                  const GroceryNotifications()),
            );
          },
          child: Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.notifications,
              color: AppColors.buttonColor,
            ),
          ),
        ),
      ],
    );
  }
}
