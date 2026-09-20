// BookingSuccessScreen: the independent-master booking flow's post-submit
// celebration, shown after the single `POST /appointments` succeeds.
//
// MO-3 (single-visit rework): the flow now books the whole selection as ONE
// visit with ONE start time (services run back-to-back), so the recap is a
// SINGLE card — the shared master identity + address, the ordered service list
// under ONE visit window (`startAt` → `startAt + summed duration`), and the
// «Разом» total — with ONE «Додати в календар» pill that exports the whole
// arrival as a single OS calendar event (not one card/event per service, which
// the pre-MO-3 N-appointment recap needed).
//
// Reached ONLY via `BookingConfirmScreen`'s `pushReplacement` once the visit was
// created (a failed submit keeps the client on the confirm screen). The
// scaffold's `PopScope(canPop: false)` blocks back — the pinned «На головну» is
// the only way forward.
//
// SEC: the recap renders the INDEPENDENT master's address (street/buildingNo/
// city/locationNote — a solo master's may be a HOME address), so this screen
// acquires the app-wide screenshot guard in `initState`. Do not remove in a
// future audit pass. The 2026-09-18 `venue*` override (see `_addressLine`) only
// ever REPLACES that line with the booking's own resolved address, so the guard
// covers the same class of data either way.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../domain/booking_success_args.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/calendar_button.dart';
import 'widgets/guest_identity_card.dart';

/// Booking flow — the post-submit celebration screen (one confirmed visit).
class BookingSuccessScreen extends ConsumerStatefulWidget {
  const BookingSuccessScreen({super.key, required this.args});

  final BookingSuccessArgs args;

  @override
  ConsumerState<BookingSuccessScreen> createState() =>
      _BookingSuccessScreenState();
}

class _BookingSuccessScreenState extends ConsumerState<BookingSuccessScreen> {
  late final ScreenProtectionManager _screenProtection;

  /// Re-entry guard for the OS calendar INSERT intent. On Android
  /// `Add2Calendar.addEvent2Cal` resolves as soon as `startActivity` returns
  /// (not when the sheet is dismissed), so a same-gesture double-tap could fire
  /// two INSERT intents; this drops the second until the first resolves.
  /// Deliberately NOT `setState`-driven — nothing on screen is painted from it.
  bool _calendarInFlight = false;

  // `widget.args` never changes for this screen's lifetime, so the visit's
  // selections + summed duration are computed once.
  late final List<BookingSelection> _selections = widget.args.services
      .map(
        (MasterService s) => BookingSelection(
          name: s.name,
          price: ServicePriceDisplay.format(s),
          duration: DurationMinutes.format(s.durationMinutes),
          durationMinutes: s.durationMinutes,
          priceMin: s.priceMin,
          priceMax: s.priceMax,
        ),
      )
      .toList();

  late final int _totalDurationMinutes = widget.args.services.fold<int>(
    0,
    (int sum, MasterService s) => sum + s.durationMinutes,
  );

  /// VENUE ADDRESS (2026-09-18) — the visit's address, resolved ONCE for BOTH
  /// the recap card and the OS-calendar event's `location` (the two used to
  /// compose it separately from the same broken source and could drift).
  ///
  /// PREFERS the `venue*` fields — the address the backend already resolved
  /// salon-vs-independent on the `Booking`
  /// (`BookingDetailResponse.java:580-648`), threaded in by
  /// `reschedule_navigation.dart`. FALLS BACK to [Master], whose USER-level
  /// street/buildingNo/city the backend DELIBERATELY nulls for a
  /// `SALON_MASTER`/`SALON_OWNER` (`MasterDetailResponse.java:104-127`) — the
  /// reason a salon reschedule used to render «Адресу не вказано».
  ///
  /// Every CREATE call site passes no `venue*` field, so the first compose
  /// returns `null` and this is byte-identical to the pre-existing
  /// master-only line for them.
  late final String? _addressLine =
      formatStreetCityLine(
        street: widget.args.venueStreet,
        buildingNo: widget.args.venueBuildingNo,
        city: widget.args.venueCity,
      ) ??
      formatStreetCityLine(
        street: widget.args.master.street,
        buildingNo: widget.args.master.buildingNo,
        city: widget.args.master.city,
      );

  /// The arrival hint, same venue-first precedence as [_addressLine]. Never
  /// part of the composed line (see `composeAddressLine`'s doc) — rendered as
  /// the recap's separate detail row.
  late final String? _addressDetail =
      _trimmedOrNull(widget.args.venueLocationNote) ??
      _trimmedOrNull(widget.args.master.locationNote);

  static String? _trimmedOrNull(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed?.isNotEmpty ?? false) ? trimmed : null;
  }

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final DateTime startAt = widget.args.startAt;

    // Phase 263 D1 — three-way copy switch. Precedence is reschedule > walk-in
    // > client create, matched in that ORDER.
    //
    // Originally `isReschedule` and `isWalkIn` were mutually exclusive by
    // construction (`BookingConfirmScreen._submit` sets `isReschedule:
    // rescheduleId != null` and `isWalkIn: guest != null`, and its reschedule
    // `if` is checked BEFORE its walk-in `else if`, so a seed could never
    // reach that branch with both set — see phase-262's recorded deviation).
    // «Додати в календар» removal (2026-08-21) broke that exclusivity on
    // PURPOSE: `isWalkIn` now ALSO folds in `widget.args
    // .rescheduleTargetIsWalkIn` (a master rescheduling an existing WALK-IN
    // booking), so both flags CAN be `true` together. This switch's explicit
    // `isReschedule` arm — checked first — is what keeps that combination
    // showing reschedule copy; ordering is now load-bearing, not merely
    // structural. [doneLabel]/`onPressed` below were widened the same way
    // for the same reason.
    final (String title, String subline) = switch (widget.args) {
      BookingSuccessArgs(isReschedule: true) => (
        l10n.bookingRescheduleSuccessTitle,
        l10n.bookingRescheduleSuccessSubline,
      ),
      BookingSuccessArgs(isWalkIn: true) => (
        l10n.bookingSuccessTitle,
        l10n.masterCreateBookingDoneSubline,
      ),
      _ => (l10n.bookingSuccessTitle, l10n.bookingSuccessSubline),
    };

    // Phase 263 D4 — same three-way precedence, walk-in arm after the
    // reschedule arm. Reschedule and client-create both keep the existing
    // «На головну» label — only the walk-in arm differs. Reuses the shipped
    // `masterCreateBookingDoneCta` («Готово») — no new ARB key.
    //
    // «Додати в календар» removal (2026-08-21) — the `isReschedule` arm is now
    // load-bearing, not merely documented: a walk-in RESCHEDULE seeds BOTH
    // `isReschedule: true` AND `isWalkIn: true` (see `BookingConfirmScreen
    // ._submit`), so without an explicit reschedule arm here this switch would
    // fall into the walk-in arm and swap the CTA label — a change this fix
    // does not intend. Checking `isReschedule` FIRST keeps every reschedule
    // (walk-in-target or not) on the ordinary «На головну» label, matching the
    // title/subline switch above.
    final String doneLabel = switch (widget.args) {
      BookingSuccessArgs(isReschedule: true) => l10n.bookingSuccessHomeCta,
      BookingSuccessArgs(isWalkIn: true) => l10n.masterCreateBookingDoneCta,
      _ => l10n.bookingSuccessHomeCta,
    };

    return BookingSuccessScaffold(
      title: title,
      subline: subline,
      actions: <Widget>[
        SuccessSecondaryButton(
          buttonKey: const Key('booking-success-home-cta'),
          label: doneLabel,
          icon: Icons.home_outlined,
          // Phase 27.2 follow-up — this screen is now also reached by an
          // INDEPENDENT_MASTER that just RESCHEDULED its own booking, so a
          // hard-coded `clientHome` would strand a provider in the CLIENT
          // shell. Resolve the landing from the session through the shared
          // `roleHomePath` dispatch, same shape as `done_screen.dart`.
          //
          // Phase 263 D3 — an early return ABOVE the existing block, for the
          // walk-in path only: returns the master to their own «Мої записи»
          // calendar (the wizard's retired done CTA did the same), rather
          // than `roleHomePath`'s generic landing surface. The lines below
          // are untouched.
          //
          // «Додати в календар» removal (2026-08-21) — `!widget.args
          // .isReschedule` guards this early return too, for the same reason
          // as [doneLabel] above: a walk-in RESCHEDULE now sets `isWalkIn:
          // true` alongside `isReschedule: true`, and that combination must
          // keep landing on `roleHomePath` like every other reschedule, not
          // divert to «Мої записи». Every PRE-EXISTING call site had
          // `isReschedule` and `isWalkIn` mutually exclusive, so
          // `!isReschedule && isWalkIn` is byte-identical to the old bare
          // `isWalkIn` check for all of them — only the new co-occurring case
          // changes, and only in the intended direction.
          onPressed: () {
            if (!widget.args.isReschedule && widget.args.isWalkIn) {
              context.go(RouteNames.masterBookings);
              return;
            }
            final session = ref.read(authProvider).value;
            context.go(
              session is Authenticated
                  ? roleHomePath(session.user.role)
                  : RouteNames.clientHome,
            );
          },
        ),
      ],
      recapCards: <Widget>[
        // FIX 1 (audit-fix cycle 2, 2026-08-21) — WHO: the walk-in guest
        // identity card, restored from the retired wizard's `_DoneStep`
        // (`git show HEAD:.../master_create_booking_screen.dart`), which this
        // screen's port dropped. Gated on `isWalkIn && guest != null` (not
        // `isWalkIn` alone) so a walk-in seed that somehow omits the guest
        // degrades to "no card" rather than a null-check crash, and so the
        // CLIENT path (`guest` always `null`) is unaffected either way. SEC:
        // the guest's name+phone here was raised as a security MEDIUM and
        // DISMISSED BY USER DECISION 2026-08-20
        // (`docs/mobile-phases/mobile-backlog.md`) — this screen already
        // acquires `ScreenProtectionManager` above.
        //
        // AUDIT-FIX CYCLE 3 (FIX 1) — PROMOTED to `GuestIdentityCard`
        // (`widgets/guest_identity_card.dart`): `BookingConfirmScreen` needed
        // the identical card and REUSE-FIRST forbids a second hand-copied
        // `NeumorphicCard`+`LabelledRow` block. Byte-identical render (same
        // key, same padding, same `LabelledRow` args) — proven by this
        // screen's own goldens/widget tests, unmodified by the extraction.
        if (widget.args.isWalkIn && widget.args.guest != null)
          GuestIdentityCard(
            key: const Key('booking-success-guest-card'),
            guest: widget.args.guest!,
          ),
        // CLIENT IDENTITY PARITY (2026-08-22) — the RESCHEDULE-path
        // counterpart of the walk-in guest card just above: a PROVIDER
        // rescheduling a booking with a registered client sees the SAME
        // `GuestIdentityCard` (via `.identity`) on the terminal done screen,
        // rather than an empty gap. `rescheduleClientName` is `null` on
        // every CREATE path and on a CLIENT's own reschedule (see
        // `BookingSuccessArgs.rescheduleClientName`'s doc), so those paths
        // render byte-identically.
        if (widget.args.rescheduleClientName != null)
          GuestIdentityCard.identity(
            key: const Key('booking-success-client-card'),
            name: widget.args.rescheduleClientName!,
            phone: widget.args.rescheduleClientPhone,
            label: l10n.bookingClientLabel,
          ),
        // ONE visit recap: the shared address, the single window, the ordered
        // service list + «Разом» total, with the whole-visit calendar export as
        // the card's trailing action. No master card — the celebration badge +
        // title already establish "you're booked", matching the pre-MO-3
        // success recap (which likewise omitted the identity card).
        BookingSummaryCards(
          key: const Key('booking-success-visit-card'),
          showBorder: true,
          compactText: true,
          dense: true,
          addressLine: _addressLine,
          addressDetail: _addressDetail,
          dateLabel: formatFullDate(startAt),
          timeLabel: formatTimeRange(startAt, _totalDurationMinutes),
          selections: _selections,
          // AUDIT-FIX CYCLE 3 (FIX 2) — no OS-calendar export on the walk-in
          // path: the master is standing at the chair with the client right
          // there, so "add to MY calendar" doesn't apply the way it does for
          // a client booking their own future visit. `null` (not an empty
          // widget) so `BookingSummaryCards` renders no trailing rule/action
          // block at all, exactly as the pre-existing salon/detail call sites
          // that also pass no `trailingAction` do. The CLIENT path
          // (`isWalkIn` always `false`) is UNCHANGED — this ternary's other
          // arm is byte-for-byte the pre-existing unconditional call.
          //
          // PROVIDER-VIEWER GATE (2026-09-18) — `isProviderViewer` widens the
          // same suppression to a salon owner / salon admin / master who just
          // rescheduled a REGISTERED client's booking. That path keeps
          // `clientId != null` → `isGuestBooking == false` →
          // `rescheduleTargetIsWalkIn == false` → `isWalkIn == false`, so the
          // pre-existing walk-in arm never caught it and the button rendered
          // for a provider who has no use for someone else's visit in their
          // own OS calendar. Deliberately NOT `isReschedule`: a CLIENT
          // rescheduling their OWN booking must KEEP the button (locked
          // product decision). `isProviderViewer` defaults to `false` and is
          // seeded ONLY from `BookingConfirmArgs.hideMasterIdentity`, so every
          // create path and every client path renders exactly as before.
          trailingAction: (widget.args.isProviderViewer || widget.args.isWalkIn)
              ? null
              : CalendarButton(
                  buttonKey: const Key('booking-success-add-calendar'),
                  semanticsLabel: l10n.bookingAddCalendarSemantics,
                  onTap: () => _onAddToCalendar(context),
                ),
        ),
      ],
    );
  }

  /// Opens the OS calendar's "new event" sheet for the WHOLE visit — one event
  /// spanning `startAt` → `startAt + summed duration`, since the services are a
  /// single back-to-back arrival. Guarded by [_calendarInFlight] against a
  /// double-tap stacking two platform activities.
  Future<void> _onAddToCalendar(BuildContext context) async {
    if (_calendarInFlight) return;
    _calendarInFlight = true;
    try {
      final l10n = AppLocalizations.of(context);
      final master = widget.args.master;
      final DateTime startAt = widget.args.startAt;
      final DateTime end = startAt.add(
        Duration(minutes: _totalDurationMinutes),
      );

      // VENUE ADDRESS (2026-09-18) — the SAME resolved line the recap card
      // renders, not a second master-only compose (which rendered an empty
      // location for a salon booking). See [_addressLine].
      final String? location = _addressLine;
      final String provider = '${master.firstName} ${master.lastName}'.trim();
      final String serviceLabel = widget.args.services
          .map((MasterService s) => s.name)
          .join(', ');
      final String priceLabel = formatBookingTotalsFromTerms(
        widget.args.services.map(
          (MasterService s) => (
            min: s.priceMin,
            max: s.priceType == ServicePriceType.range
                ? (s.priceMax ?? s.priceMin)
                : s.priceMin,
            minutes: s.durationMinutes,
          ),
        ),
      ).priceLabel;

      // Structured facts only — NO free-text note fields reach the calendar. A
      // just-submitted visit is auto-approved CONFIRMED (see domain rules).
      final String? description = buildCalendarDescription(
        l10n: l10n,
        service: serviceLabel,
        provider: provider,
        providerRole: CalendarProviderRole.master,
        dateTime:
            '${formatFullDate(startAt)}, '
            '${formatTimeRange(startAt, _totalDurationMinutes)}',
        address: location,
        price: priceLabel,
        status: l10n.bookingStatusConfirmed,
      );

      await addBookingToCalendar(
        context: context,
        title: l10n.bookingCalendarEventTitle(serviceLabel, provider),
        location: location,
        start: startAt,
        end: end,
        description: description,
      );
    } finally {
      _calendarInFlight = false;
    }
  }
}
