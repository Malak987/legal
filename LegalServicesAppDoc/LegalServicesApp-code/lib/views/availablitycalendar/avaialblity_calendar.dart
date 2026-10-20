import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../Widgets/customapp_bar.dart';
import '../../Widgets/custombtn.dart';

class AvailabilityCalendarScheduleScreen extends StatefulWidget {
  const AvailabilityCalendarScheduleScreen({super.key});

  @override
  AvailabilityCalendarScheduleScreenState createState() =>
      AvailabilityCalendarScheduleScreenState();
}

class AvailabilityCalendarScheduleScreenState
    extends State<AvailabilityCalendarScheduleScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedTimeSlot = '';

  // Mock available time slots for specific dates
  final Map<DateTime, List<String>> _availableTimeSlots = {
    DateTime.utc(2024, 9, 15): ['9:00 AM', '11:00 AM', '2:00 PM', '4:00 PM'],
    DateTime.utc(2024, 9, 16): ['10:00 AM', '12:00 PM', '3:00 PM'],
    DateTime.utc(2024, 9, 17): ['8:00 AM', '1:00 PM', '5:00 PM'],
  };

  List<String> getTimeSlotsForDate(DateTime date) {
    return _availableTimeSlots[DateTime.utc(date.year, date.month, date.day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 20.0),
          child: Column(
            children: [
              // Calendar View
              const CustomAppBar(text: 'Availablity', text1: ''),
              const SizedBox(height: 20),

              _buildCalendar(),
              const SizedBox(height: 20),
        
              // Selected Date
              Text(
                'Available Slots for ${_selectedDate.day}-${_selectedDate.month}-${_selectedDate.year}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
        
              // Availability Schedule (time slots)
              Expanded(
                child: _buildTimeSlots(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // Build Calendar Widget
  Widget _buildCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TableCalendar(
        focusedDay: _selectedDate,
        firstDay: DateTime.utc(2023, 1, 1),
        lastDay: DateTime.utc(2025, 12, 31),
        selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDate = selectedDay;
            _selectedTimeSlot = ''; // Reset selected time slot on new date
          });
        },
        calendarStyle: const CalendarStyle(
          todayDecoration: BoxDecoration(
            color: Colors.purpleAccent,
            shape: BoxShape.circle,
          ),
          selectedDecoration: BoxDecoration(
            color: Colors.deepPurpleAccent,
            shape: BoxShape.circle,
          ),
          weekendTextStyle: TextStyle(color: Colors.redAccent),
        ),
      ),
    );
  }

  // Build Time Slots Grid
  Widget _buildTimeSlots() {
    final timeSlots = getTimeSlotsForDate(_selectedDate);

    if (timeSlots.isEmpty) {
      return const Center(
        child: Text(
          'No available time slots for this date.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 15,
        crossAxisSpacing: 15,
        childAspectRatio: 2.5,
      ),
      itemCount: timeSlots.length,
      itemBuilder: (context, index) {
        bool isSelected = timeSlots[index] == _selectedTimeSlot;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedTimeSlot = timeSlots[index];
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.deepPurpleAccent : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? Colors.deepPurpleAccent : Colors.grey.shade300,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              timeSlots[index],
              style: TextStyle(
                fontSize: 16,
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }

  // Build Bottom Navigation Bar for Confirmation
  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12,vertical: 13),
      child: CustomButton(text: 'Confirm Booking', onTap:(){}),
    );
  }
}
