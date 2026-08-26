// Phase 110 Part 2 — QA gap-closure (mobile-security LOW).
//
// WHY THIS FILE EXISTS
// ---------------------
// `categoryIconFor` (`lib/core/icons/category_icons.dart`) is the ONE
// shared category → icon resolver, and its name-fallback stage consumes a
// SERVER-CONTROLLED string (`TimelineEntry.category`, ultimately
// `service_definitions.category` off the wire — see `timeline_mapper.dart`'s
// header). Before this file, its safety against malformed/adversarial input
// was proven only by inspection, not by a test. mobile-security flagged this
// as a LOW: "no dedicated test exercises the resolver with adversarial
// input". This file closes that gap.
//
// Strategy: plain `test()`, no widget tree — `categoryIconFor` is pure Dart
// (imports only `beautica_asset_icons.dart`), matching `app_icon_test.dart`'s
// documented split between plain-Dart unit tests and widget tests.
//
// The headline invariant pinned throughout is FALLBACK TOTALITY: for ANY
// input — known, unknown, null, empty, or adversarial — the function must
// (a) never throw and (b) always return one of the 20 real, bundled
// `BeauticaAssetIcons.category*` asset paths. See the "totality" group at
// the bottom, which is the load-bearing assertion for the security finding.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/icons/category_icons.dart';

// ---------------------------------------------------------------------------
// The 20 live `platform_categories` slugs (V74__seed_taxonomy_platform_
// categories.sql) mapped to the asset constant `_fromKey` must resolve them
// to. Declared once here so the "every known slug" and "totality" groups
// share one source of truth instead of two hand-typed lists drifting apart.
// ---------------------------------------------------------------------------

const Map<String, String> _knownSlugToAsset = <String, String>{
  'HAIRDRESSING': BeauticaAssetIcons.categoryHairdressing,
  'NAIL_SERVICE': BeauticaAssetIcons.categoryNailService,
  'LASH_EXTENSIONS': BeauticaAssetIcons.categoryLashExtensions,
  'MAKEUP': BeauticaAssetIcons.categoryMakeup,
  'PODOLOGY': BeauticaAssetIcons.categoryPodology,
  'BARBERING': BeauticaAssetIcons.categoryBarbering,
  'BEARD_CARE': BeauticaAssetIcons.categoryBeardCare,
  'BROWS': BeauticaAssetIcons.categoryBrows,
  'HAIR_COLORING': BeauticaAssetIcons.categoryHairColoring,
  'HAIR_TREATMENT': BeauticaAssetIcons.categoryHairTreatment,
  'HAIR_EXTENSIONS': BeauticaAssetIcons.categoryHairExtensions,
  'TRICHOLOGY': BeauticaAssetIcons.categoryTrichology,
  'LASH_LAMINATION': BeauticaAssetIcons.categoryLashLamination,
  'COSMETOLOGY': BeauticaAssetIcons.categoryCosmetology,
  'INJECTION_COSMETOLOGY': BeauticaAssetIcons.categoryInjectionCosmetology,
  'HARDWARE_COSMETOLOGY': BeauticaAssetIcons.categoryHardwareCosmetology,
  'AESTHETIC_COSMETOLOGY': BeauticaAssetIcons.categoryAestheticCosmetology,
  'LASER_COSMETOLOGY': BeauticaAssetIcons.categoryLaserCosmetology,
  'HAIR_REMOVAL': BeauticaAssetIcons.categoryHairRemoval,
  'PERMANENT_MAKEUP': BeauticaAssetIcons.categoryPermanentMakeup,
};

/// All 20 registered category asset constants — the resolver's total
/// codomain. Any input, however adversarial, must resolve to a member of
/// this set (see the "totality" group).
final Set<String> _registeredCategoryAssets = _knownSlugToAsset.values.toSet();

void main() {
  // ── Known slugs — each resolves to its own distinct, correct asset ───────

  group('categoryIconFor — known slugs (Stage 1: categoryKey)', () {
    _knownSlugToAsset.forEach((String slug, String expectedAsset) {
      test('"$slug" resolves to its own registered asset', () {
        expect(
          categoryIconFor(categoryKey: slug, categoryName: null),
          expectedAsset,
        );
      });
    });

    test(
      'all 20 known slugs are registered (sanity on the fixture itself)',
      () {
        expect(_knownSlugToAsset.length, 20);
      },
    );

    test('all 20 known slugs resolve to 20 DISTINCT assets — no accidental '
        'many-to-one collapse in the switch', () {
      final Set<String> resolved = _knownSlugToAsset.keys
          .map((String slug) => categoryIconFor(categoryKey: slug))
          .toSet();
      expect(
        resolved.length,
        20,
        reason:
            'a copy-paste error in _fromKey\'s switch could map two slugs '
            'to the same asset without any single-slug test catching it',
      );
    });

    test('categoryKey takes priority over a conflicting categoryName', () {
      // A key that resolves to BROWS, paired with a name that would resolve
      // (via Stage 2) to NAIL_SERVICE. Stage 1 must win.
      expect(
        categoryIconFor(categoryKey: 'BROWS', categoryName: 'Манікюр'),
        BeauticaAssetIcons.categoryBrows,
      );
    });
  });

  // ── Case-insensitivity of the slug match ──────────────────────────────────

  group('categoryIconFor — slug case-insensitivity', () {
    test('lowercase slug resolves the same as uppercase', () {
      expect(
        categoryIconFor(categoryKey: 'nail_service'),
        BeauticaAssetIcons.categoryNailService,
      );
    });

    test('mixed-case slug resolves the same as uppercase', () {
      expect(
        categoryIconFor(categoryKey: 'Nail_Service'),
        BeauticaAssetIcons.categoryNailService,
      );
      expect(
        categoryIconFor(categoryKey: 'InJeCtIoN_CoSmEtOlOgY'),
        BeauticaAssetIcons.categoryInjectionCosmetology,
      );
    });
  });

  // ── Unknown/legacy slug falls through to Stage 2 (name), then fallback ───

  group('categoryIconFor — unknown/legacy slug fallthrough', () {
    test('legacy slug SHAVING with no matching name falls all the way to the '
        'fallback', () {
      expect(
        categoryIconFor(categoryKey: 'SHAVING', categoryName: null),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('legacy slug PEDICURE with no matching name falls all the way to the '
        'fallback (NOT the podology asset — the key alone is not enough; the '
        'literal string "PEDICURE" is not in _fromKey\'s switch)', () {
      expect(
        categoryIconFor(categoryKey: 'PEDICURE', categoryName: null),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('legacy slug BODY with no matching name falls all the way to the '
        'fallback', () {
      expect(
        categoryIconFor(categoryKey: 'BODY', categoryName: null),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('an unrecognised key DOES fall through to a matching name — proves '
        'the two-stage fallthrough is genuinely reachable, not merely '
        'declared', () {
      expect(
        categoryIconFor(categoryKey: 'PEDICURE', categoryName: 'педикюр'),
        BeauticaAssetIcons.categoryPodology,
        reason:
            'Stage 1 must return null for "PEDICURE" (not a registered '
            'slug), handing control to Stage 2, which matches "педикюр"',
      );
    });
  });

  // ── null / empty inputs ───────────────────────────────────────────────────

  group('categoryIconFor — null / empty inputs never throw', () {
    test('both null resolves to the fallback, no throw', () {
      expect(
        () => categoryIconFor(categoryKey: null, categoryName: null),
        returnsNormally,
      );
      expect(
        categoryIconFor(categoryKey: null, categoryName: null),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('both empty strings resolves to the fallback, no throw', () {
      expect(
        categoryIconFor(categoryKey: '', categoryName: ''),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('null key + empty name resolves to the fallback, no throw', () {
      expect(
        categoryIconFor(categoryKey: null, categoryName: ''),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('empty key + null name resolves to the fallback, no throw', () {
      expect(
        categoryIconFor(categoryKey: '', categoryName: null),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('no arguments at all (both default to null) resolves to fallback', () {
      expect(categoryIconFor(), BeauticaAssetIcons.categoryCosmetology);
    });
  });

  // ── Adversarial strings ───────────────────────────────────────────────────

  group('categoryIconFor — adversarial input never throws', () {
    test(
      'a 100,000-character categoryKey resolves to the fallback, no throw',
      () {
        final String huge = 'X' * 100000;
        expect(() => categoryIconFor(categoryKey: huge), returnsNormally);
        expect(
          categoryIconFor(categoryKey: huge),
          BeauticaAssetIcons.categoryCosmetology,
        );
      },
    );

    test(
      'a 100,000-character categoryName resolves to the fallback, no throw',
      () {
        final String huge = 'я' * 100000; // Cyrillic, so toLowerCase() runs
        expect(() => categoryIconFor(categoryName: huge), returnsNormally);
        expect(
          categoryIconFor(categoryName: huge),
          BeauticaAssetIcons.categoryCosmetology,
        );
      },
    );

    test('emoji-only categoryKey and categoryName resolve to the fallback', () {
      expect(
        () => categoryIconFor(
          categoryKey: '💅💇‍♀️🔥',
          categoryName: '💅💇‍♀️🔥',
        ),
        returnsNormally,
      );
      expect(
        categoryIconFor(categoryKey: '💅💇‍♀️🔥', categoryName: '💅💇‍♀️🔥'),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('RTL text (Arabic) as both categoryKey and categoryName resolves to '
        'the fallback, no throw', () {
      const String rtl = 'صالون تجميل';
      expect(
        () => categoryIconFor(categoryKey: rtl, categoryName: rtl),
        returnsNormally,
      );
      expect(
        categoryIconFor(categoryKey: rtl, categoryName: rtl),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });

    test('mixed control characters / null bytes / newlines never throw', () {
      const String weird = 'NAIL_SERVICE \n\t\r';
      expect(() => categoryIconFor(categoryKey: weird), returnsNormally);
      // Not an exact match against the registered slug (extra bytes), so
      // this must fall through to the fallback rather than crash.
      expect(
        categoryIconFor(categoryKey: weird),
        BeauticaAssetIcons.categoryCosmetology,
      );
    });
  });

  // ── Totality: the resolver NEVER returns a path outside the 20 real ──────
  //              registered/bundled assets — the security-load-bearing group.

  group('categoryIconFor — totality: every returned path is a real, registered '
      'asset (mobile-security LOW closure)', () {
    /// The full battery: every known slug, every legacy/unknown slug, null/
    /// empty combinations, and the adversarial strings above — anything
    /// that could plausibly reach this resolver off the wire.
    final List<(String? key, String? name)> battery = <(String?, String?)>[
      for (final String slug in _knownSlugToAsset.keys) (slug, null),
      for (final String slug in _knownSlugToAsset.keys)
        (slug.toLowerCase(), null),
      (null, null),
      ('', ''),
      ('SHAVING', null),
      ('PEDICURE', null),
      ('BODY', null),
      ('FACE', null),
      ('PEDICURE', 'педикюр'),
      ('UNKNOWN_FUTURE_CATEGORY', 'Якась нова категорія'),
      ('X' * 100000, null),
      (null, 'я' * 100000),
      ('💅💇‍♀️🔥', '💅💇‍♀️🔥'),
      ('صالون تجميل', 'صالون تجميل'),
      ('NAIL_SERVICE \n\t\r', null),
      (null, 'манікюр'),
      (null, 'педикюр'),
      (null, 'брови'),
      (null, "ін'єкційна косметологія"),
      (null, 'зовсім невідома категорія'),
    ];

    for (final (String? key, String? name) in battery) {
      final String label = key == null && name == null
          ? '(null, null)'
          : '(${key?.substring(0, key.length.clamp(0, 24))}…, '
                '${name?.substring(0, name.length.clamp(0, 24))}…)';
      test('battery case $label resolves to a registered asset', () {
        final String result = categoryIconFor(
          categoryKey: key,
          categoryName: name,
        );
        expect(
          _registeredCategoryAssets.contains(result),
          isTrue,
          reason:
              'categoryIconFor returned "$result", which is NOT one of '
              'the 20 registered BeauticaAssetIcons.category* constants',
        );
      });
    }

    test('every one of the 20 registered category assets is a real file '
        'bundled under assets/icons/ (catches a typo\'d/missing SVG the '
        'Dart type system cannot)', () {
      for (final String assetPath in _registeredCategoryAssets) {
        expect(
          File(assetPath).existsSync(),
          isTrue,
          reason:
              '$assetPath is registered on BeauticaAssetIcons but no '
              'such file exists on disk',
        );
      }
    });
  });
}
