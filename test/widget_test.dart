import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yallanews/main.dart';

void main() {
  testWidgets('YallaNews app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that SplashPage displays the application name.
    expect(find.text('يلا News'), findsOneWidget);
    expect(find.text('Your AI-Powered News Companion'), findsOneWidget);
  });
}
