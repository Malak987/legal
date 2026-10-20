import 'package:legalserviceapp/constants/colors.dart';
import 'package:flutter/material.dart';
import '../../widgets/custombtn.dart';
import '../../widgets/detailstext1.dart';
import '../../widgets/detailstext2.dart';
import '../booking/booking.dart';

class LegalServiceDetailsScreen extends StatelessWidget {
  const LegalServiceDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 200,
                floating: false,
                pinned: true,
                backgroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    children: [
                      Container(
                        width: double.infinity, // Takes full width of the screen
                        height: 310, // Set the height according to your needs
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          child: Image.network(
                            'https://img.freepik.com/premium-photo/portrait-lawyer-looking-documents-office_107420-12586.jpg?w=996', // Adjusted image for legal services
                            width: double.infinity, // Ensures the image takes up full width
                            height: 310, // Ensures the image respects the container height
                            fit: BoxFit.cover, // Ensures the image fits correctly in the container
                          ),
                        ),
                      )

                    ],
                  ),
                ),
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: AppColors.buttonColor,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ];
          },
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitleAndFav(),
                const SizedBox(height: 8),
                _buildLocation(),
                const SizedBox(height: 16),
                _buildExperience(),
                const SizedBox(height: 16),
                _buildAboutService(),
                const SizedBox(height: 16),
                _buildKeyFeatures(),
              ],
            ),
          ),
        ),
      ),
      bottomSheet: Padding(
        padding: const EdgeInsets.all(16.0),
        child: CustomButton(
          text: 'Book Now',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const BookingScreen()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitleAndFav() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text1(
            text1: 'Legal Consultation Service',
            size: 22,
          ),
        ),
        const Icon(Icons.favorite, color: Colors.red, size: 32),
      ],
    );
  }

  Widget _buildLocation() {
    return const Row(
      children: [
        Icon(Icons.location_on, color: Colors.orangeAccent),
        SizedBox(width: 6),
        Text2(text2: 'Available in New York & Nearby Areas'),
      ],
    );
  }

  Widget _buildExperience() {
    return Text(
      '10+ Years of Legal Experience',
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Color(0xFF3498db),
      ),
    );
  }

  Widget _buildAboutService() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.2 * 255).toInt(), 158, 158, 158),
            spreadRadius: 1,
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text1(text1: 'About Legal Service', size: 20),
          const SizedBox(height: 10),
          Text2(
            text2:
            'Our legal experts offer personalized consultations and legal representation for individuals and businesses. Services include legal advice, contract review, dispute resolution, and more. Get expert guidance for your legal needs.',
          ),
        ],
      ),
    );
  }

  Widget _buildKeyFeatures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text1(text1: 'Key Features', size: 20),
        const SizedBox(height: 8),
        _buildFeature('Experienced Lawyers with Proven Success'),
        _buildFeature('Free Initial Consultation'),
        _buildFeature('Personalized Legal Services for Every Client'),
        _buildFeature('Affordable Pricing Plans'),
        _buildFeature('24/7 Legal Support Available'),
      ],
    );
  }

  Widget _buildFeature(String feature) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(feature,
                style: const TextStyle(fontSize: 16, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
