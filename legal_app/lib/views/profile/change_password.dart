import 'package:flutter/material.dart';

import '../../../widgets/customapp_bar.dart';
import '../../../widgets/custombtn.dart';
import '../../../widgets/customtextfield.dart';
import '../../../widgets/detailstext1.dart';

class ChangePassword extends StatelessWidget {
  const ChangePassword({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13,vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CustomAppBar(text: 'Change Password', text1:''),
                const SizedBox(height: 45,),
                const Text1(text1: 'Change Your Password'),
                const SizedBox(height: 8,),
                const CustomTextField(
                    icon: Icons.lock,
                    icon2: Icons.visibility_off,
                    label: 'Current Password'),
                const SizedBox(height: 8,),
                const CustomTextField(
                    icon: Icons.lock,
                    icon2: Icons.visibility_off,
                    label: 'New Password'),
                const SizedBox(height: 8,),
                const CustomTextField(
                    icon: Icons.lock,
                    icon2: Icons.visibility_off,
                    label: 'Confirm New Password'),
                const SizedBox(height: 16,),
                CustomButton(
                  text: 'Change Password',
                  onTap: () {
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
