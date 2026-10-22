import 'package:flutter/material.dart';


import '../../constants/colors.dart';
import '../../widgets/customapp_bar.dart';
import '../../widgets/custombtn.dart';
import '../../widgets/detailstext1.dart';
import '../../widgets/detailstext2.dart';
import 'add_money.dart';


class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          children: [
            const CustomAppBar(text: 'Wallet', text1: ''),
            const SizedBox(
              height: 13,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              height: 135,
              decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text2(text2: 'Wallet Balance'),
                          Text1(
                            text1: '\$12000.00',
                            size: 17,
                          )
                        ],
                      ),
                      Spacer(),
                      Icon(
                        Icons.wallet,
                        color: AppColors.buttonColor,
                        size: 30,
                      )
                    ],
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  CustomButton(
                      text: 'Add Money',
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) => const AddMoneyScreen()));
                      })
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              itemCount: 8,
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text1(
                        text1: 'Today',
                        size: 17,
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromARGB((0.1 * 255).toInt(), 128, 128, 128),
                              spreadRadius: 2,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Column(
                          children: [
                            Row(
                              children: [
                                Text1(
                                  text1: 'Money Added To Wallet',
                                  size: 16,
                                ),
                                Spacer(),
                                Text1(
                                  text1: '-\$5000.00',
                                  size: 16,
                                  color: Colors.green,
                                )
                              ],
                            ),
                            SizedBox(
                              height: 4,
                            ),
                            Row(
                              children: [
                                Text2(
                                  text2: '23 September | 7:30 AM',
                                ),
                                Spacer(),
                                Text2(
                                  text2: 'Balance\$5000.00',
                                )
                              ],
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
