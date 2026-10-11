// Regression test for the bundled-font crash fixed on 2026-06-03.
//
// THE BUG
// -------
// The app requested Nunito weights w400 (Regular) and w800 (ExtraBold) — via
// `GoogleFonts.nunitoTextTheme()` (app_theme.dart, Material roles at w400 plus
// the M3 w500 roles remapped to w600 by `_nunitoTextTheme`) and the
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
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:beautica_mobile/core/theme/app_theme.dart';
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
///   - app_theme.dart _nunitoTextTheme()                            -> Nunito w400 + w600
///     (M3 w500 roles remapped to w600; Nunito w500 is NOT bundled)
///   - velvet_text.dart (body/input/label/link/feedback/statCaption) -> Nunito w600/w700
///   - velvet_text.dart:321 (_pillStyle)                            -> Nunito w800
///   - velvet_field.dart:110 / service_form.dart:653                -> Nunito w800
///   - velvet_text.dart (wordmark/heading/cta/displayName/...)      -> Comfortaa w700
///   - velvet_text.dart (subheading/sectionLabel)                   -> Comfortaa w600
///   - registration_progress.dart:319                              -> Comfortaa w600
///   - main.dart:91-102 pre-warm block                            -> all of the above
const List<_RequestedFont> _requestedFonts = <_RequestedFont>[
  _RequestedFont('Nunito', FontWeight.w400, 'nunitoTextTheme Material roles'),
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
        // (app_theme.dart -> _nunitoTextTheme), not via VelvetText.
        final textTheme = velvetTheme().textTheme;

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

  // ───────────────────────────────────────────────────────────────────────────
  // Layer 4 — glyph coverage of the SUBSET fonts (phase 077 audit N1).
  //
  // The bundled TTFs are fonttools subsets of the originals. User content
  // (salon / master / review text) can contain any Latin-script name, so the
  // subset must keep Latin Extended-A/B/Additional, € and the Ukrainian set.
  // Re-subset FROM THE ORIGINAL full TTFs (git show HEAD:...), never from an
  // already-subset file. A codepoint missing from the cmap renders as tofu or
  // a fallback-font glyph.
  // ───────────────────────────────────────────────────────────────────────────
  group('bundled TTFs keep the glyph coverage user content needs', () {
    // ł ș ț č ő ğ ą € ₴ і ї є ґ № + Vietnamese ế + Turkish ı İ + Romanian ă â
    // + U+02BC (ʼ, the Ukrainian apostrophe used in words like «м'який»).
    const String representative =
        '\u0142\u0219\u021B\u010D\u0151\u011F\u0105\u20AC\u20B4'
        '\u0456\u0457\u0454\u0491\u2116\u1EBF\u0131\u0130\u0103\u00E2'
        '\u02BC';
    final Set<int> required = <int>{
      for (int c = 0x20; c <= 0x7E; c++) c, // Basic Latin
      ...representative.runes,
    };

    for (final String name in <String>[
      'Comfortaa-SemiBold',
      'Comfortaa-Bold',
      'Nunito-Regular',
      'Nunito-SemiBold',
      'Nunito-Bold',
      'Nunito-ExtraBold',
    ]) {
      test('$name.ttf cmap contains the representative set', () {
        final Set<int> cmap = _readCmap(
          File('assets/fonts/$name.ttf').readAsBytesSync(),
        );
        final List<String> missing = <String>[
          for (final int c in required.toList()..sort())
            if (!cmap.contains(c))
              'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}',
        ];
        expect(missing, isEmpty, reason: '$name.ttf lacks $missing');
      });
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Layer 3 — no explicit lib/ usage requests an unbundled weight.
  //
  // Bundled: Comfortaa w600/w700, Nunito w400/w600/w700/w800. Nothing may ask
  // for w100/w200/w300/w500/w900. (Also enforced by
  // scripts/forbid_unbundled_font_weight.sh; this keeps it in `flutter test`.)
  // ───────────────────────────────────────────────────────────────────────────
  test('no lib/ file requests an unbundled FontWeight', () {
    final RegExp bad = RegExp(r'FontWeight\.w(100|200|300|500|900)\b');
    final List<String> hits = <String>[];
    for (final FileSystemEntity f in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.startsWith('lib/api/')) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (bad.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: 'unbundled weights requested: $hits');
  });
}

/// Minimal sfnt `cmap` reader (formats 4 and 12) returning every mapped
/// codepoint. Enough for Unicode BMP / full-repertoire subtables.
Set<int> _readCmap(Uint8List bytes) {
  final ByteData d = ByteData.sublistView(bytes);
  final int numTables = d.getUint16(4);
  int cmapOff = -1;
  for (int i = 0; i < numTables; i++) {
    final int rec = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(rec, rec + 4)) == 'cmap') {
      cmapOff = d.getUint32(rec + 8);
    }
  }
  expect(cmapOff, greaterThanOrEqualTo(0), reason: 'no cmap table');
  final int subCount = d.getUint16(cmapOff + 2);
  final Set<int> out = <int>{};
  for (int i = 0; i < subCount; i++) {
    final int sub = cmapOff + d.getUint32(cmapOff + 4 + i * 8 + 4);
    final int format = d.getUint16(sub);
    if (format == 4) {
      final int segX2 = d.getUint16(sub + 6);
      final int endBase = sub + 14;
      final int startBase = endBase + segX2 + 2;
      for (int s = 0; s < segX2 ~/ 2; s++) {
        final int end = d.getUint16(endBase + s * 2);
        final int start = d.getUint16(startBase + s * 2);
        if (start == 0xFFFF) continue;
        for (int c = start; c <= end; c++) {
          out.add(c);
        }
      }
    } else if (format == 12) {
      final int groups = d.getUint32(sub + 12);
      for (int g = 0; g < groups; g++) {
        final int o = sub + 16 + g * 12;
        for (int c = d.getUint32(o); c <= d.getUint32(o + 4); c++) {
          out.add(c);
        }
      }
    }
  }
  return out;
}
