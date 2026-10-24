import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for SalonBookingSlugInfoResponse
void main() {
  final instance = SalonBookingSlugInfoResponseBuilder();
  // TODO add properties to the builder and call build()

  group(SalonBookingSlugInfoResponse, () {
    // String salonId
    test('to test the property `salonId`', () async {
      // TODO
    });

    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // Settlement display name (salons.city, denormalised from the taxonomy city).
    // String city
    test('to test the property `city`', () async {
      // TODO
    });

    // String avatarUrl
    test('to test the property `avatarUrl`', () async {
      // TODO
    });

    // String coverImageUrl
    test('to test the property `coverImageUrl`', () async {
      // TODO
    });

    // null while the salon has no reviews (never a fabricated 0).
    // num avgRating
    test('to test the property `avgRating`', () async {
      // TODO
    });

    // int reviewCount
    test('to test the property `reviewCount`', () async {
      // TODO
    });

    // false when no master of the salon is bookable yet; masters is then empty.
    // bool bookable
    test('to test the property `bookable`', () async {
      // TODO
    });

    // BuiltList<SalonBookingSlugMasterItem> masters
    test('to test the property `masters`', () async {
      // TODO
    });
  });
}
