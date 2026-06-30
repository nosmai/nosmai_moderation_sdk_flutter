// Basic Flutter integration test. Runs in a full app against the host-side
// plugin (Pigeon channel). Until the native Nosmai SDK is attached, the host
// stubs return neutral SAFE results — this just verifies the channel works.
//
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:nosmai_moderation_sdk/nosmai_moderation_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('moderateText round-trips over the Pigeon channel',
      (WidgetTester tester) async {
    final NosmaiTextResult result =
        await NosmaiModeration.moderateText('hello world');
    // Stub host returns blocked = false; once the SDK is wired this exercises
    // the real classifier.
    expect(result.blocked, isNotNull);
  });
}
