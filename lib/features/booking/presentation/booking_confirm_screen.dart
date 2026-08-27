// BookingConfirmScreen: the independent-master booking flow's final
// review-and-submit step (the `/booking/confirm` route).
//
// MO-3 (single-visit rework): the client multi-selects services in Step 1 and
// picks ONE date + ONE start time for the whole visit on the time step. This
// screen reviews the WHOLE visit — the ordered service list, a single visit
// window (`startAt` → `startAt + summed duration`), the summed total (or a
// min–max band when any service is range-priced), and an optional visit-level
// «Коментар для майстра» — then submits it as ONE `POST /appointments`
// (`AppointmentSubmit.submitVisit`), auto-confirmed to CONFIRMED. This REPLACES
// the pre-MO-3 "N `POST /bookings`, one per service" fan-out and its
// per-appointment partial-failure UI.
//
// ERROR HANDLING: one call now, so one clear error state. A failed submit maps
// the typed [Failure] (a 409 `CLIENT_BOOKING_CONFLICT` / `BOOKING_ALREADY_ELAPSED`
// / `DUPLICATE_SERVICE`, a 429 rate-limit, or a generic failure) to ONE inline
// error banner pinned directly above the CTA — the screen stays fully
// interactive so the client can re-tap «Записатись» (reusing the SAME
// idempotency key, so a retry de-duplicates) or back out and re-pick a time.
//
// RESCHEDULE: when `rescheduleBookingId` is non-null the flow moves a single
// EXISTING booking — [services] holds one element and the submit swaps to
// `PATCH /bookings/{id}/reschedule` (`AppointmentSubmit.reschedule`); the
// comment field is hidden (that endpoint has no comment channel). A
// `ClientBookingConflictFailure` on either reschedule endpoint (backend
// commit c1c2349 added `allowClientOverlap` to both) opens the SAME
// `showClientBookingConflictDialog` the client-create branch uses, resubmits
// with the override on confirm — but ONLY when the session-derived
// `bookingViewerRoleProvider` (read directly, NOT via `widget.args
// .hideMasterIdentity` — that field is a presentation flag with an
// independent, role-unrelated producer, see the `_submit` read site) resolves
// to `BookingViewerRole.client`. The backend honours `allowClientOverlap`
// ONLY for a CLIENT actor; a PROVIDER reschedule rethrows straight to the
// generic `on Failure` banner instead of opening a dialog whose confirm would
// just 409 again.
//
// PER-ITEM VISIT RESCHEDULE (track 30.x, superseding track 27.x/MO-6's
// whole-visit flow): when `rescheduleAppointmentId` is ALSO non-null (checked
// FIRST — see `_submit`), [rescheduleBookingId] identifies ONE service of a
// multi-service visit, and the submit swaps to
// `PATCH /appointments/{id}/services/{bookingId}/reschedule`
// (`AppointmentSubmit.rescheduleAppointmentItem`) instead of the per-booking
// `AppointmentSubmit.reschedule`. [services] STILL holds exactly the one item
// being moved (mirroring the plain single-booking reschedule path above) —
// this endpoint moves ONLY that service, never its siblings (no re-layout, no
// cascade, no gap-closing; the visit may legally become non-contiguous
// afterwards). The endpoint itself is dual-actor (the visit's own CLIENT or
// an assigned PROVIDER); either footer of `booking_detail_screen.dart`'s
// `_onReschedule` may set it. Because this now shares the exact same
// single-item shape as the plain reschedule branch, the post-write
// invalidation is UNIFIED with the plain-reschedule set too
// (`bookingDetailProvider(id)` + `myBookingsProvider(BookingTab.upcoming)` +
// `nextAppointmentProvider`) — PLUS `bookingsDayProvider`, scoped to the
// affected date(s) (the NEW day from `widget.args.startAt` and, when still
// resolvable, the OLD day the moved booking's PRE-reschedule
// `bookingDetailProvider(rescheduleId)` cache reports) — mirroring
// `booking_calendar_invalidation.dart`'s per-date-scoped precedent, NOT the
// bare-family invalidation `booking_detail_screen.dart`'s
// `_confirmDecline`/`_confirmComplete` still use (that whole-family shape is
// the EXACT mobile-perf MEDIUM pattern `booking_calendar_invalidation.dart`
// was written to replace — evicting the bounded 3-day keepAlive LRU for every
// kept day, not just the one this write touched). `_onReschedule` forwards
// `appointmentId` for BOTH client and provider viewers: a PROVIDER moving one
// service of their own visit must also refresh their own day-calendar
// screen, or it keeps showing the item at its OLD slot until the ≤3-day
// keepAlive LRU evicts (mobile-perf CRITICAL fix). The earlier whole-visit
// flow's endpoint is untouched on the backend; only this mobile entry point
// to it was retired.
//
// DATA SOURCE: `BookingConfirmArgs` carries the fully-resolved ordered
// [services] + the single [startAt] + the stable visit idempotency key + the
// master. The master identity + address are re-read from
// `publicMasterProfileProvider(masterId)` — the SAME 5-minute-keepAlive family
// the earlier flow screens already warmed — so reaching this screen normally
// costs zero extra round trips.
//
// SEC: renders the INDEPENDENT master's address (street/buildingNo/city/
// locationNote — for a solo master that may be a HOME address) — acquires the
// app-wide screenshot guard in `initState`. Do not remove in a future audit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/booking_calendar_invalidation.dart';
import '../application/booking_detail_notifier.dart';
import '../application/booking_notifier.dart';
import '../application/booking_viewer_role.dart';
import '../application/master_create_booking_notifier.dart';
import '../application/my_bookings_notifier.dart';
import '../domain/appointment.dart';
import '../domain/booking_confirm_args.dart';
import '../domain/booking_success_args.dart';
import '../domain/booking_tab.dart';
import '../domain/create_appointment_request.dart';
import '../domain/create_master_booking_request.dart';
import 'widgets/booking_comment_field.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/client_booking_conflict_dialog.dart';
import 'widgets/guest_identity_card.dart';
import 'widgets/master_strip.dart';

/// Booking flow final review — the single-visit confirm-and-submit screen.
class BookingConfirmScreen extends ConsumerStatefulWidget {
  const BookingConfirmScreen({super.key, required this.args});

  final BookingConfirmArgs args;

  @override
  ConsumerState<BookingConfirmScreen> createState() =>
      _BookingConfirmScreenState();
}

class _BookingConfirmScreenState extends ConsumerState<BookingConfirmScreen> {
  static const int _maxComment = 500;

  final TextEditingController _comment = TextEditingController();

  /// The last submit's failure, or `null` before/after a successful submit —
  /// drives the single inline error banner. Cleared at the start of each
  /// submit.
  Failure? _failure;

  /// Phase 262 D5 — a SYNCHRONOUS reentrancy guard, closing a race window
  /// `masterCreateBookingProvider`'s own `isLoading` structurally cannot
  /// cover: `isLoading` flips back to `false` a microtask BEFORE this
  /// screen's own post-await continuation runs (the `mounted`/`hasError`
  /// checks, then the `pushReplacement`), leaving a real window for a second
  /// tap to fire a second POST. Checked and flipped synchronously, before any
  /// `await`, in `_submit`'s walk-in branch.
  ///
  /// AUDIT-FIX CYCLE 2 (FIX 4, 2026-08-21) — corrects an earlier framing.
  /// This is NOT the `_stagedDate`/rebuild-blast-radius fix
  /// (`master_create_booking_screen.dart`'s retired `_stagedDate` doc, which
  /// this field otherwise mirrors in NAME and mechanism): `_submitting.value
  /// = true` and `masterCreateBookingProvider`'s own `state =
  /// AsyncLoading()` both fire synchronously in the SAME tap-handler stack,
  /// before any `await`, and `build()` already `ref.watch`es
  /// `masterCreateBookingProvider.select(isLoading)` — so both are scheduled
  /// for the SAME frame either way; a plain `setState`-driven `bool` here
  /// would cost this screen nothing extra. This field's genuine value is
  /// purely as the reentrancy guard above — a property a `ValueNotifier`
  /// gives no more of than a plain field would; it is a `ValueNotifier`
  /// here only so its own narrowly-scoped `ValueListenableBuilder` (see the
  /// CTA footer's doc below) can read it without a `setState` on the
  /// screen's `State`. Do NOT copy this pattern elsewhere expecting a
  /// rebuild-scoping perf win — pin the reentrancy-guard behaviour itself,
  /// as `should_submitOnce_when_ctaDoubleTapped_onWalkInPath` does.
  ///
  /// USER-LOCKED NARROWING (phase-262 doc's D5 proposed covering all four
  /// `_submit` branches — the client-create path is approved/retested and
  /// must not change behaviour, so this guard is checked and set ONLY
  /// inside the walk-in (`guest != null`) branch of `_submit`. It is
  /// unreachable from the reschedule and client-create branches — those
  /// keep relying solely on `inFlight` exactly as before this phase. See
  /// `docs/mobile-phases/phase-262-walkin-confirm-fourth-submit-branch.md`'s
  /// Status section for the recorded deviation.
  final ValueNotifier<bool> _submitting = ValueNotifier<bool>(false);

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _comment.dispose();
    _submitting.dispose();
    super.dispose();
  }

  bool get _isReschedule => widget.args.rescheduleBookingId != null;

  /// The visit's summed duration in minutes — drives the single window's end
  /// time everywhere (confirm window, success window, calendar event).
  /// `widget.args.services` never changes for this screen's life, so it is
  /// summed once (mirrors `BookingSuccessScreen`'s `late final`) rather than
  /// re-folded on each submit-spinner-toggle / failure `setState` rebuild.
  late final int _totalDurationMinutes = widget.args.services.fold<int>(
    0,
    (int sum, MasterService s) => sum + s.durationMinutes,
  );

  /// The visit's ordered service selections, mapped for the summary card once —
  /// `widget.args.services` is immutable for this screen's life, so this is not
  /// re-derived on the submit-spinner-toggle / failure `setState` rebuilds
  /// (mirrors `BookingSuccessScreen`'s `late final _selections`).
  late final List<BookingSelection> _selections = <BookingSelection>[
    for (final MasterService s in widget.args.services)
      BookingSelection(
        name: s.name,
        price: ServicePriceDisplay.format(s),
        duration: DurationMinutes.format(s.durationMinutes),
        durationMinutes: s.durationMinutes,
        priceMin: s.priceMin,
        priceMax: s.priceMax,
      ),
  ];

  Future<void> _submit(Master master, List<MasterService> services) async {
    FocusScope.of(context).unfocus();
    if (_failure != null) setState(() => _failure = null);

    final String? rescheduleId = widget.args.rescheduleBookingId;
    final String? rescheduleAppointmentId = widget.args.rescheduleAppointmentId;
    final WalkInGuest? guest = widget.args.guest;
    // Phase 262 D2 step 0 — the doc's own sample pairs this branch order with
    // a debug-only `assert(guest == null || rescheduleId == null)`. NOT
    // implemented here: it directly conflicts with this track's HARD
    // CONSTRAINT 3, which requires a passing acceptance test for exactly the
    // seed shape the assert would forbid — a walk-in-shaped arg that ALSO
    // carries a reschedule id, where reschedule must still win. An assert
    // there would throw (uncaught, outside the `try`/`on Failure` below)
    // before either reschedule branch could run, failing that required test.
    // The doc itself calls the assert "belt-and-braces" and names the
    // if/else-if STRUCTURE below as the real guarantee — that structural
    // guarantee is what this phase actually ships; see the phase doc's
    // Status section for this recorded deviation.
    try {
      if (rescheduleId != null) {
        // Captured BEFORE the write, from whatever `bookingDetailProvider
        // (rescheduleId)` already has cached — `startBookingReschedule`
        // (`reschedule_navigation.dart`) is this flow's ONLY entry point and
        // always awaits that exact provider to seed the picker, so by the
        // time this screen's CTA is reachable it is already resolved with
        // the booking's PRE-move `startAt`. `.value` (never the removed
        // Riverpod 2.x `valueOrNull` — see `auth_selectors.dart`) degrades to
        // `null` (never a stale/failed guess) if that assumption ever
        // breaks — see the invalidation block below for how a `null` old day
        // is handled.
        final DateTime? oldStartAt = ref
            .read(bookingDetailProvider(rescheduleId))
            .value
            ?.startAt;
        // Read the SAME session-backed `bookingViewerRoleProvider`
        // `reschedule_navigation.dart` reads (never `widget.args
        // .hideMasterIdentity` — that field is a PRESENTATION flag with a
        // second, role-unrelated producer: `walk_in_service_step_screen
        // .dart` hardcodes it `true` by flow construction, no role involved.
        // `bookingViewerRoleProvider`'s own doc argues against exactly a
        // caller-supplied widget parameter standing in for role — a
        // copy-pasted route registration would silently carry the wrong
        // flag through). Fails CLOSED onto the client branch for a
        // null/loading/unauthenticated session, same as every other reader
        // of this provider.
        final bool isProviderReschedule = ref
            .read(bookingViewerRoleProvider)
            .isProvider;
        try {
          if (rescheduleAppointmentId != null) {
            // Track 30.x — per-item VISIT reschedule, checked FIRST (both
            // fields are set together on this path — see the file header).
            // Moves ONLY this one service via the appointment-scoped
            // endpoint; siblings are untouched.
            await ref
                .read(appointmentSubmitProvider.notifier)
                .rescheduleAppointmentItem(
                  rescheduleAppointmentId,
                  rescheduleId,
                  widget.args.startAt,
                );
          } else {
            await ref
                .read(appointmentSubmitProvider.notifier)
                .reschedule(rescheduleId, widget.args.startAt);
          }
        } on ClientBookingConflictFailure catch (conflict) {
          // CLIENT-actor counterpart of the client-create catch below — SAME
          // shared dialog, SAME resubmit-with-override contract (backend
          // commit c1c2349 added `allowClientOverlap` to BOTH reschedule
          // endpoints, honoured ONLY for a CLIENT actor —
          // `BookingRepository.rescheduleBooking`'s doc). A PROVIDER
          // reschedule ignores the flag and still 409s regardless (a
          // provider cannot waive a client's overlap on their behalf), so
          // opening the dialog for one would only earn a second identical
          // 409 on "confirm" — rethrow instead and let the generic
          // `on Failure` clause below render the shared banner, unchanged
          // from before this wiring.
          if (isProviderReschedule) rethrow;
          if (!mounted) return;
          final bool proceed =
              await showClientBookingConflictDialog(
                context,
                ClientBookingConflictPreview(
                  newServiceNames: services.map((s) => s.name).join(', '),
                  newMasterName: '${master.firstName} ${master.lastName}'
                      .trim(),
                  newStart: widget.args.startAt,
                  newEnd: widget.args.startAt.add(
                    Duration(minutes: _totalDurationMinutes),
                  ),
                  conflict: conflict,
                ),
              ) ??
              false;
          if (!proceed) return;
          if (!mounted) return;
          if (rescheduleAppointmentId != null) {
            await ref
                .read(appointmentSubmitProvider.notifier)
                .rescheduleAppointmentItem(
                  rescheduleAppointmentId,
                  rescheduleId,
                  widget.args.startAt,
                  allowClientOverlap: true,
                );
          } else {
            await ref
                .read(appointmentSubmitProvider.notifier)
                .reschedule(
                  rescheduleId,
                  widget.args.startAt,
                  allowClientOverlap: true,
                );
          }
        }
        if (!mounted) return;
        // A successful RESCHEDULE moved an EXISTING booking (a plain one, or
        // ONE service of a visit — both share this exact invalidation set) —
        // refresh its detail page + the upcoming My Bookings list from the
        // widget layer (a `ref` outside a Notifier), mirroring the cancel
        // flow's post-write invalidation, so a cross-provider invalidate
        // never runs from inside a Notifier (the
        // `forbid_provider_self_invalidation` cycle footgun). Also refreshes
        // the Home Hub's own «Найближчий запис» card — a reschedule may move
        // this booking to/from being the client's soonest upcoming
        // appointment (Phase 225).
        ref.invalidate(bookingDetailProvider(rescheduleId));
        ref.invalidate(myBookingsProvider(BookingTab.upcoming));
        ref.invalidate(nextAppointmentProvider);
        if (rescheduleAppointmentId != null) {
          // Track 30.x per-item VISIT reschedule only — `_onReschedule`
          // forwards `appointmentId` for BOTH the client and provider
          // viewers, so a PROVIDER moving one service of their own visit
          // must also drop the master's own «Мої записи» day-calendar cache
          // for the affected date(s), or it keeps showing the item at its
          // OLD slot until the ≤3-day keepAlive LRU evicts (mobile-perf
          // CRITICAL). Scoped to the NEW day (`widget.args.startAt`) and, if
          // resolvable, the OLD day (`oldStartAt`, captured above BEFORE the
          // write) — a move across midnight changes both. Mirrors
          // `booking_calendar_invalidation.dart`'s per-date-scoped precedent,
          // NEVER the bare-family `ref.invalidate(bookingsDayProvider)` that
          // file's own header documents as a mobile-perf MEDIUM fix (2026-07-
          // 26): the whole family refetches every day currently cached —
          // including days this write never touched — defeating the bounded
          // 3-day keepAlive LRU's "settled revisit costs nothing" guarantee.
          // Invalidating a family MEMBER with no live listener is still a
          // documented no-op, so this is safe to run unconditionally even for
          // a CLIENT viewer who has no day-calendar screen at all.
          //
          // FIX A (mobile-debugger, this session) — a bare `ref.invalidate`
          // loop here used to be able to crash `bookings_discovery_view.dart`
          // ("Bad state: ProviderSubscription.read on a subscription that was
          // closed") or leave its skeleton stuck forever, whenever the
          // invalidated day was pinned-but-unwatched. See
          // `invalidateBookingsDayAfterAppointmentItemReschedule`'s doc in
          // `booking_calendar_invalidation.dart` for the full mechanism and
          // fix — extracted there (not left inline) so the exact same
          // invalidation this call site performs is independently testable
          // and reusable, mirroring that file's other "one fan-out point"
          // helpers.
          invalidateBookingsDayAfterAppointmentItemReschedule(
            ref,
            affectedDays: <DateTime>{
              dateOnly(toBeauticaTime(widget.args.startAt)),
              if (oldStartAt != null) dateOnly(toBeauticaTime(oldStartAt)),
            },
          );
        }
      } else if (guest != null) {
        // Phase 262 D2/D3 — the WALK-IN branch. An `else if` hanging off the
        // reschedule `if` above, so it is structurally impossible for this
        // branch to pre-empt either reschedule mode — the structural
        // guarantee itself (no runtime assert; see the deviation note above
        // [_submit]'s `try`). Reuses the SHIPPED `masterCreateBookingProvider`
        // notifier — never `bookingRepositoryProvider.createMasterBooking`
        // directly — so the write gets the same validation, the same
        // `invalidateBookingViewsAfterBookingCreated` fan-out (drops the
        // master's own `bookingsDayProvider` + `bookedDaysProvider`), and
        // stays shared with the SALON wizard that also consumes this
        // notifier (`salon_create_booking_screen.dart`).
        //
        // Phase 262 D5 (user-locked narrowing) — the screen-owned reentrancy
        // guard lives HERE, not at the top of [_submit], so it can never
        // affect the reschedule/client-create branches. Set synchronously
        // before the only `await` in this branch.
        if (_submitting.value) return;
        _submitting.value = true;
        final Appointment? created = await ref
            .read(masterCreateBookingProvider.notifier)
            .submit(
              masterId: widget.args.masterId,
              request: CreateMasterBookingRequest(
                masterServiceIds: <String>[
                  for (final MasterService s in services) s.id,
                ],
                startsAt: widget.args.startAt,
                guest: guest,
              ),
            );
        if (!mounted) return;
        final AsyncValue<void> result = ref.read(masterCreateBookingProvider);
        if (result.hasError) {
          // The notifier maps failures into its own AsyncError rather than
          // rethrowing (see `master_create_booking_notifier.dart`) — surface
          // it through the SAME `on Failure catch` this method already has
          // for the other three branches (phase-262 D6), so the shipped
          // `_SubmitErrorBanner` renders it with no new banner widget. The
          // 409 case (`MasterBookingDuplicateFailure`) renders the shipped
          // `errMasterBookingDuplicate` copy via `Failure.userMessage`.
          final Object error = result.error!;
          throw error is Failure ? error : UnknownFailure(cause: error);
        }
        if (created == null) {
          // Defensive/unreachable when `!hasError`: the notifier's own
          // `submit` returns `null` only on ITS OWN double-submit no-op or on
          // a mapped failure — both already excluded above given this
          // screen's own guard serialises calls into it. See
          // `master_create_booking_notifier.dart`'s doc.
          return;
        }
      } else {
        final String? comment = _comment.text.trim().isEmpty
            ? null
            : _comment.text.trim();
        final CreateAppointmentRequest request = CreateAppointmentRequest(
          masterId: widget.args.masterId,
          masterServiceIds: <String>[
            for (final MasterService s in services) s.id,
          ],
          startAt: widget.args.startAt,
          idempotencyKey: widget.args.idempotencyKey,
          clientComment: comment,
        );
        try {
          await ref
              .read(appointmentSubmitProvider.notifier)
              .submitVisit(request);
        } on ClientBookingConflictFailure catch (conflict) {
          // Client-create counterpart of `salon_booking_confirm_screen.dart`
          // `_submitOne`'s identical catch — SAME shared dialog, SAME
          // resubmit-with-override contract (product decision, that file's
          // header). On a `ClientBookingConflictFailure` specifically, open
          // [showClientBookingConflictDialog] instead of letting the failure
          // reach the `on Failure` clause below (which would render it as
          // the generic bottom `_SubmitErrorBanner` — the behaviour the user
          // asked to replace here). Confirming resubmits this SAME request
          // with `allowClientOverlap: true`; dismissing (or a `mounted`
          // guard tripping across the dialog's `await`) returns out of
          // `_submit` entirely — no banner, nothing further submitted, the
          // screen left exactly as it was so the client can back out and
          // change the time. Every OTHER failure (generic slot-conflict,
          // 404, network, rate-limit, …) is unaffected — it still throws out
          // of this `try` for the shared `on Failure` clause to render as
          // usual.
          if (!mounted) return;
          final bool proceed =
              await showClientBookingConflictDialog(
                context,
                ClientBookingConflictPreview(
                  newServiceNames: services.map((s) => s.name).join(', '),
                  newMasterName: '${master.firstName} ${master.lastName}'
                      .trim(),
                  newStart: widget.args.startAt,
                  newEnd: widget.args.startAt.add(
                    Duration(minutes: _totalDurationMinutes),
                  ),
                  conflict: conflict,
                ),
              ) ??
              false;
          if (!proceed) return;
          if (!mounted) return;
          await ref
              .read(appointmentSubmitProvider.notifier)
              .submitVisit(request.copyWith(allowClientOverlap: true));
        }
        if (!mounted) return;
        // A newly-created booking is auto-CONFIRMED → lands in the upcoming
        // tab. The client shell keeps the My Bookings branch mounted
        // (`StatefulShellRoute.indexedStack`), so its autoDispose notifier never
        // re-fetches on tab re-select — invalidate it here from the widget layer
        // (mirroring the reschedule branch above) so the new booking shows
        // without a manual pull-to-refresh. A cross-provider invalidate from a
        // Notifier would trip `forbid_provider_self_invalidation`; this is a
        // widget-layer `ref`, so it is compliant. Also refreshes the Home
        // Hub's own «Найближчий запис» card, which this new booking may now
        // be (Phase 225).
        ref.invalidate(myBookingsProvider(BookingTab.upcoming));
        ref.invalidate(nextAppointmentProvider);
      }
      context.pushReplacement(
        RouteNames.bookingSuccess,
        extra: BookingSuccessArgs(
          master: master,
          services: services,
          startAt: widget.args.startAt,
          isReschedule: rescheduleId != null,
          // «Додати в календар» removal (2026-08-21) — `guest != null` is the
          // CREATE-path walk-in signal; `widget.args.rescheduleTargetIsWalkIn`
          // is the RESCHEDULE-path counterpart (seeded in
          // `reschedule_navigation.dart` from `Booking.isGuestBooking`, the
          // SAME "no registered client" fact). The two are mutually exclusive
          // by construction (`guest` is always `null` on a reschedule seed —
          // no guest step exists there), so this OR never double-counts; it
          // just recovers the fact on whichever path actually has it. A CLIENT
          // reschedule or a PROVIDER reschedule of a real client's booking
          // both keep `rescheduleTargetIsWalkIn == false`, so `isWalkIn` stays
          // `false` there exactly as before.
          isWalkIn: guest != null || widget.args.rescheduleTargetIsWalkIn,
          // FIX 1 (audit-fix cycle 2) — mirrors `guest` already threaded onto
          // `BookingConfirmArgs`, so the terminal done screen can restore the
          // retired wizard's guest-identity card. `null` on the reschedule/
          // client-create branches, same as `guest` itself.
          guest: guest,
          // CLIENT IDENTITY PARITY (2026-08-22) — the reschedule-path
          // counterpart of `guest`, forwarded unchanged from
          // `BookingConfirmArgs.rescheduleClientName`/`rescheduleClientPhone`
          // so the terminal done screen can render the same
          // `GuestIdentityCard.identity` this screen renders below. `null` on
          // every non-reschedule-provider path, same as those args fields.
          rescheduleClientName: widget.args.rescheduleClientName,
          rescheduleClientPhone: widget.args.rescheduleClientPhone,
        ),
      );
    } on Failure catch (failure) {
      if (!mounted) return;
      // Phase 262 D5 (user-locked narrowing) — clears unconditionally, but
      // this is a no-op for the reschedule/client-create branches: they
      // never set [_submitting] true in the first place, so this is exactly
      // as inert for them as it was before this phase.
      _submitting.value = false;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<PublicMasterProfileData> asyncData = ref.watch(
      publicMasterProfileProvider(widget.args.masterId),
    );
    // Phase 262 D4 — the union of both submit notifiers. On the client and
    // reschedule paths `masterCreateBookingProvider` is never submitted to,
    // so its `isLoading` stays `false` and this is byte-identical to before
    // this phase (pinned by the `confirm-loading` golden cell).
    final bool inFlight =
        ref.watch(
          appointmentSubmitProvider.select((AsyncValue<void> s) => s.isLoading),
        ) ||
        ref.watch(
          masterCreateBookingProvider.select(
            (AsyncValue<void> s) => s.isLoading,
          ),
        );

    // Resolve the master out of the cached profile. The ordered services come
    // straight from the args (already resolved during the selection step); the
    // catalogue read only supplies the master identity + address.
    final Master? master = asyncData.value?.$1;
    final bool ready = master != null;

    // Precedence is loading > reschedule > walk-in > client create — the
    // walk-in arm is checked LAST so neither the loading nor the reschedule
    // label can be pre-empted (phase-261 D6). This is the one place in this
    // screen that reads `guest` rather than `hideMasterIdentity`: it is about
    // what the button DOES, not about identity rendering.
    final String ctaLabel = inFlight
        ? l10n.bookingSubmitCtaLoading
        : _isReschedule
        ? l10n.bookingRescheduleSubmitCta
        : widget.args.guest != null
        ? l10n.masterCreateBookingSubmitCta
        : l10n.bookingSubmitCta;

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: ready
          ? ValueListenableBuilder<bool>(
              // Phase 262 D5 (user-locked narrowing) — scoped ONLY to the
              // walk-in branch's own submitting window; `_submitting` never
              // flips true on the reschedule/client-create branches, so this
              // builder rebuilds on those paths for exactly the same
              // `inFlight` changes it always did, rendering the SAME
              // `BookingCtaFooter` it built before this phase (golden-safe:
              // the footer widget is never re-parented).
              //
              // AUDIT-FIX CYCLE 2 (FIX 4) — this wrapper is NOT here to
              // narrow rebuild blast radius (unlike the retired wizard's
              // `_stagedDate`/`_submitting`, which genuinely did: see
              // `_submitting`'s own doc above for why that framing does not
              // apply here — `inFlight` and `_submitting.value` both flip in
              // the same tap-handler stack turn, so the outer `build()`
              // (which already watches `masterCreateBookingProvider.select
              // (isLoading)`) reruns on the SAME frame regardless of this
              // builder). It exists only so [_submitting]'s reentrancy-guard
              // value can reach `BookingCtaFooter.loading` without a
              // `setState` call on this screen's `State`.
              valueListenable: _submitting,
              builder: (BuildContext context, bool submitting, Widget? _) =>
                  BookingCtaFooter(
                    key: const Key('booking-confirm-cta-footer'),
                    buttonKey: const Key('booking-confirm-submit-cta'),
                    label: ctaLabel,
                    enabled: true,
                    loading: inFlight || submitting,
                    onPressed: () => _submit(master, widget.args.services),
                  ),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            BookingTopBar(
              title: l10n.bookingConfirmScreenTitle,
              backSemantics: l10n.bookingConfirmBackSemantics,
              onBack: () => context.pop(),
              backKey: const Key('booking-confirm-back'),
            ),
            Expanded(
              child: asyncData.when(
                loading: () => const _LoadingBody(),
                error: (Object e, StackTrace _) => ErrorState(
                  key: const Key('booking-confirm-error-state'),
                  failure: e is Failure ? e : UnknownFailure(cause: e),
                  onRetry: () => ref.invalidate(
                    publicMasterProfileProvider(widget.args.masterId),
                  ),
                ),
                data: (PublicMasterProfileData _) {
                  if (!ready) return const SizedBox.shrink();
                  return _ConfirmBody(
                    master: master,
                    selections: _selections,
                    startAt: widget.args.startAt,
                    totalDurationMinutes: _totalDurationMinutes,
                    comment: _comment,
                    maxComment: _maxComment,
                    // FIX 1 (audit-fix cycle 3) — the walk-in guest identity,
                    // `null` on every client/reschedule call site (they never
                    // set `BookingConfirmArgs.guest`), so this is a purely
                    // additive read.
                    guest: widget.args.guest,
                    // CLIENT IDENTITY PARITY (2026-08-22) — the reschedule
                    // counterpart of `guest` just above; `null` on every
                    // call site except a PROVIDER rescheduling a booking
                    // with a registered client (see
                    // `reschedule_navigation.dart`).
                    rescheduleClientName: widget.args.rescheduleClientName,
                    rescheduleClientPhone: widget.args.rescheduleClientPhone,
                    // The reschedule endpoint takes only the new start — a
                    // note-to-master input would be silently ignored, so it is
                    // hidden on the reschedule path. Also hidden on the
                    // walk-in path (phase-261 D5): `clientComment` is a note
                    // FROM the client TO the provider, and on a walk-in the
                    // provider is the author with no client account — there
                    // is nowhere for the value to go
                    // (`CreateMasterBookingRequest` has no comment field).
                    showComment:
                        !_isReschedule && !widget.args.hideMasterIdentity,
                    failure: _failure,
                    hideMasterIdentity: widget.args.hideMasterIdentity,
                    // Phase 262 D6 — only the walk-in branch gets a
                    // recoverable refresh action on a duplicate-409; `null`
                    // on every other path renders `_SubmitErrorBanner`
                    // exactly as before this phase. The wizard's equivalent
                    // action returned to `dateTime`; on the routed chain
                    // that is popping back to `SlotTimeScreen`, whose slots
                    // refetch on re-entry.
                    onDuplicateRefresh: widget.args.guest != null
                        ? () => context.pop()
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.master,
    required this.selections,
    required this.startAt,
    required this.totalDurationMinutes,
    required this.comment,
    required this.maxComment,
    required this.showComment,
    required this.failure,
    this.hideMasterIdentity = false,
    this.onDuplicateRefresh,
    this.guest,
    this.rescheduleClientName,
    this.rescheduleClientPhone,
  });

  final Master master;
  final List<BookingSelection> selections;
  final DateTime startAt;
  final int totalDurationMinutes;
  final TextEditingController comment;
  final int maxComment;

  /// Whether the optional «Коментар для майстра» field is shown — false on the
  /// reschedule path (the reschedule endpoint has no comment channel).
  final bool showComment;

  /// The last submit failure, or `null` — drives the single inline error
  /// banner pinned at the end of the scroll body (directly above the CTA).
  final Failure? failure;

  /// `true` when the viewer IS the master being booked (the walk-in path) —
  /// hides the master identity card, its `Hero`, and the address block.
  /// Defaults to `false` so every client/reschedule call site (which passes
  /// none of this) renders identically. See phase-261.
  final bool hideMasterIdentity;

  /// Phase 262 D6 — non-null ONLY on the walk-in path, and only meaningful
  /// for a `MasterBookingDuplicateFailure`: shows the shipped «Оновити»
  /// action beside the error banner, popping back to `SlotTimeScreen` so its
  /// slots refetch on re-entry. `null` on every other call site — the
  /// banner renders exactly as it did before this phase.
  final VoidCallback? onDuplicateRefresh;

  /// FIX 1 (audit-fix cycle 3, 2026-08-21) — the walk-in guest identity to
  /// echo back on this last-review screen, mirroring the terminal success
  /// screen's own restored guest card (audit-fix cycle 2). `null` on every
  /// client/reschedule call site (`BookingConfirmArgs.guest` is `null`
  /// there), so those paths render byte-identically — the card is gated on
  /// this field being non-null, never on [hideMasterIdentity] alone, so a
  /// hypothetical future `hideMasterIdentity: true` seed with no guest still
  /// renders no card rather than a null-check crash.
  final WalkInGuest? guest;

  /// CLIENT IDENTITY PARITY (2026-08-22) — the RESCHEDULE-path counterpart of
  /// [guest]: forwarded from `BookingConfirmArgs.rescheduleClientName`/
  /// `rescheduleClientPhone`, populated ONLY when a PROVIDER is rescheduling
  /// a booking with a registered client (see `reschedule_navigation.dart`).
  /// `null` on every other call site, so those paths render byte-identically.
  final String? rescheduleClientName;
  final String? rescheduleClientPhone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? addressLine = formatStreetCityLine(
      street: master.street,
      buildingNo: master.buildingNo,
      city: master.city,
    );
    final String? addressDetail =
        (master.locationNote?.trim().isNotEmpty ?? false)
        ? master.locationNote!.trim()
        : null;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // FIX 1 (audit-fix cycle 3, 2026-08-21) — the walk-in guest
          // identity, occupying the visual slot the hidden master card would
          // otherwise take. REUSE-FIRST: the SAME `GuestIdentityCard` the
          // terminal success screen renders (promoted from that screen's own
          // inline card — see that widget's file header) — no second
          // hand-copied implementation. `null` on every client/reschedule
          // call site, so those paths render byte-identically (no extra
          // card, no extra gap).
          if (guest != null) ...<Widget>[
            GuestIdentityCard(
              key: const Key('booking-confirm-guest-card'),
              guest: guest!,
            ),
            const SizedBox(height: VelvetSpacing.md),
          ] else if (rescheduleClientName != null) ...<Widget>[
            // CLIENT IDENTITY PARITY (2026-08-22) — the RESCHEDULE-path
            // counterpart of the walk-in card just above: a PROVIDER
            // rescheduling a booking with a registered client sees the SAME
            // `GuestIdentityCard` (via `.identity`) in the same visual slot,
            // rather than an empty gap where the hidden master card would
            // otherwise sit. `null` on every client-viewer reschedule and
            // every create path, so those render byte-identically.
            GuestIdentityCard.identity(
              key: const Key('booking-confirm-client-card'),
              name: rescheduleClientName!,
              phone: rescheduleClientPhone,
              label: l10n.bookingClientLabel,
            ),
            const SizedBox(height: VelvetSpacing.md),
          ],
          // ONE visit recap: the master identity card, the shared address, the
          // single visit window (start → start + summed duration), the ordered
          // service list and the «Разом» total — all in one card stack.
          BookingSummaryCards(
            key: const Key('booking-confirm-visit-card'),
            // FIX 2 (mobile-perf LOW, audit-fix cycle 2) — the `Hero` is now
            // short-circuited INLINE, so a walk-in build never constructs it
            // just to discard it a line later. Genuinely mirrors
            // `slot_picker_screen.dart:296`/`:678`'s collection-`if` guard
            // now (this call site takes a single `masterCard:` Widget?
            // param, not a widget list, so the equivalent form here is a
            // ternary rather than `if ... ...[]`) — for `hideMasterIdentity
            // == false` this produces the exact same `Hero` tree as before,
            // so the client-path render is unchanged (goldens are the
            // proof).
            masterCard: hideMasterIdentity
                ? null
                : Hero(
                    tag: 'master-strip-${master.id}',
                    child: MasterStrip.fromMaster(
                      master,
                      showRole: true,
                      showRating: true,
                      // TAPPABLE per the policy on `MasterStrip.onTap`: this
                      // is the last step, everything is already chosen, and
                      // checking the master's reviews before committing is
                      // exactly the doubt a client has here. `push` returns
                      // to this screen with the selections and the typed
                      // comment intact.
                      onTap: () => context.push(
                        RouteNames.masterPublicReviews(master.id),
                      ),
                    ),
                  ),
            showAddress: !hideMasterIdentity,
            addressLine: addressLine,
            addressDetail: addressDetail,
            dateLabel: formatFullDate(startAt),
            timeLabel: formatTimeRange(startAt, totalDurationMinutes),
            selections: selections,
          ),
          if (showComment) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            BookingCommentField(
              controller: comment,
              fieldKey: const Key('booking-confirm-comment-field'),
              maxLength: maxComment,
            ),
          ],
          if (failure != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            _SubmitErrorBanner(
              failure: failure!,
              onRefresh: onDuplicateRefresh,
            ),
          ],
        ],
      ),
    );
  }
}

/// The single inline error banner shown when a submit fails — an error-tone
/// icon + the failure's localized message in a bordered neumorphic card, pinned
/// at the end of the scroll body so it reads directly above the pinned CTA.
class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({required this.failure, this.onRefresh});

  final Failure failure;

  /// Phase 262 D6 — non-null only on the walk-in path. Shows an «Оновити»
  /// action UNDER the message when both this is non-null AND [failure] is a
  /// `MasterBookingDuplicateFailure` (the shipped 409 copy). `null` on the
  /// client/reschedule paths, where this whole widget renders exactly the
  /// single `Row` it always has.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final Widget message = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: BrandColors.error,
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        Expanded(
          child: Text(
            failure.userMessage(context),
            style: VelvetText.feedback(BrandColors.error),
          ),
        ),
      ],
    );

    final bool showRefresh =
        onRefresh != null && failure is MasterBookingDuplicateFailure;

    return NeumorphicCard(
      key: const Key('booking-confirm-submit-error'),
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
      child: showRefresh
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                message,
                const SizedBox(height: VelvetSpacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('booking-confirm-duplicate-refresh'),
                    onPressed: onRefresh,
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).masterCreateBookingDuplicateRefreshAction,
                    ),
                  ),
                ),
              ],
            )
          : message,
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.lg,
        ),
        children: const <Widget>[
          SkeletonBlock(
            width: double.infinity,
            height: 96,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 220,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}
