import 'package:flutter/material.dart';
import '../../Widgets/customapp_bar.dart';
import 'earningdetails.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  EarningsScreenState createState() => EarningsScreenState();
}

class EarningsScreenState extends State<EarningsScreen> {
  DateTime selectedDate = DateTime.now();

  void _previousWeek() {
    setState(() {
      selectedDate = selectedDate.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      selectedDate = selectedDate.add(const Duration(days: 7));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(13.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// **Custom App Bar**
              CustomAppBar(text: 'Earnings', text1: ''),

              const SizedBox(height: 12),

              /// **Week Selector**
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_left, size: 28),
                    onPressed: _previousWeek,
                  ),
                  Text(
                    "${selectedDate.subtract(const Duration(days: 3)).toLocal().toString().split(' ')[0]} - ${selectedDate.add(const Duration(days: 3)).toLocal().toString().split(' ')[0]}",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_right, size: 28),
                    onPressed: _nextWeek,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              /// **Earnings Overview Card**
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xffF38B08), Color(0xffFFBB33)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha((0.2 * 255).toInt()),
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Current Balance (₦)",
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "\$1,250.75",
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Next Payout: Jan 15, 2025",
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              /// **Earnings Breakdown**
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                      blurRadius: 6,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildEarningsRow("Total Deliveries", "52"),
                    _buildEarningsRow("Hours Worked", "48 Hours 15 Minutes"),
                    _buildEarningsRow("Base Fare", "\$820.00"),
                    _buildEarningsRow("Distance Earnings", "\$220.50"),
                    _buildEarningsRow("Tips Received", "\$85.75"),
                    _buildEarningsRow("Bonuses", "\$125.00"),
                    _buildEarningsRow("Referral Bonus", "\$100.00"),
                    _buildEarningsRow("Surge Earnings", "\$50.00"),
                    const Divider(),
                    _buildTotalEarningsRow("Total Earnings", "\$1,250.75"),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              /// **See Details Button**
              Center(
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EarningDetailsScreen()),
                    );
                  },
                  child: const Text(
                    "See Full Details",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// **Reusable Widget for Earnings Rows**
  Widget _buildEarningsRow(String label, String value) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(),
      ],
    );
  }

  /// **Total Earnings Row with Highlighted Color**
  Widget _buildTotalEarningsRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blue)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
      ],
    );
  }
}
