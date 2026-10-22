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
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
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

/// Weekly templates read from a mutable test-owned flag.
class _FakeWeekly extends WeeklyScheduleNotifier {
  _FakeWeekly(this._read);
  final Future<List<WeeklySchedule>> Function() _read;

  @override
  Future<List<WeeklySchedule>> build(ScheduleScope scope) => _read();
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

final WeeklySchedule _template = WeeklySchedule(
  validFrom: DateTime(2026, 1, 1),
  validTo: null,
  days: const <TemplateDay>[],
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
  late bool hasServices;
  late bool hasSalonSchedule;
  late bool hasSalonServices;
  Completer<void>? gate;
  bool failReads = false;
  bool servicesInactive = false;
  Completer<void>? servicesGate;
  DateTime? fixedToday;
  int masterCatalogFetches = 0;
  int salonCatalogFetches = 0;
  int weeklyFetches = 0;
  List<Salon> mySalons = const <Salon>[
    Salon(id: 'salon-a', name: 'Lumière', isPrimary: true),
  ];

  setUp(() {
    links = _MockLinksRepo();
    roster = _MockRosterRepo();
    pushed = <String>[];
    hasSchedule = true;
    hasServices = true;
    hasSalonSchedule = true;
    hasSalonServices = true;
    gate = null;
    failReads = false;
    servicesInactive = false;
    servicesGate = null;
    fixedToday = null;
    masterCatalogFetches = 0;
    salonCatalogFetches = 0;
    weeklyFetches = 0;
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
        ownScheduleScopeProvider.overrideWithValue(
          const ScheduleScope.own(masterId: 'm1'),
        ),
        weeklyScheduleProvider.overrideWith2(
          (_) => _FakeWeekly(() async {
            weeklyFetches++;
            await gate?.future;
            if (failReads) throw const NetworkFailure();
            return hasSchedule ? <WeeklySchedule>[_template] : const [];
          }),
        ),
        mySalonsProvider.overrideWith(() => _FakeMySalons(() => mySalons)),
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
          find.byKey(_hint('schedule', _master.slug)),
          sched ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(_hint('services', _master.slug)),
          serv ? findsNothing : findsOneWidget,
        );
        final AppLocalizations l10n = l10nOf(tester);
        if (sched && serv) {
          // Nothing missing: only the pre-existing generic note remains.
          expect(find.byKey(_setup(_master.slug)), findsOneWidget);
        } else {
          // Specific hints REPLACE the generic note.
          expect(find.byKey(_setup(_master.slug)), findsNothing);
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
      expect(find.byKey(_hint('services', _master.slug)), findsOneWidget);
    });

    testWidgets('a bookable link never shows hints', (tester) async {
      hasSchedule = false;
      hasServices = false;
      await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master.copyWith(bookable: true),
      );
      expect(find.byKey(_hint('schedule', _master.slug)), findsNothing);
      expect(find.byKey(_hint('services', _master.slug)), findsNothing);
      expect(find.byKey(_setup(_master.slug)), findsNothing);
    });

    testWidgets('failed readiness check → no hint, no error, generic note '
        'stays', (tester) async {
      failReads = true;
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('schedule', _master.slug)), findsNothing);
      expect(find.byKey(_hint('services', _master.slug)), findsNothing);
      expect(find.byKey(_setup(_master.slug)), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('error')), findsNothing);
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
          weeklyScheduleProvider.overrideWith2(
            (_) => _FakeWeekly(() async {
              await gate!.future;
              return const <WeeklySchedule>[];
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
      expect(find.byKey(_hint('schedule', _master.slug)), findsNothing);
      gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.slug)), findsOneWidget);
    });

    testWidgets('tap «Налаштувати розклад» pushes /schedule; back returns '
        'and a set-up schedule clears the hint', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.slug)));
      await tester.tap(find.byKey(_hint('schedule', _master.slug)));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.masterSchedule);

      hasSchedule = true; // the user set it up over there
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookingLinkScreen), findsOneWidget);
      expect(find.byKey(_hint('schedule', _master.slug)), findsNothing);
    });

    testWidgets('tap «Додати послугу» pushes /services', (tester) async {
      hasServices = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      await tester.ensureVisible(find.byKey(_hint('services', _master.slug)));
      await tester.tap(find.byKey(_hint('services', _master.slug)));
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
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.slug)));
      await tester.tap(find.byKey(_hint('schedule', _master.slug)));
      await tester.pumpAndSettle();

      hasSchedule = true;
      gate = Completer<void>(); // hold the refetch open
      router.pop();
      // Let the pop transition finish so the post-return invalidate has run.
      for (int i = 0; i < 40 && weeklyFetches < 2; i++) {
        // fixed-wait-ok: stepping the pop transition frame by frame until the post-return refetch starts (bounded, condition-driven)
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(weeklyFetches, 2, reason: 'refetch is genuinely in flight');
      // Refetch in flight: previous hint stays, generic note does NOT appear.
      expect(find.byKey(_hint('schedule', _master.slug)), findsOneWidget);
      expect(find.byKey(_setup(_master.slug)), findsNothing);

      gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.slug)), findsNothing);
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
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.slug)));
      await tester.tap(find.byKey(_hint('schedule', _master.slug)));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.slug)), findsOneWidget);
      verifyNever(() => links.getMine());

      // Round trip 2: the schedule was set up.
      await tester.tap(find.byKey(_hint('schedule', _master.slug)));
      await tester.pumpAndSettle();
      hasSchedule = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _master.slug)), findsNothing);
      verify(() => links.getMine()).called(1);
    });

    testWidgets('account switch while a refresh is in flight never shows the '
        "previous account's hint", (tester) async {
      hasServices = false;
      await pump(tester, role: UserRole.independentMaster, link: _master);
      expect(find.byKey(_hint('services', _master.slug)), findsOneWidget);

      servicesGate = Completer<void>();
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingLinkScreen)),
      );
      (container.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(_hint('services', _master.slug)),
        findsNothing,
        reason: "the catalogue is re-fetching for u2; u1's answer is not shown",
      );

      servicesGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('services', _master.slug)), findsOneWidget);
    });

    testWidgets('schedule hint invalidates ONLY the schedule member (+links): '
        'the services catalogue is not refetched', (tester) async {
      hasSchedule = false;
      final GoRouter router = await pump(
        tester,
        role: UserRole.independentMaster,
        link: _master,
      );
      final int weeklyBefore = weeklyFetches;
      final int catalogBefore = masterCatalogFetches;
      await tester.ensureVisible(find.byKey(_hint('schedule', _master.slug)));
      await tester.tap(find.byKey(_hint('schedule', _master.slug)));
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(weeklyFetches, weeklyBefore + 1);
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
      final int weeklyBefore = weeklyFetches;
      final int catalogBefore = masterCatalogFetches;
      await tester.ensureVisible(find.byKey(_hint('services', _master.slug)));
      await tester.tap(find.byKey(_hint('services', _master.slug)));
      await tester.pumpAndSettle();
      hasServices = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(masterCatalogFetches, catalogBefore + 1);
      expect(weeklyFetches, weeklyBefore);
      expect(find.byKey(_hint('services', _master.slug)), findsNothing);
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
      expect(find.byKey(_hint('schedule', _salon.slug)), findsNothing);
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
      expect(find.byKey(_hint('schedule', _salon.slug)), findsOneWidget);
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
          find.byKey(_hint('schedule', _salon.slug)),
          sched ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(_hint('services', _salon.slug)),
          serv ? findsNothing : findsOneWidget,
        );
        if (sched && serv) {
          expect(find.byKey(_setup(_salon.slug)), findsOneWidget);
        } else {
          expect(find.byKey(_setup(_salon.slug)), findsNothing);
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
      await tester.ensureVisible(find.byKey(_hint('schedule', _salon.slug)));
      await tester.tap(find.byKey(_hint('schedule', _salon.slug)));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, RouteNames.ownerMasterSchedule);

      hasSalonSchedule = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(_hint('schedule', _salon.slug)), findsNothing);
      expect(find.byKey(_hint('services', _salon.slug)), findsOneWidget);

      await tester.ensureVisible(find.byKey(_hint('services', _salon.slug)));
      await tester.tap(find.byKey(_hint('services', _salon.slug)));
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
      await tester.ensureVisible(find.byKey(_hint('services', _salon.slug)));
      await tester.tap(find.byKey(_hint('services', _salon.slug)));
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        RouteNames.salonShell('salon-a', openTeam: true),
      );
    });

    testWidgets('failed salon readiness → no hint', (tester) async {
      failReads = true;
      await pump(tester, role: UserRole.salonOwner, link: _salon);
      expect(find.byKey(_hint('schedule', _salon.slug)), findsNothing);
      expect(find.byKey(_hint('services', _salon.slug)), findsNothing);
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
      await tester.ensureVisible(find.byKey(_hint('services', _salon.slug)));
      await tester.tap(find.byKey(_hint('services', _salon.slug)));
      await tester.pumpAndSettle();
      hasSalonServices = true;
      router.pop();
      await tester.pumpAndSettle();
      expect(salonCatalogFetches, before + 1);
      expect(find.byKey(_hint('services', _salon.slug)), findsNothing);
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

      expect(find.byKey(_hint('schedule', _salon.slug)), findsOneWidget);
      expect(find.byKey(_hint('services', _salon.slug)), findsOneWidget);
      expect(find.byKey(_hint('schedule', other.slug)), findsNothing);
      expect(find.byKey(_hint('services', other.slug)), findsNothing);
      expect(find.byKey(_setup(other.slug)), findsOneWidget);
      expect(salonCatalogFetches, 1, reason: 'only the primary salon');
      verify(
        () => roster.salonRosterEffectiveSchedule('salon-a', any(), any()),
      ).called(1);
      verifyNever(
        () => roster.salonRosterEffectiveSchedule('salon-b', any(), any()),
      );
    });
  });
}
