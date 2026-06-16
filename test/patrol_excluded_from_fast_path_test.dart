// Phase 17.5 — META-TEST: patrol native tests stay OFF the fast headless path.
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 17.5 added native-instrumentation E2E tests under
// `integration_test/patrol/`. They compile and run ONLY under patrol's native
// runner (`patrol test` + PatrolJUnitRunner) on an emulator — NEVER under
// `flutter test`. Two invariants keep them off the fast jobs:
//
//   1. The aggregator `integration_test/all_tests.dart` must NOT import any
//      `integration_test/patrol/**` file. If it did, the fast headless job
//      (`flutter test integration_test/all_tests.dart`) would try to compile the
//      patrol binding (`package:patrol/...` + `$.platform.mobile.*`), which has
//      no headless backing — the fast path would break.
//
//   2. The Phase 17.3 aggregator wiring guard
//      (`test/integration_aggregator_meta_test.dart`) enumerates runnable flow
//      files via `Directory('integration_test').listSync()` (NON-recursive) and
//      demands each be imported by `all_tests.dart`. That guard currently
//      excludes `patrol/` ONLY because `listSync()` is non-recursive and
//      `.whereType<File>()` drops the `patrol/` subdirectory. That exclusion is
//      IMPLICIT: a future refactor to `listSync(recursive: true)` would silently
//      start demanding the patrol files be aggregated into the fast path —
//      breaking it. This test makes the exclusion EXPLICIT and load-bearing, so
//      such a refactor fails here first.
//
// Pure file-IO (no widgets, no emulator) — runs in the cheap unit job alongside
// the Phase 17.3 guard, gating BOTH failure modes before the emulator job is
// scheduled.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final Directory patrolDir = Directory('integration_test/patrol');
  final File aggregator = File('integration_test/all_tests.dart');

  group('patrol tests excluded from the fast headless path', () {
    test('patrol/ directory and its runnable tests exist', () {
      // Sanity: if the folder were moved/renamed, the contains() checks below
      // would vacuously pass. Anchor on the known Phase 17.5 layout.
      expect(
        patrolDir.existsSync(),
        isTrue,
        reason: 'integration_test/patrol/ must exist (Phase 17.5)',
      );

      final List<String> patrolTestFiles = _patrolTestFileNames(patrolDir);
      expect(
        patrolTestFiles,
        isNotEmpty,
        reason:
            'expected at least one *_test.dart under integration_test/patrol/',
      );
    });

    test('all_tests.dart imports NONE of the patrol test files', () {
      expect(
        aggregator.existsSync(),
        isTrue,
        reason: 'integration_test/all_tests.dart must exist',
      );

      final String aggregatorSrc = aggregator.readAsStringSync();
      final List<String> patrolTestFiles = _patrolTestFileNames(patrolDir);

      // The aggregator imports flow files by their bare relative path
      // (e.g. 'auth_login_flow_test.dart'). A patrol import would reference the
      // patrol/ subpath. Catch BOTH the bare filename and the patrol/ path form,
      // so neither `import 'patrol/x_test.dart'` nor an accidental same-named
      // bare import slips a patrol binding onto the fast path.
      final List<String> leaked = <String>[
        for (final String name in patrolTestFiles)
          if (aggregatorSrc.contains("'patrol/$name'") ||
              aggregatorSrc.contains("'$name'"))
            name,
      ];

      expect(
        leaked,
        isEmpty,
        reason:
            'all_tests.dart (the FAST headless path) imports these patrol '
            'native tests: $leaked. Patrol tests need native instrumentation '
            'and have no headless backing — they must run ONLY via the nightly '
            '`patrol test` job. Remove the import(s) from all_tests.dart.',
      );

      // The aggregator must not pull the whole patrol/ folder in either.
      expect(
        aggregatorSrc.contains("patrol/"),
        isFalse,
        reason:
            'all_tests.dart references the patrol/ folder; it must not — patrol '
            'tests are native-only and excluded from the fast headless path.',
      );
    });

    test('aggregator wiring guard glob does NOT pick up patrol test files', () {
      // This locks in the IMPLICIT exclusion the Phase 17.3 guard relies on:
      // a NON-recursive top-level scan of integration_test/ that drops the
      // patrol/ subdirectory. We replicate that scan here and assert no patrol
      // file appears. If someone changes the 17.3 guard to a recursive scan
      // (which would falsely demand patrol files be aggregated into the fast
      // path), this test fails — surfacing the regression in the cheap job.
      final Directory integrationDir = Directory('integration_test');

      final List<String> topLevelTestFiles =
          integrationDir
              .listSync() // NON-recursive — must mirror the 17.3 guard.
              .whereType<File>()
              .map((File f) => f.uri.pathSegments.last)
              .where((String name) => name.endsWith('_test.dart'))
              .toList()
            ..sort();

      final Set<String> patrolNames = _patrolTestFileNames(patrolDir).toSet();

      final List<String> overlap = <String>[
        for (final String name in topLevelTestFiles)
          if (patrolNames.contains(name)) name,
      ];

      expect(
        overlap,
        isEmpty,
        reason:
            'the non-recursive integration_test/ scan picked up patrol test '
            'files: $overlap. The Phase 17.3 aggregator guard would then '
            'FALSELY demand they be imported into all_tests.dart (the fast '
            'headless path), which cannot compile them. Keep the scan '
            'non-recursive and patrol tests under integration_test/patrol/.',
      );
    });
  });
}

/// Runnable patrol test file names (top-level `*_test.dart` under patrol/).
List<String> _patrolTestFileNames(Directory patrolDir) =>
    patrolDir
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String name) => name.endsWith('_test.dart'))
        .toList()
      ..sort();
