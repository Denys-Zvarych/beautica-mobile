// Regression test for the bundled-font crash fixed on 2026-06-03.
//
// THE BUG
// -------
// The app requested Nunito weights w400 (Regular) and w800 (ExtraBold) — via
// `GoogleFonts.nunitoTextTheme()` (app_theme.dart:25, defaults to w400) and the
// w800 pill / field-accent / form-caption styles (velvet_text.dart:321,
// velvet_field.dart:110, service_form.dart:653) — but the matching TTFs were
// NOT bundled under assets/fonts/. With `GoogleFonts.config.allowRuntimeFetching
// = false` (main.dart:79), google_fonts cannot fall back to a network fetch, so
// `loadFontIfNecessary` throws an unhandled `Exception` on device the first time
// one of those weights is painted.
//
// THE GUARD (two complementary layers)
// ------------------------------------
//   1. Static asset-existence test — fast, deterministic, no Flutter binding.
//      Enumerates every (family, weight) the app requests and asserts a matching
//      bundled `assets/fonts/<Family>-<Suffix>.ttf` exists on disk. This FAILS if
//      any TTF is missing — i.e. it would have failed before the fix because
//      Nunito-Regular.ttf and Nunito-ExtraBold.ttf were absent.
//
//   2. Runtime resolution test — defense in depth. With runtime fetching
//      disabled (the on-device config), it instantiates every requested style
//      and `VelvetText.*` accessor, then awaits `GoogleFonts.pendingFonts()` and
//      asserts it completes without throwing. This reproduces the exact on-device
//      failure mode inside a widget test: google_fonts resolves each (family,
//      weight) against the test asset bundle and rethrows the missing-asset
//      `Exception` through the pending future.
//
// If you add a new (family, weight) tuple to the app, add it to
// `_requestedFonts` below or this test will not protect it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// One (family, weight) tuple the production app requests from google_fonts.
class _RequestedFont {
  const _RequestedFont(this.family, this.weight, this.usedBy);

  final String family;
  final FontWeight weight;

  /// Human-readable note of where this weight is consumed — surfaces in the
  /// failure message so a future dev knows which call site breaks.
  final String usedBy;

  /// google_fonts derives the bundled filename from the family + a weight-name
  /// suffix (see `findFamilyWithVariantAssetPath` in google_fonts_base.dart,
  /// which matches asset paths against `<Family>-<WeightName>`). The asset file
  /// must therefore be `assets/fonts/<Family>-<suffix>.ttf`.
  String get assetFileName => '$family-${_weightSuffix(weight)}.ttf';

  @override
  String toString() =>
      '$family ${_weightSuffix(weight)} (w${weight.value}) — $usedBy';
}

/// Maps a [FontWeight] to the google_fonts filename suffix.
/// w400 -> Regular, w600 -> SemiBold, w700 -> Bold, w800 -> ExtraBold.
String _weightSuffix(FontWeight w) {
  switch (w.value) {
    case 400:
      return 'Regular';
    case 500:
      return 'Medium';
    case 600:
      return 'SemiBold';
    case 700:
      return 'Bold';
    case 800:
      return 'ExtraBold';
    default:
      throw ArgumentError(
        'No google_fonts filename suffix mapped for w${w.value}',
      );
  }
}

/// The complete set of (family, weight) tuples the production app paints.
///
/// Cross-referenced against:
///   - app_theme.dart:25            GoogleFonts.nunitoTextTheme()  -> Nunito w400
///   - velvet_text.dart (body/input/label/link/feedback/statCaption) -> Nunito w600/w700
///   - velvet_text.dart:321 (_pillStyle)                            -> Nunito w800
///   - velvet_field.dart:110 / service_form.dart:653                -> Nunito w800
///   - velvet_text.dart (wordmark/heading/cta/displayName/...)      -> Comfortaa w700
///   - velvet_text.dart (subheading/sectionLabel)                   -> Comfortaa w600
///   - registration_progress.dart:319                              -> Comfortaa w600
///   - main.dart:91-102 pre-warm block                            -> all of the above
const List<_RequestedFont> _requestedFonts = <_RequestedFont>[
  _RequestedFont('Nunito', FontWeight.w400, 'nunitoTextTheme default body'),
  _RequestedFont('Nunito', FontWeight.w600, 'VelvetText.body / input'),
  _RequestedFont(
    'Nunito',
    FontWeight.w700,
    'VelvetText.bodyStrong / label / link / feedback',
  ),
  _RequestedFont(
    'Nunito',
    FontWeight.w800,
    'VelvetText.pill / field accent / form caption',
  ),
  _RequestedFont(
    'Comfortaa',
    FontWeight.w600,
    'VelvetText.subheading / sectionLabel',
  ),
  _RequestedFont(
    'Comfortaa',
    FontWeight.w700,
    'VelvetText.wordmark / heading / cta / displayName',
  ),
];

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // Layer 1 — Static asset-existence test (primary, deterministic, fast).
  //
  // Reads files directly from the repo's assets/fonts/ directory via dart:io.
  // No Flutter binding, no font loading — just a filesystem existence check.
  // Would have FAILED before the fix: Nunito-Regular.ttf and
  // Nunito-ExtraBold.ttf did not exist on disk.
  // ───────────────────────────────────────────────────────────────────────────
  group('bundled font assets exist for every requested (family, weight)', () {
    // Tests run with CWD = package root (beautica-mobile/), so this is the
    // on-disk fonts directory declared in pubspec under flutter: assets.
    final Directory fontsDir = Directory('assets/fonts');

    test('assets/fonts/ directory exists', () {
      expect(
        fontsDir.existsSync(),
        isTrue,
        reason: 'assets/fonts/ must exist and be declared in pubspec.yaml',
      );
    });

    for (final font in _requestedFonts) {
      test('${font.assetFileName} is bundled (for $font)', () {
        final File ttf = File('${fontsDir.path}/${font.assetFileName}');
        expect(
          ttf.existsSync(),
          isTrue,
          reason:
              'The app requests $font but assets/fonts/${font.assetFileName} '
              'is missing. With allowRuntimeFetching=false this throws an '
              'unhandled runtime exception on device the first time the weight '
              'is painted. Add the TTF under assets/fonts/.',
        );
        // A zero-byte placeholder would pass existence but fail to load on
        // device, so assert the file actually has glyph data.
        expect(
          ttf.lengthSync(),
          greaterThan(1024),
          reason:
              'assets/fonts/${font.assetFileName} exists but looks empty / '
              'truncated — it would fail to load on device.',
        );
      });
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Layer 2 — Runtime resolution test (defense in depth).
  //
  // Reproduces the exact on-device failure mode: with runtime fetching
  // disabled, instantiate every requested style + VelvetText.* accessor, then
  // await GoogleFonts.pendingFonts(). google_fonts resolves each (family,
  // weight) against the test asset bundle (which carries the pubspec-declared
  // assets/fonts/ TTFs) and rethrows the missing-asset Exception through the
  // pending future. Before the fix this throws; after the fix it completes.
  // ───────────────────────────────────────────────────────────────────────────
  group('GoogleFonts resolves every requested style with runtime fetching off', () {
    setUpAll(() {
      // Mirror the production config (main.dart:79). Never re-enable runtime
      // fetching — doing so would mask the very bug this test guards against.
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    testWidgets(
      'pendingFonts completes without throwing for all app text styles',
      (tester) async {
        // Touch every public VelvetText accessor so each backing
        // GoogleFonts.* style is requested and queued for loading.
        final styles = <TextStyle>[
          // Comfortaa display / heading / CTA family.
          VelvetText.wordmark(),
          VelvetText.heading(),
          VelvetText.subheading(),
          VelvetText.cta(),
          VelvetText.displayName(),
          VelvetText.sectionLabel(),
          VelvetText.statValue(),
          VelvetText.cardTitle(),
          // Nunito body / input / label / link family.
          VelvetText.body(),
          VelvetText.bodyStrong(),
          VelvetText.input(),
          VelvetText.label(),
          VelvetText.link(),
          VelvetText.statCaption(),
          // The two weights that were missing before the fix:
          VelvetText.pill(), // Nunito w800
        ];

        // The Nunito w400 path comes in through the Material text theme
        // (app_theme.dart -> GoogleFonts.nunitoTextTheme), not via VelvetText.
        final textTheme = GoogleFonts.nunitoTextTheme();

        // Explicitly request the four Nunito weights + two Comfortaa weights so
        // the runtime path is exercised even if a VelvetText style is later
        // refactored. Matches the main.dart pre-warm block.
        GoogleFonts.nunito(fontWeight: FontWeight.w400);
        GoogleFonts.nunito(fontWeight: FontWeight.w600);
        GoogleFonts.nunito(fontWeight: FontWeight.w700);
        GoogleFonts.nunito(fontWeight: FontWeight.w800);
        GoogleFonts.comfortaa(fontWeight: FontWeight.w600);
        GoogleFonts.comfortaa(fontWeight: FontWeight.w700);

        // Keep the analyzer from flagging the locals as unused; they exist to
        // force the GoogleFonts.* side-effect that queues each font load.
        expect(styles, isNotEmpty);
        expect(textTheme.bodyLarge, isNotNull);

        // The assertion: every queued (family, weight) must resolve against the
        // bundled assets. If any TTF is missing, pendingFonts rethrows the
        // 'allowRuntimeFetching is false but font ... was not found' Exception.
        await expectLater(GoogleFonts.pendingFonts(), completes);
      },
    );
  });
}
