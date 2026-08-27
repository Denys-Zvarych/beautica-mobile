import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for GuestClientDto
void main() {
  final instance = GuestClientDtoBuilder();
  // TODO add properties to the builder and call build()

  group(GuestClientDto, () {
    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // String surname
    test('to test the property `surname`', () async {
      // TODO
    });

    // Normalised to E.164 (+380XXXXXXXXX) server-side; foreign numbers are rejected.
    // String phone
    test('to test the property `phone`', () async {
      // TODO
    });
  });
}
