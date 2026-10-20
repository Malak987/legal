import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../widgets/customapp_bar.dart';

class EarningDetailsScreen extends StatelessWidget {
  const EarningDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomAppBar(text: 'Earnings Details', text1: ''),
                SizedBox(height: 12),
          
                // Total Earnings
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Total Earnings',
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '₦750,450',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.teal),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
          
                // Earnings Chart
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (value, meta) {
                                List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                return Text(days[value.toInt()], style: TextStyle(fontSize: 12));
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              FlSpot(0, 50),
                              FlSpot(1, 120),
                              FlSpot(2, 180),
                              FlSpot(3, 90),
                              FlSpot(4, 230),
                              FlSpot(5, 150),
                              FlSpot(6, 200),
                            ],
                            isCurved: true,
                            dotData: FlDotData(show: true),
                            color: Colors.teal,
                            belowBarData: BarAreaData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
          
                // Info Cards
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildInfoCard(Icons.access_time, 'Time Logged', '42h 32m', Colors.orange),
                    _buildInfoCard(Icons.delivery_dining, 'Total Deliveries', '120', Colors.blue),
                  ],
                ),
                SizedBox(height: 10),
          
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildInfoCard(Icons.directions_car, 'Total Distance', '315 km', Colors.green),
                    _buildInfoCard(Icons.payment, 'Pending Payments', '₦50,000', Colors.redAccent),
                  ],
                ),
                SizedBox(height: 10),
          
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildInfoCard(Icons.attach_money, 'Bonuses Earned', '₦15,000', Colors.purple),
                    _buildInfoCard(Icons.stars, 'Ratings', '4.8 ★', Colors.amber),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      backgroundColor: Colors.grey[100],
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value, Color iconColor) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withAlpha((0.2 * 255).toInt()),
              radius: 27,
              child: Icon(icon, size: 30, color: iconColor),
            ),
            SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
