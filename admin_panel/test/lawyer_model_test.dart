import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/models/models.dart';

void main() {
  test('lawyer model round-trips category ID and experience', () {
    final lawyer = Lawyer.fromJson({
      'id': 'lawyer-1',
      'name': 'Mona Fahmy',
      'specialty': 'Commercial Law',
      'experience': '8 years',
      'categoryId': 'category-commercial',
      'price': '\$150/hr',
      'priceValue': 150,
    });

    expect(lawyer.experience, '8 years');
    expect(lawyer.categoryId, 'category-commercial');
    expect(lawyer.toJson(), containsPair('experience', '8 years'));
    expect(lawyer.toJson(), containsPair('categoryId', 'category-commercial'));
  });

  test('case model reads related display names without persisting them', () {
    final item = CaseItem.fromJson({
      'id': 'case-1',
      'title': 'Contract dispute',
      'categoryId': 'category-commercial',
      'categoryName': 'Commercial Law',
      'lawyerId': 'lawyer-1',
      'lawyerName': 'Mona Fahmy',
    });

    expect(item.categoryName, 'Commercial Law');
    expect(item.lawyerName, 'Mona Fahmy');
    expect(item.toJson().containsKey('categoryName'), isFalse);
    expect(item.toJson().containsKey('lawyerName'), isFalse);
  });
}
