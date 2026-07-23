// mobile-qa regression — the expanded itemized list inside [SelectedServicesShelf]
// (keyed `booking-summary-expanded-list`) sits in a
// `ConstrainedBox(maxHeight: listMaxHeight /* 188 */)`. It shipped for a while
// WITHOUT `shrinkWrap: true`, so a non-shrink-wrapped `ListView` in a bounded
// viewport greedily filled the ENTIRE 188dp regardless of row count — leaving a
// large blank gap under the last service whenever only 1–2 services were
// selected (visible in EVERY booking flow, salon and independent alike, since
// this is the ONE shared shelf both compose). The fix adds `shrinkWrap: true`.
//
// This file pins the shrink-wrap contract from BOTH entry points — it is a
// single shared behaviour, so a future regression on either page is caught:
//
//   1. Fits content — expand with 2 services → the expanded-list panel's
//      rendered height is well UNDER `listMaxHeight` (fits its 2-row content,
//      no excess gap). Pre-fix this measured exactly 188.0; post-fix ~82.
//   2. Caps + scrolls — expand with ~10 services → panel height EQUALS
//      `listMaxHeight` (clamped) AND the `ListView` is `shrinkWrap: true` with a
//      positive `maxScrollExtent` (content overflows the cap → still scrollable).
//   3. Both compositions — the same fits-content + caps sizing is asserted
//      through the independent path (`IndependentScheduleConfirmBar`) and the
//      salon path (`ScheduleConfirmBar`), each confirmed to compose the fixed
//      shelf, so neither page can regress the shrink-wrap contract silently.
//
// No Cyrillic UI-copy literals appear in any finder: the panel is located by its
// stable `booking-summary-expanded-list` key and the toggle by its key; only
// fixture service names (test data) are ever referenced by value.

import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/schedule_confirm_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/selected_services_shelf.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _toggleKey = Key('booking-summary-expand-toggle');
const Key _expandedListKey = Key('booking-summary-expanded-list');

/// Two selected services — their combined 2-row content is comfortably shorter
/// than [SelectedServicesShelf.listMaxHeight], so a non-shrink-wrapped list
/// would leave a visible blank gap. This is the exact pre-fix bug repro.
final List<MasterService> _twoServices = List<MasterService>.generate(
  2,
  _service,
);

/// Enough services that the itemized rows exceed [listMaxHeight] outright, so
/// the `ConstrainedBox` clamps the panel and the list must scroll.
final List<MasterService> _manyServices = List<MasterService>.generate(
  10,
  _service,
);

MasterService _service(int i) => MasterService(
  id: 'svc-$i',
  serviceDefId: 'def-$i',
  // i18n-finder-ok: fixture service name (test data), never asserted by value.
  name: 'Послуга $i',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

/// The bare shared shelf, top-left aligned so its intrinsic height is what gets
/// measured (not stretched by a parent). Mirrors the salon callers' contract:
/// `services:` only — no `onRemove`, no `chosenLabelFor`.
Widget _bareShelf(List<MasterService> services) => Scaffold(
  body: Align(
    alignment: Alignment.topLeft,
    child: SelectedServicesShelf(services: services),
  ),
);

/// The independent-flow bar composing the shelf. Post-MO-3 the independent
/// booking flow's shelf is [BookingSummaryBar] (the per-service
/// `IndependentScheduleConfirmBar` was retired with the single-visit rework);
/// it composes the SAME shared [SelectedServicesShelf], so the shrink-wrap
/// contract is pinned from this entry point too.
Widget _independentBar(List<MasterService> services) => Scaffold(
  bottomNavigationBar: BookingSummaryBar(
    services: services,
    // i18n-finder-ok: test-only CTA caption, never asserted by value.
    ctaLabel: 'Далі',
    ctaIcon: Icons.arrow_forward_rounded,
    enabled: true,
    onAction: () {},
  ),
);

/// The salon-flow bar composing the shelf. `selectedServices` is the flattened
/// client selection the shelf itemizes; the single schedule just satisfies the
/// required constructor params (the shelf sizing is driven by `selectedServices`).
Widget _salonBar(List<MasterService> services) {
  final SalonMasterSchedule schedule = SalonMasterSchedule(
    masterId: 'm1',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    type: MasterType.independentMaster,
    services: <SalonCatalogService>[
      for (final MasterService s in services)
        SalonCatalogService(
          id: s.id,
          name: s.name,
          durationLabel: '1 год',
          priceDisplay: s.priceDisplay,
          durationMinutes: s.durationMinutes,
          priceType: ServicePriceType.fixed,
          priceMin: s.priceMin,
        ),
    ],
    primaryServiceAssignmentId: 'assignment-m1-${services.first.id}',
  );
  return Scaffold(
    bottomNavigationBar: ScheduleConfirmBar(
      schedules: <SalonMasterSchedule>[schedule],
      selectedServices: services,
      scheduledCount: 0,
      totalCount: 1,
      onConfirm: () {},
    ),
  );
}

/// Expands the shelf and returns the rendered height of the itemized-list panel.
Future<double> _expandAndMeasurePanel(WidgetTester tester) async {
  await tester.tap(find.byKey(_toggleKey));
  await tester.pumpAndSettle();
  expect(
    find.byKey(_expandedListKey),
    findsOneWidget,
    reason: 'the itemized list must be built once expanded',
  );
  return tester.getSize(find.byKey(_expandedListKey)).height;
}

/// The `Scrollable` the ListView builds under [_expandedListKey] — its
/// `maxScrollExtent` is > 0 exactly when content overflows the capped viewport.
ScrollableState _panelScrollable(WidgetTester tester) => tester.state(
  find.descendant(
    of: find.byKey(_expandedListKey),
    matching: find.byType(Scrollable),
  ),
);

void main() {
  group('direct SelectedServicesShelf — shrink-wrap sizing contract', () {
    testWidgets(
      'fits content: 2 services size the panel well under listMaxHeight — no '
      'excess blank gap (pre-fix this measured exactly 188.0)',
      (tester) async {
        await tester.pumpApp(_bareShelf(_twoServices));
        await tester.pumpAndSettle();

        final double panelHeight = await _expandAndMeasurePanel(tester);

        // Core regression guard: a non-shrink-wrapped ListView filled the whole
        // 188dp (188.0 < 188.0 is false → this line fails pre-fix). Shrink-wrap
        // makes it fit → ~82dp.
        expect(
          panelHeight,
          lessThan(SelectedServicesShelf.listMaxHeight),
          reason:
              'without shrinkWrap the list greedily fills the full '
              'listMaxHeight (188) regardless of the 2-row content',
        );
        // "Well under" — encode the no-excess-gap property, not just "not 188":
        // two ~40dp rows should land far below the cap.
        expect(
          panelHeight,
          lessThan(SelectedServicesShelf.listMaxHeight * 0.75),
          reason:
              'the 2-row content should fit snugly, leaving no large blank gap '
              'under the last service',
        );
      },
    );

    testWidgets(
      'caps + scrolls: ~10 services clamp the panel to listMaxHeight and the '
      'ListView stays shrink-wrapped AND scrollable (content overflows the cap)',
      (tester) async {
        await tester.pumpApp(_bareShelf(_manyServices));
        await tester.pumpAndSettle();

        final double panelHeight = await _expandAndMeasurePanel(tester);

        // Clamped at the cap — the ConstrainedBox still bounds worst-case height.
        expect(
          panelHeight,
          moreOrLessEquals(SelectedServicesShelf.listMaxHeight, epsilon: 0.5),
          reason:
              'with more rows than the cap allows, the panel must clamp to '
              'listMaxHeight (188), not grow unbounded',
        );

        // The shrink-wrap contract itself is pinned as an observable widget
        // property, so a future edit dropping it fails here directly.
        final ListView list = tester.widget<ListView>(
          find.byKey(_expandedListKey),
        );
        expect(
          list.shrinkWrap,
          isTrue,
          reason: 'shrinkWrap: true is the fix under regression test',
        );

        // Cap-and-scroll path still works: content exceeds the capped viewport,
        // so the list is scrollable (maxScrollExtent > 0).
        expect(
          _panelScrollable(tester).position.maxScrollExtent,
          greaterThan(0),
          reason:
              'a shrink-wrapped list clamped at the cap must still scroll its '
              'overflowing rows — not truncate them',
        );
      },
    );
  });

  group('both compositions — independent + salon entry points size alike', () {
    testWidgets('independent bar (BookingSummaryBar) fits-content: 2 services '
        'size the shelf panel well under the cap — proving the independent page '
        'composes the fixed shelf', (tester) async {
      await tester.pumpApp(_independentBar(_twoServices));
      await tester.pumpAndSettle();

      final double panelHeight = await _expandAndMeasurePanel(tester);
      expect(panelHeight, lessThan(SelectedServicesShelf.listMaxHeight));
      expect(
        panelHeight,
        lessThan(SelectedServicesShelf.listMaxHeight * 0.75),
        reason: 'the independent bar must not reintroduce the blank gap',
      );
    });

    testWidgets(
      'independent bar caps-and-scrolls: ~10 services clamp the shelf panel to '
      'the cap and keep it shrink-wrapped + scrollable',
      (tester) async {
        await tester.pumpApp(_independentBar(_manyServices));
        await tester.pumpAndSettle();

        final double panelHeight = await _expandAndMeasurePanel(tester);
        expect(
          panelHeight,
          moreOrLessEquals(SelectedServicesShelf.listMaxHeight, epsilon: 0.5),
        );
        expect(
          tester.widget<ListView>(find.byKey(_expandedListKey)).shrinkWrap,
          isTrue,
        );
        expect(
          _panelScrollable(tester).position.maxScrollExtent,
          greaterThan(0),
        );
      },
    );

    testWidgets(
      'salon bar (ScheduleConfirmBar) fits-content: 2 services size the shelf '
      'panel well under the cap — proving the salon page composes the same '
      'fixed shelf',
      (tester) async {
        await tester.pumpApp(_salonBar(_twoServices));
        await tester.pumpAndSettle();

        final double panelHeight = await _expandAndMeasurePanel(tester);
        expect(panelHeight, lessThan(SelectedServicesShelf.listMaxHeight));
        expect(
          panelHeight,
          lessThan(SelectedServicesShelf.listMaxHeight * 0.75),
          reason: 'the salon bar must not reintroduce the blank gap',
        );
      },
    );

    testWidgets(
      'salon bar caps-and-scrolls: ~10 services clamp the shelf panel to the '
      'cap and keep it shrink-wrapped + scrollable',
      (tester) async {
        await tester.pumpApp(_salonBar(_manyServices));
        await tester.pumpAndSettle();

        final double panelHeight = await _expandAndMeasurePanel(tester);
        expect(
          panelHeight,
          moreOrLessEquals(SelectedServicesShelf.listMaxHeight, epsilon: 0.5),
        );
        expect(
          tester.widget<ListView>(find.byKey(_expandedListKey)).shrinkWrap,
          isTrue,
        );
        expect(
          _panelScrollable(tester).position.maxScrollExtent,
          greaterThan(0),
        );
      },
    );
  });
}
