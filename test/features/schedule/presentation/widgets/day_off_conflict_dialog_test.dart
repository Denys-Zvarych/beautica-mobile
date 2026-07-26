// mobile-qa (2026-07-26 booking-conflict design) — widget-level regression
// guards for `DayOffConflictDialog` that `day_hours_sheet_test.dart`'s
// booking-conflict-gate group does NOT cover (that group only proves the
// gate's CONTROL FLOW — dialog shows on conflicts, confirm sets
// `cancelOverlapping: true`, back-out writes nothing). This file covers the
// dialog's own CONTENT and SHAPE contract:
//
//   1. no note field (D2 — a master gives no reason for a day off; a future
//      contributor must not re-add one);
//   2. Ukrainian plural forms for the count (1 / 2-4 / 5+);
//   3. `truncated` / `scanTruncated` → the header count must never read as a
//      false EXACT number — see the dedicated group below for a genuine
//      finding this test surfaces;
//   4. the 1-row and ~20-row layouts both fit at a small phone size (the
//      designer fixed a real 48px overflow at 320×560 with 20 rows — this
//      pins it via the suite-wide overflow guard, `pumpApp` installs it
//      automatically);
//   5. barrier tap / OS back gesture resolve to CANCEL (`null`), never
//      confirm.
//
// Drives `showDayOffConflictDialog` directly (the same entry point
// `DayHoursSheet._saveWithConflictCheck` uses) so the resolved value is
// asserted at the source, exactly like `cancel_booking_dialog_test.dart`.

import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/day_off_conflict_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

OverrideConflict _conflict({
  String bookingId = 'b1',
  DateTime? date,
  String client = 'Олена Гриценко',
  String service = 'Манікюр з покриттям',
}) {
  final DateTime d = date ?? DateTime(2026, 7, 27);
  return OverrideConflict(
    bookingId: bookingId,
    appointmentId: null,
    date: d,
    startsAt: DateTime.utc(d.year, d.month, d.day, 10),
    endsAt: DateTime.utc(d.year, d.month, d.day, 11),
    clientDisplayName: client,
    serviceName: service,
  );
}

List<OverrideConflict> _nConflictsSameDay(int n) =>
    List<OverrideConflict>.generate(
      n,
      (i) => _conflict(bookingId: 'b$i', client: 'Клієнт $i'),
    );

OverrideConflictCheck _check(
  List<OverrideConflict> conflicts, {
  int? totalCount,
  bool truncated = false,
  bool scanTruncated = false,
}) => OverrideConflictCheck(
  conflicts: conflicts,
  totalCount: totalCount ?? conflicts.length,
  truncated: truncated,
  scanTruncated: scanTruncated,
);

DayOffConflictPreview _preview(
  OverrideConflictCheck check, {
  DayOffChangeKind kind = DayOffChangeKind.singleDay,
}) => DayOffConflictPreview(
  kind: kind,
  from: DateTime(2026, 7, 27),
  to: DateTime(2026, 7, 27),
  check: check,
);

void main() {
  /// Pumps a host that opens the dialog on first frame and captures its
  /// resolved value (`true` = confirmed, `null`/other = backed out).
  Future<void> pumpDialog(
    WidgetTester tester,
    DayOffConflictPreview preview, {
    required void Function(bool?) onResolved,
    double? width,
    double? height,
  }) async {
    if (width != null || height != null) {
      tester.view.physicalSize = Size(width ?? 800, height ?? 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpApp(
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                final bool? r = await showDayOffConflictDialog(
                  context,
                  preview,
                );
                onResolved(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day-off-conflict-dialog')), findsOneWidget);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byKey(const Key('open'))));

  // ── 1. No note field (D2) ───────────────────────────────────────────────

  testWidgets(
    'the dialog carries NO note/reason input — a master gives no reason for '
    'a day off (D2, 2026-07-26 REVISION superseding the earlier optional-note '
    'design)',
    (tester) async {
      await pumpDialog(
        tester,
        _preview(_check(_nConflictsSameDay(2))),
        onResolved: (_) {},
      );

      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'no free-text input of any kind belongs in this dialog',
      );
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  // ── 2. Ukrainian plural forms ────────────────────────────────────────────

  for (final int n in <int>[1, 3, 11]) {
    testWidgets(
      'title renders the exact UA plural form for n=$n via AppLocalizations '
      '(1=one, 3=few, 11=many — the "teen" many-exception)',
      (tester) async {
        await pumpDialog(
          tester,
          _preview(_check(_nConflictsSameDay(n))),
          onResolved: (_) {},
        );
        final AppLocalizations l10n = l10nOf(tester);
        final String expectedPhrase = l10n.dayOffConflictCountPhrase(n);
        final String expectedTitle = l10n.dayOffConflictTitleSingleDay(
          expectedPhrase,
        );
        expect(
          find.text(expectedTitle),
          findsOneWidget,
          reason:
              'n=$n must resolve through the real ICU plural category, not '
              'a hardcoded suffix',
        );
      },
    );
  }

  // ── 3. truncated / scanTruncated → never a false EXACT count ────────────
  //
  // Per `OverrideConflictCheck`'s own doc: `totalCount` is the AUTHORITATIVE
  // count — equal to `conflicts.length` only in the untruncated case.
  // `isCountExact` (`!scanTruncated`) decides which l10n phrase (exact vs.
  // "щонайменше" approx) to use, but EITHER phrase must be filled with
  // `totalCount`, never `conflicts.length` — that field is only "how many
  // rows the trough happens to render".

  group('truncated / scanTruncated header count', () {
    testWidgets(
      'scanTruncated=true selects the APPROX phrase template ("щонайменше '
      'N"), never the plain-exact one',
      (tester) async {
        // Selects the APPROX phrase template AND asserts the number filling
        // it — `totalCount` (the authoritative count; see the "FINDING" case
        // below, now fixed: `DayOffConflictPreview.count` reads
        // `check.totalCount`, never `check.conflicts.length`).
        final check = _check(
          _nConflictsSameDay(5),
          totalCount: 500,
          truncated: true,
          scanTruncated: true,
        );
        await pumpDialog(tester, _preview(check), onResolved: (_) {});
        final AppLocalizations l10n = l10nOf(tester);

        expect(
          check.isCountExact,
          isFalse,
          reason: 'sanity: scanTruncated must flip isCountExact false',
        );
        // Compare the FULL composed title by equality, not substring
        // containment — the approx phrase ("щонайменше 500 записів") contains
        // the plain-exact phrase ("500 записів") as a literal substring, so a
        // `textContaining` check on the tail alone can't tell them apart.
        final String plainExactTitle = l10n.dayOffConflictTitleSingleDay(
          l10n.dayOffConflictCountPhrase(check.totalCount),
        );
        final String approxTitle = l10n.dayOffConflictTitleSingleDay(
          l10n.dayOffConflictCountPhraseApprox(check.totalCount),
        );
        expect(
          find.text(approxTitle),
          findsOneWidget,
          reason: 'scanTruncated must select the approx phrase template',
        );
        expect(
          find.text(plainExactTitle),
          findsNothing,
          reason:
              'scanTruncated must never fall through to the plain-exact '
              'phrase template',
        );
      },
    );

    testWidgets(
      'FINDING: truncated=true, scanTruncated=false — the header must show '
      'the AUTHORITATIVE totalCount (still exact per OverrideConflictCheck\'s '
      'own doc), not conflicts.length (the number of ROWS the server happened '
      'to return before capping the result list)',
      (tester) async {
        // 8 real conflicts exist (totalCount=8, scan NOT capped → still an
        // exact figure), but the server trimmed the RESULT LIST to 5 rows
        // (truncated=true). isCountExact is true here (scanTruncated=false),
        // so the dialog must use the EXACT phrase — but filled with 8, the
        // true count, not 5, the row count.
        final check = _check(
          _nConflictsSameDay(5),
          totalCount: 8,
          truncated: true,
        );
        await pumpDialog(tester, _preview(check), onResolved: (_) {});
        final AppLocalizations l10n = l10nOf(tester);

        expect(check.isCountExact, isTrue, reason: 'sanity check');

        final String correctTitle = l10n.dayOffConflictTitleSingleDay(
          l10n.dayOffConflictCountPhrase(8),
        );
        expect(
          find.text(correctTitle),
          findsOneWidget,
          reason:
              'DayOffConflictDialog.count reads check.conflicts.length '
              '(row count = 5) instead of check.totalCount (true count = 8) — '
              'a master who saved a day off with 8 real conflicts sees "5 '
              'записів", an UNDERCOUNT presented as an exact figure. This is '
              'a genuine production bug (day_off_conflict_dialog.dart:93 '
              '`int get count => check.conflicts.length;`), reported to '
              'mobile-dev rather than patched here.',
        );
      },
      // Documents a REAL bug found during this audit — see the reason string
      // and the QA report. Left failing on purpose rather than weakened.
    );
  });

  // ── 4. Layout fits at a small phone size — 1 row and ~20 rows ───────────
  //
  // No manual overflow assertion needed: `pumpApp` installs the suite-wide
  // overflow guard (`test/helpers/overflow_guard.dart`), which fails the test
  // automatically if ANY `RenderFlex overflowed` diagnostic fires during the
  // pump. This pins the designer's real 48px-overflow-at-320×560-with-20-rows
  // fix so it cannot silently regress.

  testWidgets(
    'a single-row conflict list fits at 320×560 with no layout overflow',
    (tester) async {
      await pumpDialog(
        tester,
        _preview(_check(_nConflictsSameDay(1))),
        onResolved: (_) {},
        width: 320,
        height: 560,
      );
      expect(find.byKey(const Key('day-off-conflict-confirm')), findsOneWidget);
      expect(find.byKey(const Key('day-off-conflict-keep')), findsOneWidget);
    },
  );

  testWidgets(
    'a twenty-row conflict list fits at 320×560 with no layout overflow — '
    'the trough scrolls internally, the action buttons never do',
    (tester) async {
      await pumpDialog(
        tester,
        _preview(_check(_nConflictsSameDay(20))),
        onResolved: (_) {},
        width: 320,
        height: 560,
      );
      expect(find.byKey(const Key('day-off-conflict-confirm')), findsOneWidget);
      expect(find.byKey(const Key('day-off-conflict-keep')), findsOneWidget);
    },
  );

  // ── 5. Barrier tap / back gesture → CANCEL, never confirm ───────────────

  testWidgets('tapping the scrim barrier resolves to CANCEL (not true)', (
    tester,
  ) async {
    bool? resolved;
    bool done = false;
    await pumpDialog(
      tester,
      _preview(_check(_nConflictsSameDay(2))),
      onResolved: (bool? r) {
        resolved = r;
        done = true;
      },
    );

    // Tap a corner well outside the centred, width-capped dialog card.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(done, isTrue, reason: 'the barrier tap must dismiss the dialog');
    expect(
      resolved,
      isNot(true),
      reason: 'a scrim tap must never be treated as "yes, cancel the bookings"',
    );
    expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
  });

  testWidgets(
    'the OS back gesture resolves to CANCEL (not true) and writes nothing',
    (tester) async {
      bool? resolved;
      bool done = false;
      await pumpDialog(
        tester,
        _preview(_check(_nConflictsSameDay(2))),
        onResolved: (bool? r) {
          resolved = r;
          done = true;
        },
      );

      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue, reason: 'the dialog route must consume back');
      expect(done, isTrue);
      expect(
        resolved,
        isNot(true),
        reason: 'the back gesture must never resolve to a confirmed cancel',
      );
      expect(find.byKey(const Key('day-off-conflict-dialog')), findsNothing);
    },
  );
}
