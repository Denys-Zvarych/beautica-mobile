// Pins that every `scripts/forbid_*.sh` drift-prevention gate is actually
// WIRED into `pr-validate.yml` — both its plain (enforcing) invocation and its
// `--self-test` invocation.
//
// THE HOLE THIS CLOSES
// --------------------
// Each `forbid_*.sh` script is only load-bearing if CI actually runs it. A
// script that exists on disk with a correct, tested `--self-test` mode but
// is never invoked from the workflow is fail-OPEN, not fail-closed: nothing
// stops the exact defect it was written to catch from landing on `main`,
// and — because the script still runs cleanly by hand — it is easy to
// mistake for "covered" during review. Equally, a script that IS run for
// enforcement but whose `--self-test` is never wired into the "Self-test
// drift-prevention gates" step can silently regress its own detection logic
// (an edit that breaks the annotation/comment handling would only be caught
// by luck, not by CI).
//
// This is enumerated from DISK (`scripts/forbid_*.sh`), not from a hand-kept
// list in this file, so a newly added gate is covered automatically the day
// it is added — the same self-updating property `forbid_stale_future_date_fixture.sh`
// and its siblings rely on for their own scan roots.
//
// 2026-08-02: written alongside `scripts/forbid_host_local_instant_anchor.sh`.
// Running this test against the tree BEFORE that gate was wired in surfaced
// two pre-existing, genuinely unwired scripts —
// `scripts/forbid_cycle_stub_in_tests.sh` and
// `scripts/forbid_provider_self_invalidation.sh` — both enforced in CI but
// with their `--self-test` mode never added to the "Self-test
// drift-prevention gates" step. Both were fixed in the same change that
// added this test (backlog :413 territory) rather than allow-listed here;
// this file has no exemption mechanism by design — see "NO ALLOW-LIST" below.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final File _workflow = File('.github/workflows/pr-validate.yml');
final Directory _scriptsDir = Directory('scripts');

/// True when some INVOCATION of `./scripts/<name>` in [yaml] is not directly
/// followed by the `--self-test` flag — i.e. a genuine enforcing invocation,
/// not the self-test-only one.
///
/// Invocation-anchored (not line-anchored, and not `yaml.contains(...)`)
/// deliberately, on two counts:
///   - A plain `yaml.contains('./scripts/$name')` substring check also
///     matches INSIDE the `--self-test` invocation (`./scripts/$name
///     --self-test` contains `./scripts/$name` as a substring), so a script
///     wired ONLY via `--self-test` would false-pass the "is it enforced"
///     check.
///   - A LINE-anchored check (matching the whole line, then asking whether
///     the whole line contains `--self-test` anywhere) over-reaches the
///     other way: a single line chaining a plain invocation with a
///     `--self-test` invocation (`./scripts/x.sh && ./scripts/x.sh
///     --self-test`) would wrongly disqualify the plain occurrence, and a
///     trailing comment merely mentioning `--self-test` in prose
///     (`./scripts/x.sh  # see --self-test for the drift check`) would
///     wrongly disqualify a genuine plain invocation too.
/// Matching the invocation itself and inspecting only the token that
/// immediately follows it avoids both: each occurrence of `./scripts/<name>`
/// is judged solely by what comes directly after THAT occurrence.
///
/// `(?=\s|$)` after the script name is a lookahead boundary (not consumed)
/// so a shorter name never matches as a prefix of a longer sibling
/// (`forbid_x.sh` vs. `forbid_x_extra.sh`), while still leaving the next
/// group free to capture the flag/token that immediately follows.
bool _isPlainlyInvoked(String yaml, String name) {
  final RegExp invocation = RegExp(
    r'\./scripts/' + RegExp.escape(name) + r'(?=\s|$)[ \t]*(\S*)',
  );
  return invocation.allMatches(yaml).any((match) {
    final String nextToken = match.group(1) ?? '';
    return nextToken != '--self-test';
  });
}

void main() {
  group('every scripts/forbid_*.sh gate is wired into pr-validate.yml', () {
    late final String yaml;
    late final List<String> scriptNames;

    setUpAll(() {
      expect(
        _workflow.existsSync(),
        isTrue,
        reason: '${_workflow.path} not found — run from the package root.',
      );
      expect(
        _scriptsDir.existsSync(),
        isTrue,
        reason: '${_scriptsDir.path} not found — run from the package root.',
      );
      yaml = _workflow.readAsStringSync();

      // Enumerated from disk, not hand-maintained — see file header.
      scriptNames =
          _scriptsDir
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where(
                (name) => name.startsWith('forbid_') && name.endsWith('.sh'),
              )
              .toList()
            ..sort();

      // A change here means the enumeration itself broke, not that there are
      // no gates — fail loudly rather than let every per-script test below
      // vacuously pass on an empty list.
      expect(
        scriptNames,
        isNotEmpty,
        reason:
            'No scripts/forbid_*.sh files found on disk. Either the drift-'
            'prevention gates were all deleted (unlikely) or this test is '
            'being run from the wrong working directory.',
      );
    });

    // NO ALLOW-LIST, BY DESIGN. Every forbid_*.sh gate found on disk is
    // asserted here with no exemption mechanism. A gate that legitimately
    // does not need CI wiring should not exist as a `scripts/forbid_*.sh`
    // file at all (that naming + location IS the "this is a CI gate"
    // contract every sibling script upholds) — it belongs somewhere else, or
    // should be deleted.
    test('each gate is both enforced and self-tested from pr-validate.yml', () {
      final List<String> missingEnforcement = <String>[];
      final List<String> missingSelfTest = <String>[];

      for (final name in scriptNames) {
        final String selfTestInvocation = './scripts/$name --self-test';

        if (!_isPlainlyInvoked(yaml, name)) {
          missingEnforcement.add(name);
        }
        if (!yaml.contains(selfTestInvocation)) {
          missingSelfTest.add(name);
        }
      }

      expect(
        missingEnforcement,
        isEmpty,
        reason:
            'The following scripts/forbid_*.sh gates exist on disk but are '
            'NEVER invoked (plain, enforcing form) from pr-validate.yml, so '
            'they cannot block anything in CI: $missingEnforcement. Add a '
            "step running './scripts/<name>'.",
      );
      expect(
        missingSelfTest,
        isEmpty,
        reason:
            'The following scripts/forbid_*.sh gates are enforced in CI but '
            'their `--self-test` mode is never invoked from pr-validate.yml '
            '(the "Self-test drift-prevention gates" step), so a regression '
            'in their own detection logic (annotation handling, comment '
            'stripping, …) would not be caught by CI: $missingSelfTest. Add '
            "'./scripts/<name> --self-test' to that step.",
      );
    });
  });
}
