// Phase 422 QA — guard: the app targets API 36 and nothing opts back out of
// the Android 16 behaviours that come with it.
//
//   1. `android/app/build.gradle.kts` declares exactly ONE active
//      `targetSdk = 36`. Play rejects uploads below API 36 from 2026-08-31,
//      and 409's `verify_release_aab.sh` rule 3 only runs on a built AAB — this
//      catches a downgrade on every PR, in milliseconds.
//   2. No `windowOptOutEdgeToEdgeEnforcement` anywhere under `android/app/src/`.
//      It is ignored on Android 16 at targetSdk 36, so a reintroduced opt-out
//      would make API 35 devices render differently from API 36 ones (D1:
//      edge-to-edge is the single behaviour on every API level).
//   3. No `enableOnBackInvokedCallback="false"` under `android/app/src/` (D3:
//      predictive back stays ON; the opt-out is a fallback that must be
//      recorded as a finding, not slipped in).
//   4. No `WillPopScope` in `lib/` (D3; deprecated, and it disables predictive
//      back for the route it wraps).
//
// Baselines are EMPTY on the real tree with no allow-list (M16). Each rule's
// detector is also run against a synthetic defect so a broken regex cannot
// turn the guard into decoration.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const int kRequiredTargetSdk = 36;

/// Strips `//` line comments and `/* */` block comments (Kotlin DSL).
String stripKotlinComments(String text) => text
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((String l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

/// Every active `targetSdk = N` assignment's N, in file order.
List<int> targetSdkValues(String gradleKts) =>
    RegExp(r'\btargetSdk\s*=\s*(\d+)')
        .allMatches(stripKotlinComments(gradleKts))
        .map((RegExpMatch m) => int.parse(m.group(1)!))
        .toList();

/// `path:line` for every line of [text] containing [needle].
List<String> hits(String text, String needle, String path) {
  final List<String> out = <String>[];
  final List<String> lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].contains(needle)) out.add('$path:${i + 1}');
  }
  return out;
}

final RegExp _predictiveBackOptOut = RegExp(
  r'''enableOnBackInvokedCallback\s*=\s*["']false["']''',
);

List<String> scanTree(
  String root,
  bool Function(String path) include,
  List<String> Function(String text, String path) detect,
) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in Directory(
    root,
  ).listSync(recursive: true, followLinks: false)) {
    if (e is! File || !include(e.path)) continue;
    final String text;
    try {
      text = e.readAsStringSync();
    } on FileSystemException {
      continue; // binary resource (png, jks, …) — cannot carry the attribute
    }
    out.addAll(detect(text, e.path));
  }
  return out;
}

bool _isResourceOrManifest(String p) =>
    p.endsWith('.xml') || p.endsWith('.kt') || p.endsWith('.java');

void main() {
  group('detectors catch a reintroduced defect (self-test)', () {
    test('targetSdk parser reads the active value and ignores comments', () {
      expect(targetSdkValues('android {\n  targetSdk = 35\n}'), <int>[35]);
      expect(
        targetSdkValues(
          '// targetSdk = 36\n/* targetSdk = 36 */\ntargetSdk=35',
        ),
        <int>[35],
      );
      expect(targetSdkValues('targetSdk = flutter.targetSdkVersion'), isEmpty);
    });

    test('opt-out detectors fire on the attribute', () {
      expect(
        hits(
          '<item name="android:windowOptOutEdgeToEdgeEnforcement">true</item>',
          'windowOptOutEdgeToEdgeEnforcement',
          's.xml',
        ),
        <String>['s.xml:1'],
      );
      expect(
        _predictiveBackOptOut.hasMatch(
          'android:enableOnBackInvokedCallback="false"',
        ),
        isTrue,
      );
      expect(
        _predictiveBackOptOut.hasMatch(
          'android:enableOnBackInvokedCallback="true"',
        ),
        isFalse,
      );
    });
  });

  group('real tree (phase 422)', () {
    test(
      'android/app/build.gradle.kts declares exactly one targetSdk = 36',
      () {
        final String kts = File(
          'android/app/build.gradle.kts',
        ).readAsStringSync();
        expect(
          targetSdkValues(kts),
          <int>[kRequiredTargetSdk],
          reason:
              'Play requires API $kRequiredTargetSdk for new apps and updates '
              'from 2026-08-31 (phase 422); a literal so a Flutter-default '
              'drift cannot lower it silently',
        );
      },
    );

    test('no windowOptOutEdgeToEdgeEnforcement under android/app/src/', () {
      expect(
        scanTree(
          'android/app/src',
          _isResourceOrManifest,
          (String t, String p) =>
              hits(t, 'windowOptOutEdgeToEdgeEnforcement', p),
        ),
        isEmpty,
        reason:
            'edge-to-edge is the single behaviour on every API level (422 '
            'D1); the opt-out is ignored on Android 16 anyway',
      );
    });

    test('predictive back is not opted out under android/app/src/', () {
      expect(
        scanTree('android/app/src', _isResourceOrManifest, (
          String t,
          String p,
        ) {
          return _predictiveBackOptOut.hasMatch(t) ? <String>[p] : <String>[];
        }),
        isEmpty,
        reason:
            '422 D3: predictive back stays enabled; the opt-out is a '
            'recorded-finding fallback only',
      );
    });

    test('no WillPopScope in lib/', () {
      expect(
        scanTree(
          'lib',
          (String p) => p.endsWith('.dart'),
          (String t, String p) => hits(t, 'WillPopScope', p),
        ),
        isEmpty,
        reason: '422 D3: use PopScope; WillPopScope disables predictive back',
      );
    });
  });
}
