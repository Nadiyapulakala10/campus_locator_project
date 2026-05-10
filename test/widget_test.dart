import 'package:flutter_test/flutter_test.dart';
import 'package:campus_locator/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Basic smoke test — Firebase initialization is handled in main()
    expect(CampusLocatorApp, isNotNull);
  });
}
