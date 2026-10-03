// Phase 076 (10.2 jank audit) — pinning tests for findings #1, #2, #3, #5
// (ServiceCard half) and #8 on the services list.
//
// Each test names the finding it pins. They were falsified against the
// pre-fix tree (see the phase report) — a pin that cannot go red is not a pin.

import 'dart:async';

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _StubServicesList extends ServicesList {
  _StubServicesList(this._data);
  final List<MasterService> _data;

  /// Replaces the loaded list (test hook for a data change on a live screen).
  void push(List<MasterService> next) => state = AsyncData(next);

  @override
  Future<List<MasterService>> build() {
    Future<void>.microtask(() => state = AsyncData(_data));
    return Completer<List<MasterService>>().future;
  }
}

MasterService _svc(int i, String category) => MasterService(
  id: 'svc-$i',
  serviceDefId: 'def-$i',
  name: 'Test $i',
  category: category,
  durationMinutes: 30,
  priceMin: 100,
  priceDisplay: '100 ₴',
);

const List<ServiceCategoryOption> _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
  ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
];

Future<void> _pumpList(
  WidgetTester tester,
  List<MasterService> services, {
  String? initialExpandCategory,
  bool settle = true,
}) async {
  await tester.pumpApp(
    ServicesListScreen(initialExpandCategory: initialExpandCategory),
    overrides: [
      servicesListProvider.overrideWith(() => _StubServicesList(services)),
      serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
      approvedCategoriesProvider.overrideWith((ref) async => _categories),
    ],
  );
  await tester.pump();
  await tester.pump();
  if (!settle) return;
  // fixed-wait-ok: runs out the 460 ms staggered entrance (+ timers).
  await tester.pump(const Duration(milliseconds: 600));
}

Finder _section(String slug) => find.byKey(Key('category_section_$slug'));
Finder _card(int i) => find.byKey(Key('service_card_svc-$i'));

void main() {
  group('phase 076 #1 — expanded category is lazy', () {
    testWidgets(
      '60 services in one category: expanding mounts far fewer than 60 cards, '
      'and scrolling to the end builds the last one',
      (tester) async {
        await _pumpList(tester, <MasterService>[
          for (int i = 0; i < 60; i++) _svc(i, 'HAIRCUT'),
        ]);
        expect(find.byType(ServiceCard), findsNothing);

        await tester.tap(_section('HAIRCUT'));
        await tester.pumpAndSettle();

        final int mounted = tester.widgetList(find.byType(ServiceCard)).length;
        expect(mounted, greaterThan(0), reason: 'the open section shows cards');
        expect(
          mounted,
          lessThan(20),
          reason: 'cards must virtualize, not mount all 60 in one Column',
        );
        expect(_card(59), findsNothing);

        await tester.scrollUntilVisible(
          _card(59),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(_card(59), findsOneWidget);
        // The drag's ballistic tail can still build cards (and start their
        // 450 ms stagger timers) after the last pump: settle, don't wait.
        await tester.pumpAndSettle();
        // fixed-wait-ok: the settle's last frame may have built cards whose
        // 450 ms stagger timers are not frames; run them out.
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });

  group('phase 076 #2 — expansion survives a section leaving the cache', () {
    testWidgets('expanded section stays expanded after scrolling far away and '
        'back, and its cards do not replay the entrance', (tester) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 60; i++) _svc(i, 'HAIRCUT'),
      ]);
      await tester.tap(_section('HAIRCUT'));
      await tester.pumpAndSettle();
      expect(_card(0), findsOneWidget);

      final Finder list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(
        _card(0),
        findsNothing,
        reason: 'scrolled out of the cache extent',
      );

      await tester.scrollUntilVisible(
        _card(0),
        -500,
        scrollable: list,
        maxScrolls: 200,
      );
      expect(
        _card(0),
        findsOneWidget,
        reason: 'the section must still be expanded after returning',
      );
      final FadeTransition fade = tester.widget<FadeTransition>(
        find.descendant(of: _card(0), matching: find.byType(FadeTransition)),
      );
      expect(
        fade.opacity.value,
        1.0,
        reason: 'a re-mounted card must be settled, not replay its 460 ms fade',
      );
      await tester.pumpAndSettle();
    });
  });

  group('phase 076 #3 — approved-categories select', () {
    testWidgets('invalidating approvedCategoriesProvider with an unchanged '
        'result does not rebuild the loaded body', (tester) async {
      await _pumpList(tester, <MasterService>[_svc(0, 'HAIRCUT')]);

      int loadedBodyBuilds = 0;
      final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
        if (e.widget.runtimeType.toString() == '_LoadedBody') {
          loadedBodyBuilds++;
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = old);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ServicesListScreen)),
      );
      container.invalidate(approvedCategoriesProvider);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        loadedBodyBuilds,
        0,
        reason:
            'same resolved list ⇒ the select filters out the '
            'loading/refresh transition',
      );
    });
  });

  group('phase 076 #5 — ServiceCard press is leaf-scoped', () {
    testWidgets('tap-down + cancel animates the shell but rebuilds no card '
        'content', (tester) async {
      await _pumpList(tester, <MasterService>[_svc(0, 'HAIRCUT')]);
      await tester.tap(_section('HAIRCUT'));
      await tester.pumpAndSettle();

      int infoBuilds = 0;
      final RebuildDirtyWidgetCallback? old = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
        if (e.widget is ServiceInfo) infoBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = old);

      final TestGesture g = await tester.startGesture(
        tester.getCenter(_card(0)),
      );
      // fixed-wait-ok: lets the 110-150 ms press/release shell animation run.
      await tester.pump(const Duration(milliseconds: 300));
      final AnimatedScale scale = tester.widget<AnimatedScale>(
        find.descendant(of: _card(0), matching: find.byType(AnimatedScale)),
      );
      expect(scale.scale, 0.99, reason: 'the press shell must still react');
      await g.cancel();
      // fixed-wait-ok: lets the 110-150 ms press/release shell animation run.
      await tester.pump(const Duration(milliseconds: 300));

      expect(infoBuilds, 0, reason: 'press must not rebuild card content');
    });
  });

  // Phase 076 B — the 220 ms expand reveal that flattening the cards into the
  // lazy list dropped, restored per card via `SizeReveal`.
  group('phase 076 B — expand/collapse reveal on the lazy list', () {
    Finder reveal(int i) => find.byKey(Key('service_card_reveal_svc-$i'));

    /// The reveal's own height factor: the OUTERMOST `Align` under it.
    double factor(WidgetTester tester, int i) => tester
        .widget<Align>(
          find.descendant(of: reveal(i), matching: find.byType(Align)).first,
        )
        .heightFactor!;

    testWidgets('a user expand grows the cards in over 220 ms, then idles', (
      tester,
    ) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 3; i++) _svc(i, 'HAIRCUT'),
      ]);
      // Baseline: tickers the screen owns by itself, before any reveal.
      final int baselineTickers = tester.binding.transientCallbackCount;
      await tester.tap(_section('HAIRCUT'));
      await tester.pump();
      await tester.pump(); // first frame of the controller (t = 0)
      expect(factor(tester, 0), lessThan(0.5), reason: 'starts collapsed');

      // fixed-wait-ok: mid-way through the 220 ms reveal.
      await tester.pump(const Duration(milliseconds: 100));
      final double mid = factor(tester, 0);
      expect(mid, inExclusiveRange(0.0, 1.0), reason: 'mid-reveal');

      // fixed-wait-ok: past the 220 ms reveal and every entrance/stagger timer.
      await tester.pump(const Duration(seconds: 3));
      // fixed-wait-ok: a stagger timer firing in the pump above starts its
      // 460 ms entrance only then; this runs that out.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(); // lets a just-completed ticker unschedule itself
      expect(factor(tester, 0), 1.0);
      expect(
        tester.binding.transientCallbackCount,
        baselineTickers,
        reason: 'a settled reveal must leave no ticker running (no idle cost)',
      );
    });

    testWidgets('the seeded initial expand does NOT play the reveal', (
      tester,
    ) async {
      await _pumpList(
        tester,
        <MasterService>[for (int i = 0; i < 3; i++) _svc(i, 'HAIRCUT')],
        initialExpandCategory: 'HAIRCUT',
        settle: false,
      );
      // Checked on the FIRST built frame, before any 220 ms could have run.
      expect(reveal(0), findsOneWidget);
      expect(factor(tester, 0), 1.0);
      // fixed-wait-ok: drains the entrance Future.delayed timers.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('re-mounting on scroll-back does not replay the reveal', (
      tester,
    ) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 60; i++) _svc(i, 'HAIRCUT'),
      ]);
      await tester.tap(_section('HAIRCUT'));
      await tester.pumpAndSettle();
      expect(factor(tester, 0), 1.0);

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scrollable.position.jumpTo(6000);
      await tester.pump();
      expect(reveal(0), findsNothing, reason: 'scrolled out of the cache');

      scrollable.position.jumpTo(0);
      await tester.pump(); // ONE frame: the card is built this frame
      expect(reveal(0), findsOneWidget);
      expect(
        factor(tester, 0),
        1.0,
        reason: 'a re-mounted card must be born settled, not grow in again',
      );
      // fixed-wait-ok: drains the entrance Future.delayed timers.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('cards built later by scrolling are not revealed either', (
      tester,
    ) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 60; i++) _svc(i, 'HAIRCUT'),
      ]);
      await tester.tap(_section('HAIRCUT'));
      await tester.pumpAndSettle();
      expect(reveal(59), findsNothing);

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      // The lazy extent is an estimate until the tail is built: jump twice.
      for (int k = 0; k < 3; k++) {
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();
      }
      expect(reveal(59), findsOneWidget);
      expect(factor(tester, 59), 1.0);
      // fixed-wait-ok: drains the entrance Future.delayed timers.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('collapse shrinks the cards out, then removes them', (
      tester,
    ) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 3; i++) _svc(i, 'HAIRCUT'),
      ], initialExpandCategory: 'HAIRCUT');
      expect(_card(0), findsOneWidget);
      // fixed-wait-ok: lets every entrance/stagger ticker finish first.
      await tester.pump(const Duration(seconds: 3));
      // fixed-wait-ok: second pass runs out entrances started by the first.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      final int baselineTickers = tester.binding.transientCallbackCount;

      await tester.tap(_section('HAIRCUT'));
      await tester.pump();
      // fixed-wait-ok: mid-way through the 220 ms collapse.
      await tester.pump(const Duration(milliseconds: 100));
      expect(_card(0), findsOneWidget, reason: 'still mounted mid-collapse');
      expect(factor(tester, 0), inExclusiveRange(0.0, 1.0));

      // fixed-wait-ok: past the 220 ms collapse.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(_card(0), findsNothing, reason: 'removed once collapsed');
      await tester.pump();
      expect(tester.binding.transientCallbackCount, baselineTickers);

      // Re-expanding afterwards reveals again (a fresh user expand).
      await tester.tap(_section('HAIRCUT'));
      await tester.pump();
      await tester.pump();
      expect(factor(tester, 0), lessThan(0.5));
      // fixed-wait-ok: drains reveal + entrance timers.
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('phase 076 N1 — the expand frame mounts a bounded number of cards', () {
    testWidgets('60 services: the FIRST expand frame (not after settle) mounts '
        'at most reveal-cap + what fits the cache', (tester) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 60; i++) _svc(i, 'HAIRCUT'),
      ]);
      await tester.tap(_section('HAIRCUT'));
      // ONE frame: every reveal card is still 0 dp tall here.
      await tester.pump();

      // Cache-extent items included: that is exactly what must stay bounded.
      final int mounted = tester
          .widgetList(find.byType(ServiceCard, skipOffstage: false))
          .length;
      expect(mounted, greaterThan(0));
      expect(
        mounted,
        lessThanOrEqualTo(30),
        reason:
            'uncapped, all 60 reveal cards are 0 dp tall on the expand frame '
            'and all mount at once; capped, only the first 12 are 0 dp and the '
            'rest fill the cache extent at natural height',
      );
      // fixed-wait-ok: drains the reveal + entrance timers.
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('phase 076 N2 — appeared / expanded bookkeeping', () {
    testWidgets('a service removed and re-added animates in again, and its '
        'section is no longer pre-expanded', (tester) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 3; i++) _svc(i, 'HAIRCUT'),
        _svc(10, 'BROWS'),
      ]);
      await tester.tap(_section('HAIRCUT'));
      await tester.pumpAndSettle();
      expect(_card(0), findsOneWidget);
      // fixed-wait-ok: lets the entrance finish so card 0 is "appeared".
      await tester.pump(const Duration(seconds: 1));

      final _StubServicesList stub =
          ProviderScope.containerOf(
                tester.element(find.byType(ServicesListScreen)),
              ).read(servicesListProvider.notifier)
              as _StubServicesList;
      stub.push(<MasterService>[_svc(10, 'BROWS')]);
      await tester.pump();
      await tester.pump();
      expect(_card(0), findsNothing);

      stub.push(<MasterService>[
        for (int i = 0; i < 3; i++) _svc(i, 'HAIRCUT'),
        _svc(10, 'BROWS'),
      ]);
      await tester.pump();
      await tester.pump();
      expect(
        _card(0),
        findsNothing,
        reason: 'the expanded key of a vanished section must be pruned',
      );

      await tester.tap(_section('HAIRCUT'));
      await tester.pump();
      await tester.pump();
      final FadeTransition fade = tester.widget<FadeTransition>(
        find.descendant(of: _card(0), matching: find.byType(FadeTransition)),
      );
      expect(
        fade.opacity.value,
        lessThan(1.0),
        reason: 'a pruned id must play its entrance again',
      );
      // fixed-wait-ok: drains reveal + entrance timers.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a card built only for the cache extent has NOT appeared: '
        'mounted later, in view, it still plays its entrance', (tester) async {
      await _pumpList(tester, <MasterService>[
        for (int i = 0; i < 60; i++) _svc(i, 'HAIRCUT'),
      ], initialExpandCategory: 'HAIRCUT');
      final Rect list = tester.getRect(find.byType(Scrollable).first);

      // The deepest card that is mounted but BELOW the viewport (cache only).
      int? cacheOnly;
      // `skipOffstage: false` — the finder otherwise hides cache-extent items.
      Finder anyCard(int i) =>
          find.byKey(Key('service_card_svc-$i'), skipOffstage: false);
      for (int i = 0; i < 60; i++) {
        if (anyCard(i).evaluate().isEmpty) break;
        if (tester.getTopLeft(anyCard(i)).dy > list.bottom) cacheOnly = i;
      }
      expect(cacheOnly, isNotNull, reason: 'fixture: a cache-only card exists');
      final double top = tester.getTopLeft(anyCard(cacheOnly!)).dy - list.top;

      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final double home = scrollable.position.pixels;
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(anyCard(cacheOnly), findsNothing, reason: 'left the cache extent');

      // One jump straight onto it: it mounts IN VIEW on this frame.
      scrollable.position.jumpTo(home + top - 100);
      await tester.pump();
      expect(_card(cacheOnly), findsOneWidget);
      final FadeTransition fade = tester.widget<FadeTransition>(
        find.descendant(
          of: _card(cacheOnly),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(
        fade.opacity.value,
        lessThan(1.0),
        reason:
            'a cache-extent-only build was counted as appeared, so the card '
            'the user had never seen mounted settled',
      );
      await tester.pumpAndSettle();
      // fixed-wait-ok: runs out stagger timers started by the last frame.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('ServiceCard reports onEntranceStarted only when it is in the '
        'viewport (a cache-extent-only card does not count)', (tester) async {
      final List<String> seen = <String>[];
      await tester.pumpApp(
        SizedBox(
          height: 300,
          child: ListView(
            cacheExtent: 2000,
            children: <Widget>[
              for (int i = 0; i < 12; i++)
                SizedBox(
                  height: 120,
                  child: ServiceCard(
                    key: Key('c$i'),
                    service: _svc(i, 'HAIRCUT'),
                    onEntranceStarted: () => seen.add('c$i'),
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(seen, contains('c0'));
      expect(seen, isNot(contains('c11')), reason: 'built, but far off-screen');
      // fixed-wait-ok: drains the entrance timers.
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('phase 076 #8 — loading skeleton uses one controller', () {
    testWidgets('exactly one transient ticker drives the skeleton', (
      tester,
    ) async {
      await tester.pumpApp(
        const ServicesListScreen(),
        overrides: [
          servicesListProvider.overrideWith(() => _NeverServicesList()),
          serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
          approvedCategoriesProvider.overrideWith((ref) async => _categories),
        ],
      );
      await tester.pump();

      expect(find.byKey(const Key('skeleton_card_0')), findsOneWidget);
      expect(find.byKey(const Key('skeleton_card_2')), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 1);
    });
  });
}

class _NeverServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Completer<List<MasterService>>().future;
}
