// Phase 7.6 — the master «Мої записи» empty states.
//
// ## Two empties, and only one of them is a dead end
//
// The design ships `_EmptyBookings` and `_NoResults` as separate widgets, and
// the distinction is the point:
//
//   * **True empty** — the master has no bookings at all. Nothing is wrong and
//     there is nothing to undo; the copy just says the list will fill up.
//   * **Filter empty** — bookings exist, but none match the day / period /
//     status / service currently selected. Without a way out the master lands
//     on a blank screen with no idea WHY it is blank, and the most likely
//     cause (a day chip they tapped 30 seconds ago, now scrolled off the rail)
//     is invisible. So this one carries «Скинути фільтри».
//
// Collapsing the two into one message is the failure mode this file exists to
// prevent — it would either tell a busy master they have no bookings, or offer
// a reset button to someone with nothing to reset.
//
// The loading, error and load-more-spinner states are NOT re-implemented here:
// `my_bookings_states.dart` already ships `BookingsSkeleton`,
// `MyBookingsErrorState` and `MyBookingsLoadMoreSpinner`, all three of which
// are perspective-neutral (a skeleton card and a failure message look the same
// from either side of a booking). The master screen consumes them directly.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Shown when the master has no bookings whatsoever — no filter is active and
/// there is nothing to reset.
class MasterBookingsEmptyState extends StatelessWidget {
  const MasterBookingsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('master-bookings-empty'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.event_note_outlined,
                size: 48,
                color: BrandColors.accent,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.masterBookingsEmptyTitle,
                textAlign: TextAlign.center,
                style: VelvetText.subheading(),
              ),
              const SizedBox(height: VelvetSpacing.xs),
              Text(
                l10n.masterBookingsEmptyBody,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when bookings exist but the active filters match none of them.
/// Always carries the escape hatch — see the file header.
class MasterBookingsNoResultsState extends StatelessWidget {
  const MasterBookingsNoResultsState({super.key, required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Center(
      key: const Key('master-bookings-no-results'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.filter_alt_off_outlined,
                size: 48,
                color: BrandColors.accent,
              ),
              const SizedBox(height: VelvetSpacing.md),
              Text(
                l10n.masterBookingsNoResultsTitle,
                textAlign: TextAlign.center,
                style: VelvetText.subheading(),
              ),
              const SizedBox(height: VelvetSpacing.xs),
              Text(
                l10n.masterBookingsNoResultsBody,
                textAlign: TextAlign.center,
                style: VelvetText.body(),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: NeumorphicButton(
                  key: const Key('master-bookings-clear-filters'),
                  label: l10n.masterBookingsClearFilters,
                  icon: Icons.refresh_rounded,
                  onPressed: onClearFilters,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
