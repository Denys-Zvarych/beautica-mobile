import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ProviderClientControllerApi
void main() {
  final instance = BeauticaApi().getProviderClientControllerApi();

  group(ProviderClientControllerApi, () {
    //Future<ApiResponseClientCardResponse> getMyGuestCard(String bookingId) async
    test('test getMyGuestCard', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientOwnRatingResponse> getMyGuestRatings(String bookingId, Pageable pageable) async
    test('test getMyGuestRatings', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientVisitResponse> getMyGuestVisits(String bookingId, Pageable pageable) async
    test('test getMyGuestVisits', () async {
      // TODO
    });

    //Future<ApiResponseClientCardResponse> getMyUserCard(String userId) async
    test('test getMyUserCard', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientOwnRatingResponse> getMyUserRatings(String userId, Pageable pageable) async
    test('test getMyUserRatings', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientVisitResponse> getMyUserVisits(String userId, Pageable pageable) async
    test('test getMyUserVisits', () async {
      // TODO
    });

    //Future<ApiResponseClientCardResponse> getSalonGuestCard(String salonId, String bookingId, { String masterId }) async
    test('test getSalonGuestCard', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientOwnRatingResponse> getSalonGuestRatings(String salonId, String bookingId, Pageable pageable, { String masterId }) async
    test('test getSalonGuestRatings', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientVisitResponse> getSalonGuestVisits(String salonId, String bookingId, Pageable pageable, { String masterId }) async
    test('test getSalonGuestVisits', () async {
      // TODO
    });

    //Future<ApiResponseClientCardResponse> getSalonUserCard(String salonId, String userId, { String masterId }) async
    test('test getSalonUserCard', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientOwnRatingResponse> getSalonUserRatings(String salonId, String userId, Pageable pageable, { String masterId }) async
    test('test getSalonUserRatings', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientVisitResponse> getSalonUserVisits(String salonId, String userId, Pageable pageable, { String masterId }) async
    test('test getSalonUserVisits', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientListItemResponse> listMyClients(Pageable pageable, { String q }) async
    test('test listMyClients', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseClientListItemResponse> listSalonClients(String salonId, Pageable pageable, { String masterId, String q }) async
    test('test listSalonClients', () async {
      // TODO
    });
  });
}
