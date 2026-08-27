// Phase 274 — unit tests for the ONE half-open overlap predicate shared by
// the slot picker's client-side conflict exclusion and (Phase 275) the
// salon schedule hub's own re-validation.
//
// Every fixture instant here is a FIXED, arbitrary UTC literal read only via
// direct DateTime comparison (never against `isPast`/the real wall clock, no
// `clockProvider`), so neither the "stale future date" nor the "host-local
// instant anchor" fragility applies — this file exercises pure interval
// arithmetic, not calendar-day or "upcoming" semantics. Each literal below
// carries its OWN `// future-date-ok:` marker on the line directly above it
// (required per-line by `forbid_stale_future_date_fixture.sh` — one marker
// only unblocks the single line it sits above).
//
// mutation check (phase-274, do not skip): flipping the predicate's strict
// `<`/`>` to `<=`/`>=` must turn the two back-to-back cases below RED. That
// flip was applied by hand against `time_window_overlap.dart` during this
// phase's implementation and confirmed both went red, then reverted — see
// the phase's own report, not a checked-in artifact of the mutation itself.

import 'package:beautica_mobile/features/booking/domain/time_window_overlap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timeWindowsOverlap', () {
    // Compared only via direct DateTime arithmetic, never `isPast`/wall-clock.
    // future-date-ok: fixed, arbitrary — see above.
    final DateTime aStart = DateTime.utc(2026, 3, 10, 10, 0);
    // future-date-ok: fixed, arbitrary — see above.
    final DateTime aEnd = DateTime.utc(2026, 3, 10, 11, 0);

    test('should_reportOverlap_when_windowsGenuinelyIntersect', () {
      // future-date-ok: fixed, arbitrary — see file header.
      final DateTime bStart = DateTime.utc(2026, 3, 10, 10, 30);
      // future-date-ok: fixed, arbitrary — see file header.
      final DateTime bEnd = DateTime.utc(2026, 3, 10, 11, 30);

      expect(
        timeWindowsOverlap(
          aStart: aStart,
          aEnd: aEnd,
          bStart: bStart,
          bEnd: bEnd,
        ),
        isTrue,
      );
    });

    test('should_reportNoOverlap_when_windowsAreFarApart', () {
      // future-date-ok: fixed, arbitrary — see file header.
      final DateTime bStart = DateTime.utc(2026, 3, 10, 14, 0);
      // future-date-ok: fixed, arbitrary — see file header.
      final DateTime bEnd = DateTime.utc(2026, 3, 10, 15, 0);

      expect(
        timeWindowsOverlap(
          aStart: aStart,
          aEnd: aEnd,
          bStart: bStart,
          bEnd: bEnd,
        ),
        isFalse,
      );
    });

    // D3 — pins the boundary. A ends 11:00, B starts 11:00: back-to-back, not
    // a conflict.
    test(
      'should_KEEP_theSlotStartingExactlyAtAnExcludedWindowEnd_when_backToBack',
      () {
        final DateTime bStart = aEnd; // 11:00 — exactly when A ends.
        // future-date-ok: fixed, arbitrary — see file header.
        final DateTime bEnd = DateTime.utc(2026, 3, 10, 12, 0);

        expect(
          timeWindowsOverlap(
            aStart: aStart,
            aEnd: aEnd,
            bStart: bStart,
            bEnd: bEnd,
          ),
          isFalse,
          reason:
              'A ends 11:00, B starts 11:00 — back-to-back must stay '
              'bookable (phase-274 D3), never reported as a conflict',
        );
      },
    );

    // D3's other boundary — A starts exactly when B ends.
    test(
      'should_KEEP_theSlotEndingExactlyAtAnExcludedWindowStart_when_backToBack',
      () {
        // future-date-ok: fixed, arbitrary — see file header.
        final DateTime bStart = DateTime.utc(2026, 3, 10, 9, 0);
        final DateTime bEnd = aStart; // 10:00 — exactly when A starts.

        expect(
          timeWindowsOverlap(
            aStart: aStart,
            aEnd: aEnd,
            bStart: bStart,
            bEnd: bEnd,
          ),
          isFalse,
          reason:
              'B ends 10:00, A starts 10:00 — back-to-back the other way '
              'round must also stay bookable',
        );
      },
    );

    test('should_reportOverlap_when_oneWindowFullyContainsTheOther', () {
      // future-date-ok: fixed, arbitrary — see file header.
      final DateTime bStart = DateTime.utc(2026, 3, 10, 9, 30);
      // future-date-ok: fixed, arbitrary — see file header.
      final DateTime bEnd = DateTime.utc(2026, 3, 10, 11, 30);

      expect(
        timeWindowsOverlap(
          aStart: aStart,
          aEnd: aEnd,
          bStart: bStart,
          bEnd: bEnd,
        ),
        isTrue,
      );
    });

    test('should_reportOverlap_when_windowsAreIdentical', () {
      expect(
        timeWindowsOverlap(
          aStart: aStart,
          aEnd: aEnd,
          bStart: aStart,
          bEnd: aEnd,
        ),
        isTrue,
      );
    });
  });
}
