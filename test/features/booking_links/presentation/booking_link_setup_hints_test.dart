// Phase 416 — readiness hints on «Посилання для запису».
//
// Real providers end to end: the REAL bookingLinksProvider, the REAL
// bookingLinkSetupHintsProvider and the real schedule / service providers,
// over mocked/fake data sources (booking-links repo, services catalogue,
// weekly-schedule notifier, salon roster-schedule repo, salon catalogue).
//
// Coverage:
//   • hint matrix (nothing missing / schedule only / services only / both)
//     for the INDEPENDENT_MASTER card and the SALON card (owner);
//   • nothing missing → no hint widget AND no generic note (no extra space);
//   • a bookable link never shows hints (server verdict wins);
//   • loading / failed readiness check → no hint (generic note remains);
//   • tapping a hint pushes the right target per role (master / owner /
//     admin) and back returns to the screen, where setting the thing up
//     clears the hint (providers re-evaluated).
//
// Finders use widget Keys (M2). Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking_links/data/booking_links_repository.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_screen.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_setup_hints_provider.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/schedule/application/own_schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/effective_schedule_notifier.dart';
import 'package:beautica_mobile/features/schedule/presentation/schedule_range.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../../helpers/clock_instant.dart';
import '../../../helpers/pump_app.dart';

class _MockLinksRepo extends Mock implements BookingLinksRepository {}

class _MockRosterRepo extends Mock implements SalonRosterScheduleRepository {}

/// The master's resolved effective days, read from a mutable test-owned
/// world. Since 2026-10-30 (architect ruling) the master readiness rule reads
/// `effectiveScheduleProvider` over the 180-day bookability window — the
/// server has already applied overrides-then-template, so each ruling case is
/// expressed as the days the backend resolves for it.
class _FakeEffective extends EffectiveScheduleNotifier {
  _FakeEffective(this._read);
  final Future<List<EffectiveDay>> Function(
    ScheduleScope scope,
    ScheduleRange range,
  )
  _read;

  @override
  Future<List<EffectiveDay>> build(ScheduleScope scope, ScheduleRange range) =>
      _read(scope, range);
}

/// The signed-in user's master row: `u1` → `m1`, `u2` → `m2` (whose load can
/// be held open with [_FakeProfile.u2Gate] to model an account switch).
class _FakeProfile extends MasterProfile {
  _FakeProfile(this._u2Gate);
  final Future<void>? Function() _u2Gate;

  @override
  Future<Master> build() async {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    if (userId == 'u2') await _u2Gate();
    return Master(
      id: userId == 'u2' ? 'm2' : 'm1',
      firstName: 'Олена',
      lastName: 'Т',
      reviewCount: 0,
      type: MasterType.independentMaster,
    );
  }
}

/// How the backend resolves the master's 180-day window, per ruling case.
enum _MasterDays {
  /// A template with working hours → template days with intervals.
  template,

  /// No template at all → every day NO_SCHEDULE.
  none,

  /// A template whose every day is off → template days, no intervals.
  allDaysOffTemplate,

  /// A template whose `validTo` is in the past → NO_SCHEDULE in the window.
  expiredTemplate,

  /// A template starting > 180 days out → NO_SCHEDULE in the window.
  farFutureTemplate,

  /// No template, one CUSTOM_HOURS override with intervals → bookable.
  customHoursOnly,

  /// No template, one explicit-times CUSTOM_HOURS override → bookable.
  customTimesOnly,

  /// No template, one DAY_OFF override → not bookable.
  dayOffOverrideOnly,
}

List<EffectiveDay> _resolve(_MasterDays world) {
  EffectiveDay day(
    int d,
    EffectiveSource source, {
    bool working = false,
    bool times = false,
  }) => EffectiveDay(
    date: DateTime(2026, 6, d),
    source: source,
    intervals: working && !times
        ? <WorkInterval>[
            WorkInterval(
              start: const TimeOfDay(hour: 9, minute: 0),
              end: const TimeOfDay(hour: 18, minute: 0),
            ),
          ]
        : const <WorkInterval>[],
    times: times
        ? const <TimeOfDay>[TimeOfDay(hour: 10, minute: 0)]
        : const <TimeOfDay>[],
  );
  final List<EffectiveDay> empty = <EffectiveDay>[
    for (int d = 15; d <= 21; d++) day(d, EffectiveSource.noSchedule),
  ];
  return switch (world) {
    _MasterDays.template => <EffectiveDay>[
      day(15, EffectiveSource.template, working: true),
      day(16, EffectiveSource.template),
    ],
    _MasterDays.none ||
    _MasterDays.expiredTemplate ||
    _MasterDays.farFutureTemplate => empty,
    _MasterDays.allDaysOffTemplate => <EffectiveDay>[
      for (int d = 15; d <= 21; d++) day(d, EffectiveSource.template),
    ],
    _MasterDays.customHoursOnly => <EffectiveDay>[
      ...empty.skip(1),
      day(22, EffectiveSource.overrideCustom, working: true),
    ],
    _MasterDays.customTimesOnly => <EffectiveDay>[
      ...empty.skip(1),
      day(22, EffectiveSource.overrideCustom, working: true, times: true),
    ],
    _MasterDays.dayOffOverrideOnly => <EffectiveDay>[
      ...empty.skip(1),
      day(22, EffectiveSource.overrideDayOff),
    ],
  };
}

class _FakeMySalons extends MySalons {
  _FakeMySalons(this._read);
  final List<Salon> Function() _read;

  @override
  Future<List<Salon>> build() async => _read();
}

const BookingLink _master = BookingLink(
  kind: BookingLinkKind.master,
  slug: 'olena-x7k2',
  url: 'https://beautica.app/book/olena-x7k2',
  displayName: 'Олена',
  bookable: false,
);

const BookingLink _salon = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'lumiere-kyiv',
  url: 'https://beautica.app/book/s/lumiere-kyiv',
  displayName: 'Lumière',
  salonId: 'salon-a',
  bookable: false,
);

const MasterService _activeService = MasterService(
  id: 'ms-1',
  serviceDefId: 'sd-1',
  name: 'Манікюр',
  durationMinutes: 60,
);

const SalonCatalogService _salonService = SalonCatalogService(
  id: 'ss-1',
  name: 'Манікюр',
  durationLabel: '60 хв',
  priceDisplay: '500 ₴',
);

Key _hint(String which, String slug) =>
    Key('link-booking-link-hint-$which-$slug');
Key _setup(String slug) => Key('link-booking-link-setup-$slug');

GoRouter _router(List<String> pushed) {
  GoRoute stub(String path) => GoRoute(
    path: path,
    builder: (_, GoRouterState s) {
      pushed.add(s.uri.toString());
      return Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('stub-back'),
            onPressed: () {},
            child: const Text('stub'),
          ),
        ),
      );
    },
  );
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: SizedBox()),
      ),
      GoRoute(
        path: RouteNames.bookingLinks,
        builder: (_, _) => const BookingLinkScreen(),
      ),
      stub(RouteNames.masterSchedule),
      stub(RouteNames.services),
      stub(RouteNames.ownerMasterSchedule),
      stub(RouteNames.ownerMasterServices),
      stub('/salons/:salonId/shell'),
    ],
  );
}

void main() {
  setUpAll(() => registerFallbackValue(DateTime(2026)));

  late _MockLinksRepo links;
  late _MockRosterRepo roster;
  late List<String> pushed;

  // Mutable "world" the fakes read — flipped to simulate setting things up.
  late bool hasSchedule;
  // Overrides [hasSchedule] when set — one of the ruling cases.
  _MasterDays? masterDays;
  // Per-master world (overrides [masterDays]) for the account-switch test.
  Map<String, _MasterDays>? masterDaysByMaster;
  // When true the REAL own-schedule scope is used (it follows the profile).
  bool realOwnScope = false;
  Completer<void>? u2ProfileGate;
  ScheduleRange? masterRange;
  late bool hasServices;
  late bool hasSalonSchedule;
  late bool hasSalonServices;
  Completer<void>? gate;
  bool failReads = false;
  bool mySalonsFail = false;
  bool servicesInactive = false;
  Completer<void>? servicesGate;
  DateTime? fixedToday;
  int masterCatalogFetches = 0;
  int salonCatalogFetches = 0;
  int masterScheduleFetches = 0;
  List<Salon> mySalons = const <Salon>[
    Salon(id: 'salon-a', name: 'Lumière', isPrimary: true),
  ];

  setUp(() {
    links = _MockLinksRepo();
    roster = _MockRosterRepo();
    pushed = <String>[];
    hasSchedule = true;
    masterDays = null;
    masterDaysByMaster = null;
    realOwnScope = false;
    u2ProfileGate = null;
    masterRange = null;
    hasServices = true;
    hasSalonSchedule = true;
    hasSalonServices = true;
    gate = null;
    failReads = false;
    mySalonsFail = false;
    servicesInactive = false;
    servicesGate = null;
    fixedToday = null;
    masterCatalogFetches = 0;
    salonCatalogFetches = 0;
    masterScheduleFetches = 0;
    mySalons = const <Salon>[
      Salon(id: 'salon-a', name: 'Lumière', isPrimary: true),
    ];
    when(
      () => roster.salonRosterEffectiveSchedule(any(), any(), any()),
    ).thenAnswer((_) async {
      if (failReads) throw const NetworkFailure();
      return <String, List<EffectiveDay>>{
        'm1': <EffectiveDay>[
          EffectiveDay(
            date: DateTime(2026, 6, 15),
            source: hasSalonSchedule
                ? EffectiveSource.template
                : EffectiveSource.noSchedule,
            intervals: const <WorkInterval>[],
          ),
        ],
      };
    });
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    required UserRole role,
    required BookingLink link,
    String? salonId,
  }) async {
    when(
      () => links.getMine(),
    ).thenAnswer((_) async => BookingLinks(shareEnabled: true, links: [link]));
    final GoRouter router = _router(pushed);
    addTearDown(router.dispose);
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        authProvider.overrideWith(() => FixedRoleAuth(role, salonId: salonId)),
        bookingLinksRepositoryProvider.overrideWithValue(links),
        if (!realOwnScope)
          ownScheduleScopeProvider.overrideWithValue(
            const ScheduleScope.own(masterId: 'm1'),
          ),
        masterProfileProvider.overrideWith(
          () => _FakeProfile(() => u2ProfileGate?.future),
        ),
        effectiveScheduleProvider.overrideWith2(
          (_) =>
              _FakeEffective((ScheduleScope scope, ScheduleRange range) async {
                masterScheduleFetches++;
                masterRange = range;
                await gate?.future;
                if (failReads) throw const NetworkFailure();
                final String masterId = switch (scope) {
                  OwnScheduleScope(:final String masterId) => masterId,
                  SalonMasterScheduleScope(:final String masterId) => masterId,
                };
                return _resolve(
                  masterDaysByMaster?[masterId] ??
                      masterDays ??
                      (hasSchedule ? _MasterDays.template : _MasterDays.none),
                );
              }),
        ),
        mySalonsProvider.overrideWith(
          () => _FakeMySalons(() {
            if (mySalonsFail) throw const NetworkFailure();
            return mySalons;
          }),
        ),
        if (fixedToday != null)
          clockProvider.overrideWithValue(() => asClockInstant(fixedToday!)),
        masterServiceCatalogProvider.overrideWith((ref) async {
          // Like production: the catalogue is rebuilt on an account switch.
          ref.watch(authProvider.select(authUserIdOrNull));
          masterCatalogFetches++;
          await servicesGate?.future;
          if (failReads) throw const NetworkFailure();
          if (!hasServices) return const <MasterService>[];
          return <MasterService>[
            servicesInactive
                ? _activeService.copyWith(isActive: false)
                : _activeService,
          ];
        }),
        salonRosterScheduleRepositoryProvider.overrideWithValue(roster),
        salonServiceCatalogProvider.overrideWith((ref, String id) async {
          salonCatalogFetches++;
          if (failReads) throw const NetworkFailure();
          return hasSalonServices
              ? const <SalonServiceCategoryEntry>[
                  SalonServiceCategoryEntry(
                    category: 'nails',
                    displayName: 'Нігті',
                    count: 1,
                    services: <SalonCatalogService>[_salonService],
                  ),
                ]
              : const <SalonServiceCategoryEntry>[];
        }),
      ],
    );
    await tester.pumpAndSettle();
    unawaited(router.push(RouteNames.bookingLinks));
    await tester.pumpAndSettle();
    return router;
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(BookingLinkScreen)));

  group('independent master', () {
    for (final (bool sched, bool serv) in <(bool, bool)>[
      (true, true),
      (false, true),
      (true, false),
      (false, false),
    ]) {
      testWidgets('schedule=$sched services=$serv', (tester) async {
        hasSchedule = sched;
        hasServices = serv;
        await pump(tester, role: UserRole.independentMaster, link: _master);

        expect(
          find.byKey(_hint('schedule', _master.keyId)),
          sched ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(_hint('services', _master.keyId)),
          serv ? findsNothing : findsOneWidget,
        );
        final AppLocalizations l10n = l10nOf(tester);
        if (sched && serv) {
          // Nothing missing: only the pre-existing generic note remains.
          expect(find.byKey(_setup(_master.keyId)), findsOneWidget);
        } else {
          // Specific hints REPLACE the generic note.
          expect(find.byKey(_setup(_master.keyId)), findsNothing);
          expect(
            find.textContaining(l10n.bookingLinkHintScheduleMaster),
            sched ? findsNothing : findsOneWidget,
          );
          expect(
            find.textContaining(l10n.bookingLinkHintServicesMaster),
            serv ? findsNothing : findsOneWidget,
          );
        }
      });
    }

    testWidgets('only INACTIVE services count as none', (tester) async {
      servicesInactive = true;
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('services', _master.keyId)), findsOneWidget);
    });

    testWidgets('a bookable link never shows hints', (tester) async {
      hasSchedule = false;
      hasServices = false;
      await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master.copyWith(bookable: true),
      );
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
      expect(find.byKey(_hint('services', _master.keyId)), findsNothing);
      expect(find.byKey(_setup(_master.keyId)), findsNothing);
    });

    testWidgets('failed readiness check → no hint, no error, generic note '
        'stays', (tester) async {
      failReads = true;
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
      expect(find.byKey(_hint('services', _master.keyId)), findsNothing);
      expect(find.byKey(_setup(_master.keyId)), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('error')), findsNothing);
    });

    // Architect ruling 2026-10-30 — the master "has a schedule" verdict is the
    // backend's bookability: some WORKING day in [todayKyiv, +180).
    for (final (_MasterDays world, bool hint) in <(_MasterDays, bool)>[
      (_MasterDays.template, false),
      (_MasterDays.none, true),
      (_MasterDays.allDaysOffTemplate, true),
      (_MasterDays.expiredTemplate, true),
      (_MasterDays.farFutureTemplate, true),
      (_MasterDays.customHoursOnly, false),
      (_MasterDays.customTimesOnly, false),
      (_MasterDays.dayOffOverrideOnly, true),
    ]) {
      testWidgets('bookability rule: ${world.name} → schedule hint=$hint', (
        tester,
      ) async {
        masterDays = world;
        await pump(tester, role: UserRole.independentMaster, link: _master);
        expect(
          find.byKey(_hint('schedule', _master.keyId)),
          hint ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('readiness window is [todayKyiv, todayKyiv + 180) — the '
        'backend horizon', (tester) async {
      fixedToday = DateTime(2026, 6, 15);
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(masterRange, isNotNull);
      expect(masterRange!.from, DateTime(2026, 6, 15));
      // Inclusive `to` = today + 179 → 180 days in all.
      expect(masterRange!.to, DateTime(2026, 12, 11));
      // Calendar-field arithmetic (UTC) so a DST hour cannot skew the count.
      DateTime utc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
      expect(
        utc(masterRange!.to).difference(utc(masterRange!.from)).inDays + 1,
        kMasterReadinessHorizonDays,
      );
    });

    testWidgets('readiness still loading → no hint yet', (tester) async {
      hasSchedule = false;
      gate = Completer<void>();
      final GoRouter router = _router(pushed);
      addTearDown(router.dispose);
      when(() => links.getMine()).thenAnswer(
        (_) async => const BookingLinks(shareEnabled: true, links: [_master]),
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          authProvider.overrideWith(
            () => FixedRoleAuth(UserRole.independentMaster),
          ),
          bookingLinksRepositoryProvider.overrideWithValue(links),
          ownScheduleScopeProvider.overrideWithValue(
            const ScheduleScope.own(masterId: 'm1'),
          ),
          masterProfileProvider.overrideWith(() => _FakeProfile(() => null)),
          effectiveScheduleProvider.overrideWith2(
            (_) => _FakeEffective((_, _) async {
              await gate!.future;
              return _resolve(_MasterDays.none);
            }),
          ),
          masterServiceCatalogProvider.overrideWith(
            (ref) async => const <MasterService>[],
          ),
        ],
      );
      await tester.pumpAndSettle();
      unawaited(router.push(RouteNames.bookingLinks));
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsOneWidget);
    });

    testWidgets('tap «Налаштувати розклад» pushes /schedule; back returns '
        'and a set-up schedule clears the hint', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.masterSchedule);

      hasSchedule = true; // the user set it up over there
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookingLinkScreen), findsOneWidget);
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
    });

    testWidgets('tap «Додати послугу» pushes /services', (tester) async {
      hasServices = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      await tester.ensureVisible(find.byKey(_hint('services', _master.keyId)));
      await tester.tap(find.byKey(_hint('services', _master.keyId)));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.services);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookingLinkScreen), findsOneWidget);
    });
  });

  group('refresh, scoping and value type', () {
    test('BookingLinkSetupHints compares by contents; none is empty const', () {
      expect(
        const BookingLinkSetupHints(schedule: true),
        const BookingLinkSetupHints(schedule: true),
      );
      expect(
        const BookingLinkSetupHints(schedule: true),
        isNot(const BookingLinkSetupHints(services: true)),
      );
      expect(BookingLinkSetupHints.none.isEmpty, isTrue);
      expect(
        identical(
          BookingLinkSetupHints.none.missing,
          BookingLinkSetupHints.none.missing,
        ),
        isTrue,
      );
      expect(
        const BookingLinkSetupHints(schedule: true, services: true).missing,
        <BookingLinkSetupHint>[
          BookingLinkSetupHint.schedule,
          BookingLinkSetupHint.services,
        ],
      );
    });

    testWidgets('NO generic-note flash while the readiness refetch after '
        'return is loading', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();

      hasSchedule = true;
      gate = Completer<void>(); // hold the refetch open
      router.pop();
      // Let the pop transition finish so the post-return invalidate has run.
      for (int i = 0; i < 40 && masterScheduleFetches < 2; i++) {
        // fixed-wait-ok: stepping the pop transition frame by frame until the post-return refetch starts (bounded, condition-driven)
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        masterScheduleFetches,
        2,
        reason: 'refetch is genuinely in flight',
      );
      // Refetch in flight: previous hint stays, generic note does NOT appear.
      expect(find.byKey(_hint('schedule', _master.keyId)), findsOneWidget);
      expect(find.byKey(_setup(_master.keyId)), findsNothing);

      gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
    });

    testWidgets('NO change on return → bookingLinks NOT refetched; a real '
        'change → refetched', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      verify(() => links.getMine()).called(1);

      // Round trip 1: nothing set up over there.
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsOneWidget);
      verifyNever(() => links.getMine());

      // Round trip 2: the schedule was set up.
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();
      hasSchedule = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
      verify(() => links.getMine()).called(1);
    });

    testWidgets('setup page saves WHILE open (upstream already updated) → '
        'links ARE refetched on return', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      verify(() => links.getMine()).called(1);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingLinkScreen)),
      );

      await tester.ensureVisible(find.byKey(_hint('schedule', _master.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();

      // What the weekly editor's save does: the upstream re-emits while the
      // setup page is still on screen.
      hasSchedule = true;
      container.invalidate(effectiveScheduleProvider);
      await tester.pumpAndSettle();
      // The readiness answer is already the NEW one while the page is open
      // for any LIVE (unpaused) watcher — the screen's offstage card is
      // paused by the route, so subscribe explicitly to model that.
      final ProviderSubscription<BookingLinkSetupHints> live = container.listen(
        bookingLinkSetupHintsProvider(BookingLinkKind.master, '', 'u1'),
        (_, _) {},
      );
      addTearDown(live.close);
      hasSchedule = true;
      container.invalidate(effectiveScheduleProvider);
      await tester.pumpAndSettle();
      expect(
        container.read(
          bookingLinkSetupHintsProvider(BookingLinkKind.master, '', 'u1'),
        ),
        BookingLinkSetupHints.none,
      );

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
      verify(() => links.getMine()).called(1);
    });

    testWidgets('failed re-read on return → links refetched anyway (cannot '
        'tell, so refresh bookable)', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      verify(() => links.getMine()).called(1);
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();
      failReads = true;
      router.pop();
      await tester.pumpAndSettle();
      verify(() => links.getMine()).called(1);
    });

    testWidgets('same-user invalidate keeps the previous value; a DIFFERENT '
        'userId never gets it', (tester) async {
      hasSchedule = false;
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('schedule', _master.keyId)), findsOneWidget);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingLinkScreen)),
      );

      gate = Completer<void>();
      container.invalidate(effectiveScheduleProvider); // upstream refreshing
      container.invalidate(
        bookingLinkSetupHintsProvider(BookingLinkKind.master, '', 'u1'),
      );
      await tester.pump();
      expect(
        container.read(
          bookingLinkSetupHintsProvider(BookingLinkKind.master, '', 'u1'),
        ),
        const BookingLinkSetupHints(schedule: true),
        reason: 'same user, same instance: previous value is kept',
      );
      expect(
        container.read(
          bookingLinkSetupHintsProvider(BookingLinkKind.master, '', 'other'),
        ),
        BookingLinkSetupHints.none,
        reason: 'a different user id is a fresh instance: never the previous',
      );
      gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('account switch while a refresh is in flight never shows the '
        "previous account's hint", (tester) async {
      hasServices = false;
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('services', _master.keyId)), findsOneWidget);

      servicesGate = Completer<void>();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingLinkScreen)),
      );
      (container.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(_hint('services', _master.keyId)),
        findsNothing,
        reason: "the catalogue is re-fetching for u2; u1's answer is not shown",
      );

      servicesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('services', _master.keyId)), findsOneWidget);
    });

    testWidgets("account switch A → B: A's schedule hint never shows for B "
        "while B's profile loads (old master id retained)", (tester) async {
      // Real own scope: it follows `masterProfileProvider.value?.id`, which
      // RETAINS m1 while u2's profile is in flight.
      realOwnScope = true;
      masterDaysByMaster = <String, _MasterDays>{
        'm1': _MasterDays.none, // A: schedule missing → hint
        'm2': _MasterDays.template, // B: set up → no hint
      };
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('schedule', _master.keyId)), findsOneWidget);

      u2ProfileGate = Completer<void>();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingLinkScreen)),
      );
      expect(
        container.read(ownScheduleScopeProvider),
        const ScheduleScope.own(masterId: 'm1'),
      );
      (container.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');
      await tester.pump();
      await tester.pump();
      expect(
        container.read(ownScheduleScopeProvider),
        const ScheduleScope.own(masterId: 'm1'),
        reason: 'precondition: the stale master id is still retained',
      );
      expect(
        find.byKey(_hint('schedule', _master.keyId)),
        findsNothing,
        reason: "B's profile is loading; A's schedule answer must not show",
      );

      u2ProfileGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.keyId)), findsNothing);
    });

    testWidgets('schedule hint invalidates ONLY the schedule member (+links): '
        'the services catalogue is not refetched', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      final int weeklyBefore = masterScheduleFetches;
      final int catalogBefore = masterCatalogFetches;
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _master.keyId)));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(masterScheduleFetches, weeklyBefore + 1);
      expect(masterCatalogFetches, catalogBefore);
    });

    testWidgets('services hint invalidates ONLY the catalogue: the weekly '
        'schedule is not refetched', (tester) async {
      hasServices = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      final int weeklyBefore = masterScheduleFetches;
      final int catalogBefore = masterCatalogFetches;
      await tester.ensureVisible(find.byKey(_hint('services', _master.keyId)));
      await tester.tap(find.byKey(_hint('services', _master.keyId)));
      await tester.pumpAndSettle();
      hasServices = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(masterCatalogFetches, catalogBefore + 1);
      expect(masterScheduleFetches, weeklyBefore);
      expect(find.byKey(_hint('services', _master.keyId)), findsNothing);
    });

    testWidgets('LAST DAY of the month: window is that whole month and a '
        'scheduled master\'s past days do not read as noSchedule', (
      tester,
    ) async {
      fixedToday = DateTime(2026, 1, 31);
      hasSalonSchedule = true; // returned day is a (past) template day
      await pump(
        tester,
        role: UserRole.salonAdmin,
        link: _salon,
        salonId: 'salon-a',
      );
      final List<dynamic> args = verify(
        () => roster.salonRosterEffectiveSchedule(
          'salon-a',
          captureAny(),
          captureAny(),
        ),
      ).captured;
      expect(args[0], DateTime(2026, 1, 1));
      expect(args[1], DateTime(2026, 1, 31));
      expect(find.byKey(_hint('schedule', _salon.keyId)), findsNothing);
    });

    testWidgets('LAST DAY, nothing scheduled this month (a schedule starting '
        'only next month): the hint shows — documented limitation', (
      tester,
    ) async {
      fixedToday = DateTime(2026, 1, 31);
      hasSalonSchedule = false;
      await pump(
        tester,
        role: UserRole.salonAdmin,
        link: _salon,
        salonId: 'salon-a',
      );
      expect(find.byKey(_hint('schedule', _salon.keyId)), findsOneWidget);
    });

    testWidgets('salon schedule is read on the board\'s CURRENT-MONTH key', (
      tester,
    ) async {
      await pump(
        tester,
        role: UserRole.salonAdmin,
        link: _salon,
        salonId: 'salon-a',
      );
      final List<dynamic> args = verify(
        () => roster.salonRosterEffectiveSchedule(
          any(),
          captureAny(),
          captureAny(),
        ),
      ).captured;
      final DateTime from = args[0] as DateTime;
      final DateTime to = args[1] as DateTime;
      expect(from.day, 1);
      expect(to.add(const Duration(days: 1)).day, 1, reason: 'month end');
      expect(to.month, from.month);
    });
  });

  group('salon (owner)', () {
    for (final (bool sched, bool serv) in <(bool, bool)>[
      (true, true),
      (false, true),
      (true, false),
      (false, false),
    ]) {
      testWidgets('salon schedule=$sched services=$serv', (tester) async {
        hasSalonSchedule = sched;
        hasSalonServices = serv;
        await pump(tester, role: UserRole.salonOwner, link: _salon);

        expect(
          find.byKey(_hint('schedule', _salon.keyId)),
          sched ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(_hint('services', _salon.keyId)),
          serv ? findsNothing : findsOneWidget,
        );
        if (sched && serv) {
          expect(find.byKey(_setup(_salon.keyId)), findsOneWidget);
        } else {
          expect(find.byKey(_setup(_salon.keyId)), findsNothing);
        }
      });
    }

    testWidgets('owner hints go to the owner master-mode pages', (
      tester,
    ) async {
      hasSalonSchedule = false;
      hasSalonServices = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.salonOwner,
        link: _salon,
      );
      await tester.ensureVisible(find.byKey(_hint('schedule', _salon.keyId)));
      await tester.tap(find.byKey(_hint('schedule', _salon.keyId)));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.ownerMasterSchedule);

      hasSalonSchedule = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _salon.keyId)), findsNothing);
      expect(find.byKey(_hint('services', _salon.keyId)), findsOneWidget);

      await tester.ensureVisible(find.byKey(_hint('services', _salon.keyId)));
      await tester.tap(find.byKey(_hint('services', _salon.keyId)));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.ownerMasterServices);
    });

    testWidgets('admin hints go to the salon «Команда» tab', (tester) async {
      hasSalonServices = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.salonAdmin,
        link: _salon,
        salonId: 'salon-a',
      );
      await tester.ensureVisible(find.byKey(_hint('services', _salon.keyId)));
      await tester.tap(find.byKey(_hint('services', _salon.keyId)));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        RouteNames.salonShell('salon-a', openTeam: true),
      );
    });

    testWidgets('failed salon readiness → no hint', (tester) async {
      failReads = true;
      await pump(tester, role: UserRole.salonOwner, link: _salon);
      expect(find.byKey(_hint('schedule', _salon.keyId)), findsNothing);
      expect(find.byKey(_hint('services', _salon.keyId)), findsNothing);
    });

    testWidgets('salon CATALOGUE is refetched after a services hint return '
        'and the hint clears', (tester) async {
      hasSalonServices = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.salonOwner,
        link: _salon,
      );
      final int before = salonCatalogFetches;
      await tester.ensureVisible(find.byKey(_hint('services', _salon.keyId)));
      await tester.tap(find.byKey(_hint('services', _salon.keyId)));
      await tester.pumpAndSettle();
      hasSalonServices = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(salonCatalogFetches, before + 1);
      expect(find.byKey(_hint('services', _salon.keyId)), findsNothing);
    });

    testWidgets('owner with several salons: hints ONLY on the primary card; '
        'the other keeps the generic note and fetches nothing', (tester) async {
      hasSalonSchedule = false;
      hasSalonServices = false;
      mySalons = const <Salon>[
        Salon(id: 'salon-b', name: 'Loft', isPrimary: false),
        Salon(id: 'salon-a', name: 'Lumière', isPrimary: true),
      ];
      const BookingLink other = BookingLink(
        kind: BookingLinkKind.salon,
        slug: 'beauty-loft',
        url: 'https://beautica.app/book/s/beauty-loft',
        displayName: 'Loft',
        salonId: 'salon-b',
        bookable: false,
      );
      when(() => links.getMine()).thenAnswer(
        (_) async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_salon, other],
        ),
      );
      // pump() re-stubs getMine for one link, so build the app by hand.
      final GoRouter router = _router(pushed);
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          authProvider.overrideWith(() => FixedRoleAuth(UserRole.salonOwner)),
          bookingLinksRepositoryProvider.overrideWithValue(links),
          mySalonsProvider.overrideWith(() => _FakeMySalons(() => mySalons)),
          salonRosterScheduleRepositoryProvider.overrideWithValue(roster),
          salonServiceCatalogProvider.overrideWith((ref, String id) async {
            salonCatalogFetches++;
            return const <SalonServiceCategoryEntry>[];
          }),
        ],
      );
      await tester.pumpAndSettle();
      unawaited(router.push(RouteNames.bookingLinks));
      await tester.pumpAndSettle();

      expect(find.byKey(_hint('schedule', _salon.keyId)), findsOneWidget);
      expect(find.byKey(_hint('services', _salon.keyId)), findsOneWidget);
      expect(find.byKey(_hint('schedule', other.keyId)), findsNothing);
      expect(find.byKey(_hint('services', other.keyId)), findsNothing);
      expect(find.byKey(_setup(other.keyId)), findsOneWidget);
      expect(salonCatalogFetches, 1, reason: 'only the primary salon');
      verify(
        () => roster.salonRosterEffectiveSchedule('salon-a', any(), any()),
      ).called(1);
      verifyNever(
        () => roster.salonRosterEffectiveSchedule('salon-b', any(), any()),
      );
    });
  });

  // Phase 416 QA — owner/admin edge cases the matrix above does not reach.
  group('salon readiness edge cases', () {
    Future<void> expectNoHintsGenericNote(WidgetTester tester) async {
      expect(find.byKey(_hint('schedule', _salon.keyId)), findsNothing);
      expect(find.byKey(_hint('services', _salon.keyId)), findsNothing);
      expect(find.byKey(_setup(_salon.keyId)), findsOneWidget);
    }

    testWidgets('owner: my-salons lookup FAILS → no hint, generic 414 note, '
        'no error state', (tester) async {
      hasSalonSchedule = false;
      hasSalonServices = false;
      mySalonsFail = true;
      await pump(tester, role: UserRole.salonOwner, link: _salon);

      await expectNoHintsGenericNote(tester);
      expect(find.byType(ErrorState), findsNothing);
      expect(salonCatalogFetches, 0, reason: 'primary unknown → no fetch');
    });

    testWidgets('owner with several salons and NO primary flag → no hints '
        'anywhere (the targets would act on an unknown salon)', (tester) async {
      hasSalonSchedule = false;
      hasSalonServices = false;
      mySalons = const <Salon>[
        Salon(id: 'salon-a', name: 'Lumière'),
        Salon(id: 'salon-b', name: 'Loft', isPrimary: false),
      ];
      await pump(tester, role: UserRole.salonOwner, link: _salon);

      await expectNoHintsGenericNote(tester);
      expect(salonCatalogFetches, 0);
    });

    testWidgets('owner whose ONLY salon is a different id than the link → '
        'no hints', (tester) async {
      hasSalonSchedule = false;
      hasSalonServices = false;
      mySalons = const <Salon>[Salon(id: 'salon-z', name: 'Other')];
      await pump(tester, role: UserRole.salonOwner, link: _salon);

      await expectNoHintsGenericNote(tester);
    });

    testWidgets('owner with ONE salon that has no primary flag → hints '
        '(the sole salon is the primary)', (tester) async {
      hasSalonSchedule = false;
      mySalons = const <Salon>[Salon(id: 'salon-a', name: 'Lumière')];
      await pump(tester, role: UserRole.salonOwner, link: _salon);

      expect(find.byKey(_hint('schedule', _salon.keyId)), findsOneWidget);
    });

    testWidgets('empty roster (no master at all) reads as NO schedule → '
        'schedule hint', (tester) async {
      when(
        () => roster.salonRosterEffectiveSchedule(any(), any(), any()),
      ).thenAnswer((_) async => <String, List<EffectiveDay>>{});
      await pump(tester, role: UserRole.salonOwner, link: _salon);

      expect(find.byKey(_hint('schedule', _salon.keyId)), findsOneWidget);
      expect(find.byKey(_hint('services', _salon.keyId)), findsNothing);
    });

    testWidgets('one master working among masters with none → NO schedule '
        'hint', (tester) async {
      when(
        () => roster.salonRosterEffectiveSchedule(any(), any(), any()),
      ).thenAnswer(
        (_) async => <String, List<EffectiveDay>>{
          'm-off': <EffectiveDay>[
            EffectiveDay(
              date: DateTime(2026, 6, 15),
              source: EffectiveSource.noSchedule,
              intervals: const <WorkInterval>[],
            ),
          ],
          'm-on': <EffectiveDay>[
            EffectiveDay(
              date: DateTime(2026, 6, 16),
              source: EffectiveSource.template,
              intervals: const <WorkInterval>[],
            ),
          ],
        },
      );
      await pump(tester, role: UserRole.salonOwner, link: _salon);

      expect(find.byKey(_hint('schedule', _salon.keyId)), findsNothing);
    });

    testWidgets('admin link without a salon id → no hints and no tappable '
        'setup link', (tester) async {
      hasSalonSchedule = false;
      hasSalonServices = false;
      const BookingLink noSalon = BookingLink(
        kind: BookingLinkKind.salon,
        slug: 'no-salon',
        url: 'https://beautica.app/book/s/no-salon',
        displayName: 'Lumière',
        bookable: false,
      );
      await pump(tester, role: UserRole.salonAdmin, link: noSalon);

      expect(find.byKey(_hint('schedule', noSalon.keyId)), findsNothing);
      expect(find.byKey(_hint('services', noSalon.keyId)), findsNothing);
      expect(find.byKey(_setup(noSalon.keyId)), findsNothing);
      expect(salonCatalogFetches, 0);
    });
  });
}
