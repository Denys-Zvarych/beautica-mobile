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

  // ==========================================================================
  // THE SPLIT AGGREGATORS — the half of this gate that was missing.
  //
  // The group above guards `all_tests.dart`. But `all_tests.dart` is NOT what
  // CI runs: at 19 flows a single long-lived `flutter test` process started
  // crashing the emulator at teardown, so CI was moved to
  // `all_tests_part1.dart` + `all_tests_part2.dart` (2026-07-01) and
  // `all_tests.dart` was demoted to a local convenience entrypoint.
  //
  // That left the meta-test guarding the file CI no longer runs. A new flow
  // wired ONLY into `all_tests.dart` passes every check above, passes CI, and
  // never executes there — the exact silent-omission regression this file was
  // written to prevent, reintroduced by the split. `all_tests.dart`'s own
  // header says "update all THREE files together"; this group is what enforces
  // it.
  // ==========================================================================
  group('E2E split aggregators (all_tests_part1/part2) wiring', () {
    final File part1 = File('integration_test/all_tests_part1.dart');
    final File part2 = File('integration_test/all_tests_part2.dart');

    test('both CI entrypoints exist', () {
      expect(
        part1.existsSync(),
        isTrue,
        reason: 'CI runs all_tests_part1.dart',
      );
      expect(
        part2.existsSync(),
        isTrue,
        reason: 'CI runs all_tests_part2.dart',
      );
    });

    test('every flow on disk is run by part1 OR part2 — the entrypoints CI '
        'actually executes', () {
      final List<String> flowFiles =
          integrationDir
              .listSync()
              .whereType<File>()
              .map((File f) => f.uri.pathSegments.last)
              .where((String name) => name.endsWith('_test.dart'))
              .where(
                (String name) =>
                    name != 'all_tests.dart' &&
                    name != 'all_tests_part1.dart' &&
                    name != 'all_tests_part2.dart' &&
                    name != 'test_bundle.dart',
              )
              .toList()
            ..sort();

      expect(flowFiles, isNotEmpty);

      final String src1 = part1.readAsStringSync();
      final String src2 = part2.readAsStringSync();

      final List<String> missing = <String>[
        for (final String flow in flowFiles)
          if (!src1.contains("'$flow'") && !src2.contains("'$flow'")) flow,
      ];

      expect(
        missing,
        isEmpty,
        reason:
            'these flow files are in integration_test/ but are wired into '
            'NEITHER all_tests_part1.dart NOR all_tests_part2.dart, so CI '
            'will not run them (being present in all_tests.dart is NOT '
            'enough — CI stopped running that file): $missing',
      );
    });

    test('no flow is registered in BOTH halves — a duplicate would run twice '
        'and double the emulator cost it was split to avoid', () {
      final RegExp importRe = RegExp(r"import\s+'([a-z0-9_]+_test\.dart)'");
      Set<String> importsOf(File f) => importRe
          .allMatches(f.readAsStringSync())
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      final Set<String> both = importsOf(part1).intersection(importsOf(part2));

      expect(
        both,
        isEmpty,
        reason: 'these flows are wired into both halves of the CI split: $both',
      );
    });

    test('every flow imported by a half is registered in a group() there', () {
      final RegExp importRe = RegExp(
        r"import\s+'([a-z0-9_]+_test\.dart)'\s+as\s+([a-z0-9_]+)\s*;",
      );

      for (final File half in <File>[part1, part2]) {
        final String src = half.readAsStringSync();
        final List<String> unregistered = <String>[
          for (final RegExpMatch m in importRe.allMatches(src))
            if (!src.contains('${m.group(2)}.main')) m.group(1)!,
        ];

        expect(
          unregistered,
          isEmpty,
          reason:
              'imported but never registered via group(..., <alias>.main) in '
              '${half.path}, so they will NOT run: $unregistered',
        );
      }
    });
  });
}
