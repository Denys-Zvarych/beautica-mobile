// mobile-perf LOW (phase 341 audit) — memoization test for
// `_SalonDateStepState._coveringMasterIds`'s cache in
// `salon_booking_wizard_steps.dart`, mirroring
// `salon_masters_step_memoization_test.dart`'s identical shape for its twin,
// `_SalonMastersStepState._resolveDerived` (own doc there — reused
// verbatim: content-equality on the ordered service ids, identity on
// roster/coverage).
//
// `debugCoveringMasterIdsCallCount` only increments on a genuine cache MISS
// — asserting on it, rather than rendered output, is load-bearing: a
// regression back to recomputing the covering-ids comprehension
// unconditionally on every `build()` would render byte-identical output and
// pass every OTHER test that exercises this widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_masters_roster_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/salon_booking_wizard_steps.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/selected_services_shelf.dart'
    show salonServiceForShelf;
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

import '../../../../helpers/fakes/fake_slot_repository.dart';
import '../../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';

// Two covering masters — never the roster-count-1 collapse path (irrelevant
// here: `SalonDateStep` has no collapse rule of its own).
const SalonMasterSummary _kMasterA = SalonMasterSummary(
  masterId: 'master-a',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  type: MasterType.salonMaster,
  reviewCount: 0,
);
const SalonMasterSummary _kMasterB = SalonMasterSummary(
  masterId: 'master-b',
  firstName: 'Ірина',
  lastName: 'Бондар',
  type: MasterType.salonMaster,
  reviewCount: 0,
);

const SalonCatalogService _kSvc1 = SalonCatalogService(
  id: 'salon-svc-1',
  name: 'Манікюр',
  durationLabel: '60 хв',
  priceDisplay: '500 ₴',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);
const SalonCatalogService _kSvc2 = SalonCatalogService(
  id: 'salon-svc-2',
  name: 'Педикюр',
  durationLabel: '45 хв',
  priceDisplay: '400 ₴',
  durationMinutes: 45,
  priceType: ServicePriceType.fixed,
  priceMin: 400,
);

final MasterService _kService1 = salonServiceForShelf(_kSvc1);
final MasterService _kService2 = salonServiceForShelf(_kSvc2);

// Both masters cover both services — the covering-set computation itself
// isn't this suite's concern, only how often it RECOMPUTES.
Map<String, Map<String, String>> _coverageBoth() =>
    <String, Map<String, String>>{
      _kMasterA.masterId: <String, String>{
        _kSvc1.id: 'assignment-a-1',
        _kSvc2.id: 'assignment-a-2',
      },
      _kMasterB.masterId: <String, String>{
        _kSvc1.id: 'assignment-b-1',
        _kSvc2.id: 'assignment-b-2',
      },
    };

/// Mutable holder the tests poke, so a rebuild can change exactly ONE
/// input — mirrors `salon_masters_step_memoization_test.dart`'s
/// `_HostController`/`_Host` pattern.
class _HostController {
  List<MasterService> services = <MasterService>[_kService1, _kService2];
  DateTime? selected;
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

  @override
  Widget build(BuildContext context) => SalonDateStep(
    salonId: _kSalonId,
    services: widget.state.services,
    selected: widget.state.selected,
    onSelect: (DateTime d) {},
  );
}

Future<_HostController> _pump(WidgetTester tester) async {
  final _HostController c = _HostController();
  await tester.pumpApp(
    _Host(state: c),
    overrides: <Object>[
      salonMastersRosterProvider.overrideWith(
        (ref, String salonId) async => <SalonMasterSummary>[
          _kMasterA,
          _kMasterB,
        ],
      ),
      salonMasterServiceCoverageProvider.overrideWith(
        (ref, args) async => _coverageBoth(),
      ),
      slotRepositoryProvider.overrideWith((_) => FakeSlotRepository()),
    ],
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUp(debugResetCoveringMasterIdsCallCount);

  testWidgets(
    'N rebuilds with UNCHANGED inputs recompute the covering-ids list ONCE',
    (WidgetTester tester) async {
      final _HostController c = await _pump(tester);

      // The initial `data` build (after roster/coverage resolve) is the one
      // and only expected cache MISS.
      expect(debugCoveringMasterIdsCallCount, 1);

      for (int i = 0; i < 5; i++) {
        c.rebuild();
        await tester.pump();
      }

      expect(
        debugCoveringMasterIdsCallCount,
        1,
        reason:
            'five no-op rebuilds over the SAME roster/coverage/service-order '
            'must all be absorbed by the memo, not just the first',
      );
    },
  );

  testWidgets(
    'a FRESH List with IDENTICAL ordered content still HITS the cache — the '
    'key is content, not list identity',
    (WidgetTester tester) async {
      final _HostController c = await _pump(tester);
      expect(debugCoveringMasterIdsCallCount, 1);

      // A brand-new List instance, same elements, same order — exactly the
      // shape an `identical()`-only key would wrongly reject.
      c.services = List<MasterService>.of(c.services);
      c.rebuild();
      await tester.pump();

      expect(
        debugCoveringMasterIdsCallCount,
        1,
        reason:
            'same serviceDefIds in the same order must hit the cache even '
            'though the List object itself is new',
      );
    },
  );

  testWidgets(
    'a REORDERED selected-services list MISSES the cache and recomputes',
    (WidgetTester tester) async {
      final _HostController c = await _pump(tester);
      expect(debugCoveringMasterIdsCallCount, 1);

      c.services = <MasterService>[_kService2, _kService1];
      c.rebuild();
      await tester.pump();
      // The reordered `selectedServiceIds` mint a NEW
      // `salonMasterServiceCoverageProvider` family entry (order is part of
      // its args), so `coverage` is briefly null again — one more pump lets
      // the override's Future resolve, same as the real app's own loading
      // flicker on a genuine selection change.
      await tester.pump();

      expect(
        debugCoveringMasterIdsCallCount,
        2,
        reason:
            'the ordered assignment ids drive the visit — a reorder is a '
            'semantically different selection and MUST recompute',
      );
    },
  );
}
