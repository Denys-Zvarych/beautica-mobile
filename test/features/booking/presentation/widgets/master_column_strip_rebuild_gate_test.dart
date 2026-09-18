// mobile-perf LOW (audit cycle 3, 2026-09-17) — `MasterColumnStrip`'s
// render-identity cache, and the gate that arms it.
//
// ## WHAT IS BEING PROTECTED, AND FROM WHICH SIDE
//
// The optimisation is one line of behaviour: a rebuild whose inputs did not
// move must hand the SAME widget instance back, so `Element.updateChild`
// skips the chip subtree. Measured before the fix (element-identity snapshot
// across one no-op parent `setState`): 362 of 512 elements took a fresh widget
// instance at 10 masters, 110/155 at 3 — including an all-day-off board where
// nothing on screen can have moved. After: 1 of 512, the strip widget itself.
//
// But a cache is only ever wrong in ONE direction, and it is the direction a
// green test suite does not notice: a gate NARROWER than the recompute ships
// a STALE strip, silently and correctly-looking. So the bulk of this file is
// not the cache hit — it is one case per input `build()` reads, each proving
// the cache is thrown away when that input moves. The class doc on
// `MasterColumnStrip` carries the same list as a table; if a param is ever
// added to that widget, it needs a row there AND a case here.
//
// ## THE TWO INPUTS DELIBERATELY NOT IN THE GATE
//
// `AppLocalizations` is read by `_MasterColumnChip.build`, not by the strip's
// own `build`, so each chip ELEMENT is itself a `Localizations` dependant: a
// locale change marks those elements dirty directly and they rebuild with
// their unchanged configuration. Handing back an identical parent cannot
// suppress that — `updateChild` skips the `update()` call, it does not remove
// elements from the dirty list. The last test asserts exactly that, and it is
// the one case here where the cached instance is EXPECTED to be retained
// while the rendered text still changes.
//
// MUTATIONS, each reddening a different case:
//   * delete `_cached = null;` from `didUpdateWidget`  → the four gate cases.
//   * drop `height == _cachedHeight` from `build`      → the text-scale case.
//
// 2026-09-18 — the strip's tap-to-select affordance (`selectedMasterId` /
// `onSelectMaster`) was REMOVED (it filtered nothing; see
// `master_column_strip.dart`'s class doc). The gate table and the two cases
// that covered those params went with it — there is nothing left in the
// widget for them to protect.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../../../helpers/pump_app.dart';

MasterColumnEntry _entry(
  String id, {
  String name = 'Олена Ковальчук',
  int bookingCount = 2,
  bool dayOff = false,
}) => MasterColumnEntry(
  masterId: id,
  name: name,
  type: MasterType.salonMaster,
  bookingCount: bookingCount,
  avgRating: 4.6,
  dayOff: dayOff,
);

/// Identity-stable entries, exactly as `_columnsFor`'s memo produces them —
/// the list literal is rebuilt per host build, the ELEMENTS are not. That is
/// why the gate compares with `listEquals` and not `identical`.
final MasterColumnEntry _a = _entry('m1');
final MasterColumnEntry _b = _entry('m2', name: 'Ірина Бондар');
final MasterColumnEntry _freeC = _entry('m3', name: 'Ася Лис', bookingCount: 0);

class _Host extends StatefulWidget {
  const _Host({required this.state});
  final _HostController state;
  @override
  State<_Host> createState() => _HostState();
}

/// Mutable holder the tests poke, so a rebuild can change exactly ONE input.
class _HostController {
  List<MasterColumnEntry> entries = <MasterColumnEntry>[_a, _b, _freeC];
  double columnWidth = 148;
  double gutter = 8;
  late void Function() rebuild;
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.state.rebuild = () => setState(() {});
  }

  // `Align` rather than a scroll view: it hands the strip LOOSE constraints
  // in both axes, so `getSize` reads the strip's own intrinsic width (which
  // the columnWidth/gutter cases assert on) and its own 64dp height (which
  // the text-scale case asserts on). Under a tight parent — which is what
  // the real board gives it — both would read the parent, and both
  // assertions would be vacuous.
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: MasterColumnStrip(
      entries: <MasterColumnEntry>[...widget.state.entries],
      columnWidth: widget.state.columnWidth,
      gutter: widget.state.gutter,
    ),
  );
}

/// The widget instance `MasterColumnStrip.build` produced — its root
/// `SizedBox`. Identity of THIS object is the whole contract.
Widget _built(WidgetTester tester) => tester.widget(
  find
      .descendant(
        of: find.byType(MasterColumnStrip),
        matching: find.byType(SizedBox),
      )
      .first,
);

Finder _chip(String id) =>
    find.byKey(ValueKey<String>('salon-bookings-column-chip-$id'));

Future<_HostController> _pump(
  WidgetTester tester, {
  double textScaleFactor = 1.0,
}) async {
  final _HostController c = _HostController();
  await tester.pumpApp(
    _Host(state: c),
    width: 900,
    textScaleFactor: textScaleFactor,
  );
  await tester.pump();
  return c;
}

void main() {
  testWidgets('a NO-OP rebuild returns the SAME widget instance — the cache '
      'hit this optimisation exists for', (WidgetTester tester) async {
    final _HostController c = await _pump(tester);
    final Widget first = _built(tester);

    c.rebuild();
    await tester.pump();

    expect(
      identical(_built(tester), first),
      isTrue,
      reason:
          'nothing moved, so Element.updateChild must be able to skip the '
          'whole chip subtree',
    );

    // And again — a cache that survives exactly one rebuild is not a cache.
    c.rebuild();
    await tester.pump();
    expect(identical(_built(tester), first), isTrue);
  });

  // ── one case per gate input ──────────────────────────────────────────────

  testWidgets('entries CONTENT change evicts the cache and re-renders', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    final Widget first = _built(tester);
    // i18n-finder-ok: a fixture master's name — this test's own data, handed
    // in as `MasterColumnEntry.name`, never sourced from AppLocalizations.
    expect(find.text('Ірина Бондар'), findsOneWidget);

    c.entries = <MasterColumnEntry>[_a, _entry('m2', name: 'Ната Гай'), _freeC];
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    // i18n-finder-ok: fixture master names — this test's own data (see above).
    expect(find.text('Ната Гай'), findsOneWidget);
    // i18n-finder-ok: fixture master names — this test's own data (see above).
    expect(find.text('Ірина Бондар'), findsNothing);
  });

  testWidgets('entries LENGTH change evicts the cache and re-renders', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    final Widget first = _built(tester);

    c.entries = <MasterColumnEntry>[_a, _b];
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    // i18n-finder-ok: fixture master names — this test's own data (see above).
    expect(find.text('Ася Лис'), findsNothing);
  });

  testWidgets('columnWidth change evicts the cache and resizes the strip', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    final Widget first = _built(tester);
    // MEASURED off the laid-out chip, not read off the widget field: the
    // strip itself expands to the incoming max width either way, so a
    // strip-level measure would be constant and the assertion vacuous.
    expect(tester.getSize(_chip('m1')).width, closeTo(148, 0.01));

    c.columnWidth = 200;
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    expect(
      tester.getSize(_chip('m1')).width,
      closeTo(200, 0.01),
      reason: 'a stale strip would keep the 148dp chips',
    );
  });

  testWidgets('gutter change evicts the cache and resizes the strip', (
    WidgetTester tester,
  ) async {
    final _HostController c = await _pump(tester);
    final Widget first = _built(tester);
    double gap() =>
        tester.getTopLeft(_chip('m2')).dx - tester.getTopRight(_chip('m1')).dx;
    expect(gap(), closeTo(8, 0.01));

    c.gutter = 40;
    c.rebuild();
    await tester.pump();

    expect(identical(_built(tester), first), isFalse);
    expect(
      gap(),
      closeTo(40, 0.01),
      reason: 'a stale strip would keep the 8dp gutters',
    );
  });

  // ── the tap-to-select affordance is GONE (2026-09-18) ────────────────────
  //
  // The two cases that used to live here (`selectedMasterId` evicting the
  // cache and moving the selected flag; `onSelectMaster` null → non-null
  // making the chips tappable) are GONE, not narrowed: the widget no longer
  // has either param, so there is nothing left for a gate case to protect.
  // What replaces them is the inert-tap contract itself — a tap must do
  // NOTHING, and the chip must never announce itself as selectable or
  // tappable to a screen reader.
  testWidgets('a chip tap is INERT — no selection, no callback, and the chip '
      'never announces itself as tappable or selectable', (
    WidgetTester tester,
  ) async {
    // Disposed INLINE, not via addTearDown: the framework's
    // "a SemanticsHandle was active at the end of the test" assertion fires
    // before tearDowns run.
    final SemanticsHandle handle = tester.ensureSemantics();
    await _pump(tester);
    final Finder chip = find.byKey(
      const ValueKey<String>('salon-bookings-column-chip-m2'),
    );
    final Matcher inert = isSemantics(
      isSelected: false,
      isButton: false,
      hasTapAction: false,
    );
    expect(
      tester.getSemantics(chip),
      inert,
      reason:
          'the chip must not announce itself as tappable or selectable '
          'before a tap',
    );

    // A semantics check alone has a hole: `GestureDetector(excludeFromSemantics:
    // true)` or a bare `InkWell` with the ripple suppressed still WORKS as a
    // tap handler while leaving `isSemantics(...)` above green. Guard the
    // mechanism itself, not just its semantics footprint — no gesture-handling
    // widget belongs anywhere inside this strip.
    expect(
      find.descendant(
        of: find.byType(MasterColumnStrip),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
      reason: 'no GestureDetector belongs in the inert roster strip',
    );
    expect(
      find.descendant(
        of: find.byType(MasterColumnStrip),
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason: 'no InkWell belongs in the inert roster strip',
    );
    expect(
      find.descendant(
        of: find.byType(MasterColumnStrip),
        matching: find.byType(InkResponse),
      ),
      findsNothing,
      reason: 'no InkResponse belongs in the inert roster strip',
    );

    await tester.tap(chip);
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'tapping a chip with no affordance must not throw',
    );
    expect(
      tester.getSemantics(chip),
      inert,
      reason:
          'a tap must change NOTHING about the chip — no ripple, no '
          'selected flag, no button flag',
    );
    handle.dispose();
  });

  testWidgets('a MediaQuery text-scale change bypasses the cache and regrows '
      'the strip — didUpdateWidget never runs for an inherited-dependency '
      'rebuild, so this gate lives in build()', (WidgetTester tester) async {
    await _pump(tester);
    final double atOne = tester.getSize(find.byType(MasterColumnStrip)).height;
    expect(atOne, closeTo(MasterColumnStrip.height, 0.01));

    // Re-pump the SAME host at a larger scale: the element tree is updated in
    // place, so the strip's State — and its cache — survive.
    await _pump(tester, textScaleFactor: 1.6);

    expect(
      tester.getSize(find.byType(MasterColumnStrip)).height,
      greaterThan(atOne),
      reason:
          'a cache keyed only on the widget fields would serve the scale-1.0 '
          'strip and overflow it',
    );
  });

  // ── the input deliberately NOT in the gate ───────────────────────────────

  testWidgets('a LOCALE change re-renders the chips THROUGH the retained '
      'cache — l10n is read by the chip, not by the strip, so each chip '
      'element is its own Localizations dependant', (
    WidgetTester tester,
  ) async {
    // Both captions come FROM AppLocalizations, never spelled here: the whole
    // point is that the chip re-reads them, and a hard-coded literal would
    // both couple this test to today's copy and trip
    // `forbid_cyrillic_finder.sh`.
    //
    // The probe is the chip's ROLE SUB-LINE (`masterRoleLabel`), not the
    // trailing load readout it used to be: that readout no longer renders in
    // any state. The sub-line is the chip's remaining l10n-sourced text, so
    // it carries the same proof — all three entries are `salonMaster` with no
    // `professionalTitle`, so all three fall back to the role label.
    final AppLocalizations uk = await AppLocalizations.delegate.load(
      const Locale('uk'),
    );
    final AppLocalizations en = await AppLocalizations.delegate.load(
      const Locale('en'),
    );
    expect(
      uk.masterRoleSalonMaster,
      isNot(en.masterRoleSalonMaster),
      reason:
          'the two locales must genuinely differ here, or the flip below '
          'proves nothing',
    );

    final _HostController c = _HostController();
    await tester.pumpApp(_Host(state: c), width: 900);
    await tester.pump();
    expect(find.text(uk.masterRoleSalonMaster), findsNWidgets(3));

    await tester.pumpApp(
      _Host(state: c),
      width: 900,
      locale: const Locale('en'),
    );
    await tester.pump();

    expect(
      find.text(en.masterRoleSalonMaster),
      findsNWidgets(3),
      reason:
          'updateChild skipping an identical widget does not remove elements '
          'from the dirty list — the chip rebuilds itself on the locale flip',
    );
    expect(find.text(uk.masterRoleSalonMaster), findsNothing);
  });

  // ── the readout that is GONE ─────────────────────────────────────────────

  testWidgets('the chip renders NO trailing load readout in any state — not '
      'the booking figure, not «вільно», not «Вихідний» — while still '
      'rendering the master identity it exists for', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await AppLocalizations.delegate.load(
      const Locale('uk'),
    );

    final _HostController c = _HostController();
    // `_a`/`_b` are booked (2 each), `_freeC` has none; add a fourth that is
    // OFF, so all three former readout states are on screen at once.
    c.entries = <MasterColumnEntry>[
      _a,
      _b,
      _freeC,
      _entry('m4', name: 'Іра Ткач', bookingCount: 0, dayOff: true),
    ];
    await tester.pumpApp(_Host(state: c), width: 900);
    await tester.pump();

    // 1. The two quiet captions are gone from the strip.
    expect(find.text(uk.salonBookingsMasterColumnFree), findsNothing);
    expect(find.text(uk.salonBookingsColumnDayOff), findsNothing);
    // 2. …and so is the booked figure, in BOTH the bare («2») and the phrased
    //    («2 записи») spellings the chip has historically used.
    expect(find.text('2'), findsNothing);
    expect(find.text(uk.masterBookingsCount(2)), findsNothing);

    // 3. NOT VACUOUS: every chip still renders the identity it exists for —
    //    the master's NAME and the role sub-line — so a change that gutted
    //    the chip cannot pass this test.
    //
    //    Located by KEY and asserted against the name the fixture SEEDED
    //    (`e.name`), never against a spelled-out literal: a hard-coded
    //    Cyrillic `find.text` would both couple this test to the UA locale
    //    (`forbid_cyrillic_finder.sh`) and let the assertion drift away from
    //    the data it is supposed to be checking.
    for (final MasterColumnEntry e in c.entries) {
      final Finder chip = _chip(e.masterId);
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text(e.name)),
        findsOneWidget,
        reason: '${e.masterId} must still render its master name',
      );
      expect(
        find.descendant(
          of: chip,
          matching: find.text(uk.masterRoleSalonMaster),
        ),
        findsOneWidget,
        reason: '${e.masterId} must still render its role sub-line',
      );
    }
    expect(find.text(uk.masterRoleSalonMaster), findsNWidgets(4));
  });

  testWidgets('the load the chip stopped DRAWING is still SPOKEN — a screen '
      'reader has no grid to scan', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final AppLocalizations uk = await AppLocalizations.delegate.load(
      const Locale('uk'),
    );

    final MasterColumnEntry offD = _entry(
      'm4',
      name: 'Іра Ткач',
      bookingCount: 0,
      dayOff: true,
    );
    final _HostController c = _HostController();
    c.entries = <MasterColumnEntry>[_a, _freeC, offD];
    await tester.pumpApp(_Host(state: c), width: 900);
    await tester.pump();

    // A RegExp, not the bare string: the chip's `Semantics` node MERGES its
    // descendants, so the node's own label is this phrase plus whatever the
    // merged children contribute, and `bySemanticsLabel(String)` compares for
    // EQUALITY.
    void expectSpoken(MasterColumnEntry e, String load) => expect(
      find.bySemanticsLabel(
        RegExp(
          RegExp.escape(
            uk.salonBookingsMasterColumnSemantics(
              e.name,
              uk.masterRoleSalonMaster,
              load,
            ),
          ),
        ),
      ),
      findsOneWidget,
      reason: 'the «$load» load must survive as speech for ${e.masterId}',
    );

    expectSpoken(_a, uk.masterBookingsCount(2));
    expectSpoken(_freeC, uk.salonBookingsMasterColumnFree);
    expectSpoken(offD, uk.salonBookingsColumnDayOff);
    handle.dispose();
  });
}
