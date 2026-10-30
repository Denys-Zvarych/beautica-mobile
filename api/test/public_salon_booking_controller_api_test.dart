import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for PublicSalonBookingControllerApi
void main() {
  final instance = BeauticaApi().getPublicSalonBookingControllerApi();

  group(PublicSalonBookingControllerApi, () {
    //Future<BuiltList<AvailableSlotResponse>> availability1(String slug, String masterId, Date date, BuiltList<String> serviceId) async
    test('test availability1', () async {
      // TODO
    });

    //Future<GuestBookingResponse> book1(String slug, String masterId, GuestBookingRequest guestBookingRequest, { String authorization }) async
    test('test book1', () async {
      // TODO
    });

    //Future<BuiltList<MasterWorkingDayResponse>> bookableDays1(String slug, String masterId, Date from, Date to, BuiltList<String> serviceId) async
    test('test bookableDays1', () async {
      // TODO
    });
  });
}
