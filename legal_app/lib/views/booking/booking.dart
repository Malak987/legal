 import 'package:legalserviceapp/constants/colors.dart';
import 'package:flutter/material.dart';

import '../../widgets/customapp_bar.dart';
import '../checkout/payment_screen.dart';


class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int selectedDateIndex = 0;
  int selectedTimeIndex = -1;
  int selectedHourIndex = -1;

  final List<String> dates = ['30 Jun', '01 Jul', '02 Jul', '03 Jul', '04 Jul', '05 Jul', '06 Jul'];
  final List<String> days = ['Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed'];
  final List<String> times = ['08:30 am', '09:00 am', '10:30 am', '11:00 am'];
  final List<String> hours = ['1 hour', '2 hours', '3 hours', '4 hours'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              CustomAppBar(text: 'Book Your Appointment', text1: ''),
              const SizedBox(height: 10),

              const Text('Select date', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: dates.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selectedDateIndex = index;
                        });
                      },
                      child: Container(
                        width: 70,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: selectedDateIndex == index ? AppColors.buttonColor : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(dates[index], style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: selectedDateIndex == index ? Colors.white : Colors.black,
                            )),
                            Text(days[index], style: TextStyle(
                              color: selectedDateIndex == index ? Colors.white : Colors.grey,
                            )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              const Text('Select time', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['Morning', 'Afternoon', 'Evening'].map((e) {
                  return Chip(
                    label: Text(e,style: TextStyle(color: Colors.white),),
                    backgroundColor: AppColors.buttonColor,
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: List.generate(times.length, (index) {
                  return ChoiceChip(
                    label: Text(times[index],style: TextStyle(
                      color: selectedTimeIndex == index ? Colors.white : Colors.black,
                    ),),
                    selected: selectedTimeIndex == index,
                    selectedColor: AppColors.buttonColor,
                    onSelected: (selected) {
                      setState(() {
                        selectedTimeIndex = selected ? index : -1;
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: 20),
              const Text('Select no. of hrs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: List.generate(hours.length, (index) {
                  return ChoiceChip(
                    label: Text(
                      hours[index],
                      style: TextStyle(
                        color: selectedHourIndex == index ? Colors.white : Colors.black,
                      ),
                    ),
                    selected: selectedHourIndex == index,
                    selectedColor: AppColors.buttonColor,
                    onSelected: (selected) {
                      setState(() {
                        selectedHourIndex = selected ? index : -1;
                      });
                    },
                  );
                }),
              ),

              const SizedBox(height: 30),

        
              Center(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selectedTimeIndex == -1 || selectedHourIndex == -1
                        ? null
                        : () {

                      Navigator.push(context, MaterialPageRoute(builder:(_)=>PaymentScreen()));


                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonColor,
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Confirm Booking', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
