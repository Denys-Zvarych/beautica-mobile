// Phase 110 Part 2 — the ONE shared category → icon resolver.
//
// ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
//
// Before this change there were TWO drifted private category-icon mappers —
// `beauty_timeline_section.dart`'s `_categoryIcon`/`_categoryIconFromName`
// (substring matcher over Material `IconData`) and
// `booking_card.dart:407`'s `_categoryIconFor` (exact-match `switch` over
// Material `IconData`) — plus `favorites_filter.dart` explicitly declining to
// add a third because no shared helper existed. The two existing mappers
// disagree with each other on «Вії» (lash) and on their fallback glyph. See
// `docs/mobile-phases/category-icons-provenance.md` and
// `docs/mobile-phases/category-icons-resume.md` for the full history.
//
// [categoryIconFor] is the reconciliation point: ONE function, returning a
// real SVG asset path (not a generic Material glyph) from the 20 category
// icons registered on [BeauticaAssetIcons]. Its first caller was the BEAUTY
// TIMELINE rail (`lib/features/home/presentation/widgets/beauty_timeline_section.dart`);
// a second caller was added when the CLIENT SEARCH category rail migrated
// onto it (`lib/features/discovery/presentation/search_filters_screen.dart:953`).
//
// ── SCOPE — DO NOT MIGRATE THE OTHER TWO MAPPERS HERE ──────────────────────
//
// `booking_card.dart:407` (`_categoryIconFor`) and
// `favorites_filter.dart:56` (the collapsed-pill glyph) are DELIBERATELY left
// untouched by this change. Migrating them changes what two SHIPPED screens
// render — a visual diff that needs its own review, not a drive-by rename.
// The NEXT author who touches either of those two files should MIGRATE them
// onto this resolver rather than editing their private mapper or forking a
// third/fourth one. That is the whole point of promoting this file now
// instead of waiting for a third caller to justify it.
//
// ── CONTRACT ─────────────────────────────────────────────────────────────
//
// Two-stage lookup, mirroring the shape the timeline rail's private mapper
// used before this change:
//   1. [categoryKey] — the backend's stable uppercase slug
//      (`platform_categories.name`, e.g. `"NAIL_SERVICE"`;
//      see `V74__seed_taxonomy_platform_categories.sql`). Preferred whenever
//      present because it is locale-independent and typo-proof.
//   2. [categoryName] — the Ukrainian display name, keyword-matched. Used
//      only when [categoryKey] is null/empty/unrecognised — the fallback for
//      pre-Phase-110 callers/tests that only ever carried a display name.
//
// Never returns null: an unrecognised slug/name resolves to [_fallback]
// rather than forcing every caller to handle a missing-icon case. The
// backend gates the picker to ~20-24 APPROVED platform categories (see
// `GET /service-categories/approved`), so an unknown slug reaching this
// resolver is expected to be rare (a brand-new admin-added category, or a
// legacy/soft-disabled slug like `SHAVING`/`PEDICURE`/`HAIR`/`BODY`/`FACE`
// still attached to old data) rather than the common case.

import 'beautica_asset_icons.dart';

/// Resolves the SVG asset path for one category, preferring the backend's
/// stable [categoryKey] slug and falling back to keyword-matching the
/// Ukrainian [categoryName]. Always returns a usable asset path — see the
/// file header's contract section for the fallback rule.
String categoryIconFor({String? categoryKey, String? categoryName}) {
  final String? byKey = _fromKey(categoryKey);
  if (byKey != null) return byKey;
  return _fromName(categoryName) ?? _fallback;
}

/// Fallback for an unrecognised/absent category — the closest general
/// "beauty services" glyph among the 20 registered category icons.
const String _fallback = BeauticaAssetIcons.categoryCosmetology;

/// Stage 1 — exact match against the 20 live `platform_categories` slugs.
String? _fromKey(String? categoryKey) {
  if (categoryKey == null || categoryKey.isEmpty) return null;
  return switch (categoryKey.toUpperCase()) {
    'HAIRDRESSING' => BeauticaAssetIcons.categoryHairdressing,
    'NAIL_SERVICE' => BeauticaAssetIcons.categoryNailService,
    'LASH_EXTENSIONS' => BeauticaAssetIcons.categoryLashExtensions,
    'MAKEUP' => BeauticaAssetIcons.categoryMakeup,
    'PODOLOGY' => BeauticaAssetIcons.categoryPodology,
    'BARBERING' => BeauticaAssetIcons.categoryBarbering,
    'BEARD_CARE' => BeauticaAssetIcons.categoryBeardCare,
    'BROWS' => BeauticaAssetIcons.categoryBrows,
    'HAIR_COLORING' => BeauticaAssetIcons.categoryHairColoring,
    'HAIR_TREATMENT' => BeauticaAssetIcons.categoryHairTreatment,
    'HAIR_EXTENSIONS' => BeauticaAssetIcons.categoryHairExtensions,
    'TRICHOLOGY' => BeauticaAssetIcons.categoryTrichology,
    'LASH_LAMINATION' => BeauticaAssetIcons.categoryLashLamination,
    'COSMETOLOGY' => BeauticaAssetIcons.categoryCosmetology,
    'INJECTION_COSMETOLOGY' => BeauticaAssetIcons.categoryInjectionCosmetology,
    'HARDWARE_COSMETOLOGY' => BeauticaAssetIcons.categoryHardwareCosmetology,
    'AESTHETIC_COSMETOLOGY' => BeauticaAssetIcons.categoryAestheticCosmetology,
    'LASER_COSMETOLOGY' => BeauticaAssetIcons.categoryLaserCosmetology,
    'HAIR_REMOVAL' => BeauticaAssetIcons.categoryHairRemoval,
    'PERMANENT_MAKEUP' => BeauticaAssetIcons.categoryPermanentMakeup,
    _ => null,
  };
}

/// Stage 2 — keyword match over the Ukrainian display name. Mirrors the
/// substring vocabulary the timeline rail's retired `_categoryIconFromName`
/// private helper used, extended to route through the real SVG set.
String? _fromName(String? categoryName) {
  if (categoryName == null || categoryName.isEmpty) return null;
  final String lower = categoryName.toLowerCase();

  if (lower.contains('манікюр')) return BeauticaAssetIcons.categoryNailService;
  if (lower.contains('педикюр')) return BeauticaAssetIcons.categoryPodology;
  if (lower.contains('бров')) return BeauticaAssetIcons.categoryBrows;
  if (lower.contains('ламінування') && lower.contains('вій')) {
    return BeauticaAssetIcons.categoryLashLamination;
  }
  if (lower.contains('вій') || lower.contains('lash')) {
    return BeauticaAssetIcons.categoryLashExtensions;
  }
  if (lower.contains('перманентн')) {
    return BeauticaAssetIcons.categoryPermanentMakeup;
  }
  if (lower.contains('макіяж')) return BeauticaAssetIcons.categoryMakeup;
  if (lower.contains('фарбування')) {
    return BeauticaAssetIcons.categoryHairColoring;
  }
  if (lower.contains('відновлення') && lower.contains('волос')) {
    return BeauticaAssetIcons.categoryHairTreatment;
  }
  if (lower.contains('нарощування') && lower.contains('волос')) {
    return BeauticaAssetIcons.categoryHairExtensions;
  }
  if (lower.contains('трихолог')) return BeauticaAssetIcons.categoryTrichology;
  if (lower.contains('барбер')) return BeauticaAssetIcons.categoryBarbering;
  if (lower.contains('борода') || lower.contains('вуса')) {
    return BeauticaAssetIcons.categoryBeardCare;
  }
  if (lower.contains('волос') || lower.contains('стриж')) {
    return BeauticaAssetIcons.categoryHairdressing;
  }
  if (lower.contains('апаратна')) {
    return BeauticaAssetIcons.categoryHardwareCosmetology;
  }
  if (lower.contains('ін\'єкційна') || lower.contains('ін’єкційна')) {
    return BeauticaAssetIcons.categoryInjectionCosmetology;
  }
  if (lower.contains('естетична')) {
    return BeauticaAssetIcons.categoryAestheticCosmetology;
  }
  if (lower.contains('лазерна')) {
    return BeauticaAssetIcons.categoryLaserCosmetology;
  }
  if (lower.contains('косметол')) return BeauticaAssetIcons.categoryCosmetology;
  if (lower.contains('депіляц') || lower.contains('епіляц')) {
    return BeauticaAssetIcons.categoryHairRemoval;
  }
  return null;
}
