// Pins the CI steps that give zone-sensitive tests somewhere to actually run
// under a zone other than the main suite's UTC. THREE such steps are pinned
// here:
//   1. "DST rail guards (market zone)" — TZ=Europe/Kyiv, covering the day
//      rail's DST guards (unchanged from the original single-step version of
//      this file).
//   2. "Third-timezone sweep (host-clock leak detector)" — TZ=Asia/Tokyo,
//      added 2026-08-02 to catch host-local-clock leaks that happen to agree
//      with the correct Kyiv-derived value on either UTC or Europe/Kyiv (see
//      that step's own comment in pr-validate.yml, and
//      scripts/forbid_host_local_instant_anchor.sh, for the full story).
//   3. "Fourth-timezone sweep (west-of-Kyiv day-boundary detector)" —
//      TZ=Pacific/Honolulu, added 2026-08-04. Asia/Tokyo is EAST of Kyiv and
//      can therefore only push a host-local fixture BACKWARD over the Kyiv day
//      boundary — measured, it only fires for fixture hours 00:00-05:59.
//      Pacific/Honolulu covers the mirror band, 11:00-23:59. The two bands are
//      DISJOINT: neither step subsumes the other, and both directions were
//      proven by executed mutation on booking_confirm_test.dart rather than
//      derived (probes A and B, recorded on the Honolulu step in
//      pr-validate.yml). That is why the tests below pin BOTH zones on
//      SEPARATE steps and additionally assert their scopes are identical —
//      "consolidating the two sweeps into one" silently halves the covered
//      hour band while leaving a plausible-looking single zone step behind.
//
// THE HOLE THIS CLOSES
// --------------------
// `bookings_day_rail_test.dart`'s two rendered DST guards skip on any host
// whose UTC offset does not change across the transition. CI is
// `ubuntu-latest` with no `TZ`, i.e. UTC — so on the main test step they
// ALWAYS skip. The only thing making them real coverage rather than decoration
// is the dedicated `TZ=Europe/Kyiv` step in `pr-validate.yml`.
//
// A skipped test is silent. If that step is renamed, reordered away, or
// dropped while "cleaning up the workflow", the two guards would go on
// reporting green-with-a-skip forever and the DST regression they exist to
// catch would ship unnoticed. Nothing else in the suite would react. The same
// is true of the Asia/Tokyo sweep: it exists purely as a CI step, invisible to
// `dart analyze` and to any assertion inside the test files it runs — the
// step itself IS the coverage, so if the step goes, the coverage goes with it,
// silently.
//
// So both workflow steps are asserted as structural facts, the same way the
// `forbid_*` gates assert source-level ones.
//
// Deliberately asserts BEHAVIOUR (a zone-scoped step running specific test
// paths), not an exact YAML string: a step may be renamed or reworded, but it
// must keep running the right paths under the right zone. Step boundaries are
// found via a `- name:` split at the workflow's own step indentation (6
// spaces), so "one step contains both X and Y" genuinely means adjacency
// within a single step block, not merely "both strings appear somewhere in
// the file" — see backlog :369: an earlier version of this file asserted the
// TZ and the rail path as two INDEPENDENT `contains` checks, which stayed
// green even after the TZ override was moved onto an unrelated step, silently
// letting the DST guards go back to skipping on CI while both assertions kept
// passing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The workflow, resolved from the package root (`flutter test`'s cwd).
final File _workflow = File('.github/workflows/pr-validate.yml');

const String _kRailTestPath =
    'test/features/booking/presentation/bookings_day_rail_test.dart';

/// Splits the raw workflow YAML into per-step chunks at each `- name:` line
/// indented at the step level (6 spaces — a job's steps sit one level deeper
/// than the job key itself). Step N's chunk runs from its own `- name:` up to
/// (not including) the next step's `- name:`, so `env:`/`run:` lines that
/// belong to a step always land in THAT step's chunk and never a
/// neighbour's — which is exactly what "one step contains both X and Y" needs
/// to mean adjacency rather than mere co-occurrence anywhere in the file.
List<String> _steps(String yaml) =>
    yaml.split(RegExp(r'^      - name:', multiLine: true));

void main() {
  group('CI runs zone-scoped tests in DST-observing / third-party zones', () {
    late final String yaml;
    late final List<String> steps;

    setUpAll(() {
      expect(
        _workflow.existsSync(),
        isTrue,
        reason: '${_workflow.path} not found — run from the package root.',
      );
      yaml = _workflow.readAsStringSync();
      steps = _steps(yaml);
    });

    test('ONE step sets TZ=Europe/Kyiv AND runs the day-rail file — not two '
        'independent facts (backlog :369)', () {
      final bool hasAdjacentStep = steps.any(
        (step) =>
            step.contains('TZ: Europe/Kyiv') && step.contains(_kRailTestPath),
      );
      expect(
        hasAdjacentStep,
        isTrue,
        reason:
            'No SINGLE step sets TZ=Europe/Kyiv and runs $_kRailTestPath. '
            'backlog :369: an earlier version of this test asserted these '
            'as two INDEPENDENT `contains(yaml, ...)` checks, which stayed '
            'green even when the TZ override was moved onto a different '
            'step than the one running the rail file — the day rail\'s two '
            'rendered DST guards went back to permanently skipping on CI '
            'while both old assertions kept passing. Restore (or keep '
            'adjacent) the "DST rail guards (market zone)" step, with its '
            'TZ override and the rail-file invocation on the SAME step.',
      );
    });

    test('the Europe/Kyiv override is scoped to a step, never the whole job '
        '— the main suite must stay UTC', () {
      // `slot_time_tz_regression_test.dart` proves the booking formatters are
      // Kyiv-pinned IN CODE by asserting Kyiv wall-clocks on a non-Kyiv
      // runner. Under a job-wide TZ=Europe/Kyiv a regression to `.toLocal()`
      // passes it silently (verified by mutation), so the override must not
      // escape its step.
      //
      // Step-level `env:` is indented deeper than the job-level `env:` that
      // would sit at the job's own key depth. A job-level env block appears
      // at exactly 4 spaces (job key at 2, its children at 4). This is
      // deliberately "the sharp one" — a job-level env block anywhere in this
      // file is disqualifying regardless of which zone it carries, unlike the
      // adjacency checks above, which are step-scoped by construction.
      expect(
        yaml,
        isNot(contains(RegExp(r'^    env:', multiLine: true))),
        reason:
            'A job-level `env:` block appeared in pr-validate.yml. If it '
            'carries TZ, the whole suite leaves UTC and '
            'slot_time_tz_regression_test.dart stops being able to catch a '
            '.toLocal() regression — the exact bug it was written for.',
      );
    });

    test('ONE step sets TZ=Asia/Tokyo AND runs the booking + home suites — the '
        'third-timezone host-clock leak detector', () {
      final bool hasAdjacentStep = steps.any(
        (step) =>
            step.contains('TZ: Asia/Tokyo') &&
            step.contains('test/features/booking/') &&
            step.contains('test/features/home/'),
      );
      expect(
        hasAdjacentStep,
        isTrue,
        reason:
            'No SINGLE step sets TZ=Asia/Tokyo and runs both '
            'test/features/booking/ and test/features/home/. This step is '
            'the only CI coverage that exercises those suites under a zone '
            'with no relationship to Europe/Kyiv, which is what catches a '
            'host-local-clock leak that happens to agree with the correct '
            'Kyiv-derived value on both UTC (the main suite) and '
            'Europe/Kyiv (the DST rail step) — see '
            'scripts/forbid_host_local_instant_anchor.sh. Restore the '
            '"Third-timezone sweep (host-clock leak detector)" step.',
      );
    });

    test('the SAME Asia/Tokyo step also runs test/features/calendar/ — '
        '`working_hours_repository.dart` became zone-critical alongside '
        'scripts/forbid_raw_clock_read.sh (2026-08-02)', () {
      final bool hasAdjacentStep = steps.any(
        (step) =>
            step.contains('TZ: Asia/Tokyo') &&
            step.contains('test/features/calendar/'),
      );
      expect(
        hasAdjacentStep,
        isTrue,
        reason:
            'No SINGLE step sets TZ=Asia/Tokyo and runs '
            'test/features/calendar/. `HttpWorkingHoursRepository._todayKyiv`'
            ' now derives "today" through the Kyiv-anchored clock seam '
            '(shared/time/kyiv_day.dart), so this directory needs the same '
            'third-timezone host-clock-leak coverage as booking/home/'
            'schedule. Add test/features/calendar/ back to the '
            '"Third-timezone sweep (host-clock leak detector)" step.',
      );
    });

    test('ONE step sets TZ=Pacific/Honolulu AND runs the booking + home + '
        'calendar suites — the WEST-of-Kyiv mirror of the Tokyo sweep', () {
      final bool hasAdjacentStep = steps.any(
        (step) =>
            step.contains('TZ: Pacific/Honolulu') &&
            step.contains('test/features/booking/') &&
            step.contains('test/features/home/') &&
            step.contains('test/features/calendar/'),
      );
      expect(
        hasAdjacentStep,
        isTrue,
        reason:
            'No SINGLE step sets TZ=Pacific/Honolulu and runs '
            'test/features/booking/, test/features/home/ and '
            'test/features/calendar/. Asia/Tokyo (UTC+9) is EAST of Kyiv, so '
            'it can only push a host-local `DateTime(Y,M,D,H)` fixture '
            'BACKWARD across the Kyiv day boundary — measured, only for '
            'H < 6. Pacific/Honolulu (UTC-10) is the only step covering the '
            'mirror band, H >= 11, which is where most booking fixtures '
            'actually sit. Reintroducing the pre-030ddb18 host-local '
            '`_kStartAt` in booking_confirm_test.dart turns THIS step red '
            'and the Tokyo step green (probe A); the early-morning variant '
            'does the opposite (probe B). Restore the "Fourth-timezone sweep '
            '(west-of-Kyiv day-boundary detector)" step.',
      );
    });

    test('the Tokyo and Honolulu sweeps are SEPARATE steps covering the SAME '
        'directory list — a directory added to one is never silently '
        'uncovered in the other direction', () {
      // Only the `run:` block's continuation lines look like
      // `<indent>test/some/dir/ \` — a comment line always starts with `#`
      // after its indent, so this can never pick a path out of prose.
      final RegExp pathLine = RegExp(
        r'^ +(test/[A-Za-z0-9_/]+/) \\$',
        multiLine: true,
      );
      Set<String> scopeOf(String zone) {
        final Iterable<String> matching = steps.where(
          (String step) => step.contains('TZ: $zone'),
        );
        expect(
          matching,
          hasLength(1),
          reason:
              'Expected exactly ONE step carrying `TZ: $zone`; found '
              '${matching.length}. Two steps in the same zone means one of '
              'the two sweep directions was duplicated instead of mirrored.',
        );
        return pathLine
            .allMatches(matching.single)
            .map((m) => m.group(1)!)
            .toSet();
      }

      final Set<String> tokyo = scopeOf('Asia/Tokyo');
      final Set<String> honolulu = scopeOf('Pacific/Honolulu');

      expect(
        tokyo,
        isNotEmpty,
        reason:
            'Parsed an EMPTY scope for the Asia/Tokyo sweep. If that step '
            'stopped using a `run: |` block with one `test/dir/ \\` per '
            'line, this parity check silently compares two empty sets and '
            'proves nothing — fix the parser, do not delete the test.',
      );
      expect(
        honolulu,
        equals(tokyo),
        reason:
            'The Asia/Tokyo and Pacific/Honolulu sweeps cover DIFFERENT '
            'directories. They are mirror halves of one gate: Tokyo catches '
            'host-local fixture hours < 06:00, Honolulu catches >= 11:00. A '
            'directory present in only one of them is covered in only one '
            'day-boundary direction, which is exactly the half-coverage the '
            'Honolulu step was added to end. Keep the two lists identical.',
      );
    });
  });
}
