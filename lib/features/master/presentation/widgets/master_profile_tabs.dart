import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Phase 351 (D15) — the three sections every master profile screen tabs
/// between: «Про майстра» / «Послуги» / «Відгуки». Shared by
/// `PublicMasterProfileScreen`, `MasterProfileScreen` and
/// `SalonMasterProfileScreen` so the tab vocabulary and index-to-label
/// mapping lives in exactly one place.
enum MasterProfileTab { about, services, reviews }

/// Localized tab labels, in [MasterProfileTab] order — passed straight to
/// `ProfileTabBar.tabs`.
///
/// `services`/`reviews` reuse the salon profile's neutral
/// `salonTabServices`/`salonTabReviews` keys (D5) rather than forking
/// master-specific duplicates — the wording says nothing salon-specific.
List<String> masterProfileTabLabels(AppLocalizations l10n) => <String>[
  l10n.publicMasterTabAbout,
  l10n.salonTabServices,
  l10n.salonTabReviews,
];
