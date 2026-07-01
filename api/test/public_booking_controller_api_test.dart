import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for PublicBookingControllerApi
void main() {
  final instance = BeauticaApi().getPublicBookingControllerApi();

  group(PublicBookingControllerApi, () {
    //Future<BuiltList<AvailableSlotResponse>> availability(String slug, Date date, String serviceId) async
    test('test availability', () async {
      // TODO
    });

    //Future<GuestBookingResponse> book(String slug, GuestBookingRequest guestBookingRequest, { String authorization }) async
    test('test book', () async {
      // TODO
    });

    //Future cancel(String token) async
    test('test cancel', () async {
      // TODO
    });

    //Future<CancelTokenInfoResponse> cancelInfo(String token) async
    test('test cancelInfo', () async {
      // TODO
    });

    //Future<BookingSlugInfoResponse> info(String slug) async
    test('test info', () async {
      // TODO
    });
  });
}
