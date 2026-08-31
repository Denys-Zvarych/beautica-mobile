// The salon card used by the «Мої салони» hub and the Phase 21.6 rotate-admin
// destination picker.
//
// PROMOTED (REUSE-FIRST, Phase 21.6) out of `my_salons_screen.dart`, where it
// was the file-private `_SalonHubCard`. [MoveAdminSalonScreen] needs exactly
// this card — logo + name + address block + chevron, depressing on press —
// and the design preview draws it as the hub card verbatim
// (`docs/signup-designs/SalonManagementDesign/lib/screens/
// move_admin_salon_screen.dart:258-354`: "mirrors the 'Мої салони' hub
// card"). Being private was the signal a promotion was due, not a licence to
// copy it.
//
// The public API is BYTE-IDENTICAL to the private original — `({Key? key,
// required Salon salon, required VoidCallback onTap})`, no parameter added,
// no default changed — so `my_salons_screen.dart` renders exactly as it did
// before the move. Everything the card derives (the «Основний» badge, the
// resolved locality line, the street line, the monogram) it still derives
// from the [Salon] it is handed; a caller holding a narrower projection
// builds the display [Salon] itself (see [MoveAdminSalonScreen], which maps
// a [SiblingSalonOption] into one).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';

import '../../domain/salon.dart';
import 'salon_cover_widgets.dart';

/// A salon card in the hub: logo + name + "Основний" badge (primary only) +
/// locality/address. Depresses on press.
///
/// `ConsumerStatefulWidget` (Phase 21.14 follow-up — was `StatefulWidget`)
/// so [_SalonHubCardState.build] can `ref.watch` [resolvedLocalityProvider]
/// for the taxonomy city name — see that method for the fallback chain and
/// why `salon.city` is not read directly. Mirrors `_ManagementHeroCard` in
/// `salon_management_profile_screen.dart`, reusing the SAME promoted
/// provider rather than a second resolution path.
class SalonHubCard extends ConsumerStatefulWidget {
  const SalonHubCard({super.key, required this.salon, required this.onTap});

  final Salon salon;
  final VoidCallback onTap;

  @override
  ConsumerState<SalonHubCard> createState() => _SalonHubCardState();
}

class _SalonHubCardState extends ConsumerState<SalonHubCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Salon s = widget.salon;
    // `salon.city` is legacy free-text, frozen (no longer written by the
    // backend since Phase 10.6 — see `Salon.city`'s own doc): once a salon's
    // address has been edited through the taxonomy cascade, `city` can be
    // stale or blank while `cityId`/`oblastId` carry the real location. This
    // watches the SAME promoted `resolvedLocalityProvider`
    // (`features/location/state/resolved_locality_provider.dart`)
    // `_ManagementHeroCard` uses — no second by-id scan here.
    //
    // PER-ROW watch, not hoisted above the list: `resolvedLocalityProvider`
    // is a family, but the `oblastList`/`cityList(oblastId)`/
    // `districtList(cityId)` providers it reads underneath are
    // `keepAlive: true` and memoized for the app's lifetime. An owner's
    // salons are typically in the same oblast/city, so distinct
    // `(oblastId, cityId, districtId)` triples across N cards collapse to at
    // most a handful of family instances — and even those only ever hit the
    // network once per distinct oblast/city/district; every other card
    // resolving the same triple (or a triple sharing an already-fetched
    // oblast/city) re-scans an in-memory list, not a fresh HTTP round trip.
    // Hoisting a single resolve above the list would only help if every
    // salon shared one identical triple, which the model doesn't guarantee
    // (an owner can have salons in different cities) — per-row is both
    // simpler and correct here.
    //
    // `AsyncValue.value` is nullable (Riverpod 3.x) and collapses BOTH
    // "still loading" and "resolution failed" to `null` uniformly — no
    // spinner, no error box, no layout jump. `city` falls back to the legacy
    // `s.city` ONLY when the salon genuinely has no taxonomy id at all
    // (`s.cityId` blank — [Salon.cityId] is non-nullable, `@Default('')`,
    // RESUME §4 step D) — a pre-Phase-10.6 salon that was never re-saved (in
    // practice no longer reachable from a real backend read, which now
    // always populates it, but the fixture-only shape stays representable).
    // While `cityId` IS set but resolution hasn't completed yet, the line is
    // simply blank until it fills in — never the stale legacy text, which
    // would risk showing a WRONG city before the correct one arrives.
    final ResolvedLocality? resolved = ref
        .watch(
          resolvedLocalityProvider(
            oblastId: s.oblastId,
            cityId: s.cityId,
            districtId: s.districtId,
          ),
        )
        .value;
    final bool hasTaxonomyCity = s.cityId.trim().isNotEmpty;
    final String? locality = buildLocalityLine(
      resolved?.city?.name ?? (hasTaxonomyCity ? null : s.city),
    );
    final String? street = buildStreetLine(s.street, s.buildingNo);
    final String? monogram = s.name.trim().isEmpty
        ? null
        : s.name.trim()[0].toUpperCase();

    return Semantics(
      button: true,
      label: AppLocalizations.of(
        context,
      ).mySalonsCardSemanticLabel(s.name, locality ?? ''),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
            ),
            padding: const EdgeInsets.all(VelvetSpacing.md + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SalonLogo(diameter: 58, monogram: monogram),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              s.name,
                              style: VelvetText.displayName21,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (s.isPrimary ?? false) ...<Widget>[
                            const SizedBox(width: VelvetSpacing.sm),
                            const _PrimaryBadge(),
                          ],
                        ],
                      ),
                      if (locality != null || street != null) ...<Widget>[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: BrandColors.accentDeep,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                <String>[?locality, ?street].join('\n'),
                                style: VelvetText.salonHubAddressLine,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: VelvetSpacing.sm),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: BrandColors.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The camel "Основний" primary-salon badge.
class _PrimaryBadge extends StatelessWidget {
  const _PrimaryBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: VelvetSpacing.xs - 1,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
        ),
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.star_rounded,
            size: 12,
            color: BrandColors.white.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 3),
          Text(
            AppLocalizations.of(context).mySalonsPrimaryBadgeLabel,
            style: VelvetText.salonHubPrimaryBadgeLabel,
          ),
        ],
      ),
    );
  }
}
