// 2026-10-30 — master-nav setup-hint dots («Послуги» tile 0, «Графік» tile 2).
//
// Real `masterNavSetupHintsProvider` over the REAL phase 416
// `bookingLinkSetupHintsProvider` and the REAL `ownScheduleScopeProvider`,
// with only the leaf data sources faked (services catalogue, master profile,
// the effective-schedule readiness window).
//
// Coverage:
//   • dot + semantics hint per tile when that step is missing, absent when done;
//   • schedule = backend bookability (architect ruling, cycle 1): all-days-off
//     template / no working day → dot; CUSTOM_HOURS-only → no dot;
//   • absent while loading and on error (no flicker, no guess);
//   • absent for every non-INDEPENDENT_MASTER role;
//   • `showSetupHints` defaults off — the default bar never shows a dot;
//   • dot clears after the catalogue is re-fetched with a service;
//   • account switch A → B: A's cached schedule answer never shows for B
//     (security LOW, cycle 1);
//   • after sign-out the hint chain drives no schedule read on the emptied
//     scope (perf LOW, cycle 1).
//
// Finders use widget Keys (M2). Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../helpers/pump_app.dart';

/// [FixedRoleAuth] plus a sign-out, for the logout-boundary test.
class _Auth extends FixedRoleAuth {
  _Auth(super.role);

  void signOut() =>
      state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
}

/// The master row per signed-in user id; `u2`'s load can be held open.
class _FakeProfile extends MasterProfile {
  _FakeProfile(this._read);
  final Future<Master> Function(String? userId) _read;

  @override
  Future<Master> build() =>
      _read(ref.watch(authProvider.select(authUserIdOrNull)));
}

class _FakeEffective extends EffectiveScheduleNotifier {
  _FakeEffective(this._read);
  final Future<List<EffectiveDay>> Function(ScheduleScope scope) _read;

  @override
  Future<List<EffectiveDay>> build(ScheduleScope scope, ScheduleRange range) =>
      _read(scope);
}

const MasterService _active = MasterService(
  id: 'ms-1',
  serviceDefId: 'sd-1',
  name: 'Манікюр',
  durationMinutes: 60,
);

Master _master(String id) => Master(
  id: id,
  firstName: 'Олена',
  lastName: 'Т',
  reviewCount: 0,
  type: MasterType.independentMaster,
);

EffectiveDay _day(EffectiveSource source, {bool working = false}) =>
    EffectiveDay(
      date: DateTime(2026, 6, 15),
      source: source,
      intervals: working
          ? <WorkInterval>[
              WorkInterval(
                start: const TimeOfDay(hour: 9, minute: 0),
                end: const TimeOfDay(hour: 18, minute: 0),
              ),
            ]
          : const <WorkInterval>[],
    );

final List<EffectiveDay> _working = <EffectiveDay>[
  _day(EffectiveSource.template, working: true),
];
final List<EffectiveDay> _noSchedule = <EffectiveDay>[
  _day(EffectiveSource.noSchedule),
];

const Key _servicesDot = Key('master-nav-setup-dot-0');
const Key _scheduleDot = Key('master-nav-setup-dot-2');

void main() {
  late bool hasServices;
  late bool servicesInactive;
  late bool failReads;
  late List<EffectiveDay> Function(String masterId) daysFor;
  late int scheduleFetches;
  late List<ScheduleScope> fetchedScopes;
  Completer<void>? gate;
  Completer<void>? u2ProfileGate;

  setUp(() {
    hasServices = true;
    servicesInactive = false;
    failReads = false;
    daysFor = (_) => _working;
    scheduleFetches = 0;
    fetchedScopes = <ScheduleScope>[];
    gate = null;
    u2ProfileGate = null;
  });

  Future<void> pump(
    WidgetTester tester, {
    UserRole role = UserRole.independentMaster,
    bool showSetupHints = true,
  }) async {
    await tester.pumpApp(
      Scaffold(
        bottomNavigationBar: VelvetBottomNavBar(
          activeIndex: 3,
          showSetupHints: showSetupHints,
        ),
      ),
      retry: (_, _) => null,
      overrides: <Object>[
        authProvider.overrideWith(() => _Auth(role)),
        masterProfileProvider.overrideWith(
          () => _FakeProfile((String? userId) async {
            if (userId == 'u2') {
              await u2ProfileGate?.future;
              return _master('m-B');
            }
            return _master('m-A');
          }),
        ),
        effectiveScheduleProvider.overrideWith2(
          (_) => _FakeEffective((ScheduleScope scope) async {
            scheduleFetches++;
            fetchedScopes.add(scope);
            await gate?.future;
            if (failReads) throw const NetworkFailure();
            return switch (scope) {
              OwnScheduleScope(:final String masterId) => daysFor(masterId),
              _ => _working,
            };
          }),
        ),
        masterServiceCatalogProvider.overrideWith((ref) async {
          await gate?.future;
          if (failReads) throw const NetworkFailure();
          if (!hasServices) return const <MasterService>[];
          return <MasterService>[
            if (servicesInactive)
              _active.copyWith(isActive: false)
            else
              _active,
          ];
        }),
      ],
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(VelvetBottomNavBar)),
      );

  group('INDEPENDENT_MASTER', () {
    testWidgets('both steps done → no dot on any tile', (tester) async {
      await pump(tester);
      expect(find.byKey(_servicesDot), findsNothing);
      expect(find.byKey(_scheduleDot), findsNothing);
    });

    testWidgets('no services → «Послуги» dot only, with semantics hint', (
      tester,
    ) async {
      hasServices = false;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('master-nav-tile-0')),
          matching: find.byKey(_servicesDot),
        ),
        findsOneWidget,
      );
      expect(find.byKey(_scheduleDot), findsNothing);
      expect(
        tester.getSemantics(find.byKey(const Key('master-nav-tile-0'))).hint,
        'Додайте послуги',
      );
      // The dot never puts a hint on a tile whose step is done.
      expect(
        tester.getSemantics(find.byKey(const Key('master-nav-tile-2'))).hint,
        isEmpty,
      );
      semantics.dispose();
    });

    testWidgets('only inactive services → «Послуги» dot', (tester) async {
      servicesInactive = true;
      await pump(tester);
      expect(find.byKey(_servicesDot), findsOneWidget);
    });

    testWidgets('no working day in the window → «Графік» dot only, with '
        'semantics hint', (tester) async {
      daysFor = (_) => _noSchedule;
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('master-nav-tile-2')),
          matching: find.byKey(_scheduleDot),
        ),
        findsOneWidget,
      );
      expect(find.byKey(_servicesDot), findsNothing);
      expect(
        tester.getSemantics(find.byKey(const Key('master-nav-tile-2'))).hint,
        'Налаштуйте розклад',
      );
      semantics.dispose();
    });

    testWidgets('all-days-off template (template days, no hours) → dot', (
      tester,
    ) async {
      daysFor = (_) => <EffectiveDay>[_day(EffectiveSource.template)];
      await pump(tester);
      expect(find.byKey(_scheduleDot), findsOneWidget);
    });

    testWidgets('CUSTOM_HOURS override only → no dot', (tester) async {
      daysFor = (_) => <EffectiveDay>[
        _day(EffectiveSource.noSchedule),
        _day(EffectiveSource.overrideCustom, working: true),
      ];
      await pump(tester);
      expect(find.byKey(_scheduleDot), findsNothing);
    });

    testWidgets('both missing → both dots', (tester) async {
      hasServices = false;
      daysFor = (_) => _noSchedule;
      await pump(tester);
      expect(find.byKey(_servicesDot), findsOneWidget);
      expect(find.byKey(_scheduleDot), findsOneWidget);
    });

    testWidgets('while loading → no dot; settles to dot on zero', (
      tester,
    ) async {
      hasServices = false;
      daysFor = (_) => _noSchedule;
      gate = Completer<void>();
      await pump(tester);
      expect(find.byKey(_servicesDot), findsNothing);
      expect(find.byKey(_scheduleDot), findsNothing);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_servicesDot), findsOneWidget);
      expect(find.byKey(_scheduleDot), findsOneWidget);
    });

    testWidgets('on error → no dot', (tester) async {
      hasServices = false;
      daysFor = (_) => _noSchedule;
      failReads = true;
      await pump(tester);
      expect(find.byKey(_servicesDot), findsNothing);
      expect(find.byKey(_scheduleDot), findsNothing);
    });

    // The two dots are independent: one upstream failing must not suppress
    // (or fake) the other tile's answer.
    testWidgets('schedule read fails, no services → «Послуги» dot only', (
      tester,
    ) async {
      hasServices = false;
      daysFor = (_) => throw const NetworkFailure();
      await pump(tester);
      expect(find.byKey(_servicesDot), findsOneWidget);
      expect(find.byKey(_scheduleDot), findsNothing);
    });

    testWidgets('catalogue RE-read fails → «Послуги» dot drops, «Графік» '
        'dot stays', (tester) async {
      hasServices = false;
      daysFor = (_) => _noSchedule;
      await pump(tester);
      expect(find.byKey(_servicesDot), findsOneWidget);
      expect(find.byKey(_scheduleDot), findsOneWidget);
      failReads = true;
      // Only the catalogue re-reads (schedule stays settled on _noSchedule).
      containerOf(tester).invalidate(masterServiceCatalogProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(_servicesDot), findsNothing);
      expect(find.byKey(_scheduleDot), findsOneWidget);
    });

    testWidgets('dot clears once a service exists (catalogue re-fetched)', (
      tester,
    ) async {
      hasServices = false;
      await pump(tester);
      expect(find.byKey(_servicesDot), findsOneWidget);
      hasServices = true;
      containerOf(tester).invalidate(masterServiceCatalogProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(_servicesDot), findsNothing);
    });

    testWidgets('showSetupHints off (default) → never a dot', (tester) async {
      hasServices = false;
      daysFor = (_) => _noSchedule;
      await pump(tester, showSetupHints: false);
      expect(find.byKey(_servicesDot), findsNothing);
      expect(find.byKey(_scheduleDot), findsNothing);
    });

    testWidgets("account switch A → B: A's cached schedule answer never shows "
        'for B while B loads', (tester) async {
      // A has no schedule (dot), B has one (no dot).
      daysFor = (String id) => id == 'm-A' ? _noSchedule : _working;
      await pump(tester);
      expect(find.byKey(_scheduleDot), findsOneWidget, reason: "A's own dot");

      // Logout + login as B on the same device: B's profile is in flight, so
      // the own-schedule scope still carries A's retained master id.
      u2ProfileGate = Completer<void>();
      (containerOf(tester).read(authProvider.notifier) as _Auth).switchUser(
        'u2',
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(_scheduleDot),
        findsNothing,
        reason: "B's profile is loading; A's schedule answer must not show",
      );

      u2ProfileGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_scheduleDot), findsNothing, reason: 'B is set up');
    });

    testWidgets(
      'after sign-out the hint chain drives no further schedule read',
      (tester) async {
        daysFor = (_) => _noSchedule;
        await pump(tester);
        expect(find.byKey(_scheduleDot), findsOneWidget);
        final ProviderContainer container = containerOf(tester);
        final int before = scheduleFetches;

        // What logout does, in the same turn: flip the session, then sweep the
        // schedule windows.
        (container.read(authProvider.notifier) as _Auth).signOut();
        container.invalidate(effectiveScheduleProvider);
        await tester.pumpAndSettle();

        expect(find.byKey(_scheduleDot), findsNothing);
        // The invalidated window may refresh ITSELF once (it still had a
        // listener when swept — and the production sweep eagerly re-reads
        // every pinned window anyway). What the hint chain controls: it never
        // drives a read keyed on the emptied own scope after sign-out.
        final List<ScheduleScope> after = fetchedScopes.sublist(before);
        expect(after.length, lessThanOrEqualTo(1));
        expect(
          after,
          isNot(contains(const ScheduleScope.own(masterId: ''))),
          reason: 'no readiness read on the signed-out (empty) scope',
        );
      },
    );
  });

  for (final UserRole role in <UserRole>[
    UserRole.client,
    UserRole.salonOwner,
    UserRole.salonAdmin,
    UserRole.salonMaster,
  ]) {
    testWidgets('${role.name}: nothing set up → still no dot', (tester) async {
      hasServices = false;
      daysFor = (_) => _noSchedule;
      await pump(tester, role: role);
      expect(find.byKey(_servicesDot), findsNothing);
      expect(find.byKey(_scheduleDot), findsNothing);
    });
  }
}
