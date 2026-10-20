import 'package:flutter/material.dart';
import 'package:legalserviceapp/Widgets/customapp_bar.dart';

import 'casedashboard.dart';

// Define consistent colors based on the screenshot
const Color primaryRed = Color(0xFFB71C1C); // Dark red for AppBar
const Color cardRed = Color(0xFFD32F2F);   // Slightly lighter red for cards
const Color searchBgGrey = Color(0xFFF0F0F0); // Light grey for search background
const Color hintGrey = Colors.grey;
const Color cardTextWhite = Colors.white;

class MyCasesScreen extends StatelessWidget {
  const MyCasesScreen({super.key});

  // Sample Data (Replace with your actual data source)
  final List<Map<String, String>> caseData = const [
    {
      'title': 'Case 1',
      'description': 'This is how we do it there is no a', // Truncated as per image
      'date': '9:30, Today',
      'image': 'images/case.png' // Make sure this path is correct
    },
    {
      'title': 'Case 2',
      'description': 'This is how we do it there is no',
      'date': '2 sep, last week',
      'image': 'images/case.png' // Make sure this path is correct
    },
    {
      'title': 'Case 3',
      'description': 'This is how we do it there is no',
      'date': '2 sep, last week',
      'image': 'images/case.png' // Make sure this path is correct
    },
    {
      'title': 'Case 4',
      'description': 'This is how we do it there is no',
      'date': '2 sep, last week',
      'image': 'images/case.png' // Make sure this path is correct
    }, {
      'title': 'Case 1',
      'description': 'This is how we do it there is no a', // Truncated as per image
      'date': '9:30, Today',
      'image': 'images/case.png' // Make sure this path is correct
    },
    {
      'title': 'Case 2',
      'description': 'This is how we do it there is no',
      'date': '2 sep, last week',
      'image': 'images/case.png' // Make sure this path is correct
    },
    {
      'title': 'Case 3',
      'description': 'This is how we do it there is no',
      'date': '2 sep, last week',
      'image': 'images/case.png' // Make sure this path is correct
    },
    {
      'title': 'Case 4',
      'description': 'This is how we do it there is no',
      'date': '2 sep, last week',
      'image': 'images/case.png' // Make sure this path is correct
    },
    // Add more cases as needed
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use default light theme background (usually white/off-white)

      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: CustomAppBar(text: 'My Cases', text1: ''),
            ),
            Expanded(
              child: GestureDetector(
                onTap: (){

                  Navigator.push(context, MaterialPageRoute(builder:(_)=>CaseStatusScreen()));

                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  itemCount: caseData.length,
                  itemBuilder: (context, index) {
                    final caseItem = caseData[index];
                    return _buildCaseCard(
                      context: context,
                      title: caseItem['title']!,
                      description: caseItem['description']!,
                      date: caseItem['date']!,
                      imagePath: caseItem['image']!,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for the search bar area

  // Helper widget for building each case card
  Widget _buildCaseCard({
    required BuildContext context,
    required String title,
    required String description,
    required String date,
    required String imagePath,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0), // Spacing between cards
      child: Card(
        color: Colors.white,
        child: IntrinsicHeight( // Ensures Row children have same height
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children vertically
            children: [
              // Image part
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10.0),
                  bottomLeft: Radius.circular(10.0),
                ),
                child: Image.asset(
                  imagePath,
                  width: 100, // Adjust width as needed
                  height: 80, // Make it square or adjust aspect ratio
                  fit: BoxFit.cover,
                  // Error handling for image loading
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 100,
                      height: 80,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    );
                  },
                ),
              ),

              // Text content part
              SizedBox(width: 10,),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(0.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center, // Center text vertically
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                        maxLines: 2, // Allow description to wrap slightly
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        date,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- To Run this Screen (Example Usage) ---
