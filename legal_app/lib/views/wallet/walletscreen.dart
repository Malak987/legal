import 'package:legalserviceapp/views/wallet/toppup.dart';
import 'package:flutter/material.dart';

import '../../../constants/colors.dart';
import '../../../widgets/detailstext1.dart';



class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  WalletScreenState createState() => WalletScreenState();
}

class WalletScreenState extends State<WalletScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {},
        ),
        title: const Text('Wallet'),
      centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GestureDetector(
              onTap: (){
                Navigator.push(context, MaterialPageRoute(builder: (_)=>const TopUp()));

              },
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.buttonColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'My Balance',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              'Top Up',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 10,),
                    Text1(text1: '\$4,875.00',color: Colors.white,size: 19,)


                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: (){
                // showModalBottomSheet(
                //   context: context,
                //   isScrollControlled: true, // This allows it to occupy a larger portion of the screen
                //   builder: (BuildContext context) {
                //     return const PaymentBottomSheet();
                //   },
                // );
              },
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 13,vertical: 4),
                color: Colors.white,


                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'Payment Method',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.add,color: AppColors.buttonColor,)
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.tabColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.asset(
                              'images/card.png',
                              height: 24,
                              width: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mastercard',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '6895 3526 8456 ****',
                                style: TextStyle(
                                  fontSize: 12,
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
            ),
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transaction History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  transactionItem(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Drop Off Payment',
                    date: 'Mar 18, 2022',
                    amount: '\$25.5',
                  ),
                  transactionItem(
                    icon: Icons.delivery_dining,
                    title: 'Cargo Shipping',
                    date: 'Mar 10, 2022',
                    amount: '\$29.5',
                  ),
                  transactionItem(
                    icon: Icons.local_shipping,
                    title: 'Express Shipping',
                    date: 'Mar 6, 2022',
                    amount: '\$50.6',
                  ),transactionItem(
                    icon: Icons.delivery_dining,
                    title: 'Cargo Shipping',
                    date: 'Mar 10, 2022',
                    amount: '\$29.5',
                  ),
                  transactionItem(
                    icon: Icons.local_shipping,
                    title: 'Express Shipping',
                    date: 'Mar 6, 2022',
                    amount: '\$50.6',
                  ),
                  transactionItem(
                    icon: Icons.local_offer,
                    title: 'Pick Up Payment',
                    date: 'Mar 2, 2022',
                    amount: '\$16.8',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget transactionItem({
    required IconData icon,
    required String title,
    required String date,
    required String amount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha((0.2 * 255).toInt()),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.buttonColor,
                child: Icon(
                  icon,
                  color: Colors.deepOrange,

                  size: 25,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}