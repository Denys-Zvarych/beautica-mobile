// mobile-perf LOW (audit cycle 3, 2026-09-17) — `BookingsDayRail`'s
// render-identity cache, and the gate that arms it.
//
// ## WHAT IS BEING PROTECTED, AND FROM WHICH SIDE
//
// The rail is shape-INDEPENDENT chrome that was paying a full rebuild on
// every rebuild of the board above it: measured 161 of 175 elements taking a
// fresh widget instance per no-op parent rebuild, byte-constant across all
// seven board shapes the audit sampled. After the fix: 1 of 175 (the rail
// widget itself). It already sat behind an `AnimatedBuilder`'s `child:` in
// `bookings_month_calendar_panel.dart`, so animation ticks never reached it —
// this closes the other door, the host's own rebuilds.
//
// A cache is only ever wrong in ONE direction, and it is the direction a green
// suite does not notice: a gate NARROWER than the recompute ships a STALE
// rail. So most of this file is one case per input `build()` reads, each
// proving the cache is thrown away when that input moves. `_cached`'s doc
// carries the same list as a table; a new param on `BookingsDayRail` needs a
// row there AND a case here.
//
// ## THE TWO INPUTS DELIBERATELY NOT IN THE GATE
//
//   * `onVisibleWeekChanged` is never captured into the built tree — it is
//     read through `widget.` inside `_onRailScroll`, at NOTIFICATION time, so
//     a cached tree still calls the current one. Gating on it would throw the
//     cache away every time the host minted a fresh tear-off, for nothing.
//     The last-but-one test drives a real settle to prove the swapped-in
//     callback fires THROUGH the retained cache.
//   * `AppLocalizations` is read by `build()` itself, so it is gated — but in
//     `build`, not `didUpdateWidget`, because an inherited-dependency rebuild
//     never calls `didUpdateWidget` at all. The last test covers it.
//
// MUTATIONS, each reddening a different case:
//   * delete `_cached = null;` from `didUpdateWidget`   → the seven gate cases
//   * drop `identical(l10n, _cachedL10n)` from `build`  → the locale case
//   * change `widget.onSelectDay != oldWidget.onSelectDay` to `!identical(…)`
//                                                       → the no-op cases (the
//     cache never hits again) — how this optimisation gets silently deleted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../../../helpers/pump_app.dart';

/// 2026-06-01 is a Monday, so it is a valid `firstWeekStart`; 2026-06-17 is
/// the Wednesday of page 2.
final DateTime _firstWeek = DateTime(2026, 6, 1);
final DateTime _today = DateTime(2026, 6, 17);
final Set<DateTime> _booked = <DateTime>{DateTime(2026, 6, 18)};

class _HostController {
  late PageController controller;
  DateTime firstWeekStart = _firstWeek;
  int weekCount = 53;
  DateTime today = _today;
  DateTime selectedDay = _today;
  Set<DateTime> bookedDays = _booked;
  ValueChanged<DateTime>? onSelectDay;
  ValueChanged<DateTime>? onVisibleWeekChanged;
  late void Function() rebuild;
}

class _Host extends StatefulWidget {
  const _Host({required this.state});
  final _HostController state;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.state.rebuild = () => setState(() {});
  }

  void _defaultSelect(DateTime _) {}

  @override
  Widget build(BuildContext context) => BookingsDayRail(
    controller: widget.state.controller,
    firstWeekStart: widget.state.firstWeekStart,
    weekCount: widget.state.weekCount,
    today: widget.state.today,
    selectedDay: widget.state.selectedDay,
    bookedDays: widget.state.bookedDays,
    onSelectDay: widget.state.onSelectDay ?? _defaultSelect,
    onVisibleWeekChanged: widget.state.onVisibleWeekChanged,
  );
}

/// The widget instance `BookingsDayRail.build` produced — its root `SizedBox`.
/// Identity of THIS object is the whole contract.
Widget _built(WidgetTester tester) => tester.widget(
  find
      .descendant(
        of: find.byType(BookingsDayRail),
        matching: find.byType(SizedBox),
      )
      .first,
);

Future<_HostController> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('uk'),
  _HostController? reuse,
}) async {
  final _HostController c =
      reuse ?? (_HostController()..controller = PageController(initialPage: 2));
  await tester.pumpApp(_Host(state: c), locale: locale);
  await tester.pump();
  return c;
}

void main() {
  testWidgets('a NO-OP rebuild returns the SAME widget instance — the cache '
      'hit this optimisation exists for', (WidgetTester tester) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);

    c.rebuild();
    await tester.pump();
    expect(identical(_built(tester), first), isTrue);

    // A cache that survives exactly one rebuild is not a cache.
    c.rebuild();
    await tester.pump();
    expect(identical(_built(tester), first), isTrue);
  });

  testWidgets('a NO-OP rebuild is a hit even when onSelectDay is a fresh '
      'tear-off of the same method — `!=`, never `!identical`', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final _Recorder rec = _Recorder();
    c.onSelectDay = rec.call;
    c.rebuild();
    await tester.pump();
    final Widget first = _built(tester);

    // A SECOND tear-off of the same instance method on the same receiver:
    // `==` but never `identical`. This is exactly what the host does on every
    // build, so `!identical` would make the cache never hit again.
    c.onSelectDay = rec.call;
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isTrue);
  });

  // ── one case per gate input ──────────────────────────────────────────────

  testWidgets('selectedDay change evicts the cache', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);

    c.selectedDay = DateTime(2026, 6, 18);
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
  });

  testWidgets('today change evicts the cache', (WidgetTester tester) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);

    c.today = DateTime(2026, 6, 18);
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
  });

  testWidgets('bookedDays change evicts the cache and moves the dot', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);
    expect(find.byKey(dayDotKey(DateTime(2026, 6, 18))), findsOneWidget);
    expect(find.byKey(dayDotKey(DateTime(2026, 6, 19))), findsNothing);

    c.bookedDays = <DateTime>{DateTime(2026, 6, 19)};
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    expect(
      find.byKey(dayDotKey(DateTime(2026, 6, 19))),
      findsOneWidget,
      reason: 'a stale rail would keep showing the previous dots',
    );
    expect(find.byKey(dayDotKey(DateTime(2026, 6, 18))), findsNothing);
  });

  testWidgets('firstWeekStart change evicts the cache and re-dates the chips', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);
    expect(find.byKey(dayChipKey(DateTime(2026, 6, 17))), findsOneWidget);

    // One week earlier — page 2 now shows 8–14 June instead of 15–21.
    c.firstWeekStart = DateTime(2026, 5, 25);
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    expect(
      find.byKey(dayChipKey(DateTime(2026, 6, 10))),
      findsOneWidget,
      reason: 'a stale rail would keep rendering the old week',
    );
  });

  testWidgets('weekCount change evicts the cache', (WidgetTester tester) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);

    c.weekCount = 40;
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
  });

  testWidgets('controller change evicts the cache', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    final PageController old = c.controller;
    addTearDown(old.dispose);
    final Widget first = _built(tester);

    final PageController next = PageController(initialPage: 2);
    addTearDown(next.dispose);
    c.controller = next;
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
  });

  testWidgets('onSelectDay change evicts the cache and rewires the taps', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final Widget first = _built(tester);

    final _Recorder rec = _Recorder();
    c.onSelectDay = rec.call;
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    await tester.tap(find.byKey(dayChipKey(DateTime(2026, 6, 17))));
    await tester.pump();
    expect(rec.days, <DateTime>[
      DateTime(2026, 6, 17),
    ], reason: 'a stale rail would keep calling the previous callback');
  });

  // ── the inputs deliberately NOT in the gate ─────────────────────────────

  testWidgets('onVisibleWeekChanged is swapped THROUGH the retained cache — '
      'it is read at notification time, never captured into the tree', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    final _Recorder stale = _Recorder();
    c.onVisibleWeekChanged = stale.call;
    c.rebuild();
    await tester.pump();
    final Widget first = _built(tester);

    final _Recorder fresh = _Recorder();
    c.onVisibleWeekChanged = fresh.call;
    c.rebuild();
    await tester.pump();

    expect(
      identical(_built(tester), first),
      isTrue,
      reason:
          'this input is not captured into the built tree, so swapping it '
          'must not cost a rebuild',
    );

    // A programmatic settle raises a ScrollEndNotification, which is the path
    // `_onRailScroll` answers on.
    c.controller.jumpToPage(4);
    await tester.pumpAndSettle();

    expect(
      fresh.days,
      isNotEmpty,
      reason: 'the CURRENT callback must fire, cache or no cache',
    );
    expect(stale.days, isEmpty);
  });

  testWidgets('a LOCALE change bypasses the cache and re-renders the weekday '
      'captions — l10n is read by build(), and an inherited-dependency '
      'rebuild never calls didUpdateWidget', (WidgetTester tester) async {
    // Both captions come FROM AppLocalizations, never spelled here: the whole
    // point is that `build()` re-reads them, and a hard-coded literal would
    // both couple this test to today's copy and trip
    // `forbid_cyrillic_finder.sh`.
    final AppLocalizations uk = await AppLocalizations.delegate.load(
      const Locale('uk'),
    );
    final AppLocalizations en = await AppLocalizations.delegate.load(
      const Locale('en'),
    );

    final _HostController c = await _pump(tester);
    addTearDown(c.controller.dispose);
    expect(find.text(uk.weekdayShortMon), findsOneWidget);

    await _pump(tester, locale: const Locale('en'), reuse: c);

    expect(
      find.text(en.weekdayShortMon),
      findsOneWidget,
      reason:
          'a cache gated only on the widget fields would serve the Ukrainian '
          'captions forever',
    );
    expect(find.text(uk.weekdayShortMon), findsNothing);
  });
}

class _Recorder {
  final List<DateTime> days = <DateTime>[];
  void call(DateTime d) => days.add(d);
}
