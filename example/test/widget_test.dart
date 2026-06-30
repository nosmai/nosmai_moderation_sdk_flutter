import 'package:flutter_test/flutter_test.dart';

import 'package:nosmai_moderation_sdk_example/main.dart';

void main() {
  testWidgets('App renders the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NosmaiExampleApp());
    expect(find.text('Nosmai'), findsOneWidget);
  });
}
