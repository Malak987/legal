import 'package:flutter/material.dart';

import '../../../widgets/customapp_bar.dart';
import 'manage_adress.dart';

class AddressBookScreen extends StatelessWidget {
  final List<Map<String, String>> addresses = [
    {
      'name': 'James Powell',
      'phone': '86345454533',
      'email': 'James@gmail.com',
      'street': 'Uk 32 Street',
      'city': 'London',
      'state': 'UK',
      'zip': '664544',
      'country': 'UK',
      'company': 'Company Name',
      'apt': 'Apt 101'
    },
    {
      'name': 'James Powell',
      'phone': '86345454533',
      'email': 'James@gmail.com',
      'street': 'Uk 32 Street',
      'city': 'London',
      'state': 'UK',
      'zip': '664544',
      'country': 'UK',
      'company': 'Company Name',
      'apt': 'Apt 101'
    },
    {
      'name': 'James Powell',
      'phone': '86345454533',
      'email': 'James@gmail.com',
      'street': 'Uk 32 Street',
      'city': 'London',
      'state': 'UK',
      'zip': '664544',
      'country': 'UK',
      'company': 'Company Name',
      'apt': 'Apt 101'
    },
    {
      'name': 'James Powell',
      'phone': '86345454533',
      'email': 'James@gmail.com',
      'street': 'Uk 32 Street',
      'city': 'London',
      'state': 'UK',
      'zip': '664544',
      'country': 'UK',
      'company': 'Company Name',
      'apt': 'Apt 101'
    },
    {
      'name': 'James Powell',
      'phone': '86345454533',
      'email': 'James@gmail.com',
      'street': 'Uk 32 Street',
      'city': 'London',
      'state': 'UK',
      'zip': '664544',
      'country': 'UK',
      'company': 'Company Name',
      'apt': 'Apt 101'
    },
    // Add more addresses here
  ];

   AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomAppBar(text: 'Address Book', text1: ''),
              const SizedBox(height: 15,),
              Expanded(
                child: ListView.builder(
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final address = addresses[index];
                    return Card(
                      color: Colors.white,
                      elevation: 1,
                      child: ListTile(
                        title: Text(address['name']!),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(address['phone']!),
                            Text(address['email']!),
                            Text(address['street']!),
                            Text('${address['city']}, ${address['state']} ${address['zip']}'),
                            Text(address['country']!),
                            Text(address['company']!),
                            Text(address['apt']!),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ManageAddressScreen(

                                    ),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ManageAddressScreen(

                                    ),
                                  ),
                                );

                                // Handle delete address
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
