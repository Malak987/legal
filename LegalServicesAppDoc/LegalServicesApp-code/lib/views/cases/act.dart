import 'package:flutter/material.dart';
import 'package:legalserviceapp/Constants/colors.dart';
import 'package:percent_indicator/percent_indicator.dart'; // Import the package

// --- Constants --- (Adjust colors and padding as needed)
const Color primaryRed = AppColors.buttonColor;
const Color lightGreyBackground = Color(0xFFF0F0F0); // For expansion tiles
const Color darkGreyText = Colors.grey; // For "Name" label
const Color defaultTextColor = Colors.black87;
const double hPadding = 16.0; // Horizontal padding for most elements
const double vPadding = 3.0; // Vertical padding between sections

class CaseDetailsScreen extends StatelessWidget {
  const CaseDetailsScreen({
    super.key,
    // --- Pass actual data here ---
    this.caseName = "Case/Client Name Here", // Example data
    this.lastHearingDate = "20 June",
    this.nextHearingDate = "30 June",
    this.caseDetailsText = "Lorem ipsum is simply dummy text of the printing and typesetting industry. Lorem Ipsum has been the industry's standard dummy text ever since the 1500s, when an unknown printer took a galley of type and scrambled.",
    this.progressPercent = 0.65, // Example: 65%
  });

  // --- Input Data Properties ---
  final String caseName;
  final String lastHearingDate;
  final String nextHearingDate;
  final String caseDetailsText;
  final double progressPercent; // Value between 0.0 and 1.0

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Case Details',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.black),
            onPressed: () {
              // TODO: Implement edit functionality
            },
          ),
        ],
        backgroundColor: Colors.white,
        elevation: 0, // No shadow
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        // REMOVED global padding from here
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Name Label (WITH PADDING) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: hPadding),
              child: Text(
                caseName,
                style: const TextStyle(
                  color: darkGreyText,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: vPadding * 1.5),

            // --- Hearing Dates (WITH PADDING) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: hPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildHearingDateCard(
                    icon: Icons.calendar_today_outlined,
                    label: 'Last Hearing',
                    date: lastHearingDate,
                  ),
                  _buildHearingDateCard(
                    icon: Icons.calendar_today, // Slightly different icon?
                    label: 'Next Hearing',
                    date: nextHearingDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: vPadding * 2),

            // --- Case Details Section (WITH PADDING) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: hPadding),
              child: Column( // Wrap title and text in a Column for padding
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Case Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: defaultTextColor,
                    ),
                  ),
                  const SizedBox(height: vPadding / 2),
                  Text(
                    caseDetailsText,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                      height: 1.4, // Line spacing
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: vPadding * 2),

            // --- Case Progress Section (WITH PADDING) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: hPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Case Progress',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: defaultTextColor,
                    ),
                  ),
                  CircularPercentIndicator(
                    radius: 30.0,
                    lineWidth: 5.0,
                    percent: progressPercent,
                    center: Text(
                      "${(progressPercent * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.0,
                          color: primaryRed),
                    ),
                    progressColor: primaryRed,
                    backgroundColor: primaryRed.withAlpha((0.2 * 255).toInt()),
                    circularStrokeCap: CircularStrokeCap.round,
                  ),
                ],
              ),
            ),
            const SizedBox(height: vPadding * 2),

            // --- About Section Title (WITH PADDING) ---
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: hPadding),
              child: Text(
                'About',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: defaultTextColor,
                ),
              ),
            ),
            // NO general padding around the list items themselves
            const SizedBox(height: vPadding),

            // --- Expandable List Items (EDGE-TO-EDGE) ---
            _buildExpansionItem(title: 'Evidences'),
            const SizedBox(height: vPadding), // Vertical spacing between items
            _buildExpansionItem(title: 'Time Line'),
            const SizedBox(height: vPadding),
            _buildExpansionItem(title: 'Police Statement'),
            const SizedBox(height: vPadding),
            _buildExpansionItem(title: 'History'),
            const SizedBox(height: vPadding),
            _buildExpansionItem(title: 'Charges'),

            // Add some padding at the very bottom of the scroll view
            const SizedBox(height: vPadding * 2),
          ],
        ),
      ),
    );
  }

  // Helper widget for the hearing date cards (remains the same)
  Widget _buildHearingDateCard({
    required IconData icon,
    required String label,
    required String date,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: primaryRed,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                blurRadius: 5.0,
                offset: const Offset(0, 3), // Shadow position
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              date,
              style: const TextStyle(
                color: defaultTextColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper widget for the edge-to-edge expandable list items
  Widget _buildExpansionItem({required String title}) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: ExpansionTile(
        title: Container(
          decoration: BoxDecoration(
            color: lightGreyBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: hPadding),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: defaultTextColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: const BoxDecoration(
                  color: primaryRed,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                height: 50,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
        tilePadding: EdgeInsets.zero,
        trailing: const SizedBox.shrink(),
        childrenPadding: const EdgeInsets.symmetric(horizontal: hPadding, vertical: 10),
        backgroundColor: Colors.white,
        collapsedBackgroundColor: Colors.transparent,
        children: <Widget>[
          Text(
            'Details about $title will be shown here. Add relevant widgets or fetched data.',
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
