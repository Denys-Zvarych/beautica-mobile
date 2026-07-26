// Phase 15.4 — Widget + golden tests for [DayHoursSheet] (Editor B): the
// per-date override modal sheet that overrides the weekly template for ONE date.
//
// Strategy (mobile-qa M1/M2/M3/M4 + Riverpod hygiene):
//   • The sheet's ONLY network surface is the `overridesProvider(range)`
//     family — it calls `.notifier.putOverride(...)` / `.notifier.clearOverride`.
//     We override the REAL data dependency `scheduleRepositoryProvider` with a
//     mocktail mock (exactly like overrides_notifier_test.dart), so the GENUINE
//     `OverridesNotifier` runs end-to-end and we assert the EXACT
//     `ScheduleOverride` it forwards to the repository — no mocking of the
//     widget-under-test, no real network/storage (M1 isolation).
//   • Finders use the source `Key`s (override-mode-working/-dayoff,
//     override-dayoff-rest, override-save, override-delete, plus the shared
//     IntervalEditor's `override-work-*` keys) — never localised strings (M2;
//     the suite has prior locale-coupling findings).
//
// Phase 15.4 contract change: the backend dropped reason/note from schedule
// overrides. Day-off mode now renders ONLY a clean rest card (keyed
// `override-dayoff-rest`) — no reason grid, no `override-note-field`. Saving a
// day-off requires no reason selection. The clear/revert button keeps Key
// `override-delete` but is now a non-destructive «Повернути до графіка» action.
//   • Goldens use the framework's `matchesGoldenFile` (golden_toolkit is not in
//     the project; the schedule goldens already use this). A fixed device size +
//     the test font keep them deterministic; the sheet is wall-clock free, so
//     they are run-day independent.
//
// 2026-07-26 booking-conflict gate: the former OQ-1 "always allowed" rule is
// REVERSED for save. Every save now calls `previewConflicts` first
// (`_happyRepo()` stubs it empty by default so the pre-existing "no gate to
// see" tests are unaffected); the `DayHoursSheet — booking-conflict gate`
// group below asserts both the empty-conflicts pass-through AND the
// non-empty-conflicts dialog gate (confirm → `cancelOverlapping: true`; back
// out → nothing persisted).
//
// The past-date guard and the SALON_MASTER read-only gate live on the SCREEN
// (the pencil entry point), and are already covered in
// master_schedule_screen_test.dart — referenced there, not duplicated here (M's
// "reference rather than duplicate" rule). See:
//   • 'past date hides the day pencil (read-only history)'
//   • 'SALON_MASTER (read-only): all edit affordances absent ...'

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/my_bookings_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/day_hours_sheet.dart';
import 'package:beautica_mobile/features/schedule/presentation/overrides_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/day_off_conflict_dialog.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/discrete_times_editor.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/interval_editor.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockScheduleRepository extends Mock implements ScheduleRepository {}

class _MockBookingRepository extends Mock implements BookingRepository {}

/// Minimal settled-session auth stub (mirrors
/// `bookings_day_notifier_test.dart`'s `_MutableAuthNotifier`) — just enough
/// to satisfy `BookingsDayNotifier.build`'s `authProvider.select(...)` watch
/// so `bookingsDayProvider` can be read directly in the invalidation test
/// below without booting the real `AuthNotifier` (which needs a live
/// SecureStorage/AuthRepository).
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'master-1',
      email: 'master1@beautica.ua',
      role: UserRole.independentMaster,
      firstName: 'Оля',
      lastName: 'Коваль',
    ),
    accessToken: 'token-1',
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Fixtures.
// ───────────────────────────────────────────────────────────────────────────

final ScheduleRange _range = ScheduleRange(
  from: DateTime(2026, 6, 1),
  to: DateTime(2026, 6, 30),
);

final DateTime _date = DateTime(2026, 6, 21);

/// Fixed "today" injected into the sheet so its submit-time past-date guard is
/// run-day independent (keeps these tests wall-clock free). Anchored on [_date]
/// so the override target is today, never past.
DateTime _testToday() => _date;

WorkInterval _interval(int sh, int sm, int eh, int em) => WorkInterval(
  start: TimeOfDay(hour: sh, minute: sm),
  end: TimeOfDay(hour: eh, minute: em),
);

/// The day's current working intervals (a split 09:00–13:00 · 14:00–18:00 day),
/// used to seed the IntervalEditor in working-hours mode.
List<WorkInterval> _currentIntervals() => <WorkInterval>[
  _interval(9, 0, 13, 0),
  _interval(14, 0, 18, 0),
];

// ───────────────────────────────────────────────────────────────────────────
// Harness — pumps a host scaffold whose single button presents the sheet, so
// the sheet runs through its real `showModalBottomSheet` entry point.
// ───────────────────────────────────────────────────────────────────────────

Future<void> _pumpSheet(
  WidgetTester tester, {
  required ScheduleRepository repo,
  List<WorkInterval>? initialIntervals,
  bool hasExistingOverride = false,
  bool initialDayOff = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () => DayHoursSheet.show(
                  context,
                  date: _date,
                  weekdayFull: 'Неділя',
                  dateLabel: '21 червня',
                  range: _range,
                  initialIntervals: initialIntervals ?? _currentIntervals(),
                  hasExistingOverride: hasExistingOverride,
                  initialDayOff: initialDayOff,
                  clock: _testToday,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}

/// Drains the bounded-cache keepAlive [Timer] the real [OverridesNotifier] parks
/// after a successful load (`overrides_notifier.dart` —
/// `Timer(_kOverridesCacheTtl, link.close)`). Tests that build a genuine
/// `overridesProvider` and hold a live subscription leave that 5-min release
/// timer parked: the held subscription keeps the provider alive, so its
/// `onDispose(timer.cancel)` does not fire before the body ends, and Flutter's
/// FakeAsync teardown trips `A Timer is still pending even after the widget tree
/// was disposed`. This is test-side timer hygiene only — on device `onDispose`
/// cancels the timer on real disposal. Advancing fake time past the TTL fires
/// the release timer, leaving zero pending timers at teardown. It changes no
/// rendered content, so it cannot weaken the assertions made before it.
Future<void> _drainKeepAliveTimers(WidgetTester tester) async {
  await tester.pump(
    const Duration(minutes: 6),
  ); // > _kOverridesCacheTtl (5 min)
  await tester.pumpAndSettle();
}

/// An empty booking-conflict preview — [OverridesNotifier.checkConflicts]'s
/// happy-path result (2026-07-26 design). Every save now calls this ONCE
/// before the PUT; stubbing it empty preserves the pre-existing "no conflict
/// gate to see" behaviour for every test that isn't specifically exercising
/// the conflict dialog.
const OverrideConflictCheck _noConflicts = OverrideConflictCheck(
  conflicts: <OverrideConflict>[],
  totalCount: 0,
  truncated: false,
  scanTruncated: false,
);

/// One CONFIRMED booking on [_date] that a save would leave without
/// availability — used by the booking-conflict-gate tests below.
OverrideConflictCheck _oneConflict() => OverrideConflictCheck(
  conflicts: <OverrideConflict>[
    OverrideConflict(
      bookingId: 'booking-1',
      appointmentId: null,
      date: _date,
      startsAt: DateTime.utc(2026, 6, 21, 8, 0),
      endsAt: DateTime.utc(2026, 6, 21, 9, 30),
      clientDisplayName: 'Олена Гриценко',
      serviceName: 'Стрижка',
    ),
  ],
  totalCount: 1,
  truncated: false,
  scanTruncated: false,
);

/// The enriched booking [BookingRepository.getBookingById] returns for
/// `_oneConflict()`'s `bookingId: 'booking-1'` — used only by the direct
/// invalidation test below, which stubs `bookingRepositoryProvider`
/// independently of the schedule repository.
Booking _conflictBooking() => Booking(
  id: 'booking-1',
  masterId: 'master-1',
  masterFirstName: 'Оля',
  masterLastName: 'Коваль',
  masterType: 'INDEPENDENT_MASTER',
  serviceId: 'service-1',
  serviceName: 'Стрижка',
  durationMinutes: 90,
  price: 500,
  startAt: DateTime.utc(2026, 6, 21, 8, 0),
  endAt: DateTime.utc(2026, 6, 21, 9, 30),
  status: BookingStatus.declined,
  canReview: false,
);

/// A repository whose `putOverride` echoes its argument, whose
/// `previewConflicts` reports NO conflicts (see [_noConflicts]), and whose
/// `clearOverride` resolves; `listOverrides` returns empty so the
/// post-mutation reload settles.
_MockScheduleRepository _happyRepo() {
  final repo = _MockScheduleRepository();
  when(
    () => repo.listOverrides(any(), any()),
  ).thenAnswer((_) async => const <ScheduleOverride>[]);
  when(
    () => repo.previewConflicts(any()),
  ).thenAnswer((_) async => _noConflicts);
  // Named-parameter matcher REQUIRED: `OverridesNotifier.putOverride` always
  // passes `cancelOverlapping` explicitly (even when `false`), so a stub
  // registered as `putOverride(any())` alone never matches the real call —
  // mocktail then falls back to its default (`null`), and the notifier's
  // `AsyncValue.guard` turns that into a spurious AsyncError.
  when(
    () => repo.putOverride(
      any(),
      cancelOverlapping: any(named: 'cancelOverlapping'),
    ),
  ).thenAnswer(
    (inv) async => inv.positionalArguments.first as ScheduleOverride,
  );
  when(() => repo.clearOverride(any())).thenAnswer((_) async {});
  return repo;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      ScheduleOverride.dayOff(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 1),
      ),
    );
    registerFallbackValue(DateTime(2026, 6, 1));
    registerFallbackValue(<BookingStatus>{});
  });

  // ── Working-hours mode → CUSTOM_HOURS override ─────────────────────────────

  group('DayHoursSheet — working-hours mode (CUSTOM_HOURS)', () {
    testWidgets(
      'opens in working-hours mode seeded from current intervals; save puts a '
      'single-date CUSTOM_HOURS override with those intervals and NO reason',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // Working-hours mode is the default surface: the shared IntervalEditor's
        // window pickers (keyed with the `override` prefix) render; the day-off
        // rest card does not.
        expect(find.byKey(const Key('override-work-start')), findsOneWidget);
        expect(find.byKey(const Key('override-work-end')), findsOneWidget);
        expect(find.byKey(const Key('override-dayoff-rest')), findsNothing);

        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        expect(captured, hasLength(1));
        final ScheduleOverride o = captured.single;

        // CUSTOM_HOURS, single date == the targeted date.
        expect(o.kind, OverrideKind.custom);
        expect(o.isSingleDay, isTrue);
        expect(o.start, _date);
        expect(o.end, _date);

        // The intervals are the seeded current intervals (09:00–13:00 ·
        // 14:00–18:00), round-tripped through DayHours.fromIntervals/toIntervals.
        expect(o.intervals, hasLength(2));
        expect(o.intervals[0].start, const TimeOfDay(hour: 9, minute: 0));
        expect(o.intervals[0].end, const TimeOfDay(hour: 13, minute: 0));
        expect(o.intervals[1].start, const TimeOfDay(hour: 14, minute: 0));
        expect(o.intervals[1].end, const TimeOfDay(hour: 18, minute: 0));

        // The sheet dismissed itself on success.
        expect(find.byKey(const Key('override-save')), findsNothing);
      },
    );

    // STRUCTURAL PIN (Phase 15.8 — golden-is-not-acceptance). Custom-hours mode
    // now carries a work-mode sub-toggle (Інтервал / Окремі години) that swaps
    // the editor body. The acceptance for this layout is the structural
    // assertion below; the golden that follows is a SUPPLEMENTARY visual check
    // re-blessed only after this structure was confirmed correct, so the
    // self-referential re-bless can never silently mask a regression. Finders
    // use the source Keys + widget TYPES (M2/M11), never localised copy.
    testWidgets(
      'custom-hours mode renders the work-mode sub-toggle; INTERVAL shows the '
      'IntervalEditor and tapping «Окремі години» swaps to the DiscreteTimesEditor',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // The work-mode sub-toggle and both segment chips render in the default
        // (working-hours) surface.
        expect(
          find.byKey(const Key('override-work-mode-toggle')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('override-work-mode-interval')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('override-work-mode-explicit')),
          findsOneWidget,
        );

        // INTERVAL is the default mode → the IntervalEditor body is shown, the
        // DiscreteTimesEditor body is absent.
        expect(find.byType(IntervalEditor), findsOneWidget);
        expect(find.byType(DiscreteTimesEditor), findsNothing);

        // Tapping «Окремі години» swaps the body: IntervalEditor gone,
        // DiscreteTimesEditor present (with its add-time affordance keyed
        // `override-add-time`).
        await tester.tap(find.byKey(const Key('override-work-mode-explicit')));
        await tester.pumpAndSettle();

        expect(find.byType(DiscreteTimesEditor), findsOneWidget);
        expect(find.byType(IntervalEditor), findsNothing);
        expect(find.byKey(const Key('override-add-time')), findsOneWidget);
      },
    );

    // SUPPLEMENTARY golden (re-blessed for the Phase 15.8 work-mode-toggle
    // layout AFTER the structural pin above confirmed the render is correct).
    testWidgets('custom-hours mode matches its golden', (tester) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo);

      await expectLater(
        find.byType(DayHoursSheet),
        matchesGoldenFile('goldens/day_hours_sheet_custom_hours.png'),
      );
    });
  });

  // ── Day-off mode → DAY_OFF override ────────────────────────────────────────

  group('DayHoursSheet — day-off mode (DAY_OFF)', () {
    testWidgets(
      'switching to «Вихідний» shows ONLY the clean rest card — NO reason grid, '
      'NO note field, working-hours pickers gone (Phase 15.4 contract)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo);

        // Switch to day-off mode.
        await tester.tap(find.byKey(const Key('override-mode-dayoff')));
        await tester.pumpAndSettle();

        // The clean rest card is the ONLY day-off affordance.
        expect(find.byKey(const Key('override-dayoff-rest')), findsOneWidget);
        // The reason grid is GONE (the four chips no longer exist) …
        expect(find.byKey(const Key('override-reason-VACATION')), findsNothing);
        expect(find.byKey(const Key('override-reason-HOLIDAY')), findsNothing);
        expect(find.byKey(const Key('override-reason-SICK_DAY')), findsNothing);
        expect(find.byKey(const Key('override-reason-OTHER')), findsNothing);
        // … the note field is GONE …
        expect(find.byKey(const Key('override-note-field')), findsNothing);
        // … and the working-hours pickers are not on screen in day-off mode.
        expect(find.byKey(const Key('override-work-start')), findsNothing);
      },
    );

    testWidgets(
      'saving a day-off needs NO reason selection — the put fires a plain '
      'single-date DAY_OFF override with empty intervals',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        // No reason picked (none exists); save straight away.
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(captureAny()),
        ).captured.cast<ScheduleOverride>();
        expect(captured, hasLength(1));
        final ScheduleOverride o = captured.single;

        expect(o.kind, OverrideKind.dayOff);
        expect(o.isSingleDay, isTrue);
        expect(o.start, _date);
        expect(o.end, _date);
        expect(o.intervals, isEmpty);
      },
    );

    // REGRESSION (UI fix): the day-off rest card is wrapped in
    // `SizedBox(width: double.infinity)` so it spans the FULL sheet content
    // width (it previously sized to its child and looked shifted left). This is
    // the STRUCTURAL pin for that fix so the golden's self-referential re-bless
    // can never silently mask a regression (backlog: goldens are self-referential
    // — confirm against intent). We assert via the source Key (M2/M11: keyed
    // finder + the localised l10n value, never a raw UA literal) that:
    //   • the renamed `scheduleOverrideDayOffRest` label renders inside the card,
    //   • the card's rendered width equals the available sheet content width
    //     (proving `SizedBox(width: double.infinity)` took effect — guards the
    //     left-shift regression).
    testWidgets(
      'the day-off rest card spans full sheet width and shows the localized '
      'scheduleOverrideDayOffRest label (left-shift + rename regression)',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        final Finder card = find.byKey(const Key('override-dayoff-rest'));
        expect(card, findsOneWidget);

        // The label resolves to the renamed l10n value (not a raw UA literal),
        // read from AppLocalizations, and renders inside the keyed card.
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(l10n.scheduleOverrideDayOffRest),
          ),
          findsOneWidget,
        );

        // The card fills the full content width: the `SizedBox(width:
        // double.infinity)` constrains it to its parent's max width. The mode
        // toggle Row (key override-mode-toggle) is a sibling in the SAME padded
        // content column, so its rendered width IS the available content width —
        // the rest card must match it.
        final double cardWidth = tester.getSize(card).width;
        final double contentWidth = tester
            .getSize(find.byKey(const Key('override-mode-toggle')))
            .width;

        expect(
          cardWidth,
          moreOrLessEquals(contentWidth, epsilon: 1.0),
          reason:
              'the day-off rest card must fill the full sheet content width '
              '(SizedBox(width: double.infinity)); a narrower width means the '
              'left-shift regression returned',
        );
      },
    );

    // Golden is a SUPPLEMENTARY visual check only — the acceptance for day-off
    // mode is the STRUCTURAL assertion above (rest card present; reason grid +
    // note field absent). The PNG was re-blessed against the new clean rest-card
    // render after the structure was confirmed correct; it is not the source of
    // truth for the contract change.
    testWidgets('day-off mode (clean rest card) matches its golden', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, initialDayOff: true);

      await expectLater(
        find.byType(DayHoursSheet),
        matchesGoldenFile('goldens/day_hours_sheet_day_off.png'),
      );
    });
  });

  // ── Existing override → clear ──────────────────────────────────────────────

  group('DayHoursSheet — revert-to-template (clear) an existing override', () {
    testWidgets(
      'when an override already exists the revert action is present; tapping it '
      'calls clearOverride(date) — the clear→revert-to-template path',
      (tester) async {
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, hasExistingOverride: true);

        expect(find.byKey(const Key('override-delete')), findsOneWidget);

        // Phase 15.8: the sheet body now carries the work-mode sub-toggle +
        // discrete editor, so the content column is taller and the revert
        // action can sit below the fold of the scroll-controlled sheet. Scroll
        // it into view before tapping (mirrors the already-passing failure-path
        // test at the bottom of this file).
        await tester.ensureVisible(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.clearOverride(captureAny()),
        ).captured.cast<DateTime>();
        expect(captured, hasLength(1));
        expect(captured.single, _date);
        // No put on a clear.
        verifyNever(() => repo.putOverride(any()));
      },
    );

    // REGRESSION (Phase 15.4 rename): the clear/revert button is now the
    // non-destructive «Повернути до графіка» action — its label changed from
    // «Видалити перевизначення». We assert the new label via the keyed widget's
    // text resolving to `l10n.scheduleOverrideDelete` (M2/M11: keyed finder +
    // localised value, never a raw-string finder).
    testWidgets('the revert button (keyed override-delete) shows the new '
        '«Повернути до графіка» label', (tester) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, hasExistingOverride: true);

      final Finder button = find.byKey(const Key('override-delete'));
      expect(button, findsOneWidget);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(DayHoursSheet)),
      );
      // The label inside the keyed button resolves to the renamed l10n value.
      expect(
        find.descendant(
          of: button,
          matching: find.text(l10n.scheduleOverrideDelete),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the clear action is absent when no override exists', (
      tester,
    ) async {
      final repo = _happyRepo();
      await _pumpSheet(tester, repo: repo, hasExistingOverride: false);

      expect(find.byKey(const Key('override-delete')), findsNothing);
    });
  });

  // ── show() return contract (jump-to-changed-day fix) ───────────────────────
  //
  // `DayHoursSheet.show(...)` is now `Future<DateTime?>`: the host
  // (`master_schedule_screen._openDayOverride`) awaits it and, on a NON-null
  // result, moves the selected day onto the edited date and re-reads the fresh
  // effective schedule. These tests pin BOTH branches of that contract:
  //   • a successful save  → resolves with the edited date,
  //   • a successful clear → resolves with the edited date,
  //   • a plain dismiss / a validation bail → resolves with `null` (M3: the
  //     no-op branch is covered, not just the happy path).
  // We capture the resolved future via a host that stores it (the standard
  // `_pumpSheet` discards it).

  group('DayHoursSheet.show — resolves with the edited date / null', () {
    testWidgets(
      'a successful CUSTOM_HOURS save resolves the future with the edited date',
      (tester) async {
        final repo = _happyRepo();
        final DateTime? result = await _pumpCapturingSheet(
          tester,
          repo: repo,
          interact: (tester) async {
            await tester.tap(find.byKey(const Key('override-save')));
            await tester.pumpAndSettle();
          },
        );

        expect(result, isNotNull);
        expect(result, _date);
      },
    );

    testWidgets(
      'a successful DAY_OFF save resolves the future with the edited date',
      (tester) async {
        final repo = _happyRepo();
        final DateTime? result = await _pumpCapturingSheet(
          tester,
          repo: repo,
          initialDayOff: true,
          interact: (tester) async {
            await tester.ensureVisible(find.byKey(const Key('override-save')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('override-save')));
            await tester.pumpAndSettle();
          },
        );

        expect(result, _date);
      },
    );

    testWidgets('a successful clear resolves the future with the edited date', (
      tester,
    ) async {
      final repo = _happyRepo();
      final DateTime? result = await _pumpCapturingSheet(
        tester,
        repo: repo,
        hasExistingOverride: true,
        interact: (tester) async {
          // Phase 15.8: scroll the revert action into view first — the taller
          // work-mode-toggle body can push it below the scroll fold.
          await tester.ensureVisible(find.byKey(const Key('override-delete')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('override-delete')));
          await tester.pumpAndSettle();
        },
      );

      expect(result, _date);
      // The clear ran (not a put).
      verify(() => repo.clearOverride(any())).called(1);
      verifyNever(() => repo.putOverride(any()));
    });

    testWidgets(
      'dismissing via the close button resolves the future with null (no-op)',
      (tester) async {
        final repo = _happyRepo();
        final DateTime? result = await _pumpCapturingSheet(
          tester,
          repo: repo,
          interact: (tester) async {
            await tester.tap(find.byKey(const Key('override-close')));
            await tester.pumpAndSettle();
          },
        );

        expect(result, isNull);
        // A plain dismiss never persists anything.
        verifyNever(() => repo.putOverride(any()));
        verifyNever(() => repo.clearOverride(any()));
      },
    );

    testWidgets(
      'a validation bail (invalid window) does NOT resolve with a date: the '
      'sheet stays open, nothing is persisted, no pop',
      (tester) async {
        // Seed an INVALID working window (end before start) so `_hasErrors` is
        // true → tapping save shows the error banner and returns WITHOUT a pop.
        final repo = _happyRepo();
        DateTime? result;
        bool resolved = false;
        await _pumpSheetWithSink(
          tester,
          repo: repo,
          initialIntervals: <WorkInterval>[_interval(18, 0, 9, 0)],
          onResult: (DateTime? d) {
            resolved = true;
            result = d;
          },
        );

        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        // The future has NOT resolved (the sheet is still open) — the save was
        // a no-op validation bail, not a dismiss.
        expect(resolved, isFalse);
        expect(result, isNull);
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        verifyNever(() => repo.putOverride(any()));
      },
    );
  });

  // ── 2026-07-26 booking-conflict gate ────────────────────────────────────────
  //
  // REVERSES the former OQ-1 "always allowed" rule: a save now runs
  // `checkConflicts` (`previewConflicts` on the repository) FIRST. An empty
  // result saves exactly as before (no dialog); a non-empty result shows
  // `DayOffConflictDialog` and gates the PUT on the master's confirmation.

  group('DayHoursSheet — booking-conflict gate (2026-07-26 design)', () {
    testWidgets(
      'no conflicts on the date: save succeeds with NO confirmation dialog — '
      'the put fires directly with no intervening dialog',
      (tester) async {
        // _happyRepo's previewConflicts stub reports NO conflicts, so the save
        // must proceed exactly like the pre-conflict-gate behaviour: no dialog,
        // one put.
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        // Single pump: if a confirmation dialog gated the save, it would be on
        // screen now and the put would NOT have fired yet.
        await tester.pump();

        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsNothing,
          reason: 'an empty conflict check must not raise the conflict dialog',
        );

        await tester.pumpAndSettle();
        final captured = verify(
          () => repo.putOverride(
            captureAny(),
            cancelOverlapping: captureAny(named: 'cancelOverlapping'),
          ),
        ).captured;
        expect(captured, hasLength(2));
        // [override, cancelOverlapping] — the no-conflict path must never
        // opt in to cancelling anything.
        expect(captured[1], isFalse);
      },
    );

    testWidgets(
      'a conflict on the date shows DayOffConflictDialog; confirming saves '
      'with cancelOverlapping: true',
      (tester) async {
        final repo = _happyRepo();
        when(
          () => repo.previewConflicts(any()),
        ).thenAnswer((_) async => _oneConflict());

        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        // The dialog is up and the put has NOT fired yet.
        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsOneWidget,
        );
        verifyNever(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        );

        await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.putOverride(
            captureAny(),
            cancelOverlapping: captureAny(named: 'cancelOverlapping'),
          ),
        ).captured;
        expect(captured, hasLength(2));
        expect(
          captured[1],
          isTrue,
          reason: 'confirming must set cancelOverlapping: true',
        );

        // The sheet dismissed itself on the confirmed save (same success
        // contract as the no-conflict path).
        expect(find.byKey(const Key('override-save')), findsNothing);
      },
    );

    testWidgets(
      'a conflict on the date, backing out via «Залишити як є»: persists '
      'NOTHING — putOverride is never called, the sheet stays open',
      (tester) async {
        final repo = _happyRepo();
        when(
          () => repo.previewConflicts(any()),
        ).thenAnswer((_) async => _oneConflict());

        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('day-off-conflict-keep')));
        await tester.pumpAndSettle();

        // Backing out writes nothing — not the override, not the cancel.
        verifyNever(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        );
        // The dialog closed but the sheet is still open (the master's edit is
        // preserved, free to try again).
        expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
        expect(find.byKey(const Key('override-save')), findsOneWidget);
      },
    );
  });

  // ── mobile-qa MEDIUM — the 409-retry loop and the check-error dialog path ──
  //
  // `_saveWithConflictCheck` had two untested branches:
  //   1. a 409 (`ConflictFailure`) on the CONFIRMED put re-runs the conflict
  //      check; if the re-check is still non-empty, a FRESH explicit confirm
  //      is required (never a silent retry), bounded to
  //      `_kMaxConflictCheckAttempts` (2) rounds;
  //   2. the CHECK itself (`previewConflicts`) failing shows
  //      `DayOffCheckErrorDialog` rather than silently falling back to an
  //      unchecked save — retry re-enters the loop at the same attempt
  //      budget, backing out writes nothing.

  group('DayHoursSheet — 409-retry loop and check-error dialog paths', () {
    testWidgets(
      'a 409 on the confirmed PUT re-runs the check; the still-non-empty '
      'second check shows the dialog again for a FRESH confirm; confirming '
      'again succeeds — previewConflicts and putOverride each fire exactly '
      'twice; screenProtection.acquirerCount is asserted across BOTH rounds '
      '(mobile-security LOW — the ref-counted acquire/release around the '
      'PII-bearing dialog must not leak across a 409 retry, not merely be '
      'reasoned about from the try/finally shape)',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);

        int previewCalls = 0;
        when(() => repo.previewConflicts(any())).thenAnswer((_) async {
          previewCalls++;
          return _oneConflict();
        });

        int putCalls = 0;
        when(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        ).thenAnswer((Invocation inv) async {
          putCalls++;
          if (putCalls == 1) {
            throw const ConflictFailure();
          }
          return inv.positionalArguments.first as ScheduleOverride;
        });

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);

        expect(container.read(screenProtectionProvider).acquirerCount, 0);

        await _pumpSheetInContainer(
          tester,
          container: container,
          initialDayOff: true,
        );

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsOneWidget,
        );
        expect(
          container.read(screenProtectionProvider).acquirerCount,
          1,
          reason:
              'round 1: the dialog is on screen showing client names — '
              'protection must be held',
        );
        await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
        await tester.pumpAndSettle();

        // The first PUT 409'd: the sheet re-ran the check (round 2) and shows
        // the dialog again — NOT a silent retry.
        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsOneWidget,
          reason:
              'a 409 must re-show the conflict dialog for a FRESH confirm, '
              'never retry the put silently',
        );
        expect(previewCalls, 2);
        expect(putCalls, 1);
        expect(
          container.read(screenProtectionProvider).acquirerCount,
          1,
          reason:
              'round 2: protection must be re-acquired for the fresh dialog '
              'at exactly count 1 — a leaked round-1 acquirer that was never '
              'released would show 2 here instead',
        );

        await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
        await tester.pumpAndSettle();

        expect(putCalls, 2);
        expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
        // The sheet dismissed itself on the eventual (round-2) success.
        expect(find.byKey(const Key('override-save')), findsNothing);
        expect(
          container.read(screenProtectionProvider).acquirerCount,
          0,
          reason:
              'protection must be back to 0 once the retry loop finishes — '
              'no net leak across either round',
        );

        await _drainKeepAliveTimers(tester);
      },
    );

    testWidgets(
      'a SECOND consecutive 409 exhausts _kMaxConflictCheckAttempts (2): the '
      'failure surfaces as an error, the sheet stays open, and the loop does '
      'NOT try a third round',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);

        int previewCalls = 0;
        when(() => repo.previewConflicts(any())).thenAnswer((_) async {
          previewCalls++;
          return _oneConflict();
        });

        int putCalls = 0;
        when(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        ).thenAnswer((_) async {
          putCalls++;
          throw const ConflictFailure();
        });

        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
        await tester.pumpAndSettle();

        // Round 2: dialog again, confirm again — this is the SECOND
        // consecutive 409, which must exhaust the budget.
        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
        await tester.pumpAndSettle();

        expect(
          previewCalls,
          2,
          reason:
              'exactly 2 rounds — the loop must NOT attempt a third check '
              'after the second 409',
        );
        expect(putCalls, 2);
        expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
        // The sheet stays open with the mapped failure message — no pop, no
        // success snackbar.
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        expect(find.text(l10n.errConflict), findsOneWidget);
        expect(find.text(l10n.savedSnackbar), findsNothing);
      },
    );

    testWidgets(
      'the conflict CHECK itself failing (network/server error) shows '
      'DayOffCheckErrorDialog instead of saving blind; tapping retry re-runs '
      'the check and — once it succeeds — proceeds normally',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);
        when(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        ).thenAnswer(
          (inv) async => inv.positionalArguments.first as ScheduleOverride,
        );

        int previewCalls = 0;
        when(() => repo.previewConflicts(any())).thenAnswer((_) async {
          previewCalls++;
          if (previewCalls == 1) {
            throw const NetworkFailure();
          }
          return _noConflicts;
        });

        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        // The CHECK itself failed — the error dialog, not the conflict
        // dialog, and NO put has fired. NOTE: both dialogs share the SAME
        // `_DialogShell` and therefore the SAME `day-off-conflict-dialog`
        // key on their NeumorphicCard — distinguish by WIDGET TYPE, not key.
        expect(find.byType(DayOffConflictDialog), findsNothing);
        expect(find.byType(DayOffCheckErrorDialog), findsOneWidget);
        expect(
          find.byKey(const Key('day-off-check-retry')),
          findsOneWidget,
          reason:
              'a failed check must show DayOffCheckErrorDialog, never '
              'fall back to an unchecked save',
        );
        verifyNever(
          () => repo.putOverride(
            any(),
            cancelOverlapping: any(named: 'cancelOverlapping'),
          ),
        );

        await tester.tap(find.byKey(const Key('day-off-check-retry')));
        await tester.pumpAndSettle();

        expect(previewCalls, 2);
        // Round 2 succeeded with an empty check, so the save proceeded with
        // NO conflict dialog — exactly the no-conflict happy path.
        expect(find.byType(DayOffConflictDialog), findsNothing);
        expect(find.byType(DayOffCheckErrorDialog), findsNothing);
        expect(find.byKey(const Key('override-save')), findsNothing);
        final captured = verify(
          () => repo.putOverride(
            captureAny(),
            cancelOverlapping: captureAny(named: 'cancelOverlapping'),
          ),
        ).captured;
        expect(captured, hasLength(2));
        expect(
          captured[1],
          isFalse,
          reason: 'the recovered check was empty — no cancel consent needed',
        );
      },
    );

    testWidgets(
      'backing out of DayOffCheckErrorDialog writes nothing and leaves the '
      'sheet open',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);
        when(
          () => repo.previewConflicts(any()),
        ).thenAnswer((_) async => throw const NetworkFailure());

        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('day-off-check-retry')), findsOneWidget);

        await tester.tap(find.byKey(const Key('day-off-check-keep')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('day-off-check-retry')), findsNothing);
        verifyNever(() => repo.putOverride(any()));
        expect(find.byKey(const Key('override-save')), findsOneWidget);
      },
    );
  });

  // ── mobile-security MEDIUM — screen protection around the conflict dialog ──
  //
  // `DayOffConflictDialog` renders every affected booking's
  // `clientDisplayName` (PII). Every other PII-bearing screen acquires
  // `screenProtectionProvider` for its whole lifetime; this dialog is not a
  // screen, so `_saveWithConflictCheck` acquires immediately before showing
  // it and releases in a `finally` the instant it resolves. These tests pin
  // that ref-counted acquire/release directly on the manager
  // (`ScreenProtectionManager.acquirerCount`), not just the control flow.

  group('DayHoursSheet — screen protection around the conflict dialog', () {
    testWidgets(
      'the conflict dialog is up: screenProtection is acquired (count 1); '
      'confirming releases it (count 0)',
      (tester) async {
        final repo = _happyRepo();
        when(
          () => repo.previewConflicts(any()),
        ).thenAnswer((_) async => _oneConflict());

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);

        expect(container.read(screenProtectionProvider).acquirerCount, 0);

        await _pumpSheetInContainer(
          tester,
          container: container,
          initialDayOff: true,
        );

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('day-off-conflict-dialog')),
          findsOneWidget,
        );
        expect(
          container.read(screenProtectionProvider).acquirerCount,
          1,
          reason:
              'the dialog is on screen showing client names — protection '
              'must be held for as long as it is visible',
        );

        await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
        await tester.pumpAndSettle();

        expect(
          container.read(screenProtectionProvider).acquirerCount,
          0,
          reason: 'protection must release the instant the dialog resolves',
        );

        await _drainKeepAliveTimers(tester);
      },
    );

    testWidgets(
      'backing out of the conflict dialog («Залишити як є») also releases '
      'screenProtection — the release must not depend on which exit was taken',
      (tester) async {
        final repo = _happyRepo();
        when(
          () => repo.previewConflicts(any()),
        ).thenAnswer((_) async => _oneConflict());

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);

        await _pumpSheetInContainer(
          tester,
          container: container,
          initialDayOff: true,
        );

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        expect(container.read(screenProtectionProvider).acquirerCount, 1);

        await tester.tap(find.byKey(const Key('day-off-conflict-keep')));
        await tester.pumpAndSettle();

        expect(container.read(screenProtectionProvider).acquirerCount, 0);

        await _drainKeepAliveTimers(tester);
      },
    );
  });

  // ── mobile-qa LOW — invalidation is asserted DIRECTLY, not inferred ────────
  //
  // `invalidateBookingViewsAfterExternalDecline` (`booking_calendar_
  // invalidation.dart`) is only exercised end-to-end today via
  // `integration_test/schedule_override_conflict_flow_test.dart`, which infers
  // it ran through a SIDE EFFECT — the fake backend's seeded booking flipping
  // CONFIRMED → DECLINED. That proves the WRITE happened; it says nothing
  // about whether the three provider families the function targets
  // (`bookingDetailProvider`, `bookingsDayProvider`, `myBookingsProvider`
  // upcoming/cancelled) were actually invalidated. This test asserts that
  // directly: it holds a LIVE subscription on each targeted provider (so an
  // invalidation triggers a real refetch instead of Riverpod merely dropping
  // an unwatched member) and counts refetches before/after confirming the
  // conflict dialog.
  //
  // TRAP AVOIDED: `ref.invalidate` on an already-loaded provider performs a
  // SEAMLESS reload — the previous `.value` is retained while the new fetch
  // is in flight (Riverpod 3.x). A null-then-value assertion would therefore
  // never fire; the refetch COUNT is the only reliable signal.

  group('DayHoursSheet — booking-calendar invalidation is asserted directly '
      '(not merely inferred from a fake-backend side effect)', () {
    testWidgets('confirming a conflict invalidates bookingDetailProvider(id), '
        'bookingsDayProvider(day) and BOTH myBookingsProvider tabs — asserted '
        'via live-subscriber refetch counts', (tester) async {
      final scheduleRepo = _happyRepo();
      when(
        () => scheduleRepo.previewConflicts(any()),
      ).thenAnswer((_) async => _oneConflict());

      final bookingRepo = _MockBookingRepository();
      int detailFetches = 0;
      when(() => bookingRepo.getBookingById(any())).thenAnswer((_) async {
        detailFetches++;
        return _conflictBooking();
      });

      int dayFetches = 0;
      int upcomingFetches = 0;
      int cancelledFetches = 0;
      when(
        () => bookingRepo.getMyBookings(
          statuses: any(named: 'statuses'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          sort: any(named: 'sort'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((Invocation inv) async {
        final DateTime? from = inv.namedArguments[#from] as DateTime?;
        final Iterable<BookingStatus> statuses =
            inv.namedArguments[#statuses] as Iterable<BookingStatus>;
        if (from != null) {
          dayFetches++;
        } else if (statuses.contains(BookingStatus.cancelled)) {
          cancelledFetches++;
        } else {
          upcomingFetches++;
        }
        return const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        );
      });

      final container = ProviderContainer(
        overrides: <Object>[
          scheduleRepositoryProvider.overrideWithValue(scheduleRepo),
          bookingRepositoryProvider.overrideWithValue(bookingRepo),
          authProvider.overrideWith(_StubAuthNotifier.new),
        ].cast(),
      );
      addTearDown(container.dispose);
      await container.read(authProvider.future);

      // Hold LIVE subscriptions on every targeted provider so an
      // `invalidate()` triggers a genuine refetch instead of Riverpod
      // simply dropping an unwatched autoDispose member.
      final BookingsDayQuery dayQuery = BookingsDayQuery.of(day: _date);
      final detailSub = container.listen(
        bookingDetailProvider('booking-1'),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(detailSub.close);
      await container.read(bookingDetailProvider('booking-1').future);

      final daySub = container.listen(
        bookingsDayProvider(dayQuery),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(daySub.close);
      await container.read(bookingsDayProvider(dayQuery).future);

      final upcomingSub = container.listen(
        myBookingsProvider(BookingTab.upcoming),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(upcomingSub.close);
      await container.read(myBookingsProvider(BookingTab.upcoming).future);

      final cancelledSub = container.listen(
        myBookingsProvider(BookingTab.cancelled),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cancelledSub.close);
      await container.read(myBookingsProvider(BookingTab.cancelled).future);

      final int detailBefore = detailFetches;
      final int dayBefore = dayFetches;
      final int upcomingBefore = upcomingFetches;
      final int cancelledBefore = cancelledFetches;

      await _pumpSheetInContainer(
        tester,
        container: container,
        initialDayOff: true,
      );

      await tester.ensureVisible(find.byKey(const Key('override-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('override-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('day-off-conflict-confirm')));
      await tester.pumpAndSettle();

      expect(
        detailFetches,
        greaterThan(detailBefore),
        reason:
            'bookingDetailProvider(bookingId) must be invalidated and '
            'refetched for every declined booking id',
      );
      expect(
        dayFetches,
        greaterThan(dayBefore),
        reason:
            'bookingsDayProvider(BookingsDayQuery.of(day: affected date)) '
            'must be invalidated and refetched after a confirmed decline',
      );
      expect(
        upcomingFetches,
        greaterThan(upcomingBefore),
        reason:
            'the upcoming tab must be invalidated — a DECLINED '
            'booking leaves it',
      );
      expect(
        cancelledFetches,
        greaterThan(cancelledBefore),
        reason:
            'the cancelled tab must be invalidated — a DECLINED '
            'booking enters it',
      );

      await _drainKeepAliveTimers(tester);
    });
  });

  // ── Failure path → AsyncError surfaced, sheet stays open (false-success fix) ─
  //
  // RESOLVED (false-success MEDIUM): `OverridesNotifier.putOverride` /
  // `.clearOverride` wrap their work in `AsyncValue.guard`, which SWALLOWS a
  // thrown `Failure` into the provider's `AsyncError` STATE and returns
  // NORMALLY — the awaited mutation never throws back to the widget. The sheet
  // therefore reads the POST-await provider state and branches on `hasError`:
  // on failure it KEEPS the sheet open and shows the failure message, with NO
  // pop and NO success snackbar. These tests pin that correct behaviour.
  //
  // We assert against a fresh container (whose autoDispose family stays alive
  // via a held subscription) so the AsyncError the sheet observed is the same
  // state we read back afterwards.

  group('DayHoursSheet — save failure (false-success guard)', () {
    testWidgets(
      'a repository failure on put surfaces in provider state AND keeps the '
      'sheet open with an error message — no pop, no success snackbar',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);
        when(
          () => repo.previewConflicts(any()),
        ).thenAnswer((_) async => _noConflicts);
        when(
          () => repo.putOverride(any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);
        // Hold a live subscription so the autoDispose family is NOT torn down
        // (the sheet stays open here, but this keeps the read-back state stable).
        final sub = container.listen(
          overridesProvider(_range),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await container.read(overridesProvider(_range).future);

        await _pumpSheetInContainer(tester, container: container);

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        // The put was attempted exactly once.
        verify(() => repo.putOverride(any())).called(1);
        // The error landed in provider state (the notifier's AsyncError).
        final state = container.read(overridesProvider(_range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ServerFailure>());

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        // The sheet STAYS OPEN — the save button is still on screen.
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        // The mapped failure message is shown …
        expect(find.text(l10n.errServer), findsOneWidget);
        // … and the success copy is ABSENT.
        expect(find.text(l10n.savedSnackbar), findsNothing);

        // The real OverridesNotifier parked a 5-min keepAlive release timer;
        // drain it so the FakeAsync teardown sees zero pending timers.
        await _drainKeepAliveTimers(tester);
      },
    );

    testWidgets(
      'a repository failure on clear surfaces in provider state AND keeps the '
      'sheet open with an error message — no pop, no cleared snackbar',
      (tester) async {
        final repo = _MockScheduleRepository();
        when(
          () => repo.listOverrides(any(), any()),
        ).thenAnswer((_) async => const <ScheduleOverride>[]);
        when(
          () => repo.clearOverride(any()),
        ).thenThrow(const ServerFailure(statusCode: 500));

        final container = ProviderContainer(
          overrides: <Object>[
            scheduleRepositoryProvider.overrideWithValue(repo),
          ].cast(),
        );
        addTearDown(container.dispose);
        final sub = container.listen(
          overridesProvider(_range),
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await container.read(overridesProvider(_range).future);

        // hasExistingOverride → the «Видалити» (clear) action is present.
        await _pumpSheetInContainer(
          tester,
          container: container,
          hasExistingOverride: true,
        );

        await tester.ensureVisible(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-delete')));
        await tester.pumpAndSettle();

        // The clear was attempted exactly once; no put on a clear.
        verify(() => repo.clearOverride(any())).called(1);
        verifyNever(() => repo.putOverride(any()));
        // The error landed in provider state.
        final state = container.read(overridesProvider(_range));
        expect(state.hasError, isTrue);
        expect(state.error, isA<ServerFailure>());

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        // The sheet STAYS OPEN — the clear action is still on screen.
        expect(find.byKey(const Key('override-delete')), findsOneWidget);
        // The mapped failure message is shown …
        expect(find.text(l10n.errServer), findsOneWidget);
        // … and the cleared-success copy is ABSENT.
        expect(find.text(l10n.scheduleOverrideClearedSnack), findsNothing);

        // Drain the real OverridesNotifier's 5-min keepAlive release timer.
        await _drainKeepAliveTimers(tester);
      },
    );
  });

  // ── M6 — submit-time past-date guard (midnight rollover while open) ─────────
  //
  // The sheet is only ever OPENED for today/future days (the caller hides the
  // pencil on past ones), but a midnight rollover WHILE the sheet sits open can
  // turn the target [date] past between open and Save. A past `start` would 400
  // at the backend (@FutureOrPresent). The fix threads a LIVE
  // `DateTime Function()? clock` into the sheet and, at submit, re-validates the
  // target date against a FRESH today: a now-past date shows the
  // `schedulePastDayBlocked` snackbar and returns BEFORE `putOverride`.
  //
  // We advance the injected clock between open and Save (no new production seam —
  // the dev made the clock live). RED-ON-PRE-FIX: without the submit-time guard
  // the Save would PUT the override for the now-yesterday date, so
  // `verifyNever(putOverride)` fails and the block snackbar never shows.
  group('DayHoursSheet — M6 submit-time past-date guard (rollover)', () {
    testWidgets(
      'a rollover that turns the target date past between open and Save BLOCKS '
      'the put and shows schedulePastDayBlocked — sheet stays open',
      (tester) async {
        final repo = _happyRepo();
        // Live clock starts on the target date (today) and is advanced to the
        // next day AFTER the sheet is open but BEFORE Save.
        DateTime now = _date;
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Object>[
              scheduleRepositoryProvider.overrideWithValue(repo),
            ].cast(),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
              home: Scaffold(
                body: Builder(
                  builder: (BuildContext context) => Center(
                    child: ElevatedButton(
                      key: const Key('open-sheet'),
                      onPressed: () => DayHoursSheet.show(
                        context,
                        date: _date,
                        weekdayFull: 'Неділя',
                        dateLabel: '21 червня',
                        range: _range,
                        initialIntervals: _currentIntervals(),
                        hasExistingOverride: false,
                        initialDayOff: false,
                        clock: () => now,
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('open-sheet')));
        await tester.pumpAndSettle();

        // ── Cross midnight while the sheet is open: today is now _date + 1, so
        // the target [date] has fallen into the past. ──
        now = _date.add(const Duration(days: 1));

        // Save — the submit-time guard must block the PUT.
        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );
        // The block snackbar is shown …
        expect(
          find.text(l10n.schedulePastDayBlocked),
          findsOneWidget,
          reason: 'a now-past target date must surface the blocked-day copy',
        );
        // … the override was NEVER put (the guard returns before persistence) …
        verifyNever(() => repo.putOverride(any()));
        // … and the sheet stays open (no dismiss, no success snackbar).
        expect(find.byKey(const Key('override-save')), findsOneWidget);
        expect(find.text(l10n.savedSnackbar), findsNothing);
      },
    );

    testWidgets(
      'NO rollover (target date still today at Save) puts the override normally '
      '— the guard does not block a still-valid date',
      (tester) async {
        // Control case: the clock never advances, so the target stays today and
        // the put proceeds. Proves the guard is scoped to the rollover, not a
        // blanket block. (The fixed-clock _pumpSheet already injects _testToday.)
        final repo = _happyRepo();
        await _pumpSheet(tester, repo: repo, initialDayOff: true);

        // Resolve l10n while the sheet is still mounted (a successful save
        // dismisses it).
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(DayHoursSheet)),
        );

        await tester.ensureVisible(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('override-save')));
        await tester.pumpAndSettle();

        verify(() => repo.putOverride(any())).called(1);
        expect(find.text(l10n.schedulePastDayBlocked), findsNothing);
      },
    );
  });
}

/// Pumps the sheet over an externally-built [container] (so the caller can hold
/// a live subscription and read the provider's post-mutation state back). Mirror
/// of [_pumpSheet] but bound to an [UncontrolledProviderScope].
Future<void> _pumpSheetInContainer(
  WidgetTester tester, {
  required ProviderContainer container,
  bool hasExistingOverride = false,
  bool initialDayOff = true,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () => DayHoursSheet.show(
                  context,
                  date: _date,
                  weekdayFull: 'Неділя',
                  dateLabel: '21 червня',
                  range: _range,
                  initialIntervals: _currentIntervals(),
                  hasExistingOverride: hasExistingOverride,
                  initialDayOff: initialDayOff,
                  clock: _testToday,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}

/// Pumps the sheet, opens it, runs [interact], and RETURNS the value the
/// `DayHoursSheet.show(...)` future resolved to. Mirrors [_pumpSheet] but keeps
/// the awaited future so the `Future<DateTime?>` show-contract can be asserted.
Future<DateTime?> _pumpCapturingSheet(
  WidgetTester tester, {
  required ScheduleRepository repo,
  required Future<void> Function(WidgetTester) interact,
  bool hasExistingOverride = false,
  bool initialDayOff = false,
}) async {
  DateTime? captured;
  await _pumpSheetWithSink(
    tester,
    repo: repo,
    hasExistingOverride: hasExistingOverride,
    initialDayOff: initialDayOff,
    onResult: (DateTime? d) => captured = d,
  );
  await interact(tester);
  return captured;
}

/// Host whose button presents the sheet and pipes the resolved `Future<DateTime?>`
/// into [onResult]. The sink fires once the sheet's future completes (on a
/// save / clear / dismiss); it is NEVER called while the sheet stays open (e.g.
/// after a validation bail), which is what lets the bail test assert the future
/// has not resolved.
Future<void> _pumpSheetWithSink(
  WidgetTester tester, {
  required ScheduleRepository repo,
  required void Function(DateTime?) onResult,
  List<WorkInterval>? initialIntervals,
  bool hasExistingOverride = false,
  bool initialDayOff = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        scheduleRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () async {
                  final DateTime? r = await DayHoursSheet.show(
                    context,
                    date: _date,
                    weekdayFull: 'Неділя',
                    dateLabel: '21 червня',
                    range: _range,
                    initialIntervals: initialIntervals ?? _currentIntervals(),
                    hasExistingOverride: hasExistingOverride,
                    initialDayOff: initialDayOff,
                    clock: _testToday,
                  );
                  onResult(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
}
