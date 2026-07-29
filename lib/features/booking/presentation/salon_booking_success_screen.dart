// MO-4 (single-master single-visit rework) — SalonBookingSuccessScreen: salon
// booking flow step 4b, the post-submit celebration.
//
// The salon flow now books ONE visit, so this mirrors the independent-master
// `BookingSuccessScreen` — animated badge → «Записано!» → subline → the visit
// recap → a single pinned «На головну» — via the SAME shared
// [BookingSummaryCards] recap. A single shared salon-address card sits above
// the visit card.
//
// Reached ONLY via `SalonBookingConfirmScreen`'s `pushReplacement` once the
// single `POST /appointments` succeeded, so the recap here is always the
// confirmed visit. The scaffold's `PopScope(canPop: false)` blocks back.
//
// The salon's ADDRESS is a secondary read via `publicSalonProfileProvider`
// (never blocks/errors this screen).

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
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/labelled_row.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/section_rule.dart';

/// Salon booking flow step 4b — the confirmed visit recap.
class SalonBookingSuccessScreen extends ConsumerStatefulWidget {
  const SalonBookingSuccessScreen({super.key, required this.args});

  final SalonBookingSuccessArgs args;

  @override
  ConsumerState<SalonBookingSuccessScreen> createState() =>
      _SalonBookingSuccessScreenState();
}

class _SalonBookingSuccessScreenState
    extends ConsumerState<SalonBookingSuccessScreen> {
  late final ScreenProtectionManager _screenProtection;

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

    // Secondary read — never blocks/errors the whole screen.
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
      recapCards: <Widget>[
        NeumorphicCard(
          key: const Key('salon-success-address-card'),
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
        BookingSummaryCards.fromSchedule(
          key: const Key('salon-success-visit-card'),
          schedule: widget.args.visit,
          start: widget.args.startAt,
          avatarGradient: salonAvatarGradient(0),
          dense: true,
          showBorder: true,
          compactText: true,
        ),
      ],
    );
  }
}
