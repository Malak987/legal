import 'package:flutter/material.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  int selectedPaymentIndex = 0;
  final List<Map<String, String>> paymentMethods = [
    {"name": "Credit Card", "icon": "assets/credit_card.png"},
    {"name": "PayPal", "icon": "assets/paypal.png"},
    {"name": "Apple Pay", "icon": "assets/apple_pay.png"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Payment"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select Payment Method",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildPaymentMethods(),
            const SizedBox(height: 20),
            _buildCardDetails(),
            const SizedBox(height: 20),
            _buildPromoCodeField(),
            const Spacer(),
            _buildPayNowButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      children: List.generate(paymentMethods.length, (index) {
        bool isSelected = selectedPaymentIndex == index;
        return GestureDetector(
          onTap: () => setState(() => selectedPaymentIndex = index),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.teal.shade100 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal),
            ),
            child: Row(
              children: [
                Image.asset(paymentMethods[index]["icon"]!, height: 30),
                const SizedBox(width: 12),
                Text(paymentMethods[index]["name"]!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.teal),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCardDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Card Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _buildTextField("Card Number", Icons.credit_card),
        Row(
          children: [
            Expanded(child: _buildTextField("Expiry Date", Icons.calendar_today)),
            const SizedBox(width: 10),
            Expanded(child: _buildTextField("CVV", Icons.lock)),
          ],
        ),
      ],
    );
  }

  Widget _buildPromoCodeField() {
    return TextField(
      decoration: InputDecoration(
        labelText: "Promo Code",
        prefixIcon: const Icon(Icons.discount, color: Colors.teal),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildPayNowButton() {
    return ElevatedButton(
      onPressed: () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minimumSize: const Size(double.infinity, 50),
      ),
      child: const Text("Pay Now", style: TextStyle(fontSize: 18, color: Colors.white)),
    );
  }

  Widget _buildTextField(String hint, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        decoration: InputDecoration(
          labelText: hint,
          prefixIcon: Icon(icon, color: Colors.teal),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}