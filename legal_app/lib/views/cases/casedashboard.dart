import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../widgets/customapp_bar.dart';
import 'act.dart';
import 'advocatname.dart';
import 'casecode.dart';
import 'casenumber.dart';
import 'firnumber.dart';

// --- Constants ---
const Color primaryRed = AppColors.buttonColor; // Dark red similar to image
const Color cardTextIconColor = Colors.white;
const double cardCornerRadius = 12.0;
const double cardElevation = 4.0;

class CaseStatusScreen extends StatelessWidget {
  const CaseStatusScreen({super.key});

  // Helper function to navigate (Replace with your actual navigation logic)

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center, // Center items horizontally
            children: [
             CustomAppBar(text: 'Case Status', text1: ''),
              
              const SizedBox(height: 20), // Space before the grid
        
              // Using GridView.count for the 2-column layout
              GridView.count(
                crossAxisCount: 2, // 2 columns
                shrinkWrap: true, // Important inside a Column
                physics: const NeverScrollableScrollPhysics(), // Disable grid scrolling
                mainAxisSpacing: 2.0, // Vertical spacing between rows
                crossAxisSpacing: 6.0, // Horizontal spacing between columns
                childAspectRatio: 1.0, // Make items square-ish (adjust as needed)
                children: <Widget>[
                  _buildSearchCard(
                    context: context,
                    icon: Icons.person_search_outlined, // Example icon
                    text: 'Case Number',
                    onTap: (){
                      Navigator.push(context, MaterialPageRoute(builder:(_)=>SearchByCaseNumberScreen()));
                    },
                  ),
                  _buildSearchCard(
                    context: context,
                    icon: Icons.account_balance_wallet_outlined, // Example icon
                    text: 'Advocate\nName', // Added newline for wrapping if needed
                    onTap: (){
                      Navigator.push(context, MaterialPageRoute(builder:(_)=>SearchByPartyNameScreen()));
                    },                  ),
                  _buildSearchCard(
                    context: context,
                    icon: Icons.qr_code_scanner, // Example icon (barcode like)
                    text: 'Fir Number',
                    onTap: (){
                      Navigator.push(context, MaterialPageRoute(builder:(_)=>SearchByFirNumberScreen()));
                    },                  ),
                  _buildSearchCard(
                    context: context,
                    icon: Icons.qr_code, // Example icon (barcode like)
                    text: 'Case Code',
                    onTap: (){
                      Navigator.push(context, MaterialPageRoute(builder:(_)=>SearchByCaseCodeScreen()));
                    },                  ),
                  // The 'Act' card might need adjustment if you want it centered
                  // Option 1: Keep it in the grid (will align left in the last row)
                  _buildSearchCard(
                    context: context,
                    icon: Icons.gavel, // Gavel icon for Act
                    text: 'Act',
                    onTap: (){
                      Navigator.push(context, MaterialPageRoute(builder:(_)=>CaseDetailsScreen()));
                    },                  ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build each card consistently
  Widget _buildSearchCard({
    required BuildContext context,
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Card(
      color: primaryRed,
      elevation: cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(cardCornerRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(cardCornerRadius), // Match card shape for ripple
        child: Padding(
          padding: const EdgeInsets.all(12.0), // Padding inside the card
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Center content vertically
            crossAxisAlignment: CrossAxisAlignment.center, // Center content horizontally
            children: [
              Icon(
                icon,
                size: 40.0, // Adjust icon size as needed
                color: cardTextIconColor,
              ),
              const SizedBox(height: 10.0), // Space between icon and text
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: cardTextIconColor,
                  fontSize: 14.0, // Adjust text size as needed
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// --- Placeholder Screen for Navigation ---
// Replace this with your actual screen for showing search results/details
class PlaceholderSearchScreen extends StatelessWidget {
  final String searchType;

  const PlaceholderSearchScreen({super.key, required this.searchType});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search by $searchType'),
        backgroundColor: primaryRed, // Match theme
      ),
      body: Center(
        child: Text(
          'This screen will allow searching by $searchType.',
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

