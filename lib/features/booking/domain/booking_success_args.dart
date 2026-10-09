// Navigation payload for the `/booking/success` route.
//
// [BookingConfirmScreen]'s «Записатись» CTA `pushReplacement`s here once the
// single `POST /appointments` has succeeded, carrying the SAME [master] + the
// ordered [services] selection + the visit [startAt] the confirm screen already
// had in hand (loaded once via `publicMasterProfileProvider`) — the success
// screen never re-fetches, it re-renders the identical [BookingSummaryCards]
// recap so the two screens can never visually drift.
//
// MO-3 (single-visit rework): the independent-master flow now books the whole
// selection as ONE visit with ONE start time (services run back-to-back), so
// the success recap shows the ordered service list under a SINGLE visit window
// (`startAt` → `startAt + summed duration`) and offers ONE «Додати в календар»
// event for the whole arrival — not one card/event per service.
//
// Pure Dart: no Flutter imports anywhere in this file.

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../master/domain/master.dart';
import '../../services/domain/master_service.dart';
import 'create_master_booking_request.dart';

part 'booking_success_args.freezed.dart';

/// Navigation extra for `RouteNames.bookingSuccess`.
@freezed
abstract class BookingSuccessArgs with _$BookingSuccessArgs {
  const factory BookingSuccessArgs({
    required Master master,

    /// The confirmed visit's ordered services (1..10). Always non-empty (the
    /// success screen is only reached once the visit was created).
    required List<MasterService> services,

    /// The confirmed visit's single start time.
    required DateTime startAt,

    /// `true` when the flow was a RESCHEDULE (a single existing booking moved
    /// to a new time) rather than a fresh visit — the success screen swaps its
    /// celebration title/subline copy accordingly. Defaults to `false`.
    @Default(false) bool isReschedule,

    /// `true` when the flow was the master's own WALK-IN («Новий запис»)
    /// entry point rather than a client booking. Defaults to `false`. See
    /// phase-258.
    @Default(false) bool isWalkIn,

    /// Audit-fix cycle 2 (FIX 1, 2026-08-21) — the walk-in guest identity to
    /// echo back on the terminal done screen, mirroring the retired wizard's
    /// `_DoneStep` guest card (`git show HEAD:.../master_create_booking_screen
    /// .dart`, deleted by the phase-258+ routed-chain port). Non-null only on
    /// the walk-in path — threaded from `BookingConfirmScreen._submit`'s
    /// walk-in branch, the SAME `guest` it already reads off
    /// `BookingConfirmArgs`. `null` on every existing call site (client
    /// create, reschedule), so this is a purely additive field: the recap
    /// gates the guest card on `isWalkIn && guest != null`, never on
    /// [isWalkIn] alone, so those paths render byte-identically. Defaults to
    /// `null`.
    WalkInGuest? guest,

    /// RESCHEDULE-ONLY, client-identity parity fields (2026-08-22) — the
    /// reschedule-path counterpart of [guest]: forwarded unchanged from
    /// [BookingConfirmArgs.rescheduleClientName] /
    /// [BookingConfirmArgs.rescheduleClientPhone] by `BookingConfirmScreen
    /// ._submit`. `null` on every CREATE call site (client or walk-in) and on
    /// a CLIENT's own reschedule; non-null only when a PROVIDER rescheduled a
    /// booking with a registered client identity to show. The done screen
    /// gates its [GuestIdentityCard.identity] recap card on
    /// [rescheduleClientName] non-null, mirroring how it gates the walk-in
    /// card on `isWalkIn && guest != null`, so those paths render
    /// byte-identically.
    String? rescheduleClientName,
    String? rescheduleClientPhone,

    /// `true` when the person who reached this screen is a PROVIDER (salon
    /// owner / salon admin / master) acting on someone else's booking, rather
    /// than a client acting on their own. Forwarded unchanged from
    /// [BookingConfirmArgs.hideMasterIdentity] by `BookingConfirmScreen
    /// ._submit` — the SAME session-derived `bookingViewerRoleProvider
    /// .isProvider` fact `reschedule_navigation.dart` already seeds, never a
    /// second read.
    ///
    /// The done screen suppresses «Додати в календар» on this path: a master
    /// or salon admin who just moved a CLIENT's booking has no use for that
    /// visit in their OWN OS calendar (their own calendar surface is «Мої
    /// записи»). Deliberately NOT gated on [isReschedule] — a CLIENT
    /// rescheduling their own booking KEEPS the button (locked product
    /// decision, 2026-09-18). Defaults to `false`, so every CREATE call site
    /// and every client-side path renders byte-identically.
    @Default(false) bool isProviderViewer,

    /// VENUE ADDRESS OVERRIDE (2026-09-18) — the address of the place the
    /// visit actually happens, when the caller already knows it.
    ///
    /// The recap otherwise composes the address from [master]`.street /
    /// .buildingNo / .city`, which the backend DELIBERATELY nulls for a
    /// `SALON_MASTER` / `SALON_OWNER` (`MasterDetailResponse.java:104-127` —
    /// "a salon master's precise address is the salon's business address"),
    /// so a salon booking rendered «Адресу не вказано». The reschedule flow
    /// already fetches the full `Booking`, whose `street`/`buildingNo`/
    /// `cityLabel`/`locationNote` the backend resolved salon-vs-independent
    /// server-side (`BookingDetailResponse.java:580-648`) — these fields
    /// simply thread that address through
    /// `BookingSlotPickerArgs` → `BookingConfirmArgs` → here.
    ///
    /// ALL default to `null`; the screen PREFERS them and falls back to
    /// [master] when the composed venue line is `null`, so every CREATE call
    /// site (which passes none of them) renders byte-identically. Deliberately
    /// NOT modelled by widening `Master`/`MasterMapper` with salon-address
    /// fields — that would change every master surface in the app.
    String? venueStreet,
    String? venueBuildingNo,
    String? venueCity,
    String? venueLocationNote,

    /// Phase 383 (24.1f) — the WALK-IN «Готово» landing. `null` (the default)
    /// keeps `RouteNames.masterBookings` — every pre-existing call site is
    /// unchanged. The owner master-mode walk-in chain sets
    /// `RouteNames.ownerMasterBookings` (a SALON_OWNER `go`ing to `/master/*`
    /// would be bounced). Read only on the `isWalkIn && !isReschedule` branch.
    String? returnRoute,
  }) = _BookingSuccessArgs;
}
