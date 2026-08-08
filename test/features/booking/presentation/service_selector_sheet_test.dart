// Phase 14.1 — Widget tests for ServiceSelectorSheet (booking Step 1).
//
// Covers:
//   1. Loading / data / empty-catalogue states.
//   2. Category accordion expand/collapse.
//   3. Multi-select toggling drives the pinned summary shelf + "Далі" CTA.
//   4. "Далі" navigates to /booking/slots with a BookingSlotPickerArgs extra
//      carrying exactly the selected services.
//
// Strategy mirrors `public_master_profile_screen_test.dart`: override the
// [publicMasterProfileProvider] family directly (it already loads master +
// services in parallel — no separate repository mock needed) and
// [approvedCategoriesProvider] directly (it sources from the real Dio-backed
// categoryRequestApiProvider, NOT from serviceRepositoryProvider — the
// documented "approvedCategoriesProvider override footgun").

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/service_catalogue_accordion.dart'
    show CatalogueRow, CatalogueServiceTile;
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_button.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart'
    show maxServicesPerVisit;
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart'
    show wishlistRepositoryProvider;
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ---------------------------------------------------------------------------
// Auth-free favourite toggle — skips the production build()'s
// ref.watch(authProvider) so the heart renders without an auth graph. Mirrors
// `master_result_card_test.dart`'s private override exactly (per-file
// convention: each test file that pumps a favourite heart defines its own
// copy rather than sharing one across features).
// ---------------------------------------------------------------------------
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kMasterId = 'master-1';

const _kMaster = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

const _kManicure = MasterService(
  id: 'svc-mani',
  serviceDefId: 'def-mani',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'MANICURE',
);

const _kPedicure = MasterService(
  id: 'svc-pedi',
  serviceDefId: 'def-pedi',
  name: 'Педикюр з покриттям',
  durationMinutes: 120,
  priceType: ServicePriceType.range,
  priceMin: 200,
  priceMax: 600,
  priceDisplay: 'від 200 до 600 ₴',
  category: 'PEDICURE',
);

PublicMasterProfileData get _twoCategoryData =>
    (_kMaster, const <MasterService>[_kManicure, _kPedicure]);

/// [n] services all in one `NAILS` category — used to drive the visit-selection
/// cap (MO-3: at most [maxServicesPerVisit] services per visit).
List<MasterService> _manyServices(int n) => <MasterService>[
  for (int i = 0; i < n; i++)
    MasterService(
      id: 'svc-$i',
      serviceDefId: 'def-$i',
      // i18n-finder-ok: fixture service name, never asserted by value.
      name: 'Послуга $i',
      durationMinutes: 30,
      priceMin: 100,
      priceDisplay: '100 ₴',
      category: 'NAILS',
    ),
];

// A titled master for the identity-card test below: Change 2 flipped the top
// `MasterStrip` to `showRole:true, showRating:true`, so the strip must now show
// the professional title (not the bare label+name) AND the ★ rating readout.
const _kTitledMaster = Master(
  id: _kMasterId,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
  professionalTitle: 'Майстер манікюру',
);

PublicMasterProfileData get _titledTwoCategoryData =>
    (_kTitledMaster, const <MasterService>[_kManicure, _kPedicure]);

/// Fixture wish-list entry — only [masterServiceId] is ever asserted on by
/// the heart tests; the rest is filler satisfying [WishlistService]'s
/// required fields.
WishlistService _wishlistEntry(String masterServiceId) => WishlistService(
  masterServiceId: masterServiceId,
  masterId: _kMasterId,
  serviceName: 'fixture',
  masterName: 'fixture master',
  durationMinutes: 60,
  priceDisplay: '500 ₴',
);

List<Object> _overrides(
  FutureOr<PublicMasterProfileData> Function(Ref ref) create, {
  List<WishlistService> wishlist = const <WishlistService>[],
}) => <Object>[
  publicMasterProfileProvider(_kMasterId).overrideWith(create),
  // approvedCategoriesProvider footgun: sources from the real Dio-backed
  // categoryRequestApiProvider, independent of the service repository —
  // MUST be overridden directly or it fires a real request under `flutter test`.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  // Phase 240 — every catalogue row now renders a FavoriteHeartButton, which
  // watches favoriteToggleProvider (→ authProvider) and this screen watches
  // wishlistProvider (→ the real Dio-backed favoriteApiProvider, via
  // wishlistRepositoryProvider) to prime it. Both MUST be overridden or the
  // pre-existing tests in this file (which never touch favourites) would fire
  // a real auth/network call under `flutter test`.
  favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
  wishlistRepositoryProvider.overrideWithValue(
    FakeWishlistRepository(services: wishlist),
  ),
];

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.bookingNew,
  initialExtra: _kMasterId,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.bookingNew,
      builder: (context, state) =>
          ServiceSelectorSheet(masterId: (state.extra as String?) ?? ''),
    ),
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (context, state) {
        final BookingSlotPickerArgs args =
            state.extra! as BookingSlotPickerArgs;
        final String ids = args.services
            .map((MasterService s) => s.id)
            .join(',');
        return Scaffold(body: Text('slots-stub:${args.masterId}:$ids'));
      },
    ),
  ],
);

void main() {
  group('loading state', () {
    testWidgets('shows a skeleton while the profile loads', (tester) async {
      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => Completer<PublicMasterProfileData>().future,
        ),
      );

      expect(find.byKey(const Key('booking-summary-cta')), findsNothing);
    });
  });

  group('error state', () {
    // Regression coverage (mobile-build-verifier): `public_salon_profile_screen.dart`
    // pushes `RouteNames.bookingNew` with a SALON id, not a master id (salon
    // booking is out of scope for this phase — a pre-existing gap, not
    // something Phase 14.1 introduces). `ServiceSelectorSheet` always treats
    // its `masterId` as a master-row id, so that lookup 404s. This pins the
    // resulting UI never regresses to a crash/blank screen: the error state
    // renders with a working retry that actually re-invokes the provider.
    testWidgets(
      'renders the error state (with a working retry) when the master '
      'lookup fails — e.g. a salon id reaching ServiceSelectorSheet via a '
      'wrong-type /booking/new push from the salon profile CTA',
      (tester) async {
        const String wrongTypeId = 'salon-xyz';
        int callCount = 0;

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: wrongTypeId),
          overrides: <Object>[
            publicMasterProfileProvider(wrongTypeId).overrideWith((ref) {
              callCount++;
              return Future<PublicMasterProfileData>.error(
                const NotFoundFailure(),
                StackTrace.empty,
              );
            }),
            approvedCategoriesProvider.overrideWith(
              (ref) async => const <ServiceCategoryOption>[],
            ),
          ],
          // Disable Riverpod's retry so the AsyncError settles (no pending
          // backoff Timer left at test end) — mirrors
          // public_master_profile_screen_test.dart's error-state test.
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('service-selector-error-state')),
          findsOneWidget,
        );
        expect(callCount, 1);

        final Finder retryButton = find.byKey(
          const Key('error_state_retry_button'),
        );
        expect(retryButton, findsOneWidget);

        await tester.tap(retryButton);
        await tester.pumpAndSettle();

        // The retry must actually invalidate + re-invoke the provider (not
        // just re-render stale state) — the lookup fails again (same wrong
        // id), so the error state stays put, but the call count proves the
        // retry affordance is wired, not decorative.
        expect(callCount, 2);
        expect(
          find.byKey(const Key('service-selector-error-state')),
          findsOneWidget,
        );
      },
    );
  });

  group('empty catalogue', () {
    testWidgets(
      'shows the empty-state prompt when the master has no services',
      (tester) async {
        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _overrides((ref) => (_kMaster, const <MasterService>[])),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('booking_category_MANICURE')),
          findsNothing,
        );
      },
    );
  });

  group('catalogue — category accordions', () {
    testWidgets('categories start collapsed; tapping a header expands it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking_service_tile_svc-mani')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking_service_tile_svc-mani')),
        findsOneWidget,
      );
    });
  });

  group('selection + summary shelf', () {
    testWidgets('selecting a service enables «Далі» and updates the summary', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      // Nothing selected yet — the CTA (present, disabled) does nothing when
      // there is no router to navigate through; assert via the empty-state
      // prompt text absence check is covered by the navigation test below.
      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking_service_tile_svc-mani')));
      await tester.pumpAndSettle();

      // The itemized list is collapsed by default — expand the summary
      // shelf's toggle before asserting the selected service's name is
      // rendered there.
      await tester.tap(find.byKey(const Key('booking-summary-expand-toggle')));
      await tester.pumpAndSettle();

      // The selected service's name now appears in the pinned summary shelf
      // (in addition to the catalogue tile itself, hence scoping the finder).
      // i18n-finder-ok: _kManicure.name is fixture data, not UI copy.
      expect(
        find.descendant(
          of: find.byType(BookingSummaryBar),
          matching: find.text(_kManicure.name),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'removing a service via the summary shelf converges to the same '
      'deselected end-state as unchecking it in the catalogue',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _overrides((ref) => _twoCategoryData),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('booking_service_tile_svc-mani')),
        );
        await tester.pumpAndSettle();

        // The catalogue tile now shows the "selected" depth-check face.
        expect(
          find.descendant(
            of: find.byKey(const Key('booking_service_tile_svc-mani')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await tester.pumpAndSettle();

        final Finder removeButton = find.byKey(
          const Key('booking-summary-remove-svc-mani'),
        );
        expect(removeButton, findsOneWidget);

        await tester.tap(removeButton);
        await tester.pumpAndSettle();

        // The itemized entry disappears from the summary shelf...
        expect(
          find.descendant(
            of: find.byType(BookingSummaryBar),
            matching: find.text(_kManicure.name),
          ),
          findsNothing,
        );
        // ...the CTA disables again, exactly as unchecking would produce...
        final NeumorphicButton cta = tester.widget<NeumorphicButton>(
          find.byKey(const Key('booking-summary-cta')),
        );
        expect(cta.onPressed, isNull);
        // ...and the catalogue's own selection-depth control for the same
        // service reflects the deselection too — both removal paths
        // converge on identical end-state.
        expect(
          find.descendant(
            of: find.byKey(const Key('booking_service_tile_svc-mani')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
        );
      },
    );

    // mobile-qa gap: the test above only ever drives selection down to
    // EMPTY, so it cannot distinguish "remove just this one service" from a
    // regression that wipes the WHOLE selection set — both produce an empty
    // list either way. With both services selected, removing ONE via the
    // shelf must leave the OTHER selected, its catalogue tile still checked,
    // and the CTA still enabled.
    testWidgets(
      'removing one of two selected services via the shelf leaves the '
      'other selected and the CTA enabled',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _overrides((ref) => _twoCategoryData),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('booking_service_tile_svc-mani')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking_category_PEDICURE')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('booking_service_tile_svc-pedi')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('booking-summary-expand-toggle')),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('booking-summary-remove-svc-mani')),
        );
        await tester.pumpAndSettle();

        // The removed service's catalogue tile is deselected...
        expect(
          find.descendant(
            of: find.byKey(const Key('booking_service_tile_svc-mani')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsNothing,
          reason: 'removing svc-mani must deselect only svc-mani',
        );
        // ...but the OTHER selected service's catalogue tile survives —
        // this is the assertion that would catch a "clear whole selection"
        // regression, which the empty-down-to-zero test above cannot.
        expect(
          find.descendant(
            of: find.byKey(const Key('booking_service_tile_svc-pedi')),
            matching: find.byKey(const ValueKey<bool>(true)),
          ),
          findsOneWidget,
          reason:
              'removing svc-mani via the shelf must NOT deselect svc-pedi — '
              'a regression that clears the whole selection set instead of '
              'just the tapped id would slip past a down-to-zero-only test',
        );
        // ...and the itemized shelf still carries the surviving service.
        expect(
          find.descendant(
            of: find.byType(BookingSummaryBar),
            matching: find.text(_kPedicure.name),
          ),
          findsOneWidget,
        );
        // ...the CTA stays enabled (still 1 service selected).
        final NeumorphicButton cta = tester.widget<NeumorphicButton>(
          find.byKey(const Key('booking-summary-cta')),
        );
        expect(
          cta.onPressed,
          isNotNull,
          reason:
              'one service (svc-pedi) remains selected — CTA must stay '
              'enabled',
        );
      },
    );
  });

  group('identity card (top MasterStrip)', () {
    // Change 2: the Step-1 top card was a plain label+name `MasterStrip`; it is
    // now `MasterStrip(showRole:true, showRating:true)`. This proves BOTH flags
    // are live — the professional title sub-line AND the ★ rating readout —
    // neither of which the pre-change card rendered.
    testWidgets(
      'the top MasterStrip shows the professional title AND the ★ rating',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _overrides((ref) => _titledTwoCategoryData),
        );
        await tester.pumpAndSettle();

        final Finder masterStrip = find.byType(MasterStrip);
        expect(masterStrip, findsOneWidget);

        // showRole:true → the professional title renders as the sub-line
        // (previously the card showed NO sub-line at all).
        expect(
          find.descendant(
            of: masterStrip,
            // i18n-finder-ok: professionalTitle is fixture domain data, not UI copy.
            matching: find.text('Майстер манікюру'),
          ),
          findsOneWidget,
          reason:
              'Change 2 set showRole:true — the professional title must '
              'render on the Step-1 identity card.',
        );

        // showRating:true → the camel ★ + rating readout renders (previously
        // absent on the Step-1 card).
        expect(
          find.descendant(
            of: masterStrip,
            matching: find.byIcon(Icons.star_rounded),
          ),
          findsOneWidget,
          reason: 'Change 2 set showRating:true — the ★ glyph must render.',
        );
        expect(
          find.descendant(
            of: masterStrip,
            // `!` is deliberate: the fixture defines a non-null rating and
            // this assertion must stay strict.
            matching: find.text(_kTitledMaster.avgRating!.toStringAsFixed(1)),
          ),
          findsOneWidget,
          reason: 'showRating:true must render avgRating.toStringAsFixed(1).',
        );
      },
    );
  });

  group('navigation', () {
    testWidgets('«Далі» navigates to /booking/slots with the selected '
        'services', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking_service_tile_svc-mani')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(find.text('slots-stub:$_kMasterId:svc-mani'), findsOneWidget);
    });
  });

  group('autoAdvance (Phase 241 — wish-list rebook)', () {
    testWidgets(
      'initialServiceId + autoAdvance skips the manual «Далі» tap and pushes '
      'straight to /booking/slots once the catalogue resolves the match',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          initialLocation: RouteNames.bookingNew,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.bookingNew,
              builder: (context, state) => const ServiceSelectorSheet(
                masterId: _kMasterId,
                initialServiceId: 'svc-mani',
                autoAdvance: true,
              ),
            ),
            GoRoute(
              path: RouteNames.bookingSlots,
              builder: (context, state) {
                final BookingSlotPickerArgs args =
                    state.extra! as BookingSlotPickerArgs;
                final String ids = args.services
                    .map((MasterService s) => s.id)
                    .join(',');
                return Scaffold(body: Text('slots-stub:${args.masterId}:$ids'));
              },
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: _overrides((ref) => _twoCategoryData),
        );
        await tester.pumpAndSettle();

        // No manual category expand / tile tap / "Далі" tap anywhere above —
        // the push happens on its own once the catalogue data resolves.
        expect(find.text('slots-stub:$_kMasterId:svc-mani'), findsOneWidget);
      },
    );

    testWidgets(
      'a stale (no-longer-resolving) initialServiceId does not auto-advance — '
      'the catalogue just renders normally, nothing pre-selected',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          initialLocation: RouteNames.bookingNew,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.bookingNew,
              builder: (context, state) => const ServiceSelectorSheet(
                masterId: _kMasterId,
                initialServiceId: 'svc-deactivated',
                autoAdvance: true,
              ),
            ),
            GoRoute(
              path: RouteNames.bookingSlots,
              builder: (context, state) =>
                  const Scaffold(body: Text('slots-stub')),
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: _overrides((ref) => _twoCategoryData),
        );
        await tester.pumpAndSettle();

        expect(find.text('slots-stub'), findsNothing);
        expect(
          find.byKey(const Key('booking_category_MANICURE')),
          findsOneWidget,
        );
      },
    );
  });

  group('visit-selection cap (MO-3)', () {
    testWidgets(
      'caps the selection at maxServicesPerVisit (10) — the 11th add is '
      'refused with a friendly cap VelvetSnack, and «Далі» carries exactly 10 ids',
      (tester) async {
        tester.view.physicalSize = const Size(800, 8000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = _router();
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides((ref) => (_kMaster, _manyServices(11))),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('booking_category_NAILS')));
        await tester.pumpAndSettle();

        // Tap all 11 tiles — the 11th add must be refused (cap = 10).
        for (int i = 0; i < 11; i++) {
          await tester.tap(find.byKey(Key('booking_service_tile_svc-$i')));
          await tester.pump();
        }

        final l10n = AppLocalizations.of(
          tester.element(find.byType(ServiceSelectorSheet)),
        );
        expectVelvetSnack(
          l10n.bookingMaxServicesReached(maxServicesPerVisit),
          variant: VelvetSnackVariant.warning,
        );
        // Drains the dwell Timer AND removes the OverlayEntry — a still-
        // mounted snack is bottom-anchored and hit-test-intercepts the
        // «Далі» tap right below (the pinned `BookingSummaryBar` sits at the
        // very bottom of this pushed, nav-bar-less screen).
        await pumpPastVelvetSnack(tester);

        // «Далі» → the slots stub carries exactly 10 ordered ids (the 11th was
        // never added, so a duplicate/over-cap payload can never be sent).
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        final Text stub = tester.widget<Text>(
          find.textContaining('slots-stub:'),
        );
        final String ids = stub.data!.split(':').last;
        expect(
          ids.split(',').where((String s) => s.isNotEmpty).length,
          maxServicesPerVisit,
          reason: 'the visit must carry at most maxServicesPerVisit services',
        );
      },
    );
  });

  // ===========================================================================
  // Phase 240 — the favourite heart on the master-flow catalogue row.
  // ===========================================================================
  group('favourite heart (Phase 240)', () {
    Finder heartIcon(String masterServiceId, IconData icon) => find.descendant(
      of: find.byKey(Key('booking_service_heart_$masterServiceId')),
      matching: find.byIcon(icon),
    );

    testWidgets('should_showFilledHeart_when_serviceAlreadyInWishlist', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides(
          (ref) => _twoCategoryData,
          // Settled BEFORE the tile is ever built (pumpAndSettle below), so
          // the heart primes correctly on its first frame — see the "PAGE
          // 0 ONLY" / load-order comment on `_CatalogueBodyState.build()`.
          wishlist: <WishlistService>[_wishlistEntry(_kManicure.id)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        heartIcon(_kManicure.id, Icons.favorite_rounded),
        findsOneWidget,
        reason:
            'svc-mani is in the wish-list fixture — its heart must prime '
            'filled on first build, not outline-then-flip',
      );
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsNothing,
      );
    });

    testWidgets('should_showOutlineHeart_when_serviceNotFavourited', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides((ref) => _twoCategoryData),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsOneWidget,
      );
      expect(heartIcon(_kManicure.id, Icons.favorite_rounded), findsNothing);
    });

    testWidgets('should_notRebuildSiblingHearts_when_oneServiceToggled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: <Object>[
          ..._overrides(
            (ref) => _twoCategoryData,
            wishlist: <WishlistService>[
              _wishlistEntry(_kManicure.id),
              _wishlistEntry(_kPedicure.id),
            ],
          ),
          favoriteRepositoryProvider.overrideWithValue(
            FakeFavoriteRepository(),
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking_category_PEDICURE')));
      await tester.pumpAndSettle();

      expect(heartIcon(_kManicure.id, Icons.favorite_rounded), findsOneWidget);
      expect(heartIcon(_kPedicure.id, Icons.favorite_rounded), findsOneWidget);

      // mobile-qa cycle-2 finding: the previous version of this test compared
      // `identical()` on the immutable FavoriteHeartButton WIDGET object —
      // but nothing ABOVE the heart in this tree watches favoriteToggleProvider,
      // so no ancestor ever reconstructs that widget regardless of whether
      // `.select()` is present (QA proved it: stripping `.select()` for a bare
      // `ref.watch` still left the identity comparison passing). What
      // `.select()` actually controls is whether the heart's OWN `Element` is
      // marked dirty and rebuilt — so this counts ELEMENT rebuilds via
      // Flutter's `debugOnRebuildDirtyWidget` hook instead of comparing widget
      // identity, which genuinely fails when the selector is removed.
      final Element pediElement = tester.element(
        find.byKey(Key('booking_service_heart_${_kPedicure.id}')),
      );
      int pediRebuildCount = 0;
      final RebuildDirtyWidgetCallback? previousRebuildHook =
          debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (Element e, bool builtOnce) {
        previousRebuildHook?.call(e, builtOnce);
        if (identical(e, pediElement)) pediRebuildCount++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousRebuildHook);

      // Audit cycle 3 — `favorite_toggle_notifier.dart`'s `toggle` now
      // invalidates `wishlistProvider` on a successful SERVICE toggle in
      // EITHER direction (add or remove), and `_CatalogueBodyState`
      // unconditionally `ref.watch`es `wishlistProvider`. A REAL tap on any
      // heart on this screen therefore now legitimately rebuilds the WHOLE
      // catalogue body — including svc-pedi's heart — via that unrelated
      // channel. That is the intended fix, not a regression, so it can no
      // longer be dodged by picking "remove" the way the previous version of
      // this test did (both directions invalidate now).
      //
      // So the `.select()` scoping claim is isolated a different way: drive
      // the SAME notifier method the real tap uses, but with
      // `refreshWishlist: false` — the exact opt-out
      // `WishlistNotifier.removeService` itself relies on — so THIS
      // measurement changes ONLY `favoriteToggleProvider`'s map, with no
      // wishlist side-channel to confound the count. This still exercises the
      // real widget's real `.select()` expression (the heart still reads the
      // same provider via the same watch), just without going through the
      // gesture detector — the gesture-to-toggle wiring is already covered by
      // `should_showFilledHeart_when_serviceAlreadyInWishlist` and
      // `should_revertHeart_when_addFails`.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ServiceSelectorSheet)),
      );
      final FavoriteTarget manicureTarget = FavoriteTarget(
        type: FavoriteTargetType.service,
        id: _kManicure.id,
      );
      await container
          .read(favoriteToggleProvider.notifier)
          .toggle(manicureTarget, refreshWishlist: false);
      await tester.pump();
      await tester.pump();

      // Fixture guard: the toggled heart itself DID flip (un-favourited) —
      // otherwise the sibling assertion below would pass for the wrong reason
      // (nothing happened at all).
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsOneWidget,
        reason: 'the toggled heart must have actually flipped to outline',
      );

      expect(
        pediRebuildCount,
        0,
        reason:
            'toggling svc-mani\'s favourite flag (with the wishlist side-'
            'channel deliberately suppressed) rebuilt svc-pedi\'s Element — '
            'favoriteToggleProvider.select(...) must scope a rebuild to '
            'ONLY the toggled target, per FavoriteHeartButton\'s own '
            'documented guarantee',
      );
    });

    testWidgets('should_revertHeart_when_addFails', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // A completer-controlled fake, NOT a synchronous `thenThrow`: the repo
      // call must genuinely stay in flight so the test can observe the
      // optimistic FILLED frame BEFORE it resolves. A synchronous throw
      // settles the whole flip-then-revert dance within one microtask, so a
      // test built against it would never see — and therefore never actually
      // verify — the mid-flight state. That is exactly the gap mobile-qa
      // proved: a non-optimistic `toggle` (never flips before the repo call
      // resolves) still passed the old, end-state-only version of this test.
      final Completer<void> addGate = Completer<void>();
      final FakeFavoriteRepository repo = FakeFavoriteRepository()
        ..addDelay = addGate.future
        ..addResult = const NetworkFailure();

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: <Object>[
          ..._overrides((ref) => _twoCategoryData),
          favoriteRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(Key('booking_service_heart_${_kManicure.id}')),
      );
      await tester.pump();
      await tester.pump();

      // Mid-flight: `addGate` is still unresolved, so the repo call cannot
      // have settled yet — the heart must already read FILLED purely from the
      // optimistic flip, never having waited on the network.
      expect(
        heartIcon(_kManicure.id, Icons.favorite_rounded),
        findsOneWidget,
        reason:
            'the heart must fill optimistically before the add call settles',
      );
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsNothing,
      );

      // Release the gate — the add now resolves and throws the configured
      // Failure, driving the notifier's revert branch.
      addGate.complete();
      await pumpVelvetSnackIn(tester);

      // Reverted back to outline after the failed add.
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsOneWidget,
      );
      expect(heartIcon(_kManicure.id, Icons.favorite_rounded), findsNothing);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ServiceSelectorSheet)),
      );
      expectVelvetSnack(l10n.errNetwork, variant: VelvetSnackVariant.error);

      // Drains the dwell Timer + removes the OverlayEntry (leak guard).
      await pumpPastVelvetSnack(tester);
    });

    // =========================================================================
    // Audit cycle 3 — un-hearting FROM THIS SHEET must refresh the wish list.
    //
    // Phase 240 made a successful SERVICE *add* invalidate `wishlistProvider`
    // but left *remove* untouched, reasoning that the only remove call site was
    // `WishlistNotifier.removeService` (which manages its own state and must
    // NOT be refetched out from under itself). That reasoning missed that THIS
    // sheet's heart is a SECOND, independent remove call site — un-hearting a
    // service here previously left the wish list showing a service the client
    // had just removed, for up to the 5-minute TTL. See
    // `favorite_toggle_notifier.dart`'s "Audit cycle 3 fix".
    // =========================================================================
    testWidgets('should_refreshWishlist_when_unheartingFromBookingSheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // A named instance (not the anonymous one `_overrides` builds) so this
      // test can inspect `getCallCount` directly.
      final FakeWishlistRepository wishlistRepo = FakeWishlistRepository(
        services: <WishlistService>[_wishlistEntry(_kManicure.id)],
      );

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: <Object>[
          publicMasterProfileProvider(
            _kMasterId,
          ).overrideWith((ref) => _twoCategoryData),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          favoriteToggleProvider.overrideWith(
            _AuthFreeFavoriteToggleNotifier.new,
          ),
          wishlistRepositoryProvider.overrideWithValue(wishlistRepo),
          favoriteRepositoryProvider.overrideWithValue(
            FakeFavoriteRepository(),
          ),
        ],
      );
      await tester.pumpAndSettle();

      // One fetch to prime every row's heart on first build.
      expect(wishlistRepo.getCallCount, 1);

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      // svc-mani starts favourited (in the wish-list fixture) — tapping its
      // heart un-favourites it.
      await tester.tap(
        find.byKey(Key('booking_service_heart_${_kManicure.id}')),
      );
      await tester.pumpAndSettle();

      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsOneWidget,
        reason: 'the tapped heart must have actually un-favourited',
      );
      expect(
        wishlistRepo.getCallCount,
        2,
        reason:
            'un-hearting a service from the booking sheet must invalidate '
            'wishlistProvider so the Beauty Passport / wish-list screens '
            'stop showing a service the client just removed',
      );
    });
  });

  // ===========================================================================
  // The trap this phase exists to guard against: `CatalogueServiceTile` MUST
  // default `showFavoriteHeart` to false, so a call site that forgets to opt
  // in (like the salon flow) structurally cannot render a heart, rather than
  // relying on every call site remembering to pass `showFavoriteHeart: false`.
  // ===========================================================================
  group('CatalogueServiceTile default (Phase 240 structural guard)', () {
    testWidgets(
      'showFavoriteHeart defaults to false — a bare tile renders no heart',
      (tester) async {
        await tester.pumpApp(
          CatalogueServiceTile(
            row: const CatalogueRow(
              id: 'svc-x',
              name: 'X',
              categoryLabel: 'CAT',
              durationLabel: '30 хв',
              priceLabel: '100 ₴',
            ),
            selected: false,
            onToggle: () {},
          ),
        );

        expect(find.byType(FavoriteHeartButton), findsNothing);
      },
    );
  });
}
