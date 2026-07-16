// Phase 14.3 — «Деталі запису» data source.
//
// A plain family FutureProvider (not an AsyncNotifier) — there is no
// client-owned mutation here, only a fetch of `GET /bookings/{bookingId}`.
// Cancel (`CancelBookingDialog` → `BookingRepository.cancelBooking`)
// invalidates this provider (and the affected `myBookingsProvider` tabs) so
// the screen re-fetches the fresh server state and re-renders in place —
// see `booking_detail_screen.dart`'s cancel handler.
//
// autoDispose (the default for a `@riverpod` function) — the cache drops
// once nothing watches it (the detail screen is popped).

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/booking_providers.dart';
import '../domain/booking.dart';

part 'booking_detail_notifier.g.dart';

/// The enriched detail for one booking.
@riverpod
Future<Booking> bookingDetail(Ref ref, String bookingId) {
  return ref.watch(bookingRepositoryProvider).getBookingById(bookingId);
}
