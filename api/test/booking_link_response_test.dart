import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for BookingLinkResponse
void main() {
  final instance = BookingLinkResponseBuilder();
  // TODO add properties to the builder and call build()

  group(BookingLinkResponse, () {
    // MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376)
    // String kind
    test('to test the property `kind`', () async {
      // TODO
    });

    // Permanent public slug; never changes once issued
    // String slug
    test('to test the property `slug`', () async {
      // TODO
    });

    // Absolute https URL, no UTM (the app appends UTM per share action): MASTER https://beautica.app/book/{slug}, SALON https://beautica.app/book/s/{slug}
    // String url
    test('to test the property `url`', () async {
      // TODO
    });

    // Master full name, or salon name for SALON links
    // String displayName
    test('to test the property `displayName`', () async {
      // TODO
    });

    // Salon id for SALON links; null for MASTER links
    // String salonId
    test('to test the property `salonId`', () async {
      // TODO
    });

    // false = clients see the page but cannot book yet (MASTER: no active service or no schedule; SALON: no bookable master)
    // bool bookable
    test('to test the property `bookable`', () async {
      // TODO
    });
  });
}
