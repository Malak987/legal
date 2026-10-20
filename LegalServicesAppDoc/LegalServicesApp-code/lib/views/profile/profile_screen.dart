
import 'package:legalserviceapp/views/Profile/past_orders.dart';
import 'package:legalserviceapp/views/Profile/user_infromation.dart';
import 'package:flutter/material.dart';



import '../../Constants/colors.dart';
import '../../Widgets/customapp_bar.dart';
import 'ManageAddress/address_book_screeen.dart';
import 'change_password.dart';
import 'edit_profile.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 13,vertical: 14),
          children: [
            const CustomAppBar(text: 'Profile', text1: ''),
            const SizedBox(height: 20,),
            ProfileRow(
              leadingIcon: Icons.person,
              title: 'User Information',
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const UserInformation()));
              },
            ),
            ProfileRow(
              leadingIcon: Icons.location_on,
              title: 'Address Book',
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) =>  AddressBookScreen()));
              },
            ),

            ProfileRow(
              leadingIcon: Icons.lock,
              title: 'Change Password',
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const ChangePassword()));
              },
            ),

            ProfileRow(
              leadingIcon: Icons.reorder,
              title: 'My Orders',
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) =>  const PastOrders()));
              },
            ),
            const Divider(),
            ProfileRow(
              leadingIcon: Icons.edit,
              title: 'Edit Profile',
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const EditProfile()));
              },
            ),
          ],
        ),
      ),
    );
  }
}


class ProfileRow extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final VoidCallback onTap;

  const ProfileRow({
    required this.leadingIcon,
    required this.title,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        color: Colors.white,
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Icon(leadingIcon,color: AppColors.text3Color,),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16,color: AppColors.text3Color,),
            ],
          ),
        ),
      ),
    );
  }
}
