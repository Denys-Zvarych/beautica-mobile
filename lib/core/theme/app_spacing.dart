// Phase 1.2 — canonical spacing scale.
//
// Single source of truth for every padding, margin, gap, and `SizedBox`
// dimension across the app. See `ARCHITECTURE-mobile.md` § 9 for the locked
// scale.
//
// Rules:
//   - Every `EdgeInsets.*` and `SizedBox(width:|height:)` literal in
//     `lib/features/**` MUST reference one of these seven constants.
//   - No semantic aliases (`cardPadding`, `dialogPadding`, …) are allowed
//     here — keep the surface minimal so designers and engineers share the
//     same vocabulary.
//   - No helper methods (`AppSpacing.allMd()` etc.) — call sites should make
//     the chosen `EdgeInsets` shape explicit at the use site.
//
// `mobile-qa` enforces this via a CI grep gate (see `analysis_options.yaml`
// and `.github/workflows/pr-validate.yml`). Numeric padding outside this
// scale is an automatic HIGH finding.

/// Beautica's canonical spacing tokens — 4 / 8 / 12 / 16 / 24 / 32 / 48.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}
