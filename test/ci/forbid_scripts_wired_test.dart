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
//
// 2026-08-18: `f9d8c213` retired the 22 hand-written `./scripts/<name>
// --self-test` lines in the "Self-test drift-prevention gates" step and
// replaced them with a single delegated step,
// `./scripts/verify_guards.sh --self-test`. That runner derives its own
// guard list from the SAME `scripts/forbid_*.sh` glob this test enumerates
// from, and only counts a guard as covered when it BOTH exits 0 AND prints
// `SELF-TEST OK: <basename>` — strictly stronger than the line-per-guard
// list it replaced (a newly added guard is auto-enrolled; exit-0-without-
// running-anything no longer passes). Per-script `--self-test` lines are
// therefore gone from the workflow BY DESIGN — do not "restore" them.
//
// Because the per-script lines are gone, `missingSelfTest` below cannot
// just grep for `./scripts/<name> --self-test` in the YAML anymore — that
// would report all guards as unwired. Nor can it accept delegation on the
// strength of the YAML alone (`yaml.contains('verify_guards.sh
// --self-test')`) — that would be exactly the kind of vacuous "the string
// is somewhere in the file" gate this whole suite exists to rule out. A
// guard counts as self-tested if EITHER it still has a direct per-script
// `--self-test` line (kept as an escape hatch, not currently used by any
// guard) OR ALL THREE hold, each asserted on its own below: (1) the
// workflow actually invokes `./scripts/verify_guards.sh --self-test`; (2)
// `scripts/verify_guards.sh` discovers guards via the same `forbid_*.sh`
// glob normal mode uses, not a hand-kept list (so a swap to a hard-coded
// list is caught, not silently accepted); (3) `scripts/verify_guards.sh`
// still requires the `SELF-TEST OK:` sentinel, not exit-code-only (so a
// downgrade back to the weaker check is caught too).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final File _workflow = File('.github/workflows/pr-validate.yml');
final Directory _scriptsDir = Directory('scripts');
final File _verifyGuardsScript = File('scripts/verify_guards.sh');

/// The literal invocation `pr-validate.yml` must contain for the delegated
/// self-test runner to be wired in at all.
const String _delegatedSelfTestInvocation =
    './scripts/verify_guards.sh --self-test';

/// Operational substring (not a comment/prose mention) proving
/// `scripts/verify_guards.sh` discovers guards from the same
/// `scripts/forbid_*.sh` glob normal mode uses, rather than a hand-kept
/// list. Taken verbatim from its `discover_guards` function's `find`
/// invocation — asserting on the operational line, not merely on the
/// substring "forbid_*.sh" appearing anywhere (which comments alone would
/// satisfy), so replacing the glob with a hard-coded array trips this.
const String _globDiscoverySnippet = r"""-name 'forbid_*.sh'""";

/// Operational substring proving `scripts/verify_guards.sh` still requires
/// the `SELF-TEST OK: <basename>` sentinel (not exit-code-only) before
/// counting a guard's self-test as having run. Taken verbatim from the
/// `grep -q` check inside `run_one`'s self-test branch — asserting on the
/// executed check, not on the sentinel string merely being mentioned in a
/// comment, so neutering the check (e.g. replacing it with `true`) trips
/// this even though "SELF-TEST OK" still appears elsewhere in the file's
/// prose.
const String _sentinelRequirementSnippet = r'grep -q "^SELF-TEST OK: $base\$"';

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
    late final String verifyGuardsSource;
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
      expect(
        _verifyGuardsScript.existsSync(),
        isTrue,
        reason:
            '${_verifyGuardsScript.path} not found. pr-validate.yml delegates '
            'the "Self-test drift-prevention gates" step to this runner — '
            'without it on disk nothing self-tests any guard.',
      );
      yaml = _workflow.readAsStringSync();
      verifyGuardsSource = _verifyGuardsScript.readAsStringSync();

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

      for (final name in scriptNames) {
        if (!_isPlainlyInvoked(yaml, name)) {
          missingEnforcement.add(name);
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

      // --- Self-test coverage: direct-per-script OR delegated runner ---
      //
      // Each of the three delegated-coverage conditions is asserted on its
      // own, with its own failure message, BEFORE it is allowed to excuse
      // any guard's missing per-script line. That ordering matters: if any
      // one of them is false, no guard should be treated as self-tested by
      // delegation, and the per-guard failure list below should say so by
      // naming every guard, not silently accept the delegation anyway.
      final bool delegatedRunnerWired = yaml.contains(
        _delegatedSelfTestInvocation,
      );
      expect(
        delegatedRunnerWired,
        isTrue,
        reason:
            'pr-validate.yml no longer invokes '
            '"$_delegatedSelfTestInvocation" from its "Self-test '
            'drift-prevention gates" step. Since 2026-08-18 that single '
            'delegated invocation is how every scripts/forbid_*.sh gate '
            'gets its --self-test run — without it, NONE of them are '
            'self-tested in CI.',
      );

      final bool verifyGuardsUsesGlobDiscovery = verifyGuardsSource.contains(
        _globDiscoverySnippet,
      );
      expect(
        verifyGuardsUsesGlobDiscovery,
        isTrue,
        reason:
            '${_verifyGuardsScript.path} no longer discovers guards via the '
            'scripts/forbid_*.sh glob (expected to find the literal '
            '"$_globDiscoverySnippet" in its discover_guards logic). If '
            'discovery was swapped for a hand-kept list, the delegated '
            'runner has regressed into exactly the kind of list that rots '
            'silently — the failure mode "verify_guards.sh --self-test" '
            'was written to retire — so it can no longer excuse any '
            "guard's missing per-script --self-test line.",
      );

      final bool verifyGuardsRequiresSentinel = verifyGuardsSource.contains(
        _sentinelRequirementSnippet,
      );
      expect(
        verifyGuardsRequiresSentinel,
        isTrue,
        reason:
            '${_verifyGuardsScript.path} no longer requires the '
            '"SELF-TEST OK: <basename>" sentinel (expected to find the '
            'literal grep check "$_sentinelRequirementSnippet" in its '
            "run_one self-test branch). Without it, a guard's --self-test "
            'mode passes just by exiting 0 without proving it ran its '
            'self-test path at all — exactly the silent-green failure mode '
            'this whole test file exists to catch — so it can no longer '
            "excuse any guard's missing per-script --self-test line.",
      );

      final bool delegatedSelfTestValid =
          delegatedRunnerWired &&
          verifyGuardsUsesGlobDiscovery &&
          verifyGuardsRequiresSentinel;

      final List<String> missingSelfTest = <String>[];
      for (final name in scriptNames) {
        final String selfTestInvocation = './scripts/$name --self-test';
        final bool directlyWired = yaml.contains(selfTestInvocation);
        if (!directlyWired && !delegatedSelfTestValid) {
          missingSelfTest.add(name);
        }
      }

      expect(
        missingSelfTest,
        isEmpty,
        reason:
            'The following scripts/forbid_*.sh gates are enforced in CI but '
            'their `--self-test` mode is not proven to run anywhere: '
            '$missingSelfTest. Each gate needs EITHER its own '
            "'./scripts/<name> --self-test' line in pr-validate.yml, OR "
            'coverage via the delegated "./scripts/verify_guards.sh '
            '--self-test" step — whose three preconditions (wired into the '
            'workflow, glob-based discovery, sentinel-checked pass) are '
            'asserted separately above and were satisfied for every other '
            "guard, so this guard's absence here means the enumeration "
            'itself is inconsistent with the delegated runner — investigate '
            'rather than re-adding a per-script line.',
      );
    });
  });
}
