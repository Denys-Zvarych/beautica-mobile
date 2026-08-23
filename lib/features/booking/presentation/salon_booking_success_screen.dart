// Phase 14.18 — SalonBookingSuccessScreen: salon booking flow step 4b, the
// post-submit celebration. Mirrors the independent-master
// `BookingSuccessScreen` (`booking_success_screen.dart`) — animated success
// badge → "Записано!" headline → reassuring subline → the booking recap →
// a single pinned "На головну" — extended to LIST every created appointment
// via the SAME generalized `BookingSummaryCards` the independent success
// screen uses (`BookingSummaryCards.fromSchedule` — see that widget's file
// header), one per master, plus a shared salon-address card.
//
// The shared celebration structure lives in
// `widgets/booking_success_scaffold.dart` (composed by both success screens);
// this screen just supplies its copy and its recap cards.
//
// PAGER REWORK (owner decision, 2026-08-23): the flat stack of N
// per-appointment recap cards is now an [AppointmentPager]
// (`widgets/appointment_pager.dart`) — one master's card on screen at a
// time, via [BookingSuccessScaffold.pagedRecap] (an additive scaffold slot
// added for this screen; the independent success screen and «Деталі
// запису» both leave it null and render byte-identically to before). The
// visit-wide grand total («Разом за візит») is REMOVED — each master's own
// «Разом» subtotal is the only total on this screen now. The shared
// salon-address card stays OUTSIDE the pager, in [BookingSuccessScaffold
// .recapCards] (non-paged, same staggered reveal as before) — it is
// identical for every appointment (all N masters work at the SAME salon).
//
// «Додати в календар» (owner decision, 2026-08-23): ONE [CalendarButton] per
// BOOKING (1 service = 1 booking — a master with 2 services gets 2 buttons),
// reusing the SAME shared widget the independent success screen's
// `trailingAction` uses. `BookingSummaryCards.fromSchedule` has no
// `trailingAction` passthrough and this port deliberately does not add one
// for a single caller (see `_SalonCalendarActionsCard`'s own doc) — the
// buttons render in a second, small card directly below each master's
// summary card instead, inside that master's own pager page.
//
// Reached ONLY via `SalonBookingConfirmScreen`'s `pushReplacement` once EVERY
// appointment's `POST /bookings` succeeded (partial failures keep the client
// on the confirm screen), so the recap here is always the full, confirmed
// set. The scaffold's `PopScope(canPop: false)` blocks back like the
// independent success screen — the pinned "На головну" is the only way
// forward.
//
// The salon's ADDRESS is a secondary read via
// `publicSalonProfileProvider(salonId)` — see `salon_booking_confirm_screen
// .dart`'s file header DATA SOURCE note for the full rationale (5-minute
// keepAlive cache, never blocks/errors this screen).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/calendar/add_to_calendar.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../domain/salon_booking_confirm_args.dart';
import 'widgets/appointment_pager.dart';
import 'widgets/booking_recap.dart' show parseDurationMinutes;
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/calendar_button.dart';
import 'widgets/labelled_row.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/section_rule.dart';

/// Salon booking flow step 4b — the confirmed N-appointment recap.
///
/// `ConsumerStatefulWidget` (rather than the original `ConsumerWidget`) so it
/// can acquire the app-wide [ScreenProtectionManager] for its lifetime — see
/// [_SalonBookingSuccessScreenState.initState]. This mirrors the ONLY
/// acquire-idiom this codebase has for that manager (every other PII screen —
/// `PublicSalonProfileScreen`, `SalonBookingConfirmScreen`, etc. — is also a
/// `ConsumerStatefulWidget` acquiring in `initState`/releasing in `dispose`).
class SalonBookingSuccessScreen extends ConsumerStatefulWidget {
  const SalonBookingSuccessScreen({super.key, required this.args});

  final SalonBookingSuccessArgs args;

  @override
  ConsumerState<SalonBookingSuccessScreen> createState() =>
      _SalonBookingSuccessScreenState();
}

class _SalonBookingSuccessScreenState
    extends ConsumerState<SalonBookingSuccessScreen> {
  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  /// Re-entry guard for the OS calendar INSERT intent — same rationale as
  /// `booking_success_screen.dart`'s `_calendarInFlight` (on Android,
  /// `Add2Calendar.addEvent2Cal` resolves as soon as `startActivity`
  /// returns, not when the sheet is dismissed, so a same-gesture double-tap
  /// could stack two platform activities). Keyed per BOOKING
  /// (`<appointmentIndex>-<serviceIndex>`) rather than a single bool, since
  /// this screen can show several buttons at once — a tap on one button must
  /// never block a DIFFERENT booking's button.
  final Set<String> _calendarInFlight = <String>{};

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders the salon's address (PII: street/buildingNo/
    // city + free-text locationNote) — guard against screenshots /
    // app-switcher snapshots while it is mounted. Mirrors the INTENTIONAL
    // PRODUCT DECISION on `PublicSalonProfileScreen` — do not remove in a
    // future audit pass.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  /// Opens the OS calendar's "new event" sheet for ONE booking (one master's
  /// one SERVICE within the appointment) — never the whole appointment, per
  /// the 1-service-1-booking rule (see the file header). [serviceStart]/
  /// [serviceEnd] are that service's own chained window, computed by
  /// [_SalonCalendarActionsCard].
  Future<void> _addToCalendar({
    required BuildContext context,
    required String guardKey,
    required SalonBookingAppointment appointment,
    required SalonCatalogService service,
    required DateTime serviceStart,
    required DateTime serviceEnd,
    required String? salonAddressLine,
    required String? salonNameResolved,
  }) async {
    if (_calendarInFlight.contains(guardKey)) return;
    _calendarInFlight.add(guardKey);
    try {
      final l10n = AppLocalizations.of(context);
      final String masterName =
          '${appointment.schedule.firstName} ${appointment.schedule.lastName}'
              .trim();
      // A salon booking names the SALON; falls back to the master when the
      // secondary salon-profile read hasn't resolved yet — mirrors
      // `booking_detail_screen.dart`'s `_onAddToCalendar` precedent
      // (`provider = booking.salonName ?? booking.masterName`).
      final String provider = salonNameResolved ?? masterName;
      // Structured facts only — NO free-text note fields reach the calendar
      // (see `buildCalendarDescription`'s own privacy boundary doc). A salon
      // appointment is auto-approved CONFIRMED at submit time (domain rules).
      final String? description = buildCalendarDescription(
        l10n: l10n,
        service: service.name,
        provider: provider,
        providerRole: CalendarProviderRole.salon,
        dateTime:
            '${formatFullDate(serviceStart)}, '
            '${formatTimeRange(serviceStart, serviceEnd.difference(serviceStart).inMinutes)}',
        address: salonAddressLine,
        price: service.priceDisplay,
        status: l10n.bookingStatusConfirmed,
      );

      await addBookingToCalendar(
        context: context,
        title: l10n.bookingCalendarEventTitle(service.name, provider),
        location: salonAddressLine,
        start: serviceStart,
        end: serviceEnd,
        description: description,
      );
    } finally {
      _calendarInFlight.remove(guardKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<SalonBookingAppointment> appointments = widget.args.appointments;

    // Secondary read — never blocks or errors the whole screen. Scoped via
    // `select` to just the resolved salon so a still-loading/resolving family
    // instance rebuilds only this read, not the whole celebration screen —
    // mobile-perf MEDIUM, Phase 14.18 audit. See
    // `salon_booking_confirm_screen.dart`'s file header DATA SOURCE note.
    final Salon? salon = ref.watch(
      publicSalonProfileProvider(
        widget.args.salonId,
      ).select((AsyncValue<PublicSalonProfileData> v) => v.value?.$1),
    );
    final String? addressLine = salon == null
        ? null
        : formatStreetCityLine(
            street: salon.street,
            buildingNo: salon.buildingNo,
            city: salon.city,
          );
    final String? addressDetail =
        (salon?.locationNote?.trim().isNotEmpty ?? false)
        ? salon!.locationNote!.trim()
        : null;
    // Confirms WHERE the booking was made — same secondary
    // `publicSalonProfileProvider` salon the address block reads (no extra
    // fetch). Null while loading/failed → the card renders address alone.
    final String? salonName = (salon?.name.trim().isNotEmpty ?? false)
        ? salon!.name.trim()
        : null;

    return BookingSuccessScaffold(
      title: l10n.salonBookingSuccessTitle,
      subline: l10n.salonBookingSuccessSubline,
      actions: <Widget>[
        SuccessSecondaryButton(
          buttonKey: const Key('salon-success-home-cta'),
          label: l10n.bookingSuccessHomeCta,
          icon: Icons.home_outlined,
          onPressed: () => context.go(RouteNames.clientHome),
        ),
      ],
      homeGap: VelvetSpacing.sm,
      // Non-paged — identical for every appointment (all N masters work at
      // the SAME salon), shown ONCE above the pager.
      recapCards: <Widget>[
        NeumorphicCard(
          key: const Key('salon-success-address-card'),
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // «Салон» identity line above the address — confirms which salon
              // this booking was made with. Dense/compact rhythm matches the
              // rest of the success recap; same composition as the confirm
              // screen and «Деталі запису».
              if (salonName != null) ...<Widget>[
                LabelledRow(
                  key: const Key('salon-success-salon-name'),
                  label: l10n.bookingSalonLabel,
                  value: salonName,
                  compactText: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SectionRule(dense: true),
              ],
              LabelledRow(
                label: l10n.bookingAddressLabel,
                value: addressLine ?? l10n.bookingAddressUnknown,
                detail: addressDetail,
                compactText: true,
              ),
            ],
          ),
        ),
      ],
      // PAGED — one master's confirmed recap + its own «Додати в календар»
      // pills on screen at a time (owner decision, 2026-08-23 — see the file
      // header). No visit-wide total: each card's own «Разом» (inside
      // `BookingSummaryCards.fromSchedule`, via `BookingRecap`) is the only
      // total shown.
      pagedRecap: AppointmentPager(
        // Test-support key — mirrors the confirm screen's identical key
        // (`salon_booking_confirm_screen.dart`), enabling
        // `pager_drag.dart`'s hand-driven swipe recipe here too.
        key: const Key('appointment-pager'),
        count: appointments.length,
        pageBuilder: (BuildContext context, int i) {
          final SalonBookingAppointment appointment = appointments[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BookingSummaryCards.fromSchedule(
                key: ValueKey<String>(
                  'salon-success-appt-${appointment.schedule.masterId}',
                ),
                schedule: appointment.schedule,
                start: appointment.startAt,
                avatarGradient: salonAvatarGradient(i),
                dense: true,
                showBorder: true,
                compactText: true,
              ),
              const SizedBox(height: VelvetSpacing.md),
              _SalonCalendarActionsCard(
                appointment: appointment,
                appointmentIndex: i,
                onTap: (int serviceIndex, DateTime start, DateTime end) =>
                    _addToCalendar(
                      context: context,
                      guardKey: 'salon-success-add-calendar-$i-$serviceIndex',
                      appointment: appointment,
                      service: appointment.schedule.services[serviceIndex],
                      serviceStart: start,
                      serviceEnd: end,
                      salonAddressLine: addressLine,
                      salonNameResolved: salonName,
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One card listing every «Додати в календар» pill for a single confirmed
/// salon appointment — ONE pill per BOOKING (1 service = 1 booking; a master
/// with 2 assigned services gets 2 buttons), because the OS "new event"
/// sheet takes exactly one event per invocation and a single per-master
/// button could only ever seed one of them.
///
/// A separate card rather than a `BookingSummaryCards.fromSchedule`
/// `trailingAction` slot: that factory constructor has no such passthrough,
/// and `booking_summary_cards.dart` is explicitly off-limits for this port
/// (single call site here — REUSE-FIRST does not ask for a new parameter on
/// a widely-shared widget to serve exactly one caller). REUSE-FIRST still
/// governs the CONTENTS: every piece below is the existing shared
/// [CalendarButton] / [NeumorphicCard] / [VelvetText]; only the composition
/// wrapping them is new, because no existing widget renders "N per-booking
/// calendar pills for one salon appointment". Single call site (this
/// screen's pager page) — stays private rather than promoted.
class _SalonCalendarActionsCard extends StatelessWidget {
  const _SalonCalendarActionsCard({
    required this.appointment,
    required this.appointmentIndex,
    required this.onTap,
  });

  final SalonBookingAppointment appointment;

  /// This appointment's position in the visit — used for per-booking keys.
  final int appointmentIndex;

  /// Called with the tapped SERVICE's index within
  /// `appointment.schedule.services` and its own chained start/end window.
  final void Function(int serviceIndex, DateTime start, DateTime end) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<SalonCatalogService> services = appointment.schedule.services;

    // Each service runs back-to-back from the appointment's single chosen
    // start — the same chaining the backend applies server-side. No
    // per-service start is threaded through the draft args (only the
    // aggregate window is shown pre-submission), so it is derived here, once
    // per build, preferring the typed `durationMinutes` and falling back to
    // parsing `durationLabel` only when it is absent (mirrors
    // `booking_recap.dart`'s own typed-field-first precedent).
    DateTime cursor = appointment.startAt;
    final List<DateTime> starts = <DateTime>[];
    final List<DateTime> ends = <DateTime>[];
    for (final SalonCatalogService service in services) {
      final int minutes =
          service.durationMinutes ??
          parseDurationMinutes(service.durationLabel);
      starts.add(cursor);
      cursor = cursor.add(Duration(minutes: minutes));
      ends.add(cursor);
    }

    return NeumorphicCard(
      key: ValueKey<String>('salon-success-calendar-$appointmentIndex'),
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < services.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: VelvetSpacing.sm),
            _CalendarActionRow(
              // A single service needs no disambiguation; several do.
              serviceName: services.length > 1 ? services[i].name : null,
              button: CalendarButton(
                buttonKey: ValueKey<String>(
                  'salon-success-add-calendar-$appointmentIndex-$i',
                ),
                semanticsLabel: l10n.bookingAddCalendarServiceSemantics(
                  services[i].name,
                ),
                onTap: () => onTap(i, starts[i], ends[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One «Додати в календар» pill, optionally preceded by the muted name of
/// the booking it seeds — mirrors the approved preview's `_CalendarRow`
/// (`docs/signup-designs/SalonBookingConfirm/lib/widgets/
/// salon_booking_summary.dart`).
class _CalendarActionRow extends StatelessWidget {
  const _CalendarActionRow({required this.serviceName, required this.button});

  final String? serviceName;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    if (serviceName == null) return button;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            serviceName!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // `feedbackMutedXs` — the shared small-muted-label token, reused
            // rather than an inline fontSize (forbid_inline_fontsize.sh).
            style: VelvetText.feedbackMutedXs,
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm),
        button,
      ],
    );
  }
}
