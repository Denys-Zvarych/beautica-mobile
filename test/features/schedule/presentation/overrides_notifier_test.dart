// Phase 15.1 — Unit tests for [OverridesNotifier] (per-date override CRUD) and
// the perf-fix contract that just landed:
//   • putSpan rejects a span > kMaxOverrideSpanDays BEFORE any PUT;
//   • a span within the cap issues exactly one PUT per calendar date (batched);
//   • a partial failure throws a ValidationFailure naming the failed date(s).
//
// Strategy: override scheduleRepositoryProvider with a mocktail mock; fresh
// ProviderContainer per test (disposed via tearDown).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

ScheduleOverride _spanDayOff(DateTime start, DateTime end) =>
    ScheduleOverride.dayOff(start: start, end: end);

ScheduleOverride _explicit(DateTime date, List<TimeOfDay> times) =>
    ScheduleOverride.explicitTimes(start: date, end: date, times: times);

WorkInterval _wi(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

void main() {
  late _MockScheduleRepository repo;
  final range = ScheduleRange(
    from: DateTime(2026, 6, 1),
    to: DateTime(2026, 8, 31),
  );

  setUpAll(() {
    registerFallbackValue(
      ScheduleOverride.dayOff(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 1),
      ),
    );
    registerFallbackValue(DateTime(2026, 6, 1));
  });

  setUp(() {
    repo = _MockScheduleRepository();
    when(
      () => repo.listOverrides(any(), any()),
    ).thenAnswer((_) async => const <ScheduleOverride>[]);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [scheduleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'putSpan over kMaxOverrideSpanDays throws ValidationFailure before any PUT',
    () async {
      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      // 93 days inclusive (start..start+92) — one past the cap of 92.
      final start = DateTime(2026, 6, 1);
      final end = start.add(
        const Duration(days: kMaxOverrideSpanDays),
      ); // 92 days later = 93 dates

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(start, end));

      final state = container.read(overridesProvider(range));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ValidationFailure>());
      // Guard fired before any network mutation.
      verifyNever(() => repo.putOverride(any()));
    },
  );

  test('span within cap issues exactly one PUT per date (batched)', () async {
    when(() => repo.putOverride(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as ScheduleOverride,
    );

    final container = makeContainer();
    await container.read(overridesProvider(range).future);

    // A 5-day span → 5 PUTs, one per calendar date.
    final start = DateTime(2026, 6, 10);
    final end = DateTime(2026, 6, 14);
    await container
        .read(overridesProvider(range).notifier)
        .putSpan(_spanDayOff(start, end));

    final state = container.read(overridesProvider(range));
    expect(state.hasError, isFalse);

    final captured = verify(
      () => repo.putOverride(captureAny()),
    ).captured.cast<ScheduleOverride>();
    expect(captured, hasLength(5));
    // Each PUT is a single-date override across the contiguous span.
    expect(captured.every((o) => o.isSingleDay), isTrue);
    expect(captured.map((o) => o.start.day).toList()..sort(), [
      10,
      11,
      12,
      13,
      14,
    ]);
    // Range reloaded after the mutation.
    verify(() => repo.listOverrides(any(), any())).called(2); // build + reload
  });

  test(
    'partial failure → OverrideSpanPartialFailure naming the failed date(s)',
    () async {
      // PUT for 2026-06-12 fails; the others succeed.
      when(() => repo.putOverride(any())).thenAnswer((inv) async {
        final o = inv.positionalArguments.first as ScheduleOverride;
        if (o.start.day == 12) {
          throw const ServerFailure(statusCode: 500);
        }
        return o;
      });

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(DateTime(2026, 6, 10), DateTime(2026, 6, 14)));

      final state = container.read(overridesProvider(range));
      expect(state.hasError, isTrue);
      final err = state.error;
      // Typed failure, not a hand-built ValidationFailure.serverMessage
      // string (mobile-security, 2026-08) — the failed date is now a real
      // `DateTime` on a dedicated field, not a substring of prose.
      expect(err, isA<OverrideSpanPartialFailure>());
      expect(
        (err as OverrideSpanPartialFailure).failedDates,
        equals(<DateTime>[DateTime(2026, 6, 12)]),
      );
    },
  );

  test('putOverride single date reloads range and clears error', () async {
    when(() => repo.putOverride(any())).thenAnswer(
      (inv) async => inv.positionalArguments.first as ScheduleOverride,
    );

    final container = makeContainer();
    await container.read(overridesProvider(range).future);

    await container
        .read(overridesProvider(range).notifier)
        .putOverride(_spanDayOff(DateTime(2026, 6, 20), DateTime(2026, 6, 20)));

    expect(container.read(overridesProvider(range)).hasError, isFalse);
    verify(() => repo.putOverride(any())).called(1);
    verify(() => repo.listOverrides(any(), any())).called(2);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 15.7 — EXPLICIT_TIMES override validation guard.
  // ───────────────────────────────────────────────────────────────────────────

  group('putOverride — EXPLICIT_TIMES validation', () {
    test(
      'accepts a working EXPLICIT_TIMES override and sends mode + times',
      () async {
        when(() => repo.putOverride(any())).thenAnswer(
          (inv) async => inv.positionalArguments.first as ScheduleOverride,
        );

        final container = makeContainer();
        await container.read(overridesProvider(range).future);

        await container
            .read(overridesProvider(range).notifier)
            .putOverride(
              _explicit(DateTime(2026, 6, 20), const <TimeOfDay>[
                TimeOfDay(hour: 9, minute: 0),
                TimeOfDay(hour: 15, minute: 0),
              ]),
            );

        expect(container.read(overridesProvider(range)).hasError, isFalse);
        final sent =
            verify(() => repo.putOverride(captureAny())).captured.single
                as ScheduleOverride;
        expect(sent.kind, OverrideKind.custom);
        expect(sent.mode, WeekdayMode.explicitTimes);
        expect(sent.times, <TimeOfDay>[
          const TimeOfDay(hour: 9, minute: 0),
          const TimeOfDay(hour: 15, minute: 0),
        ]);
        // The opposite-shape field is cleared — an EXPLICIT_TIMES override carries
        // NO intervals (the explicitTimes ctor clears them).
        expect(sent.intervals, isEmpty);
      },
    );

    test('rejects an empty-times EXPLICIT_TIMES override → ValidationFailure, '
        'no PUT', () async {
      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container
          .read(overridesProvider(range).notifier)
          .putOverride(_explicit(DateTime(2026, 6, 20), const <TimeOfDay>[]));

      final state = container.read(overridesProvider(range));
      expect(state.hasError, isTrue);
      expect(state.error, isA<ValidationFailure>());
      verifyNever(() => repo.putOverride(any()));
    });

    test('mode-flip: a CUSTOM interval override carries no times', () {
      // The interval ctor clears the discrete-times field — the two shapes
      // never coexist on one override.
      final interval = ScheduleOverride.custom(
        start: DateTime(2026, 6, 21),
        end: DateTime(2026, 6, 21),
        intervals: <WorkInterval>[
          WorkInterval(
            start: const TimeOfDay(hour: 10, minute: 0),
            end: const TimeOfDay(hour: 14, minute: 0),
          ),
        ],
      );
      expect(interval.mode, WeekdayMode.interval);
      expect(interval.times, isEmpty);

      // The explicitTimes ctor is the inverse — clears intervals.
      final explicit = _explicit(DateTime(2026, 6, 21), const <TimeOfDay>[
        TimeOfDay(hour: 10, minute: 0),
      ]);
      expect(explicit.mode, WeekdayMode.explicitTimes);
      expect(explicit.intervals, isEmpty);
    });
  });

  group('putSpan — EXPLICIT_TIMES validation', () {
    test(
      'accepts an EXPLICIT_TIMES span and sends one EXPLICIT_TIMES PUT per date',
      () async {
        when(() => repo.putOverride(any())).thenAnswer(
          (inv) async => inv.positionalArguments.first as ScheduleOverride,
        );

        final container = makeContainer();
        await container.read(overridesProvider(range).future);

        // A 3-day EXPLICIT_TIMES span → 3 EXPLICIT_TIMES PUTs, one per date.
        await container
            .read(overridesProvider(range).notifier)
            .putSpan(
              ScheduleOverride.explicitTimes(
                start: DateTime(2026, 6, 10),
                end: DateTime(2026, 6, 12),
                times: const <TimeOfDay>[
                  TimeOfDay(hour: 11, minute: 0),
                  TimeOfDay(hour: 16, minute: 0),
                ],
              ),
            );

        expect(container.read(overridesProvider(range)).hasError, isFalse);
        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        expect(captured, hasLength(3));
        expect(captured.every((o) => o.isSingleDay), isTrue);
        expect(
          captured.every((o) => o.mode == WeekdayMode.explicitTimes),
          isTrue,
        );
        expect(captured.every((o) => o.intervals.isEmpty), isTrue);
        expect(
          captured.every(
            (o) => o.times.contains(const TimeOfDay(hour: 11, minute: 0)),
          ),
          isTrue,
        );
      },
    );

    test(
      'rejects an empty-times EXPLICIT_TIMES span → ValidationFailure before '
      'any PUT',
      () async {
        final container = makeContainer();
        await container.read(overridesProvider(range).future);

        await container
            .read(overridesProvider(range).notifier)
            .putSpan(
              ScheduleOverride.explicitTimes(
                start: DateTime(2026, 6, 10),
                end: DateTime(2026, 6, 12),
                times: const <TimeOfDay>[],
              ),
            );

        final state = container.read(overridesProvider(range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ValidationFailure>());
        verifyNever(() => repo.putOverride(any()));
      },
    );
  });

  // ── 2026-07-26 booking-conflict design ────────────────────────────────────
  //
  // `checkConflicts` and `putSpan`'s `cancelOverlapping` forwarding had ZERO
  // notifier-level coverage before this audit (mobile-qa, 2026-07-26) — every
  // existing test in this file predates the design. The widget-level
  // `day_hours_sheet_test.dart` booking-conflict-gate group covers the
  // SINGLE-date `putOverride` path end-to-end; this closes the `putSpan`
  // (multi-date) gap, which no other test reaches.

  group('checkConflicts (2026-07-26 design)', () {
    test('delegates straight to repo.previewConflicts and returns its result '
        'WITHOUT touching provider state (no AsyncLoading flicker)', () async {
      final previewResult = OverrideConflictCheck(
        conflicts: <OverrideConflict>[
          OverrideConflict(
            bookingId: 'b1',
            appointmentId: null,
            date: DateTime(2026, 6, 20),
            startsAt: DateTime.utc(2026, 6, 20, 10),
            endsAt: DateTime.utc(2026, 6, 20, 11),
            clientDisplayName: 'Клієнт',
            serviceName: 'Послуга',
          ),
        ],
        totalCount: 1,
        truncated: false,
        scanTruncated: false,
      );
      when(
        () => repo.previewConflicts(any()),
      ).thenAnswer((_) async => previewResult);

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      // The provider's state is settled AsyncData before the check.
      final AsyncValue<List<ScheduleOverride>> before = container.read(
        overridesProvider(range),
      );
      expect(before, isA<AsyncData<List<ScheduleOverride>>>());

      final span = _spanDayOff(DateTime(2026, 6, 20), DateTime(2026, 6, 20));
      final result = await container
          .read(overridesProvider(range).notifier)
          .checkConflicts(span);

      expect(result, same(previewResult));
      verify(() => repo.previewConflicts(span)).called(1);
      // State is untouched by the check — same instance as before.
      expect(container.read(overridesProvider(range)), same(before));
    });

    test(
      'a thrown Failure propagates directly — NOT wrapped in AsyncValue',
      () async {
        when(
          () => repo.previewConflicts(any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = makeContainer();
        await container.read(overridesProvider(range).future);

        // `checkConflicts` is not itself `async` — it returns
        // `_repo.previewConflicts(span)` directly — so a mocktail
        // `thenThrow` fires SYNCHRONOUSLY the instant the method is called,
        // before a Future object even exists. `expectLater` needs a Future
        // or a value; a bare call-expression argument would throw while
        // being evaluated, outside the matcher's try/catch. Wrapping in a
        // closure (the sync `expect` idiom) lets `throwsA` catch it.
        expect(
          () => container
              .read(overridesProvider(range).notifier)
              .checkConflicts(
                _spanDayOff(DateTime(2026, 6, 20), DateTime(2026, 6, 20)),
              ),
          throwsA(isA<ServerFailure>()),
        );
        // The already-loaded override list is left intact — a failed CHECK must
        // not disturb the provider's settled state.
        expect(container.read(overridesProvider(range)).hasError, isFalse);
      },
    );
  });

  group('putSpan — cancelOverlapping forwarding (2026-07-26 design)', () {
    test('cancelOverlapping: true is forwarded to EVERY expanded per-date PUT '
        '(the consent is "cancel whatever overlaps", not "cancel exactly '
        'these ids")', () async {
      when(() => repo.putOverride(any(), cancelOverlapping: true)).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      final start = DateTime(2026, 6, 10);
      final end = DateTime(2026, 6, 12);
      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(start, end), cancelOverlapping: true);

      expect(container.read(overridesProvider(range)).hasError, isFalse);
      final captured = verify(
        () => repo.putOverride(
          captureAny(),
          cancelOverlapping: captureAny(named: 'cancelOverlapping'),
        ),
      ).captured;
      // [override, cancelOverlapping] pairs, one per expanded date.
      final flags = <bool>[
        for (int i = 1; i < captured.length; i += 2) captured[i] as bool,
      ];
      expect(flags, hasLength(3));
      expect(
        flags.every((f) => f == true),
        isTrue,
        reason:
            'every one of the 3 expanded dates must carry the SAME '
            'consent flag the master gave once for the whole span',
      );
    });

    test('the default cancelOverlapping: false preserves pre-existing '
        'behaviour when a caller never opts in', () async {
      when(() => repo.putOverride(any(), cancelOverlapping: false)).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(DateTime(2026, 6, 10), DateTime(2026, 6, 11)));

      final captured = verify(
        () => repo.putOverride(
          captureAny(),
          cancelOverlapping: captureAny(named: 'cancelOverlapping'),
        ),
      ).captured;
      final flags = <bool>[
        for (int i = 1; i < captured.length; i += 2) captured[i] as bool,
      ];
      expect(flags.every((f) => f == false), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // 2026-07-27 — the stored working window across a MULTI-DAY span fan-out.
  //
  // `putSpan` expands a span into one single-date PUT per calendar date. The
  // per-date rebuild (`perDayFor`) constructs a FRESH `ScheduleOverride` for
  // each date — so any field it forgets to carry is silently dropped on every
  // date but the caller's own copy. Before the window was threaded through,
  // a multi-day «однакові години» span would have persisted its display-only
  // window on NO date at all, and the master's edge-flush break would vanish
  // from the whole span on reload (the exact user-visible bug, multiplied).
  // ═════════════════════════════════════════════════════════════════════════

  group('putSpan — stored working window fan-out', () {
    test('EVERY expanded per-date PUT carries the span\'s window', () async {
      when(() => repo.putOverride(any(), cancelOverlapping: false)).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      // A 3-day span: intervals [10:00–18:00] with the outer window
      // 09:00–18:00 (a break 09:00–10:00 carved off the start edge).
      final span = ScheduleOverride.custom(
        start: DateTime(2026, 6, 10),
        end: DateTime(2026, 6, 12),
        intervals: <WorkInterval>[_wi(10, 0, 18, 0)],
        window: _wi(9, 0, 18, 0),
      );

      await container.read(overridesProvider(range).notifier).putSpan(span);

      expect(container.read(overridesProvider(range)).hasError, isFalse);
      final captured = verify(
        () => repo.putOverride(captureAny(), cancelOverlapping: false),
      ).captured.cast<ScheduleOverride>();

      expect(captured, hasLength(3));
      for (final ScheduleOverride o in captured) {
        expect(
          o.window,
          isNotNull,
          reason:
              'date ${o.start} lost the span window on the fan-out — its '
              'edge-flush break would vanish on reload',
        );
        expect(o.window!.startMinutes, 9 * 60);
        expect(o.window!.endMinutes, 18 * 60);
        // Availability is unchanged by the window; the intervals must ride
        // alongside it untouched.
        expect(o.intervals.single.startMinutes, 10 * 60);
      }
    });

    test('each expanded date gets its OWN window instance (no shared mutable '
        'state across the fan-out)', () async {
      when(() => repo.putOverride(any(), cancelOverlapping: false)).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      final window = _wi(9, 0, 18, 0);
      await container
          .read(overridesProvider(range).notifier)
          .putSpan(
            ScheduleOverride.custom(
              start: DateTime(2026, 6, 10),
              end: DateTime(2026, 6, 11),
              intervals: <WorkInterval>[_wi(10, 0, 18, 0)],
              window: window,
            ),
          );

      final captured = verify(
        () => repo.putOverride(captureAny(), cancelOverlapping: false),
      ).captured.cast<ScheduleOverride>();

      // `WorkInterval` is MUTABLE (the editors repoint pickers in place), so a
      // shared instance would let one date's later edit rewrite every other
      // date's persisted window.
      expect(identical(captured[0].window, window), isFalse);
      expect(identical(captured[0].window, captured[1].window), isFalse);
    });

    test('a DAY_OFF span carries no window on any date', () async {
      when(() => repo.putOverride(any(), cancelOverlapping: false)).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(_spanDayOff(DateTime(2026, 6, 10), DateTime(2026, 6, 12)));

      final captured = verify(
        () => repo.putOverride(captureAny(), cancelOverlapping: false),
      ).captured.cast<ScheduleOverride>();
      expect(captured, hasLength(3));
      expect(captured.every((o) => o.window == null), isTrue);
    });

    test('an EXPLICIT_TIMES span carries no window on any date', () async {
      when(() => repo.putOverride(any(), cancelOverlapping: false)).thenAnswer(
        (inv) async => inv.positionalArguments.first as ScheduleOverride,
      );

      final container = makeContainer();
      await container.read(overridesProvider(range).future);

      await container
          .read(overridesProvider(range).notifier)
          .putSpan(
            ScheduleOverride.explicitTimes(
              start: DateTime(2026, 6, 10),
              end: DateTime(2026, 6, 11),
              times: <TimeOfDay>[
                const TimeOfDay(hour: 9, minute: 0),
                const TimeOfDay(hour: 11, minute: 0),
              ],
            ),
          );

      final captured = verify(
        () => repo.putOverride(captureAny(), cancelOverlapping: false),
      ).captured.cast<ScheduleOverride>();
      expect(captured, hasLength(2));
      expect(captured.every((o) => o.window == null), isTrue);
    });
  });
}
