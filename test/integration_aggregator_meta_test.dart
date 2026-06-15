// Phase 17.3 — META-TEST for the E2E aggregating entrypoint.
//
// WHY THIS FILE EXISTS
// --------------------
// CI used to run E2E flows via a directory GLOB:
//   for f in integration_test/*_test.dart; do flutter test "$f"; done
// The glob auto-discovered any new flow file — drop a `*_flow_test.dart` in and
// CI ran it, no extra wiring.
//
// Phase 17.3 replaced that loop with a SINGLE aggregating entrypoint,
// `integration_test/all_tests.dart`, which imports each flow's `main()` by hand
// and registers it under a `group(...)`. One isolate, one app process — it
// recovers the 5x emulator boot cost (L87) and reports every failure (L88).
//
// THE REGRESSION THIS TEST GUARDS
// -------------------------------
// The aggregator traded the glob's AUTOMATIC discovery for a MANUAL import list.
// Nothing in the toolchain now fails if a future contributor adds
// `integration_test/booking_flow_test.dart` but forgets to wire it into
// `all_tests.dart`: the flow file compiles, CI's single `flutter test
// all_tests.dart` is green, and the new flow simply NEVER RUNS in CI. The gap is
// invisible — exactly the silent-omission failure mode the glob could not have.
//
// This pure-Dart test closes that gap. It enumerates the runnable flow files on
// disk and asserts each one is imported by `all_tests.dart`. It is file-IO only
// (no widgets, no emulator), so it runs in the CHEAP unit job — gating a dropped
// flow BEFORE the expensive emulator job is even scheduled.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Resolve relative to the package root. `flutter test` runs with the package
  // directory as CWD, so these relative paths are stable in CI and locally.
  final Directory integrationDir = Directory('integration_test');
  final File aggregator = File('integration_test/all_tests.dart');

  group('E2E aggregator (all_tests.dart) wiring', () {
    test('directory and aggregator exist', () {
      expect(
        integrationDir.existsSync(),
        isTrue,
        reason: 'integration_test/ directory must exist',
      );
      expect(
        aggregator.existsSync(),
        isTrue,
        reason:
            'integration_test/all_tests.dart aggregating entrypoint must '
            'exist (Phase 17.3)',
      );
    });

    test('every flow *_test.dart on disk is imported by all_tests.dart', () {
      // Runnable flow files: top-level `*_test.dart` in integration_test/,
      // excluding the aggregator itself and anything under support/ (helpers,
      // not runnable tests — they are never top-level entries here anyway).
      final List<String> flowFiles =
          integrationDir
              .listSync()
              .whereType<File>()
              .map((File f) => f.uri.pathSegments.last)
              .where((String name) => name.endsWith('_test.dart'))
              .where((String name) => name != 'all_tests.dart')
              .toList()
            ..sort();

      // Sanity: the directory is not empty (a glob-mismatch or a moved folder
      // would otherwise make this test vacuously pass).
      expect(
        flowFiles,
        isNotEmpty,
        reason: 'expected at least one *_flow_test.dart in integration_test/',
      );

      final String aggregatorSrc = aggregator.readAsStringSync();

      // Each flow must appear as an import target in all_tests.dart. We match on
      // the quoted relative path the import uses (e.g. `'register_flow_test.dart'`)
      // — that is exactly the string the aggregator's `import '<file>' as <alias>`
      // line carries, so a present file with no import line fails here.
      final List<String> missing = <String>[
        for (final String flow in flowFiles)
          if (!aggregatorSrc.contains("'$flow'")) flow,
      ];

      expect(
        missing,
        isEmpty,
        reason:
            'these flow files exist in integration_test/ but are NOT '
            'imported by all_tests.dart, so they will NOT run in CI: $missing. '
            'Add `import \'<file>\' as <alias>;` and a `group(...)` entry.',
      );
    });

    test('every flow imported by all_tests.dart is registered in a group()', () {
      final String src = aggregator.readAsStringSync();

      // Pull `import '<file>' as <alias>;` pairs for flow files only.
      final RegExp importRe = RegExp(
        r"import\s+'([a-z0-9_]+_test\.dart)'\s+as\s+([a-z0-9_]+)\s*;",
      );
      final Iterable<RegExpMatch> imports = importRe.allMatches(src);

      expect(
        imports,
        isNotEmpty,
        reason: 'all_tests.dart imports no flow files',
      );

      // Each imported alias must be wired into a `group(..., <alias>.main)` so an
      // imported-but-unregistered flow (dead import) is also caught.
      final List<String> unregistered = <String>[
        for (final RegExpMatch m in imports)
          if (!src.contains('${m.group(2)}.main')) m.group(1)!,
      ];

      expect(
        unregistered,
        isEmpty,
        reason:
            'these flows are imported but never registered via '
            'group(..., <alias>.main) in all_tests.dart, so they will NOT run: '
            '$unregistered',
      );
    });
  });
}
