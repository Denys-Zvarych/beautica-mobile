// Default «Записи» / «Архів» pending-actions count for widget-test harnesses
// (2026-11-05). The master nav bar's «Записи» tile now watches
// `pendingBookingActionsCountProvider` on every independent-master and
// owner-master-mode tab screen; unpinned, the real provider issues a Dio
// request whose zero-duration timer outlives the test tree ("A Timer is still
// pending even after the widget tree was disposed").
//
// Same opt-out shape as `withDefaultNoUnread` / `withDefaultNoReportedTargets`:
// the default is injected ONLY when the caller owns neither the count provider
// nor `bookingRepositoryProvider` — a test that supplies a booking repository
// (e.g. to drive the «Архів» badge from a stubbed `getPendingActionsCount`)
// keeps reading through it, so no badge assertion is defanged.

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:beautica_mobile/features/booking/application/pending_booking_actions_count.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';

/// Pins every [PendingActionsScope] of the count to `0` (no badge, no request).
final Object kNoPendingBookingActionsOverride =
    pendingBookingActionsCountProvider.overrideWith((ref, scope) async => 0);

/// Prepends [kNoPendingBookingActionsOverride] unless [overrides] already
/// overrides the count family or the booking repository.
List<Object> withDefaultNoPendingActions(List<Object> overrides) {
  final bool callerOwnsIt = overrides.any(
    (Object o) =>
        o is Override &&
        (o.origin == pendingBookingActionsCountProvider ||
            o.origin == bookingRepositoryProvider),
  );
  return callerOwnsIt
      ? overrides
      : <Object>[kNoPendingBookingActionsOverride, ...overrides];
}
