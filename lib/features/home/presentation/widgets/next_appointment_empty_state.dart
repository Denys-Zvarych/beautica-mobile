// Phase 13.7 — Next appointment EMPTY state (Step 5).
//
// Extracted verbatim from the retired `NextAppointmentCard` (see git history)
// when the Home Hub's populated state was switched over to the SAME shared
// `BookingCard` widget «Мої записи» uses (locked product decision — see
// `docs/mobile-phases/phase-2xx-*` and `booking_card.dart`'s library doc for
// "the card has ONE affordance: open me"). `BookingCard` renders unchanged
// and unparameterised, so it carries no empty-state variant of its own; this
// widget is `_NextAppointmentSection`'s (home_hub_screen.dart) `null` branch,
// pulled out to a standalone public widget so it can still be pumped in
// isolation (e.g. `hub_empty_state_l10n_width_test.dart`'s width-parity net)
// without a Riverpod provider dependency.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/velvet_geometry.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routing/route_names.dart';
import 'hub_widgets.dart';

/// The "Немає майбутніх записів" empty state for the Home Hub's «Найближчий
/// запис» section. See the library doc for why this is a standalone widget.
class NextAppointmentEmptyState extends StatelessWidget {
  const NextAppointmentEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      key: const Key('next_appointment_empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HubSectionTitle(title: l10n.homeHubNextAppointmentTitle),
        const SizedBox(height: VelvetSpacing.md),
        // Width is pinned to the full content width on purpose — same
        // structural hazard as the favourites / BEAUTY TIMELINE empty states.
        // The outer Column uses CrossAxisAlignment.start, which hands children
        // LOOSE width constraints, so an unpinned HubFlatCard sizes itself to
        // its widest child. Unlike those two, this card does NOT currently
        // depend on its copy length — it renders full-width only because
        // HubEmptyState's CTA (HubFilledButton wraps an aligned Container,
        // which expands to the loose max) happens to fill the row. That makes
        // the correct width an accident of a *different* widget: drop the CTA
        // here, or make HubFilledButton intrinsically sized, and this card
        // would silently shrink to its message width exactly as the timeline
        // card did. Pin it explicitly so all three siblings state the same
        // invariant instead of two stating it and one inheriting it by luck.
        SizedBox(
          width: double.infinity,
          child: HubFlatCard(
            key: const Key('next_appointment_empty_card'),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.lg,
            ),
            child: HubEmptyState(
              icon: Icons.event_busy_rounded,
              message: l10n.homeHubNoUpcomingAppointments,
              ctaLabel: l10n.homeHubFindMaster,
              onCta: () => context.push(RouteNames.clientSearch),
            ),
          ),
        ),
      ],
    );
  }
}
