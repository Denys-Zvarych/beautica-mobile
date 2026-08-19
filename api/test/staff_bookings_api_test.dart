import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for StaffBookingsApi
void main() {
  final instance = BeauticaApi().getStaffBookingsApi();

  group(StaffBookingsApi, () {
    // Create a walk-in booking on a master's calendar
    //
    // Salon owners and admins may book any master of the salon they manage; an independent master may book only themselves. The salon the booking is scoped to is derived from the caller, never from the request. The booking is created CONFIRMED with source STAFF, no cancel token, and created_by_user_id set to the caller. The guest phone is normalised to E.164 server-side; non-Ukrainian numbers are rejected.  A confirmation SMS is dispatched to that phone number after the booking is committed, subject to the platform-wide app.booking.sms.enabled switch. Delivery is best-effort: it never changes the response, and no field here reports whether a message was sent. No push or email notification is sent by this endpoint.
    //
    //Future<ApiResponseBookingResponse> createStaffBooking(String masterId, CreateStaffBookingRequest createStaffBookingRequest) async
    test('test createStaffBooking', () async {
      // TODO
    });
  });
}
