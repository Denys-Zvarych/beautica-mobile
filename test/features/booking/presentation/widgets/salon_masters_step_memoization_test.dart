// mobile-perf LOW (phase 335 diff, 2026-09-18) — memoization test for
// `_SalonMastersStepState._resolveDerived`'s `(resolved, covering,
// nonCovering)` cache in `salon_booking_wizard_steps.dart`.
//
// `debugResolveSalonMastersCallCount` only increments on a genuine cache
// MISS into `_resolveDerived` — asserting on it, rather than on rendered
// output, is load-bearing: a regression back to recomputing the three
// comprehensions unconditionally on every `build()` would render
// byte-identical output and pass every OTHER test that exercises this
// widget (mirrors `master_archive_screen_test.dart`'s
// `debugGroupArchiveByKyivDayCallCount` group).
//
// The `services` case below is the one that actually matters: the real
// caller (`salon_create_booking_screen.dart`) holds `_selectedServices` as
// ONE `final List<MasterService>` mutated IN PLACE via
// `.add`/`.removeWhere`, so a naive `identical()`-only cache key would
// report a HIT even after the selection's CONTENT changed. This file proves
// the cache key is content-based (a fresh List with identical ORDERED
// content still hits; a reordered one — same elements, different order —
// misses) rather than assuming it from reading the source.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_masters_roster.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/salon_booking_wizard_steps.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/selected_services_shelf.dart'
    show salonServiceForShelf;
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

import '../../../../helpers/booking_fixture_dates.dart';
import '../../../../helpers/fake_salon_master_coverage.dart';
import '../../../../helpers/fake_salon_staff_masters_roster.dart';
import '../../../../helpers/fakes/fake_slot_repository.dart';
import '../../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';

// Two masters (never the ROSTER-count-1 collapse path — that renders
// `_SalonCollapsedSlots`, which fetches slots eagerly and would need its own
// repository override). Only master A covers both services; master B stays
// non-covering, exercising the SAME split this widget always computes.
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

// `salonServiceForShelf` is the SAME `SalonCatalogService -> MasterService`
// adapter `salon_create_booking_screen.dart` itself uses — reused rather
// than hand-building a `MasterService` here.
final MasterService _kService1 = salonServiceForShelf(_kSvc1);
final MasterService _kService2 = salonServiceForShelf(_kSvc2);

// `date` is opaque to `_resolveDerived`'s memo key (only `ordered`/`roster`/
// `coverage` participate — see `_resolveDerived` in
// `salon_booking_wizard_steps.dart`) and this suite never expands a tile far
// enough to fetch slots for it, so any well-formed instant works here.
// `futureBookingStart()` (not a hand-rolled `DateTime.utc(2026, ...)`
// literal) keeps this fixture immune to `forbid_stale_future_date_fixture
// .sh` going forward, same as the booking-detail specs it was built for.
final DateTime _kDate = futureBookingStart();

Map<String, Map<String, String>> _coverageBoth() =>
    <String, Map<String, String>>{
      _kMasterA.masterId: <String, String>{
        _kSvc1.id: 'assignment-a-1',
        _kSvc2.id: 'assignment-a-2',
      },
    };

/// Mutable holder the tests poke, so a rebuild can change exactly ONE
/// input — mirrors `master_column_strip_rebuild_gate_test.dart`'s
/// `_HostController`/`_Host` pattern.
class _HostController {
  List<MasterService> services = <MasterService>[_kService1, _kService2];
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
  Widget build(BuildContext context) => SalonMastersStep(
    salonId: _kSalonId,
    services: widget.state.services,
    date: _kDate,
    onPick: (SalonMasterSummary master, List<String> ids, BookingSlot slot) {},
  );
}

Future<_HostController> _pump(WidgetTester tester) async {
  final _HostController c = _HostController();
  await tester.pumpApp(
    _Host(state: c),
    overrides: <Object>[
      salonStaffMastersRosterProvider.overrideWith(
        () => FakeSalonStaffMastersRoster(
          () => <SalonMasterSummary>[_kMasterA, _kMasterB],
        ),
      ),
      salonMasterServiceCoverageProvider.overrideWith(
        () => FakeSalonMasterServiceCoverage(
          () => salonCoverageOf(_coverageBoth()),
        ),
      ),
      // 2026-09-18 — `_SalonMasterTile` now watches
      // `salonMasterDaySlotsProvider` EAGERLY (not only on expand) to know
      // up front whether a covering master has free time; master A reaches
      // that watch as soon as the step mounts, so this needs a settled
      // fake rather than the real (unmocked) repository. This suite never
      // asserts on slot content, only on `_resolveDerived`'s memo count, so
      // the default empty response is fine.
      slotRepositoryProvider.overrideWith((_) => FakeSlotRepository()),
    ],
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUp(debugResetResolveSalonMastersCallCount);

  testWidgets(
    'N rebuilds with UNCHANGED inputs recompute the derived lists ONCE',
    (WidgetTester tester) async {
      final _HostController c = await _pump(tester);

      // The initial `data` build (after roster/coverage resolve) is the one
      // and only expected cache MISS.
      expect(debugResolveSalonMastersCallCount, 1);

      for (int i = 0; i < 5; i++) {
        c.rebuild();
        await tester.pump();
      }

      expect(
        debugResolveSalonMastersCallCount,
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
      expect(debugResolveSalonMastersCallCount, 1);

      // A brand-new List instance, same elements, same order — exactly what
      // `services ?? <MasterService>[service!]` would rebuild every frame if
      // the caller passed `service:` instead of `services:`, and exactly the
      // shape an `identical()`-only key would wrongly reject.
      c.services = List<MasterService>.of(c.services);
      c.rebuild();
      await tester.pump();

      expect(
        debugResolveSalonMastersCallCount,
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
      expect(debugResolveSalonMastersCallCount, 1);

      // Same two services, swapped order — mirrors the real app's
      // deselect-then-reselect flow, which appends to the END of the
      // mutated-in-place `_selectedServices` list.
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
        debugResolveSalonMastersCallCount,
        2,
        reason:
            'the ordered assignment ids drive the visit — a reorder is a '
            'semantically different selection and MUST recompute',
      );
    },
  );
}
