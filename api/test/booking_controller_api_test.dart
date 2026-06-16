import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for BookingControllerApi
void main() {
  final instance = BeauticaApi().getBookingControllerApi();

  group(BookingControllerApi, () {
    //Future cancelBooking(String bookingId, CancelBookingRequest cancelBookingRequest) async
    test('test cancelBooking', () async {
      // TODO
    });

    //Future completeBooking(String bookingId) async
    test('test completeBooking', () async {
      // TODO
    });

    //Future confirmBooking(String bookingId) async
    test('test confirmBooking', () async {
      // TODO
    });

    //Future<ApiResponseBookingResponse> createBooking(CreateBookingRequest createBookingRequest, { String idempotencyKey }) async
    test('test createBooking', () async {
      // TODO
    });

    //Future declineBooking(String bookingId, StatusUpdateRequest statusUpdateRequest) async
    test('test declineBooking', () async {
      // TODO
    });

    //Future<ApiResponseBookingDetailResponse> getBooking(String bookingId) async
    test('test getBooking', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseBookingResponse> listMyBookings(Pageable pageable, { String status }) async
    test('test listMyBookings', () async {
      // TODO
    });

    //Future notCompleteBooking(String bookingId, StatusUpdateRequest statusUpdateRequest) async
    test('test notCompleteBooking', () async {
      // TODO
    });
  });
}
