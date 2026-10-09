import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for PendingBookingActionsCountResponse
void main() {
  final instance = PendingBookingActionsCountResponseBuilder();
  // TODO add properties to the builder and call build()

  group(PendingBookingActionsCountResponse, () {
    // Total bookings still needing a provider action: toClose + toRateClient. Uncapped; the client caps its display.
    // int count
    test('to test the property `count`', () async {
      // TODO
    });

    // CONFIRMED bookings whose end has passed (offer «Завершити» / «Не відбувся»).
    // int toClose
    test('to test the property `toClose`', () async {
      // TODO
    });

    // COMPLETED bookings with a registered client and no client review yet (offer «Залишити відгук про клієнта»).
    // int toRateClient
    test('to test the property `toRateClient`', () async {
      // TODO
    });
  });
}
