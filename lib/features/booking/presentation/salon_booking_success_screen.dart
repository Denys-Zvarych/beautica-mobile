// Phase 14.18 — SalonBookingSuccessScreen: salon booking flow step 4b, the
// post-submit celebration. Mirrors the independent-master
// `BookingSuccessScreen` (`booking_success_screen.dart`) — animated success
// badge → "Записано!" headline → reassuring subline → the booking recap →
// a single pinned "На головну" — extended to LIST every created appointment
// via the SAME generalized `BookingSummaryCards` the independent success
// screen uses (`BookingSummaryCards.fromSchedule` — see that widget's file
// header), one per master, plus a shared salon-address card and a grand
// total.
//
// The shared celebration structure lives in
// `widgets/booking_success_scaffold.dart` (composed by both success screens);
// this screen just supplies its copy and its recap cards. The scaffold wraps
// each recap card in the same staggered reveal.
//
// INFORMATION PARITY (salon booking rework): the independent success
// screen's `BookingSummaryCards.fromMaster` call hides the master card
// (`showMasterCard: false`) because there is exactly one master the client
// just booked with. Here, with N masters, the master card is the only thing
// distinguishing one appointment's recap from another — so this screen keeps
// it VISIBLE (`showMasterCard: true`, the default). The salon address is
// identical for every appointment (all N masters work at the SAME salon), so
// — same as the confirm screen — it is shown ONCE at the top rather than
// repeated per card (`showAddress: false` on each per-appointment card); a
// grand total across every master's services closes the picture, suppressed
// when N == 1 (it would just repeat that one card's own subtotal).
//
// DELIBERATE OMISSION — no "Додати в календар" link: the independent success
// screen's link is a documented no-op `TODO` (see
// `booking_success_screen.dart`'s file header — no `add_2_calendar`
// dependency in `pubspec.yaml`). Replicating a dead affordance N times would
// add no value, so it is intentionally not carried over here.
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
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../domain/salon_booking_confirm_args.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/labelled_row.dart';
import 'widgets/salon_avatar_gradients.dart';

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

  // `widget.args.appointments` never changes for this screen's lifetime, so
  // the flattened grand-total selection list is computed once here instead of
  // on every build() (mobile-perf MEDIUM, Phase 14.18 salon-confirm audit).
  late final List<BookingSelection> _allSelections = widget.args.appointments
      .expand((SalonBookingAppointment a) => a.schedule.services)
      .map(BookingSelection.fromSalonCatalogService)
      .toList();

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

    return BookingSuccessScaffold(
      title: l10n.salonBookingSuccessTitle,
      subline: l10n.salonBookingSuccessSubline,
      homeButtonKey: const Key('salon-success-home-cta'),
      onHome: () => context.go(RouteNames.clientHome),
      homeGap: VelvetSpacing.sm,
      recapCards: <Widget>[
        NeumorphicCard(
          key: const Key('salon-success-address-card'),
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: LabelledRow(
            label: l10n.bookingAddressLabel,
            value: addressLine ?? l10n.bookingAddressUnknown,
            detail: addressDetail,
            compactText: true,
          ),
        ),
        for (int i = 0; i < appointments.length; i++)
          BookingSummaryCards.fromSchedule(
            key: ValueKey<String>(
              'salon-success-appt-${appointments[i].schedule.masterId}',
            ),
            schedule: appointments[i].schedule,
            start: appointments[i].startAt,
            avatarGradient: salonAvatarGradient(i),
            dense: true,
            showBorder: true,
            compactText: true,
          ),
        if (appointments.length > 1)
          NeumorphicCard(
            key: const Key('salon-success-grand-total-card'),
            showBorder: true,
            padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
            child: BookingRecap(
              selections: _allSelections,
              totalOnly: true,
              dense: true,
              compactText: true,
            ),
          ),
      ],
    );
  }
}
