// mobile-qa (2026-09-01) — widget tests for [SalonMasterProfileScreen].
//
// This screen shipped with ZERO direct tests (build-verifier MEDIUM, raised
// twice; ~649 lines across this file + `salon_master_own_profile_notifier
// .dart` with only incidental routing coverage). This file closes that gap:
//
//   • all three [AsyncValue] states — loading skeleton, error + working
//     retry, loaded body;
//   • the salon-name / salon-address rows are OMITTED ENTIRELY (a widget-list
//     gate, not an empty string) when `salon == null`, and rendered when
//     present — mutation-proved below, not merely asserted;
//   • bio / service-categories / contact sections each independently omitted
//     when empty, mirroring the sibling `master_profile_screen_test.dart`/
//     `owner_own_profile_screen_test.dart` convention;
//   • the trailing tune button pushes the SALON_MASTER settings route.
//
// `approvedCategoriesProvider` is overridden DIRECTLY — it bypasses
// `serviceRepositoryProvider` entirely (the established footgun documented in
// `owner_own_profile_notifier_test.dart` and `salon_staff_profile_screen
// _test.dart`).
//
// Finders use widget Keys, never localized/Cyrillic strings (M2).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const Master _master = Master(
  id: 'm-9',
  firstName: 'Ірина',
  lastName: 'Бондар',
  bio: 'Працюю з клієнтами вже 5 років.',
  avgRating: 4.6,
  reviewCount: 8,
  type: MasterType.salonMaster,
  salonId: 'salon-1',
  phoneNumber: '+380 67 111 22 33',
);

const Master _masterBare = Master(
  id: 'm-10',
  firstName: 'Ірина',
  lastName: 'Бондар',
  reviewCount: 0,
  type: MasterType.salonMaster,
);

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 's-1',
    serviceDefId: 'd-1',
    name: 'Стрижка',
    durationMinutes: 45,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'HAIR',
  ),
];

const Salon _salon = Salon(
  id: 'salon-1',
  name: 'Beautica Studio',
  city: 'Київ',
  street: 'Хрещатик',
  buildingNo: '1',
);

/// The three mutually-exclusive keys [MasterAddressBlock] can render under
/// `keyPrefix: 'salon-master-profile-salon'`, depending on measured layout
/// width (split two-row vs. collapsed one-row) — see that widget's own doc.
/// Exactly one of these renders when a salon carries a visible address; none
/// render when it does not.
final List<Finder> _salonAddressFinders = <Finder>[
  find.byKey(const Key('salon-master-profile-salon-locality-text')),
  find.byKey(const Key('salon-master-profile-salon-address-text')),
  find.byKey(const Key('salon-master-profile-salon-address-combined-text')),
];

List<Object> _overrides(SalonMasterOwnProfileData data) => <Object>[
  salonMasterOwnProfileProvider.overrideWith((Ref ref) async => data),
  approvedCategoriesProvider.overrideWith(
    (Ref ref) async => const <ServiceCategoryOption>[],
  ),
];

void main() {
  group('AsyncValue states', () {
    testWidgets('loading — skeleton renders; neither body nor error does', (
      tester,
    ) async {
      final Completer<SalonMasterOwnProfileData> pending =
          Completer<SalonMasterOwnProfileData>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete((_master, _services, _salon));
        }
      });

      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          salonMasterOwnProfileProvider.overrideWith(
            (Ref ref) => pending.future,
          ),
          approvedCategoriesProvider.overrideWith(
            (Ref ref) async => const <ServiceCategoryOption>[],
          ),
        ],
      );
      // `pump`, never `pumpAndSettle` — the skeleton runs a repeating shimmer
      // that never settles.
      await tester.pump();

      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byKey(const Key('salon-master-profile-name')), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('error — ErrorState with a working retry renders', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          // ASYNC throw — a synchronous throw would bypass the AsyncValue
          // error path entirely (short-circuits Riverpod's own machinery).
          salonMasterOwnProfileProvider.overrideWith(
            (Ref ref) async => throw const ServerFailure(),
          ),
          approvedCategoriesProvider.overrideWith(
            (Ref ref) async => const <ServiceCategoryOption>[],
          ),
        ],
        // Disabled so the assertion lands on the TERMINAL error, not on
        // `AsyncLoading(retrying: true)` (which still satisfies `hasError`).
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
      expect(find.byKey(const Key('salon-master-profile-name')), findsNothing);
    });

    testWidgets('error — tapping retry re-invalidates the loader and the '
        'recovered body renders', (tester) async {
      int attempt = 0;
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          salonMasterOwnProfileProvider.overrideWith((Ref ref) async {
            attempt++;
            if (attempt == 1) throw const ServerFailure();
            return (_master, _services, _salon);
          }),
          approvedCategoriesProvider.overrideWith(
            (Ref ref) async => const <ServiceCategoryOption>[],
          ),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget, reason: 'sanity');
      expect(attempt, 1);

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(find.byType(ErrorState), findsNothing);
      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
    });
  });

  group('loaded body — salon affiliation rows', () {
    testWidgets('salon present — name and address rows render', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-role-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-salon-name')),
        findsOneWidget,
        reason: 'a present salon must render the affiliation line',
      );
      final int addressWidgetsFound = _salonAddressFinders
          .map((Finder f) => f.evaluate().length)
          .fold<int>(0, (int a, int b) => a + b);
      expect(
        addressWidgetsFound,
        1,
        reason:
            'exactly one of the three MasterAddressBlock renderings must be '
            'present for a salon with a visible address',
      );
    });

    testWidgets('salon NULL — the salon-name and salon-address rows are '
        'OMITTED ENTIRELY, never rendered empty', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, null)),
      );
      await tester.pumpAndSettle();

      // Sanity: the rest of the identity card still renders.
      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-role-chip')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('salon-master-profile-salon-name')),
        findsNothing,
        reason:
            'salon == null must OMIT the affiliation line — not render it '
            'with an empty/placeholder name',
      );
      for (final Finder f in _salonAddressFinders) {
        expect(
          f,
          findsNothing,
          reason:
              'salon == null must omit the MasterAddressBlock entirely — '
              'none of its three possible renderings may appear',
        );
      }
    });
  });

  group('loaded body — optional sections', () {
    testWidgets('bio present renders the bio section', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-master-profile-bio')), findsOneWidget);
    });

    testWidgets('no bio omits the bio section', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-master-profile-bio')), findsNothing);
    });

    testWidgets('services present renders «Мої категорії»', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-service-categories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-category-HAIR')),
        findsOneWidget,
      );
    });

    testWidgets('empty services omits «Мої категорії»', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-service-categories')),
        findsNothing,
      );
    });

    testWidgets('phone present renders the contact tile', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-contact-phone')),
        findsOneWidget,
      );
    });

    testWidgets('no phone omits the contact tile', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-contact-phone')),
        findsNothing,
      );
    });

    testWidgets('services stat value reflects the loaded services count', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('salon-master-profile-services-value')),
            )
            .data,
        '1',
      );
    });
  });

  group('trailing tune — pushes settings', () {
    testWidgets('tapping the tune icon pushes RouteNames.salonMasterSettings', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: RouteNames.salonMasterProfile,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.salonMasterProfile,
            builder: (_, _) => const SalonMasterProfileScreen(),
          ),
          GoRoute(
            path: RouteNames.salonMasterSettings,
            builder: (_, _) =>
                const Scaffold(body: SizedBox(key: Key('stub-staff-settings'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-menu-salon-master')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-staff-settings')), findsOneWidget);
    });
  });
}
