// Client-profile audit (2026-11-22) — ClientListRow date rules:
//   • «Ост.» / «Наст.» show the YEAR only outside the current Kyiv year of
//     `now` (the shared `booking_date_labels.dart` formatters);
//   • a «Наст.» whose start is not after `now` is dropped (stale server value;
//     the screen re-reads `now` on app resume), also from the a11y label;
//   • DST: the Kyiv day boundary moves with the offset (2026-10-25 EEST→EET,
//     2027-03-28 EET→EEST) — a 00:00 / 23:59 Kyiv instant lands on its own
//     Kyiv day, never the neighbouring UTC one.
// The base row (name, ★, «Заблоковано», no phone) is covered by
// clients_screen_test.dart's `row (CLI-47)` group.

import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Kyiv 12:00 on 16 Nov 2026.
final DateTime _now = DateTime.utc(2026, 11, 16, 10);

ClientSummary _row({DateTime? last, DateTime? next}) => ClientSummary(
  ref: const ClientRef.registered('u1'),
  displayName: 'Оксана Мельник',
  lastVisitAt: last,
  nextVisitAt: next,
  completedVisits: 1,
);

Future<void> _pump(WidgetTester tester, ClientSummary s, DateTime now) =>
    tester.pumpApp(
      Scaffold(
        body: ClientListRow(summary: s, now: now),
      ),
      width: 360,
    );

String? _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data;

void main() {
  group('year rule (current Kyiv year → no year)', () {
    testWidgets('same year: «7 лис» / «пт, 20 лис, 14:00»', (tester) async {
      await _pump(
        tester,
        _row(
          last: DateTime.utc(2026, 11, 7, 10),
          next: DateTime.utc(2026, 11, 20, 12),
        ),
        _now,
      );
      // i18n-finder-ok: asserts the exact approved UA date format
      expect(_text(tester, ClientListRow.lastKey), 'Ост.: 7 лис');
      expect(_text(tester, ClientListRow.nextKey), 'Наст.: пт, 20 лис, 14:00');
    });

    testWidgets('last visit in a previous year shows its year', (tester) async {
      await _pump(tester, _row(last: DateTime.utc(2025, 3, 7, 10)), _now);
      // i18n-finder-ok: asserts the exact approved UA date format
      expect(_text(tester, ClientListRow.lastKey), 'Ост.: 7 бер 2025');
    });

    testWidgets('next visit in the next year shows its year', (tester) async {
      await _pump(tester, _row(next: DateTime.utc(2027, 1, 8, 12)), _now);
      // i18n-finder-ok: asserts the exact approved UA date format
      expect(
        _text(tester, ClientListRow.nextKey),
        'Наст.: пт, 8 січ 2027, 14:00',
      );
    });

    testWidgets('the year is the KYIV year: 31 Dec 23:30 UTC is already '
        '1 Jan in Kyiv', (tester) async {
      // now = Kyiv 1 Jan 2027 10:00; last = Kyiv 1 Jan 2027 01:30.
      await _pump(
        tester,
        _row(last: DateTime.utc(2026, 12, 31, 23, 30)),
        DateTime.utc(2027, 1, 1, 8),
      );
      // i18n-finder-ok: asserts the exact approved UA date format
      expect(_text(tester, ClientListRow.lastKey), 'Ост.: 1 січ');
    });
  });

  group('a past «Наст.» is dropped', () {
    testWidgets('next start before now → no «Наст.» line, not announced', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pump(
        tester,
        _row(
          last: DateTime.utc(2026, 11, 7, 10),
          next: _now.subtract(const Duration(minutes: 1)),
        ),
        _now,
      );
      expect(find.byKey(ClientListRow.nextKey), findsNothing);
      expect(find.byKey(ClientListRow.lastKey), findsOneWidget);
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(ClientListRow)),
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(l10n.clientsRowNextVisit))),
        findsNothing,
      );
      semantics.dispose();
    });

    testWidgets('next start exactly now → dropped; one minute later → shown', (
      tester,
    ) async {
      await _pump(tester, _row(next: _now), _now);
      expect(find.byKey(ClientListRow.nextKey), findsNothing);
      await _pump(
        tester,
        _row(next: _now.add(const Duration(minutes: 1))),
        _now,
      );
      expect(find.byKey(ClientListRow.nextKey), findsOneWidget);
    });
  });

  group('DST / Kyiv midnight', () {
    // 2026-10-25: clocks go back at 04:00 EEST (01:00Z); UTC+3 → UTC+2.
    final DateTime autumnNow = DateTime.utc(2026, 10, 20, 10);
    // 2027-03-28: clocks go forward at 03:00 EET (01:00Z); UTC+2 → UTC+3.
    final DateTime springNow = DateTime.utc(2027, 3, 20, 10);

    Future<String?> next(WidgetTester t, DateTime at, DateTime now) async {
      await _pump(t, _row(next: at), now);
      return _text(t, ClientListRow.nextKey);
    }

    testWidgets('2026-10-25: 00:00 EEST (21:00Z the day before) is the 25th', (
      tester,
    ) async {
      expect(
        await next(tester, DateTime.utc(2026, 10, 24, 21), autumnNow),
        'Наст.: нд, 25 жов, 00:00',
      );
    });

    testWidgets('2026-10-25: 23:59 EET (21:59Z) is still the 25th; 22:00Z is '
        'Kyiv midnight of the 26th', (tester) async {
      expect(
        await next(tester, DateTime.utc(2026, 10, 25, 21, 59), autumnNow),
        'Наст.: нд, 25 жов, 23:59',
      );
      expect(
        await next(tester, DateTime.utc(2026, 10, 25, 22), autumnNow),
        'Наст.: пн, 26 жов, 00:00',
      );
    });

    testWidgets('2026-10-25: «Ост.» at Kyiv midnight is the Kyiv day', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(last: DateTime.utc(2026, 10, 24, 21)),
        autumnNow,
      );
      expect(_text(tester, ClientListRow.lastKey), 'Ост.: 25 жов');
    });

    testWidgets('2027-03-28: 00:00 EET (22:00Z the day before) is the 28th', (
      tester,
    ) async {
      expect(
        await next(tester, DateTime.utc(2027, 3, 27, 22), springNow),
        'Наст.: нд, 28 бер, 00:00',
      );
    });

    testWidgets('2027-03-28: 23:59 EEST (20:59Z) is still the 28th; 21:00Z is '
        'Kyiv midnight of the 29th', (tester) async {
      expect(
        await next(tester, DateTime.utc(2027, 3, 28, 20, 59), springNow),
        'Наст.: нд, 28 бер, 23:59',
      );
      expect(
        await next(tester, DateTime.utc(2027, 3, 28, 21), springNow),
        'Наст.: пн, 29 бер, 00:00',
      );
    });

    testWidgets('across the spring jump: a «Наст.» one minute after a '
        'DST-day `now` is kept, one minute before is dropped', (tester) async {
      // now = 04:30 EEST on the 28th (01:30Z), just after the jump.
      final DateTime now = DateTime.utc(2027, 3, 28, 1, 30);
      await _pump(tester, _row(next: now.add(const Duration(minutes: 1))), now);
      expect(_text(tester, ClientListRow.nextKey), 'Наст.: нд, 28 бер, 04:31');
      await _pump(
        tester,
        _row(next: now.subtract(const Duration(minutes: 1))),
        now,
      );
      expect(find.byKey(ClientListRow.nextKey), findsNothing);
    });
  });
}
