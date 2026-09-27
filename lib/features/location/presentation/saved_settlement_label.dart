// Phase 346 follow-up (backend phase-330) — the localised binding of
// [composeSavedSettlementLabel].
//
// A saved locality (a profile / salon / master read) is labelled by the SAME
// [composeSettlementLabel] a picked «Населений пункт» row is, so the profile
// line, the search prefill and every settlement-field seed read
// «м. Львів, Львівська обл.» exactly as the picker does — never a bare
// «Львів». This file only supplies the four localised words, the same four
// `SettlementSelectField` passes; it formats nothing itself.

import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The label of a saved settlement, or `null` when there is none (the caller
/// shows its placeholder or falls back).
///
/// A [saved] with no settlement type renders as its bare name — see
/// [composeSavedSettlementLabel].
String? savedSettlementLabel(AppLocalizations l10n, Settlement? saved) =>
    composeSavedSettlementLabel(
      saved,
      hromadaWord: l10n.settlementHromadaWord,
      oblastWord: l10n.settlementOblastAbbrev,
      cityPrefix: l10n.settlementCityPrefix,
      villagePrefix: l10n.settlementVillagePrefix,
    );

/// The SHORT label of a saved settlement for a full-address line — the
/// prefixed name alone («с. Іванівка», «м. Львів»), with NO hromada or oblast
/// segment — or `null` when [saved] carries no settlement type.
///
/// For the salon address lines (hub card, affiliation card, management hero,
/// salon-master profile), which by the 2026-08-29 product decision never
/// render the oblast (`shared/formatters/address_lines.dart`
/// `buildFullAddressLine`'s doc). Built by the SAME
/// [composeSavedSettlementLabel] with the oblast and hromada parts blanked,
/// so the prefix and sanitising rules cannot drift from the full label.
///
/// `null` without a type on purpose: only a phase-330 read proves the name is
/// derived from the settlement id (not legacy free text), so a caller without
/// one keeps its own resolution chain.
String? savedSettlementShortLabel(AppLocalizations l10n, Settlement? saved) {
  if (saved == null || saved.settlementType == null) return null;
  return savedSettlementLabel(
    l10n,
    saved.copyWith(oblastName: '', hromadaName: null),
  );
}
