// Phase 14.0 — Client booking data foundation: [BookingSlot] domain model.
//
// DEVIATION from the phase doc's Step 3 sketch: the generated
// `AvailableSlotResponse` DTO (`GET /masters/{masterId}/slots`) carries only
// `startsAt`/`endsAt` — there is no availability boolean on the wire. The
// endpoint's contract is "every slot returned IS bookable" (unavailable slots
// are simply omitted server-side), so [available] is always mapped to `true`
// by `BookingSlotMapper.fromDto` — see that file for the full rationale. The
// field is kept (rather than dropped) so the slot picker UI has a stable,
// self-describing shape and so a future backend enrichment (e.g. a
// "held-by-another-client" transient state) would not require a domain-model
// change, only a mapper change.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_slot.freezed.dart';

/// A single bookable time slot for a given master + service on a given day.
@freezed
abstract class BookingSlot with _$BookingSlot {
  const factory BookingSlot({
    required DateTime startAt,
    required DateTime endAt,

    /// Always `true` as mapped from the current backend contract — see the
    /// file-level DEVIATION note above.
    required bool available,
  }) = _BookingSlot;
}
