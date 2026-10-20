import 'package:flutter/material.dart';
import 'package:legalserviceapp/constants/colors.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  SubscriptionScreenState createState() => SubscriptionScreenState();
}

class SubscriptionScreenState extends State<SubscriptionScreen> {
  final PageController _pageController = PageController(
    viewportFraction: 0.85,
  ); // Show parts of next/prev cards
  int _currentPage = 0;

  // Define colors matching the design
  static const Color basicPriceBg = Colors.red; // Light reddish pink
  static const Color silverPriceBg = Colors.blue; // Light blue
  static const Color premiumPriceBg =
      Colors.deepOrangeAccent; // Light orange/yellow
  static const Color choosePlanButtonColor = Color(
    0xFF3A86FF,
  ); // Consistent blue
  static const Color nextButtonColor = Color(0xFF0A2342); // Dark blue/indigo
  static const Color featureHeaderColor =
      Colors.grey; // Color for "For Every Users" etc.
  static const Color checkColor = Colors.green;
  static const Color crossColor = Colors.red;

  // Store plan data centrally, including feature groups
  final List<Map<String, dynamic>> plans = [
    {
      "title": "Basic Plan",
      "price": "\$ 0.00", // Format matching design
      "priceBgColor": basicPriceBg,
      "features": [
        "HEADER:For Every Users", // Special marker for headers
        "✅ Once 5 Mins Allowed To Talk With Advocates Via Voice Call",
        "✅ Users Can Chat In Advocates Q & A Groups",
        "HEADER:For Other Plan Users",
        "❌ User Can Hire An Family Intermediate Advocates",
        "❌ Book Advocates Appointment Schedule With In This App",
        "❌ Chat & Virtual Call Options Available",
      ],
    },
    {
      "title": "Silver Plan",
      "price": "\$ 799/- Inter Advocates", // Format matching design
      "priceBgColor": silverPriceBg,
      "features": [
        "HEADER:For Every Users",
        "✅ Once 5 Mins Allowed To Talk With Advocates Via Voice Call",
        "✅ Users Can Chat In Advocates Q & A Groups",
        "HEADER:For Silver Plan Users",
        "✅ User Can Hire An Family Intermediate Advocates",
        "✅ Book Advocates Appointment Schedule With In This App",
        "✅ Chat & Virtual Call Options Available",
      ],
    },
    {
      "title": "Premium Plan",
      "price": "\$ 1499/- Senior Advocates", // Format matching design
      "priceBgColor": premiumPriceBg,
      "features": [
        "HEADER:For Every Users",
        "✅ Once 5 Mins Allowed To Talk With Advocates Via Voice Call",
        "✅ Users Can Chat In Advocates Q & A Groups",
        "HEADER:For Premium Plan Users",
        "✅ User Can Hire An Family Senior Advocates",
        "✅ Book Advocates Appointment Schedule With In This App",
        "✅ Chat & Virtual Call Options Available",
      ],
    },
  ];

  void _nextPage() {
    if (_currentPage < plans.length - 1) {
      // Use plans.length
      _pageController.nextPage(
        duration: Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      // Handle what happens after the last page
      // Example: Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentScreen()));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Ensure AppBar matches design
        title: Text(
          "Select Your Plan",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold, // Use bold as per design
            fontSize: 18, // Adjust size if needed
          ),
        ),
        backgroundColor: AppColors.buttonColor, // White background
        elevation: 0, // No shadow
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,

            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            // Add some vertical padding around the PageView
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14.0),
              child: PageView.builder(
                controller: _pageController,
                itemCount: plans.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  // Add scaling effect for non-active pages
                  double scale = _currentPage == index ? 1.0 : 0.9;
                  return TweenAnimationBuilder(
                    duration: const Duration(milliseconds: 350),
                    tween: Tween(begin: scale, end: scale),
                    curve: Curves.ease,
                    child: buildPlan(
                      title: plan['title'],
                      price: plan['price'],
                      priceBgColor: plan['priceBgColor'],
                      features: plan['features'],
                    ),
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              bottom: 14.0,
              top: 0,
            ), // Adjust spacing
            child: SmoothPageIndicator(
              controller: _pageController,
              count: plans.length,
              effect: ExpandingDotsEffect(
                // Match design indicator
                activeDotColor: nextButtonColor, // Use dark blue for active dot
                dotColor: Colors.grey.shade300,
                dotHeight: 8,
                dotWidth: 8,
                expansionFactor: 3,
                spacing: 5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 15.0,
            ).copyWith(bottom: 25.0, top: 10.0), // Adjust padding for button
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: nextButtonColor, // Dark blue button
                minimumSize: Size(double.infinity, 50), // Make button wide
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ), // Match design rounding
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                // Text remains "Next" in the design for all pages
                "Next",
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPlan({
    required String title,
    required String price,
    required Color priceBgColor,
    required List<String> features,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 8.0,
      ), // Space between cards
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.1 * 255).toInt()), // Softer shadow
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset(0, 4),
          ),
        ],
        color: Colors.white,
      ),
      child: ClipRRect(
        // Clip content to rounded corners
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.center, // Center column items horizontally
            children: [
              // Plan Title
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: 12),

              // Price Container
              Container(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 45),
                decoration: BoxDecoration(
                  color: priceBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  price,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ), // White price text
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 20),

              // "Features" Header
              Text(
                "Features",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 15),

              // Build Feature List with Headers
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Align features left
                children:
                    features.map((feature) {
                      if (feature.startsWith("HEADER:")) {
                        // Render Feature Group Header
                        return Padding(
                          padding: const EdgeInsets.only(
                            top: 10.0,
                            bottom: 5.0,
                          ),
                          child: Text(
                            feature
                                .substring(7)
                                .trim(), // Get text after "HEADER:"
                            style: TextStyle(
                              fontSize: 13,
                              color: featureHeaderColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      } else {
                        // Render Feature Item
                        bool included = feature.startsWith("✅");
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start, // Align icon and text nicely
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2.0,
                                ), // Align icon better with text
                                child: Icon(
                                  included ? Icons.check_circle : Icons.cancel,
                                  color: included ? checkColor : crossColor,
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  feature.substring(2).trim(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black45,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    }).toList(),
              ),

              SizedBox(height: 25), // Space before button
              // "Choose Plan" Button
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      choosePlanButtonColor, // Use the consistent blue
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 45),
                  elevation: 2,
                  shadowColor: Colors.black.withAlpha((0.2 * 255).toInt()),
                ),
                child: Text(
                  "Choose Plan",
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: 10), // Some bottom padding inside card
            ],
          ),
        ),
      ),
    );
  }
}
