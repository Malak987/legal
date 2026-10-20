import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../widgets/customapp_bar.dart';
import '../../widgets/custombtn.dart';
import '../../widgets/customtextfield.dart';
import '../../widgets/detailstext1.dart';
import 'order_confirmation_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  PaymentScreenState createState() => PaymentScreenState();
}

class PaymentScreenState extends State<PaymentScreen> {
  DateTime? selectedDate;
  String? selectedTimeSlot;
  String selectedPaymentMethod = 'paypal';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomAppBar(text: 'Payment', text1: ''),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 16),
                    _buildSectionTitle('Expected date & Time'),
                    const SizedBox(height: 12),
                    _buildDateTimePicker(),
                    const SizedBox(height: 16),
                    _buildSectionTitle('Payment Method'),
                    const SizedBox(height: 12),
                    _buildPaymentMethods(),
                    const SizedBox(height: 10),
                    const CustomTextField(label: 'Card Holder Name', icon: Icons.person),
                    const CustomTextField(label: 'Card Number', icon: Icons.credit_card),
                    const CustomTextField(label: 'Expiry Date', icon: Icons.calendar_today),
                    const CustomTextField(label: 'CVV', icon: Icons.lock),
                    const SizedBox(height: 10),
                    _buildPriceDetails(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Proceed',
                onTap: _handlePayment,
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildSectionTitle(String title, [String? actionText]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text1(
          text1: title,
        ),
        if (actionText != null)
          TextButton(
            onPressed: () {},
            child: Text(actionText, style: const TextStyle(color: Colors.orange)),
          ),
      ],
    );
  }


  Widget _buildDateTimePicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _selectDate,
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: AppColors.buttonColor),
                const SizedBox(width: 8),
                Text1(
                  text1: selectedDate == null
                      ? 'Select Date'
                      : selectedDate.toString(),
                ),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              '8 AM - 11 AM',
              '11 AM - 1 PM',
              '2 PM - 5 PM',
              '5 PM - 8 PM',
              '8 PM - 11 PM'
            ]
                .map((slot) => ChoiceChip(
              backgroundColor: AppColors.bgColor,
              selectedColor: AppColors.text3Color,
              label: Text1(text1: slot),
              checkmarkColor: Colors.white,
              selected: selectedTimeSlot == slot,
              onSelected: (selected) {
                setState(() {
                  selectedTimeSlot = slot;
                });
              },
            ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPaymentMethodTile(
              'Pay with PayPal', 'paypal', 'images/icons8-paypal-48.png'),
          const Divider(),
          _buildPaymentMethodTile(
              'Cash on delivery', 'cod', 'images/icons8-payment-48.png'),
          const Divider(),
          const Text1(
            text1: 'Other Methods',
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodTile(String title, String value, String image) {
    return RadioListTile(
      value: value,
      groupValue: selectedPaymentMethod,
      activeColor: AppColors.text3Color,
      hoverColor: Colors.red,
      onChanged: (String? value) {
        setState(() {
          selectedPaymentMethod = value!;
        });
      },
      title: Row(
        children: [
          Image.asset(
            image,
            width: 30,
          ),
          const SizedBox(width: 8),
          Text1(text1: title),
        ],
      ),
    );
  }

  Widget _buildPriceDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPriceDetailRow('Sub total price', '\$1720'),
          const SizedBox(height: 8),
          _buildPriceDetailRow('Coupon', 'None'),
          const SizedBox(height: 8),
          _buildPriceDetailRow('Delivery Fee', '\$24'),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _buildPriceDetailRow('Total', '\$1960', isTotal: true),
        ],
      ),
    );
  }

  Widget _buildPriceDetailRow(String title, String value,
      {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: AppColors.buttonColor)),
        Text(value,
            style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: Colors.grey)),
      ],
    );
  }

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _handlePayment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const OrderConfirmationScreen(

        ),
      ),
    );
  }
}
