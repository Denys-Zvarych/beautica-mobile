// Phase 241 — navigation payload for `RouteNames.bookingNew`
// (`ServiceSelectorSheet`, independent-master booking flow Step 1).
//
// The route's ORIGINAL contract (Phase 14.1, `public_master_profile_screen.dart`'s
// «Записатись» CTA) is a bare masterId `String` in `GoRouterState.extra` — the
// client picks the service INSIDE the screen. This class is an ADDITIVE
// extension point, not a fork: `app_router.dart`'s `bookingNew` route still
// accepts the bare `String` shape unchanged (every existing call site keeps
// working verbatim) and now ALSO accepts this typed payload when a caller
// already knows exactly which service to book.
//
// The wish-list rebook CTA (phase 241) is the first caller: every entry is a
// (master, service) pair by construction (`WishlistService.masterId` /
// `.masterServiceId`), so there is nothing to pick — [preselectedServiceId]
// carries it straight through to `ServiceSelectorSheet.initialServiceId`,
// which (combined with `autoAdvance: true`) skips the manual "Далі" tap and
// advances straight to the slot picker the instant the catalogue confirms the
// service still resolves. See `service_selector_sheet.dart`.
//
// Pure Dart: no Flutter imports in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking_entry_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingNew` when the caller already knows
/// which service to book (as opposed to the bare masterId `String` shape,
/// which is still accepted for the "pick inside the screen" case).
@freezed
abstract class BookingEntryArgs with _$BookingEntryArgs {
  const factory BookingEntryArgs({
    /// Target master's backend UUID. Same identity `ServiceSelectorSheet`
    /// would otherwise receive as the bare-`String` extra.
    required String masterId,

    /// The exact `master_services` assignment id to pre-select — e.g.
    /// [WishlistService.masterServiceId]. `ServiceSelectorSheet` still
    /// validates it against the freshly-loaded catalogue rather than trusting
    /// it blindly (a service can be deactivated between the caller's own data
    /// load and this screen's fetch); a stale id simply fails to match and the
    /// catalogue renders normally, unselected.
    required String preselectedServiceId,
  }) = _BookingEntryArgs;
}
