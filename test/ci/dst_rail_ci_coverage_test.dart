// Pins the CI step that gives the day rail's DST guards somewhere to actually
// run.
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
// catch would ship unnoticed. Nothing else in the suite would react.
//
// So the workflow is asserted as a structural fact, the same way the
// `forbid_*` gates assert source-level ones.
//
// Deliberately asserts BEHAVIOUR (a Kyiv-zone invocation covering this file),
// not an exact YAML string: the step may be renamed or reworded, but it must
// keep running that file in that zone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The workflow, resolved from the package root (`flutter test`'s cwd).
final File _workflow = File('.github/workflows/pr-validate.yml');

const String _kRailTestPath =
    'test/features/booking/presentation/bookings_day_rail_test.dart';

void main() {
  group('CI runs the DST rail guards in a DST-observing zone', () {
    late final String yaml;

    setUpAll(() {
      expect(
        _workflow.existsSync(),
        isTrue,
        reason: '${_workflow.path} not found — run from the package root.',
      );
      yaml = _workflow.readAsStringSync();
    });

    test('a step sets TZ to the market zone', () {
      expect(
        yaml,
        contains('TZ: Europe/Kyiv'),
        reason:
            'No CI step sets TZ=Europe/Kyiv, so the two rendered DST guards in '
            '$_kRailTestPath skip on every runner and cover nothing. Restore '
            'the "DST rail guards (market zone)" step.',
      );
    });

    test('that step runs the day-rail file', () {
      expect(
        yaml,
        contains(_kRailTestPath),
        reason:
            'The DST-zone CI step no longer names $_kRailTestPath. Its guards '
            'are skip-gated on the host zone, so if nothing runs this file '
            'under a DST zone they are permanently inert.',
      );
    });

    test('the TZ override is scoped to a step, never the whole job — the main '
        'suite must stay UTC', () {
      // `slot_time_tz_regression_test.dart` proves the booking formatters are
      // Kyiv-pinned IN CODE by asserting Kyiv wall-clocks on a non-Kyiv
      // runner. Under a job-wide TZ=Europe/Kyiv a regression to `.toLocal()`
      // passes it silently (verified by mutation), so the override must not
      // escape its step.
      //
      // Step-level `env:` is indented deeper than the job-level `env:` that
      // would sit at the job's own key depth. A job-level env block appears
      // at exactly 4 spaces (job key at 2, its children at 4).
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
  });
}
