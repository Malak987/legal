import 'package:flutter/material.dart';
import 'package:legalserviceapp/Constants/colors.dart';
import 'package:legalserviceapp/views/aicasepredictiontool/aicaseprditionaitool.dart'; // Ensure correct path
import 'package:legalserviceapp/views/aidocumentsreview/aireview.dart'; // Ensure correct path
import 'package:legalserviceapp/views/cases/cases.dart'; // Ensure correct path
import 'package:legalserviceapp/views/popularlawyers/popularlawyers.dart'; // Ensure correct path
import 'package:legalserviceapp/views/tasks/tasks.dart'; // Ensure correct path

import '../views/AvailablityCalendar/avaialblity_calendar.dart'; // Ensure correct path
import '../views/BookMark/bookmark.dart'; // Ensure correct path
import '../views/Home/homescreen.dart'; // Ensure correct path
import '../views/Order/OrdersHistory/order_history_screen.dart'; // Ensure correct path
import '../views/Profile/profile_screen.dart'; // Ensure correct path
import '../views/Reviews/reviews.dart'; // Ensure correct path
import '../views/Search/search_screen.dart'; // Ensure correct path
import '../views/Settings/settings.dart'; // Ensure correct path
import '../views/booking/booking.dart'; // Ensure correct path
import '../views/chatbot/chatbot.dart'; // Ensure correct path
import '../views/earnings/earnings.dart'; // Ensure correct path
import '../views/favorites/favorite_screen.dart'; // Ensure correct path
import '../views/messages/chat_screen.dart'; // Ensure correct path
import '../views/subscription/subscription.dart'; // Ensure correct path
import '../views/toplawyers/topcaregivers.dart'; // Ensure correct path (assuming this is Top Lawyers)
import '../views/wallet/wallet_screen.dart'; // Ensure correct path
import 'detailstext1.dart'; // Ensure correct path

class DrawerWidget extends StatefulWidget {
  const DrawerWidget({super.key});

  @override
  State<DrawerWidget> createState() => _DrawerWidgetState();
}

class _DrawerWidgetState extends State<DrawerWidget> {
  String selectedMenuItem = 'Homepage'; // Track the selected menu item, default to Homepage

  @override
  Widget build(BuildContext context) {
    return Container(
      // Consider setting a max width for larger screens
      // width: MediaQuery.of(context).size.width * 0.75, // Example width constraint
      margin: const EdgeInsets.only(right: 60), // Keep margin if desired for visual effect
      decoration: BoxDecoration(
        color: Colors.white, // Use Theme.of(context).canvasColor for theme consistency?
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [ // Add subtle shadow for depth
          BoxShadow(
            color: Colors.grey.withAlpha((0.2 * 255).toInt()),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.only(left: 15, right: 5, top: 20), // Adjusted padding
      child: ListView(
           padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        children: [
          // User Info Header
          Padding(
            padding: const EdgeInsets.only(left: 5.0, bottom: 10.0), // Add padding to header
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                // Consider using NetworkImage or a placeholder if image might be dynamic
                child: Image.asset('images/c3.png', width: 50, height: 50, fit: BoxFit.cover),
              ),
              title: const Text(
                  'Hey!',
                  style: TextStyle(fontSize: 14, color: Colors.grey) // Smaller greeting
              ),
              subtitle: const Text1(
                text1: 'James Powell',
                // Optionally style Text1 if needed, e.g., fontWeight: FontWeight.bold
              ),
              contentPadding: EdgeInsets.zero, // Remove default ListTile padding if needed
            ),
          ),

          // Menu Items
          buildMenuItem(
            title: "Homepage",
            icon: Icons.home_outlined, // Use outlined version for consistency
            onTap: () => navigateTo( HomePage()), // Use const constructors where possible
          ),
          buildMenuItem(
            title: "My Cases",
            icon: Icons.folder_copy_outlined, // Icon for cases/folders
            onTap: () => navigateTo(const MyCasesScreen()),
          ),
          buildMenuItem(
            title: "Popular Lawyers",
            icon: Icons.star_border, // Icon for popular/rating
            onTap: () => navigateTo( PopularLawyersScreen()),
          ),
          buildMenuItem(
            title: "Top Lawyers",
            icon: Icons.workspace_premium_outlined, // Icon for top/premium/verified
            onTap: () => navigateTo( TopCaregiverListScreen()), // Assuming this is Top Lawyers
          ),
          buildMenuItem(
            title: "Search", // Moved Search up for discoverability
            icon: Icons.search, // Standard search icon
            onTap: () => navigateTo( SearchScreen()),
          ),
          buildMenuItem(
            title: "Booking", // Making a booking/appointment
            icon: Icons.edit_calendar_outlined, // Icon related to scheduling/editing calendar
            onTap: () => navigateTo(const BookingScreen()),
          ),
          buildMenuItem(
            title: "My Bookings", // Viewing existing bookings/orders
            icon: Icons.receipt_long_outlined, // Icon for list/receipt of orders
            onTap: () => navigateTo(const OrdersHistory()),
          ),
          buildMenuItem(
            title: "Availability",
            icon: Icons.event_available_outlined, // Icon specifically for availability/calendar checking
            onTap: () => navigateTo(const AvailabilityCalendarScheduleScreen()),
          ),
          buildMenuItem(
            title: "Tasks",
            icon: Icons.task_alt_outlined, // Icon for completed tasks or checklist
            onTap: () => navigateTo(const TasksScreen()),
          ),
          buildMenuItem(
            title: "Messages",
            icon: Icons.message_outlined, // Outlined message icon
            onTap: () => navigateTo(const ChatScreen()),
          ),

          // AI Tools Section (Optional Grouping)
          // Padding(
          //   padding: const EdgeInsets.only(top: 15.0, left: 10.0, bottom: 5.0),
          //   child: Text("AI Tools", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
          // ),
          buildMenuItem(
            title: "Legal AI Chatbot",
            icon: Icons.smart_toy_outlined, // Icon for AI/bot
            onTap: () => navigateTo(const LegalChatScreen()),
          ),
          buildMenuItem(
            title: "Case Prediction Tool",
            icon: Icons.online_prediction_outlined, // Icon for prediction/analytics
            onTap: () => navigateTo(const CasePredictionTool()),
          ),
          buildMenuItem(
            title: "Document Review AI",
            icon: Icons.find_in_page_outlined, // Icon for document analysis/search
            onTap: () => navigateTo(const DocumentReviewAI()),
          ),

          // Other Features
          buildMenuItem(
            title: "Favorite Lawyers", // More descriptive title
            icon: Icons.favorite_border, // Favorite outline
            onTap: () => navigateTo(const FavoriteScreen()),
          ),
          buildMenuItem(
            title: "Bookmarks", // Changed title casing
            icon: Icons.bookmark_border, // Bookmark outline
            onTap: () => navigateTo(const BookmarkScreen()),
          ),

          buildMenuItem(
            title: "Earnings",
            icon: Icons.account_balance_outlined, // Icon often used for finance/balance
            onTap: () => navigateTo(const EarningsScreen()),
          ),
          buildMenuItem(
            title: "Wallet",
            icon: Icons.account_balance_wallet_outlined, // Wallet outline
            onTap: () => navigateTo(const WalletScreen()),
          ),
          buildMenuItem(
            title: "Subscriptions",
            icon: Icons.subscriptions_outlined, // Subscriptions outline
            onTap: () => navigateTo(const SubscriptionScreen()),
          ),
          buildMenuItem(
            title: "Reviews",
            icon: Icons.rate_review_outlined, // Rate review outline
            onTap: () => navigateTo(const Reviews()),
          ),

          // Account & Settings Section
          const Divider(thickness: 0.8, indent: 10, endIndent: 10, height: 30), // Use Divider with height

          buildMenuItem(
            title: "Profile",
            icon: Icons.person_outline, // Person outline
            onTap: () => navigateTo(const ProfileScreen()),
          ),
          buildMenuItem(
            title: "Settings",
            icon: Icons.settings_outlined, // Settings outline
            onTap: () => navigateTo(const Settings()),
          ),
          ListTile( // Keep Logout as a distinct ListTile
            onTap: () {
              // Implement Logout Logic Here
              // e.g., show confirmation dialog, clear tokens, navigate to login
            },
            leading: const Icon(
              Icons.logout,
              color: Colors.redAccent,
              size: 22, // Slightly larger icon for logout
            ),
            title: const Text(
              "Logout",
              style: TextStyle(
                fontSize: 16,
                color: Colors.redAccent,
                fontWeight: FontWeight.w500, // Slightly bolder
              ),
            ),
            contentPadding: const EdgeInsets.only(left: 12.0), // Adjust padding
          ),
          const SizedBox(height: 20), // Add some space at the bottom
        ],
      ),
    );
  }

  Widget buildMenuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    bool isSelected = title == selectedMenuItem;
    Color contentColor = isSelected ? Colors.white : Colors.black87; // Colors for text/icon
    Color? tileColor = isSelected ? AppColors.buttonColor : null; // Background color - Changed to Teal

    return Padding(
      // Wrap with Padding instead of Container margin for better spacing control
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.0),
      child: Material( // Use Material for ink splash effect on tap
        color: tileColor ?? Colors.transparent, // Set background color
        borderRadius: BorderRadius.circular(8), // Consistent border radius
        child: InkWell( // Use InkWell for tap feedback
          onTap: () {
            setState(() {
              selectedMenuItem = title; // Update selected state
            });
            Navigator.pop(context); // Close the drawer after selection
            onTap(); // Execute the navigation / action
          },
          borderRadius: BorderRadius.circular(8), // Match Material border radius
          splashColor: Colors.teal.withAlpha((0.2 * 255).toInt()), // Customize splash color
          highlightColor: Colors.teal.withAlpha((0.1 * 255).toInt()), // Customize highlight color
          child: Padding( // Inner padding for content
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22, // Consistent icon size
                  color: contentColor,
                ),
                const SizedBox(width: 15), // Increased space after icon
                Expanded( // Allow text to wrap or truncate gracefully
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15, // Consistent font size
                      color: contentColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, // Bolder when selected
                    ),
                    overflow: TextOverflow.ellipsis, // Handle long text
                  ),
                ),
                // Removed the explicit '> ' icon, selection highlight is enough
                // If needed, add it back:
                // if (isSelected) // Maybe only show arrow when selected?
                //   Icon(Icons.arrow_forward_ios, size: 16, color: contentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Consider making navigation more robust (e.g., using named routes)
  void navigateTo(Widget page) {
    // Pushing will add to the stack. If you want to replace the current screen
    // (like going from home to settings), use Navigator.pushReplacement
    // Or use a proper navigation package like go_router.
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }
}