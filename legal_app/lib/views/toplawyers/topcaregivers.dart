import 'package:legalserviceapp/widgets/customapp_bar.dart';
import 'package:legalserviceapp/views/messages/chat_screen.dart';
import 'package:flutter/material.dart';

import '../../commonwidgets/product_data.dart';
import '../../widgets/detailstext1.dart';
import '../../models/product_model.dart';
import '../home/details.dart';

class TopCaregiverListScreen extends StatelessWidget {
  final List<Product> products = ProductData().products;


   TopCaregiverListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            children: [
              SizedBox(height: 12),

              CustomAppBar(text: 'Top Lawyers', text1: ''),
              SizedBox(height: 12),

              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder:(_)=>LegalServiceDetailsScreen()));
                      },
                      child: Card(
                        elevation: 6,
                        shadowColor: Colors.black12,
                        color: Colors.white,
                        margin: EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: SizedBox(
                                  height: 80, // Adjusted height for visibility
                                  width: 110, // Adjusted width for visibility
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.asset(
                                      products[index].imagePath,
                                      fit: BoxFit.cover,  // You can change to BoxFit.contain or BoxFit.fill if needed
                                      errorBuilder: (context, error, stackTrace) {
                                        // Handle image loading errors gracefully
                                        return Center(child: Icon(Icons.error, color: Colors.red));
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text1(
                                      text1: products[index].name,
                                    ),

                                    SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 18,
                                        ),
                                        Text(
                                          '4.5',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          color: Colors.grey.shade600,
                                          size: 18,
                                        ),
                                        Expanded(
                                          child: Text(
                                            'Uk London',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text1(
                                    text1: products[index].price,
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.purple.shade50,
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.message,
                                            color: Colors.purple,
                                          ),
                                          onPressed: () {
                                            Navigator.push(context, MaterialPageRoute(builder:(_)=>ChatScreen()));

                                            // Handle message action
                                          },
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      CircleAvatar(
                                        backgroundColor: Colors.green.shade50,
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.phone,
                                            color: Colors.green,
                                          ),
                                          onPressed: () {
                                            Navigator.push(context, MaterialPageRoute(builder:(_)=>ChatScreen()));

                                            // Handle phone action
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
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


