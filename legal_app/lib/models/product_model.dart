class Product {
  final String imagePath;
  final String name;
  final String price;

  // Optional fields populated from the backend (Firestore).
  final String? id;
  final String? specialty;
  final double? rating;
  final String? location;

  Product({
    required this.imagePath,
    required this.name,
    required this.price,
    this.id,
    this.specialty,
    this.rating,
    this.location,
  });
}