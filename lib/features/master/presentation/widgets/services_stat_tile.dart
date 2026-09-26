// The «Послуги» stat tile — shared by the master's own profile
// (`master_profile_screen.dart`) and the client-facing public profile
// (`public_master_profile_screen.dart`).
//
// Both screens used to build this tile inline with duplicated icon/caption
// wiring, and both printed a bare '0' for an empty catalogue; on the own
// profile '—' meant only "not resolved yet" (loading / failed load). Owning
// the icon, the caption and the value rule here keeps the three-way decision
// — empty, unresolved, failed — in exactly one place:
//
//   * empty catalogue (0)  → '—'  (matches the rating/reviews tiles' zero-state)
//   * unresolved (loading) → '—'
//   * failed load          → '?'  ([hasError]) — deliberately NOT '—', so a
//     suppressed `/services` response can never be mistaken for a master who
//     genuinely has no services.
//
// Rendering itself is delegated to [StatTile] — the low-level tile shared with
// the bookings/rating/reviews tiles on the same row, which is left untouched.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The services-count stat tile.
///
/// [count] is nullable so callers can hand over an unresolved catalogue
/// (loading / error) without inventing a number. A `null` count and an empty
/// catalogue render identically — the em-dash placeholder — matching the
/// zero-state of the sibling rating/reviews tiles on the same row.
///
/// [hasError] separates a *failed* load from those two: it renders '?' so a
/// catalogue that could not be fetched never reads as an empty one. Callers
/// with no error state (the public profile builds this tile from an
/// already-resolved list) simply leave it at its `false` default.
class ServicesStatTile extends StatelessWidget {
  const ServicesStatTile({
    super.key,
    required this.count,
    required this.valueKey,
    this.hasError = false,
  });

  /// Number of services, or `null` when the catalogue is not resolved.
  final int? count;

  /// Whether the catalogue load failed. Takes precedence over [count].
  final bool hasError;

  /// [Key] placed on the value [Text] — the per-screen handle widget tests use.
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Failed load gets its own glyph; unresolved (null) and empty (0) both
    // collapse onto the em-dash.
    final String value = hasError
        ? '?'
        : switch (count) {
            null || 0 => '—',
            final int resolved => resolved.toString(),
          };
    return StatTile(
      icon: Icons.design_services_outlined,
      value: value,
      caption: l10n.masterServicesLabel,
      valueKey: valueKey,
    );
  }
}
