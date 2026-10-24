import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/screens/categories_screen.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

Map<String, dynamic> _categoryList() => {
      'success': true,
      'message': 'OK',
      'data': {
        'items': [
          {'id': 'family-category', 'name': 'Family Law', 'slug': 'family-law'},
        ],
        'total': 1,
        'page': 1,
        'limit': 100,
        'totalPages': 1,
      },
    };

Future<void> _pump(WidgetTester tester, FakeApiService api) async {
  final provider = AuthProvider(FakeAuthService(api: api));
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: CategoriesScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads category names and slugs from the categories endpoint',
      (tester) async {
    final api = FakeApiService(resultsByPath: {'categories': _categoryList()});
    await _pump(tester, api);

    expect(find.text('Family Law'), findsOneWidget);
    expect(find.text('family-law'), findsOneWidget);
    final request = api.requestsFor('GET', 'categories').single;
    expect(request.query['page'], '1');
    expect(request.query['limit'], '100');
  });

  testWidgets('creates a category through POST /categories', (tester) async {
    final api = FakeApiService(resultsByPath: {'categories': _categoryList()});
    await _pump(tester, api);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Category name'), 'Estate Law');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.requestsFor('POST', 'categories'), hasLength(1));
    expect(api.lastBodyFor('POST', 'categories'), {'name': 'Estate Law'});
  });

  testWidgets('deletes through DELETE /categories/:id after confirmation',
      (tester) async {
    final api = FakeApiService(resultsByPath: {'categories': _categoryList()});
    await _pump(tester, api);

    await tester.tap(find.byTooltip('Delete category'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(api.requestsFor('DELETE', 'categories/family-category'), hasLength(1));
  });
}
