// mobile-qa gap-fix (KNOWN COVERAGE GAP 2) — widget tests for
// `ClientBookingConflictDialog` (`widgets/client_booking_conflict_dialog.dart`).
// There was NO test for this dialog before this file.
//
// Covers:
//   1. The dialog renders the clashing service name, master name, and a
//      FORMATTED time window (via `formatBookingWindow` — the same shared
//      formatter every other booking screen uses), never the raw ISO
//      `startsAt`/`endsAt` strings.
//   2. Both CTAs are present and resolve the awaited `showDialog` future with
//      the documented value: "Обрати інший час" → `true`, "Залишитись тут" →
//      `false`.
//   3. Security-fix regression guard: an absurdly long / newline-heavy
//      `serviceName` or `masterName` (untrusted, backend/user-authored free
//      text) is ellipsized (`maxLines: 2`, `TextOverflow.ellipsis` — the
//      `LabelledRow.maxLines`/`overflow` params this dialog's call sites
//      pass) and must never overflow the layout or throw a RenderFlex
//      overflow error.
//
// No `dismissOverlay` router dependency — the dialog only ever calls
// `Navigator.of(context).pop(...)` (see the widget's file header "NAVIGATION
// SPLIT" note), so a plain `pumpApp` MaterialApp `home` (no go_router) is
// sufficient; no `context.pop()`/go_router call happens inside the dialog.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/client_booking_conflict_dialog.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/labelled_row.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

ClientBookingConflictFailure _failure({
  String serviceName = 'Манікюр класичний',
  String masterName = 'Олена Коваль',
  DateTime? startsAt,
  DateTime? endsAt,
}) => ClientBookingConflictFailure(
  conflictingBookingId: 'conflict-booking-1',
  serviceName: serviceName,
  masterName: masterName,
  startsAt: startsAt ?? DateTime.utc(2026, 7, 15, 14),
  endsAt: endsAt ?? DateTime.utc(2026, 7, 15, 15, 30),
);

/// Pumps a trigger button that opens the dialog for [failure] and records the
/// resolved value in [result] once the awaited future settles.
Future<void> _pumpAndOpen(
  WidgetTester tester,
  ClientBookingConflictFailure failure,
  ValueNotifier<bool?> resultHolder,
) async {
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          key: const Key('trigger'),
          onPressed: () async {
            final bool? result = await showClientBookingConflictDialog(
              context,
              failure,
            );
            resultHolder.value = result;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pumpAndSettle();
}

void main() {
  group('ClientBookingConflictDialog', () {
    testWidgets(
      'renders the clashing service name, master name, and a FORMATTED '
      'time window — never the raw ISO strings',
      (tester) async {
        final DateTime starts = DateTime.utc(2026, 7, 15, 14);
        final DateTime ends = DateTime.utc(2026, 7, 15, 15, 30);
        final failure = _failure(startsAt: starts, endsAt: ends);
        final resultHolder = ValueNotifier<bool?>(null);
        addTearDown(resultHolder.dispose);

        await _pumpAndOpen(tester, failure, resultHolder);

        expect(
          find.byKey(const Key('client-booking-conflict-dialog')),
          findsOneWidget,
        );
        // i18n-finder-ok: service/master names are fixture data carried on
        // the Failure object, not translated UI copy.
        expect(find.text('Манікюр класичний'), findsOneWidget);
        expect(find.text('Олена Коваль'), findsOneWidget);

        final String expectedWindow = formatBookingWindow(starts, ends);
        expect(find.text(expectedWindow), findsOneWidget);

        // The raw ISO strings must never appear on screen.
        expect(find.text(starts.toIso8601String()), findsNothing);
        expect(find.text(ends.toIso8601String()), findsNothing);
        expect(find.textContaining('T14:00:00'), findsNothing);
      },
    );

    testWidgets('both CTAs are present: pick-another-time and stay-here', (
      tester,
    ) async {
      final resultHolder = ValueNotifier<bool?>(null);
      addTearDown(resultHolder.dispose);

      await _pumpAndOpen(tester, _failure(), resultHolder);

      expect(
        find.byKey(const Key('client-booking-conflict-pick-another-time')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('client-booking-conflict-stay')),
        findsOneWidget,
      );
    });

    testWidgets(
      'tapping «Обрати інший час» resolves the awaited future with true and '
      'closes the dialog',
      (tester) async {
        final resultHolder = ValueNotifier<bool?>(null);
        addTearDown(resultHolder.dispose);

        await _pumpAndOpen(tester, _failure(), resultHolder);

        await tester.tap(
          find.byKey(const Key('client-booking-conflict-pick-another-time')),
        );
        await tester.pumpAndSettle();

        expect(resultHolder.value, isTrue);
        expect(
          find.byKey(const Key('client-booking-conflict-dialog')),
          findsNothing,
          reason: 'the dialog must have closed itself via Navigator.pop',
        );
      },
    );

    testWidgets(
      'tapping «Залишитись тут» resolves the awaited future with false and '
      'closes the dialog',
      (tester) async {
        final resultHolder = ValueNotifier<bool?>(null);
        addTearDown(resultHolder.dispose);

        await _pumpAndOpen(tester, _failure(), resultHolder);

        await tester.tap(find.byKey(const Key('client-booking-conflict-stay')));
        await tester.pumpAndSettle();

        expect(resultHolder.value, isFalse);
        expect(
          find.byKey(const Key('client-booking-conflict-dialog')),
          findsNothing,
        );
      },
    );

    // -------------------------------------------------------------------
    // Security regression guard: an absurdly long / newline-heavy
    // serviceName/masterName must be ellipsized (maxLines: 2), never
    // overflow the dialog's fixed-width layout.
    // -------------------------------------------------------------------
    testWidgets(
      'an absurdly long, newline-heavy serviceName/masterName is ellipsized '
      '(maxLines: 2) and does not overflow the layout',
      (tester) async {
        const String hostile =
            'Дуже дуже дуже дуже довга назва послуги, яка ніколи не мала б '
            'вміщатися в один рядок і навіть у два рядки без обрізання тексту '
            '\n\n\n\n\n\n\n\n\n\n'
            'ще більше тексту після переносів рядків щоб перевірити переповнення';
        final failure = _failure(serviceName: hostile, masterName: hostile);
        final resultHolder = ValueNotifier<bool?>(null);
        addTearDown(resultHolder.dispose);

        await _pumpAndOpen(tester, failure, resultHolder);

        expect(
          tester.takeException(),
          isNull,
          reason:
              'an oversized/newline-heavy serviceName or masterName must '
              'never overflow the dialog\'s fixed-width layout',
        );

        // i18n-finder-ok: the hostile string is fixture data under test, not
        // translated UI copy.
        final Iterable<Text> hostileTexts = tester
            .widgetList<Text>(find.text(hostile))
            .cast<Text>();
        expect(
          hostileTexts,
          isNotEmpty,
          reason: 'the hostile string must still be the rendered Text.data',
        );
        for (final Text t in hostileTexts) {
          expect(
            t.maxLines,
            2,
            reason:
                'LabelledRow call sites for serviceName/masterName must pass '
                'maxLines: 2 (security fix) so untrusted free text cannot '
                'flood the dialog',
          );
          expect(t.overflow, TextOverflow.ellipsis);
        }

        // Sanity: the LabelledRow atoms themselves are present (2 of them
        // carry the hostile value — service + master rows).
        expect(find.byType(LabelledRow), findsNWidgets(3));
      },
    );
  });
}
