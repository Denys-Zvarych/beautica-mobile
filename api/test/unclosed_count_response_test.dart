import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for UnclosedCountResponse
void main() {
  final instance = UnclosedCountResponseBuilder();
  // TODO add properties to the builder and call build()

  group(UnclosedCountResponse, () {
    // Non-negative count of the caller's own bookings currently awaiting closure (CONFIRMED and elapsed). Scope mirrors GET /bookings/me's provider/client scope exactly — see that endpoint's role table.
    // int count
    test('to test the property `count`', () async {
      // TODO
    });
  });
}
