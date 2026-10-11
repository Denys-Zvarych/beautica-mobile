// Phase 077 (A4) regression: documentation must never ship inside the APK.
//
// `assets/icons/README.md` and `assets/lottie/README.md` were bundled because
// pubspec declares whole directories (`- assets/icons/`), so ANY file dropped
// in is shipped. They now live under `tool/asset_docs/`. This test reads the
// directories pubspec actually bundles and fails if a README, a hidden file or
// any extension outside the runtime-asset allow-list appears there again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Extensions the app loads at runtime from a bundled asset directory.
/// Adding a new kind of asset is a deliberate edit to this set.
const Set<String> _runtimeAssetExtensions = <String>{
  'ttf',
  'svg',
  'json',
  'pem',
};

/// The `flutter: assets:` entries of pubspec.yaml (comments ignored).
List<String> _declaredAssets() {
  final List<String> lines = File('pubspec.yaml').readAsLinesSync();
  final int flutterAt = lines.indexWhere((String l) => l == 'flutter:');
  expect(flutterAt, greaterThanOrEqualTo(0), reason: 'no flutter: section');
  final int assetsAt = lines.indexWhere(
    (String l) => l == '  assets:',
    flutterAt,
  );
  expect(assetsAt, greaterThanOrEqualTo(0), reason: 'no flutter.assets');
  final RegExp entry = RegExp(r'^    - (\S+)\s*$');
  final List<String> out = <String>[];
  for (final String l in lines.skip(assetsAt + 1)) {
    final String t = l.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final RegExpMatch? m = entry.firstMatch(l);
    if (m == null) break; // next pubspec key
    out.add(m.group(1)!);
  }
  return out;
}

void main() {
  test('pubspec declares the expected asset directories', () {
    expect(
      _declaredAssets(),
      containsAll(<String>[
        'assets/fonts/',
        'assets/lottie/',
        'assets/certs/',
        'assets/icons/',
      ]),
    );
  });

  test('no README, hidden or non-runtime file sits in a bundled asset dir', () {
    final List<String> offenders = <String>[];
    for (final String decl in _declaredAssets()) {
      if (!decl.endsWith('/')) {
        // A single-file entry must itself be a runtime asset.
        final String ext = decl.split('.').last.toLowerCase();
        if (!_runtimeAssetExtensions.contains(ext)) offenders.add(decl);
        continue;
      }
      final Directory dir = Directory(decl);
      expect(dir.existsSync(), isTrue, reason: '$decl declared but missing');
      // Flutter bundles a declared directory NON-recursively, but flag
      // subdirectory contents too: they are one pubspec line from shipping.
      for (final FileSystemEntity f in dir.listSync(recursive: true)) {
        if (f is! File) continue;
        final String name = f.uri.pathSegments.last;
        final String ext = name.contains('.')
            ? name.split('.').last.toLowerCase()
            : '';
        if (name.startsWith('.') ||
            name.toUpperCase().startsWith('README') ||
            !_runtimeAssetExtensions.contains(ext)) {
          offenders.add(f.path);
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'documentation / non-runtime files would ship in the APK. Move docs '
          'to tool/asset_docs/: $offenders',
    );
  });
}
