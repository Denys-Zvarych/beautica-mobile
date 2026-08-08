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
    show wishlistProvider, wishlistRepositoryProvider;
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
/// cap (MO-3: at most [maxServicesPerVisit] services per visit) and, with
/// [isFavorite] set, the >20-favourites correctness fix (Phase 243) that the
/// old wish-list-page-0 prime could never have satisfied.
List<MasterService> _manyServices(int n, {bool isFavorite = false}) =>
    <MasterService>[
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
          isFavorite: isFavorite,
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
/// `should_refreshWishlist_when_unheartingFromBookingSheet`, the one
/// remaining test that talks to `wishlistProvider` directly (Phase 243
/// dropped the sheet's own prime from it — see the "favourite heart" group
/// below). The rest is filler satisfying [WishlistService]'s required fields.
WishlistService _wishlistEntry(String masterServiceId) => WishlistService(
  masterServiceId: masterServiceId,
  masterId: _kMasterId,
  serviceName: 'fixture',
  masterName: 'fixture master',
  durationMinutes: 60,
  priceDisplay: '500 ₴',
);

List<Object> _overrides(
  FutureOr<PublicMasterProfileData> Function(Ref ref) create,
) => <Object>[
  publicMasterProfileProvider(_kMasterId).overrideWith(create),
  // approvedCategoriesProvider footgun: sources from the real Dio-backed
  // categoryRequestApiProvider, independent of the service repository —
  // MUST be overridden directly or it fires a real request under `flutter test`.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  // Every catalogue row now renders a FavoriteHeartButton, which watches
  // favoriteToggleProvider (→ authProvider) — MUST be overridden or the
  // pre-existing tests in this file (which never touch favourites) would fire
  // a real auth call under `flutter test`.
  favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
  // Phase 243 — the sheet itself no longer reads `wishlistProvider` (hearts
  // now prime from `MasterService.isFavorite` on the fetched payload; see the
  // "favourite heart" group below). This override stays as defense-in-depth:
  // `favoriteToggleProvider.toggle()` still invalidates `wishlistProvider` on
  // a successful add/remove (unrelated to priming — it keeps the Beauty
  // Passport / wish-list screens fresh), and a bare `FakeWishlistRepository`
  // here means that invalidation can never reach the real Dio-backed
  // repository if some future change makes another widget in this tree watch
  // it.
  wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
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
  // Phase 240 introduced the favourite heart on the master-flow catalogue row,
  // primed from a `GET /favorites/services` round trip fired on every mount.
  // Phase 243 replaced that source with `MasterService.isFavorite`, already
  // riding on the payload this sheet fetches — no second request, no 20-row
  // wish-list-page-0 cap. The heart widget itself (`FavoriteHeartButton`) is
  // untouched; only where its `initialIsFavorite` seed comes from changed.
  // ===========================================================================
  group('favourite heart (Phase 243)', () {
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
        // Nothing favourite-related overridden beyond `_overrides`'s own
        // defaults (an empty wish-list fake, never read by this sheet
        // anymore) — the heart's seed comes entirely from the fetched
        // service's own `isFavorite` flag now.
        overrides: _overrides(
          (ref) => (
            _kMaster,
            <MasterService>[_kManicure.copyWith(isFavorite: true), _kPedicure],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        heartIcon(_kManicure.id, Icons.favorite_rounded),
        findsOneWidget,
        reason:
            'svc-mani is fetched with isFavorite:true — its heart must prime '
            'filled on first build, not outline-then-flip',
      );
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsNothing,
      );
    });

    testWidgets('should_notFetchWishlist_when_sheetMounts', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Throws if ever called — the headline claim of this phase. Without
      // this test, the round trip could silently come back in a later
      // refactor and this would be the only thing to catch it.
      final FakeWishlistRepository throwingRepo = FakeWishlistRepository(
        failure: const NetworkFailure(),
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
          wishlistRepositoryProvider.overrideWithValue(throwingRepo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        throwingRepo.getCallCount,
        0,
        reason:
            'ServiceSelectorSheet must never read wishlistProvider — hearts '
            'prime from MasterService.isFavorite instead',
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

    testWidgets('should_showFilledHeartsBeyondTwentyFavourites', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 20000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 25 services, all favourited — more than the old wish-list prime's
      // page-0 cap of 20 (`wishlist_repository.dart`) could ever have
      // satisfied. The server-side isFavorite flag is exact and uncapped, so
      // every single one must render filled.
      const int total = 25;
      final List<MasterService> services = _manyServices(
        total,
        isFavorite: true,
      );

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: _overrides((ref) => (_kMaster, services)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_NAILS')));
      await tester.pumpAndSettle();

      for (int i = 0; i < total; i++) {
        expect(
          heartIcon('svc-$i', Icons.favorite_rounded),
          findsOneWidget,
          reason:
              'svc-$i is favourited beyond the old 20-row wish-list cap — '
              'its heart must still render filled',
        );
      }
    });

    testWidgets('should_keepUserToggle_when_servicesListRebuilds', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Mutated then re-read via `container.invalidate` below, to force a
      // second, DISTINCT `widget.services` list — same isFavorite:false seed
      // as the first — through `publicMasterProfileProvider` without any
      // change to what the fixture itself claims about favourites.
      PublicMasterProfileData current = _twoCategoryData;

      await tester.pumpApp(
        const ServiceSelectorSheet(masterId: _kMasterId),
        overrides: <Object>[
          ..._overrides((ref) => current),
          favoriteRepositoryProvider.overrideWithValue(
            FakeFavoriteRepository(),
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      // Starts outline (isFavorite:false on the fixture) — tap fills it via
      // favoriteToggleProvider, NOT via the seed.
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(Key('booking_service_heart_${_kManicure.id}')),
      );
      await tester.pumpAndSettle();
      expect(heartIcon(_kManicure.id, Icons.favorite_rounded), findsOneWidget);

      // Rebuild with a NEW `widget.services` list — same isFavorite:false
      // seed as before, standing in for a resolved-again fetch (e.g. pull-
      // to-refresh upstream). `FavoriteToggleNotifier.primeIfAbsent` must
      // never overwrite the user's own toggle with the stale seed.
      current = (
        _kMaster,
        <MasterService>[
          _kManicure.copyWith(name: 'Манікюр з покриттям (оновлено)'),
          _kPedicure,
        ],
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ServiceSelectorSheet)),
      );
      container.invalidate(publicMasterProfileProvider(_kMasterId));
      await tester.pumpAndSettle();

      expect(
        heartIcon(_kManicure.id, Icons.favorite_rounded),
        findsOneWidget,
        reason:
            'the user\'s own toggle must survive a services-list rebuild — '
            'primeIfAbsent must not stomp an existing entry with a stale '
            'isFavorite:false seed',
      );
      expect(
        heartIcon(_kManicure.id, Icons.favorite_border_rounded),
        findsNothing,
      );
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
            (ref) => (
              _kMaster,
              <MasterService>[
                _kManicure.copyWith(isFavorite: true),
                _kPedicure.copyWith(isFavorite: true),
              ],
            ),
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

      // Audit cycle 3 — `favorite_toggle_notifier.dart`'s `toggle` invalidates
      // `wishlistProvider` on a successful SERVICE toggle in EITHER direction
      // (add or remove), a channel unrelated to this sheet's own hearts. Phase
      // 243 removed `_CatalogueBodyState`'s watch on `wishlistProvider`
      // entirely (hearts now prime from `MasterService.isFavorite`), so that
      // side-channel can no longer confound this measurement even via a real
      // tap. `refreshWishlist: false` is kept anyway — driving the SAME
      // notifier method the real tap uses, the exact opt-out
      // `WishlistNotifier.removeService` itself relies on — so this stays a
      // narrow, deliberate test of `.select()` scoping rather than leaning on
      // an absence that a future change could reintroduce. This still
      // exercises the real widget's real `.select()` expression (the heart
      // still reads the same provider via the same watch), just without going
      // through the gesture detector — the gesture-to-toggle wiring is already
      // covered by `should_showFilledHeart_when_serviceAlreadyInWishlist` and
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
    // Audit cycle 3 — un-hearting FROM THIS SHEET must still invalidate the
    // wish list, so the Beauty Passport / wish-list screens don't keep showing
    // a service the client just removed. That invalidate lives in
    // `favorite_toggle_notifier.dart` (the "Audit cycle 3 fix") and is
    // EXPLICITLY out of scope for Phase 243 — only the priming source changed
    // (§ 6 of the phase doc: "the other five wishlistProvider readers are
    // unaffected").
    //
    // Before Phase 243, this sheet's own `ref.watch(wishlistProvider)` was
    // what made the invalidate observable in a widget test. Phase 243 removes
    // that watch, so this test installs a `container.listen` in its place —
    // NOT a stand-in for the real (paused) Passport consumer, just the
    // simplest active listener that makes `ref.invalidate` trigger an
    // observable refetch at all. A `container.listen` is a container-level
    // subscription, which Riverpod NEVER pauses (see
    // `leave_review_salon_surfaces_invalidation_test.dart`'s header, point 3),
    // so this test proves the invalidate call fires against an active
    // listener — a real assertion in its own right (the invalidate-on-success
    // contract), just not evidence about the paused-consumer path. That path
    // — the real risk, since `PassportScreen` is the actual sole consumer and
    // it sits COVERED behind this sheet in the live nav stack — is exercised
    // separately below by
    // `should_disposeAndRefetchOnResume_when_unheartingWhilePassportIsPaused`,
    // which pauses a real `Consumer` via `TickerMode(enabled: false)` (the
    // exact mechanism go_router's `Offstage`-wrapped inactive shell branch
    // uses under the hood — see `_IndexedStackedRouteBranchContainer` in
    // `go_router`'s `route.dart`).
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
          publicMasterProfileProvider(_kMasterId).overrideWith(
            (ref) => (
              _kMaster,
              <MasterService>[
                _kManicure.copyWith(isFavorite: true),
                _kPedicure,
              ],
            ),
          ),
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

      // The sheet itself fetches nothing — svc-mani's heart primes filled
      // straight from `isFavorite: true` on the payload it already fetched.
      expect(
        wishlistRepo.getCallCount,
        0,
        reason:
            'ServiceSelectorSheet no longer reads wishlistProvider (Phase 243)',
      );

      // An ACTIVE (never-paused) container-level listener — see the group
      // header above for why this is not a stand-in for the real, paused
      // Passport consumer. It is what makes the invalidate-on-unheart below
      // actually trigger a refetch instead of a silent no-op on a never-built
      // provider.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(ServiceSelectorSheet)),
      );
      container.listen(wishlistProvider, (_, _) {});
      await tester.pumpAndSettle();
      expect(wishlistRepo.getCallCount, 1);

      await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
      await tester.pumpAndSettle();

      // svc-mani starts favourited (isFavorite:true fixture) — tapping its
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

    // =========================================================================
    // THE REAL paused-consumer path — `should_refreshWishlist_when_
    // unheartingFromBookingSheet` above proves the invalidate CALL fires; this
    // one proves what actually happens to the one real listener
    // (`PassportScreen`) when it is genuinely paused, per
    // `favorite_toggle_notifier.dart`'s header comment.
    //
    // `TickerMode(enabled: false)` is not a stand-in or an approximation — it
    // is the EXACT signal go_router's own inactive-branch container uses
    // (`Offstage(child: TickerMode(enabled: isActive, child: ...))` in
    // go_router's `_IndexedStackedRouteBranchContainer`,
    // package:go_router/src/route.dart), and it is the exact signal
    // `flutter_riverpod`'s `Consumer` reads via `TickerMode.of` to decide
    // whether to pause its subscriptions (`flutter_riverpod`'s
    // `consumer.dart`). So a `Consumer` under a disabled `TickerMode` here is
    // paused for the identical reason `PassportScreen` would be paused behind
    // this sheet in the real nav stack.
    // =========================================================================
    testWidgets(
      'should_disposeAndRefetchOnResume_when_unheartingWhilePassportIsPaused',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final FakeWishlistRepository wishlistRepo = FakeWishlistRepository(
          services: <WishlistService>[_wishlistEntry(_kManicure.id)],
        );

        // Starts `false`: in the real nav stack the Passport branch is
        // ALREADY covered the moment this booking sheet exists on top of it.
        // Flips to `true` later only to simulate the user switching back to
        // the Passport tab (the "resume").
        final ValueNotifier<bool> passportActive = ValueNotifier<bool>(false);
        addTearDown(passportActive.dispose);
        AsyncValue<List<WishlistService>>? lastSeen;

        await tester.pumpApp(
          Stack(
            children: <Widget>[
              const ServiceSelectorSheet(masterId: _kMasterId),
              ValueListenableBuilder<bool>(
                valueListenable: passportActive,
                builder: (context, active, _) => TickerMode(
                  enabled: active,
                  child: Consumer(
                    builder: (context, ref, _) {
                      lastSeen = ref.watch(wishlistProvider);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ],
          ),
          overrides: <Object>[
            publicMasterProfileProvider(_kMasterId).overrideWith(
              (ref) => (
                _kMaster,
                <MasterService>[
                  _kManicure.copyWith(isFavorite: true),
                  _kPedicure,
                ],
              ),
            ),
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

        // Mount fetch — the paused Consumer's very first build still creates
        // the subscription (TickerMode only suppresses notification of LATER
        // changes, not this initial creation), so the repository is hit once
        // regardless of pause state.
        final int callsAfterMount = wishlistRepo.getCallCount;
        expect(callsAfterMount, greaterThanOrEqualTo(1));

        await tester.tap(find.byKey(const Key('booking_category_MANICURE')));
        await tester.pumpAndSettle();

        // svc-mani starts favourited (isFavorite:true fixture) — tapping its
        // heart un-favourites it, which invalidates `wishlistProvider` from
        // `favorite_toggle_notifier.dart`.
        await tester.tap(
          find.byKey(Key('booking_service_heart_${_kManicure.id}')),
        );
        await tester.pumpAndSettle();

        expect(
          heartIcon(_kManicure.id, Icons.favorite_border_rounded),
          findsOneWidget,
          reason: 'the tapped heart must have actually un-favourited',
        );

        // THE TRAP ITSELF: with the sole listener paused, `ref.invalidate`
        // disposes the provider instead of reloading it — there must be NO
        // immediate second fetch.
        expect(
          wishlistRepo.getCallCount,
          callsAfterMount,
          reason:
              'a PAUSED consumer must not see an immediate refetch — '
              'Riverpod 3 defers the dispose-and-refetch to resume (project '
              'memory: "Riverpod offstage-pause invalidate gotcha"); seeing '
              'a fetch here would mean the pause path was never actually '
              'exercised',
        );

        // Resume: the user switches back to the Passport tab.
        passportActive.value = true;
        await tester.pumpAndSettle();
        // One more settle: the dispose-and-recreate on resume can leave a
        // trailing microtask/timer chain (the fake repository's own
        // artificial `Future.delayed`) that the first `pumpAndSettle` call
        // catches mid-flight. A second call is a no-op once truly settled.
        await tester.pumpAndSettle();

        expect(
          wishlistRepo.getCallCount,
          greaterThan(callsAfterMount),
          reason:
              'resuming the paused consumer must trigger the deferred '
              'dispose-and-refetch — this is the "on resume" half of the '
              'documented trade in favorite_toggle_notifier.dart',
        );
        // Nothing crashed, and the resumed read is a genuine value — not
        // stuck in error/loading and not silently reusing a stale one.
        expect(
          lastSeen?.hasError,
          isFalse,
          reason: 'the resumed provider must not surface an error',
        );
        expect(
          lastSeen?.value,
          isNotNull,
          reason: 'the resumed provider must resolve to real data, not hang',
        );
      },
    );
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
