import 'package:flutter/material.dart';

import '../../../constants/colors.dart';
import '../../../widgets/custombtn.dart';
import '../../../widgets/customtextfield.dart';
import '../../../widgets/detailstext1.dart';


class EditProfile extends StatelessWidget {
  const EditProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: 30,
                        width: 30,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.text3Color),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.black54, size: 20),
                      ),
                    ),
                    const Text1(
                      text1: 'Edit Profile',
                      size: 16,
                    ),
                    const Text1(text1: ''), // Placeholder for any action button
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: CircleAvatar(
                        radius: 30,
                        backgroundImage: AssetImage('images/c3.png'), // Example profile picture
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'John Doe', // Example username
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text1Color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'john.doe@example.com', // Example email
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.text2Color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const CustomTextField(
                        icon: Icons.person_outline, label: 'First Name'),
                    const CustomTextField(
                        icon: Icons.person_outline, label: 'Last Name'),
                    const CustomTextField(
                        icon: Icons.email, label: 'Email Address'),
                    const CustomTextField(
                        icon: Icons.phone, label: 'Phone Number'),
                    const CustomTextField(
                        icon: Icons.home, label: 'Street Address'),
                    const CustomTextField(
                        icon: Icons.location_city, label: 'City'),
                    const CustomTextField(
                        icon: Icons.location_on, label: 'State'),
                    const CustomTextField(
                        icon: Icons.markunread_mailbox, label: 'Zip Code'),
                    const CustomTextField(
                        icon: Icons.flag, label: 'Country'),
                    const SizedBox(height: 15),
                    CustomButton(
                        text: 'Save Information',
                        onTap: () {
                          // Handle save information action
                        }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
