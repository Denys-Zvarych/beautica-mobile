// Phase 414 — the «Посилання для запису» settings row, promoted (REUSE-FIRST)
// from the master settings hub's private `_BookingLinksRowSlot` so the
// INDEPENDENT_MASTER hub and the salon «Налаштування» (SALON_OWNER /
// SALON_ADMIN) render the one widget.
//
// Present only while `bookingLinksVisibleProvider` is `true` (kill-switch on,
// ≥1 link for the caller's role, no error, not first-loading). Watching here
// (not in the host screen's `build`) keeps the autoDispose links load scoped
// to this slot, so the host never rebuilds on the links load and a hidden row
// leaves no trace. The slot owns its own leading [VelvetSpacing.md] gap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_links_provider.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// The «Посилання для запису» row (key `row-booking-links`), pushing
/// [RouteNames.bookingLinks]. [reveal] wraps the row in the host screen's
/// entrance animation.
class BookingLinksSettingsRow extends ConsumerWidget {
  const BookingLinksSettingsRow({super.key, required this.reveal});

  final Widget Function(Widget child) reveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool visible = ref.watch(bookingLinksVisibleProvider);
    if (!visible) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: VelvetSpacing.md),
        reveal(
          SettingsRow(
            key: const Key('row-booking-links'),
            icon: Icons.link_rounded,
            label: l10n.bookingLinksSettingsRow,
            onTap: () => context.pushOnce(RouteNames.bookingLinks),
          ),
        ),
      ],
    );
  }
}
