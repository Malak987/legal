import 'package:flutter/material.dart';
import '../../../Widgets/customapp_bar.dart';

class TransactionScreen extends StatelessWidget {
  final List<Map<String, String>> transactions = [
    {'title': 'Parking Fee - Spot A1', 'date': '24 Oct | 9:00 AM', 'amount': '-\$10.00'},
    {'title': 'Parking Fee - Spot B3', 'date': '23 Oct | 8:00 AM', 'amount': '-\$15.00'},
    {'title': 'Parking Fee - Spot C5', 'date': '22 Oct | 2:00 PM', 'amount': '-\$20.00'},
    {'title': 'Parking Fee - Spot D2', 'date': '22 Oct | 10:00 AM', 'amount': '-\$8.00'},
    {'title': 'Parking Fee - Spot E4', 'date': '21 Oct | 1:00 PM', 'amount': '-\$30.00'},
  ];

  TransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              const CustomAppBar(text: 'Your Transactions', text1: ''),
              _buildDateSection('Today'),
              _buildTransactionItem(transactions[0]),
              const SizedBox(height: 16.0),
              _buildDateSection('Yesterday'),
              _buildTransactionItem(transactions[1]),
              const SizedBox(height: 16.0),
              _buildDateSection('22 Oct 2023'),
              _buildTransactionItem(transactions[2]),
              const SizedBox(height: 5.0),
              _buildTransactionItem(transactions[3]),
              const SizedBox(height: 16.0),
              _buildDateSection('21 Oct 2023'),
              _buildTransactionItem(transactions[4]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSection(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        date,
        style: const TextStyle(
          fontSize: 16.0,
          fontWeight: FontWeight.bold,
          color: Colors.grey, // Adjust color to match your theme
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, String> transaction) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.1 * 255).toInt(), 0, 0, 0),
            blurRadius: 8,
            offset: const Offset(0, 4), // shadow direction: bottom-right
          ),
        ],
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction['title']!,
                style: const TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600, // Slightly bolder text
                  color: Colors.black, // Ensure the text stands out
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                transaction['date']!,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14.0,
                ),
              ),
            ],
          ),
          Text(
            transaction['amount']!,
            style: TextStyle(
              color: transaction['amount']!.startsWith('-') ? Colors.red : Colors.green, // Change color dynamically
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
