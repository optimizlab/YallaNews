import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yallanews/main.dart';

void main() {
  testWidgets('first launch displays the onboarding screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('اختر لغتك المفضلة'), findsOneWidget);
  });
}
