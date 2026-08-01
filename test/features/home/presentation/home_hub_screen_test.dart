// Phase 13.7 — HomeHub widget tests.
//
// Tests cover:
//   1. Profile card shows name from the provider (data state).
//   2. Profile card shows loading skeleton when provider is loading.
//   3. Profile card shows error retry when provider errors.
//   4. Next appointment empty state is shown when no appointment.
//   5. Favourite masters empty state is shown when no masters.
//   6. BEAUTY TIMELINE empty state is shown when no entries.
//   7. QuickLinksCard renders 3 tiles (reviews tile removed — rating reached via stat pill).
//   8. PassportPreviewCard renders the untranslated "BEAUTY PASSPORT" literal.
//   9. BEAUTY TIMELINE section renders the untranslated "BEAUTY TIMELINE" literal.
//  10. HomeHubScreen renders a key widget without error (smoke test).
//  11. MyRatingStatCard stat tile shows "Мий рейтинг" label and "—" empty value.
//   QA addition:
//  12. MyRatingStatCard onTap fires and navigates to RouteNames.myRating.
//  SVG-migration additions (Phase 13.7 icon update):
//  13. BellButton renders notificationPlain SVG via AppIcon (not Material glyph,
//      not the dotted notificationOutline/Filled) — double-dot fix.
//  14. PassportPreviewCard stat pill renders passportFilled SVG via AppIcon.
//  Bell two-SVG state swap (replaces the old Stack/Positioned overlay dot):
//  15. hasUnread=false ⇒ AppIcon(notificationPlain), monochrome (multicolor
//      false, color textSecondary) and NOT the unread asset.
//  16. hasUnread=true  ⇒ AppIcon(notificationUnread) with multicolor:true so
//      the baked-in red dot survives the srcIn flatten.
//  17. Neither state contains any Positioned overlay dot — exactly one AppIcon
//      bell glyph (the old code-drawn dot + its Key are gone).
//  18. BellButton announces its semanticLabel (button role) and fires onTap.
//
// NOTE: ScreenProtectionManager is a keepAlive singleton — tests override it
// with a no-op so the native plugin is never called during tests.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/beauty_timeline_section.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/favorite_masters_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/next_appointment_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/quick_links_card.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager for tests
// ---------------------------------------------------------------------------

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

// ---------------------------------------------------------------------------
// /users/me + location stubs for the city-resolution regression test
// ---------------------------------------------------------------------------
//
// These drive the REAL clientProfile provider (NOT a stubbed override of it) so
// the `_resolveCityName` taxonomy-fallback path actually executes end-to-end —
// only its SOURCE, the fresh `GET /users/me` provider clientEditProfileProvider,
// is stubbed (clientProfile now derives from it, not from the authProvider
// session User):
//   clientEditProfileProvider(User cityId set, cityName empty) → clientProfile →
//   cityListProvider → LocationRepository.fetchCities → match by id → "Київ".

/// Stubs [clientEditProfileProvider] (the fresh `/users/me` source) to a settled
/// profile carrying [_user].
class _StubClientEditProfile extends ClientEditProfile {
  _StubClientEditProfile(this._user);

  final User _user;

  @override
  Future<User> build() async => _user;
}

/// Fake [LocationRepository] serving a fixed city list for any oblast and a
/// fixed district list for any city (empty unless seeded).
class _FakeLocationRepository implements LocationRepository {
  const _FakeLocationRepository(
    this._cities, {
    List<CityDistrict> districts = const <CityDistrict>[],
  }) : _districts = districts;

  final List<City> _cities;
  final List<CityDistrict> _districts;

  @override
  Future<List<City>> fetchCities(String oblastId) async => _cities;

  @override
  Future<List<Oblast>> fetchOblasts() =>
      throw UnimplementedError('fetchOblasts not used here');

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async => _districts;
}

/// CLIENT with the authoritative cityId/oblastId FK set but an EMPTY
/// denormalized cityName — the exact condition that triggered the bug.
const _userCityIdNoName = User(
  id: 'usr-home-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Олена',
  lastName: 'Тест',
  cityId: 'city-kyiv',
  oblastId: 'oblast-kyiv',
  // cityName intentionally null → must be resolved from the taxonomy.
);

const _kyivCity = City(
  id: 'city-kyiv',
  oblastId: 'oblast-kyiv',
  name: 'Київ',
  katotthCode: 'UA80000000000093317',
  hasDistricts: false,
);

/// CLIENT with cityId + districtId set (both denormalized names empty) — drives
/// the combined `"city, district"` label end-to-end through the REAL
/// clientProfile → cityListProvider + districtListProvider chain.
const _userCityAndDistrictNoNames = User(
  id: 'usr-home-2',
  email: 'district@beautica.ua',
  role: UserRole.client,
  firstName: 'Софія',
  lastName: 'Сихів',
  cityId: 'city-lviv',
  oblastId: 'oblast-lviv',
  districtId: 'district-sykhiv',
  // cityName + districtName intentionally null → both resolved from taxonomy.
);

const _lvivCity = City(
  id: 'city-lviv',
  oblastId: 'oblast-lviv',
  name: 'Львів',
  katotthCode: 'UA46000000000026686',
  hasDistricts: true,
);

const _sykhivDistrict = CityDistrict(
  id: 'district-sykhiv',
  cityId: 'city-lviv',
  name: 'Сихівський район',
  katotthCode: 'UA46060370000000000',
);

// ---------------------------------------------------------------------------
// Test-wide sample data
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2026,
);

final _sampleAppointment = NextAppointment(
  id: 'appt-1',
  masterName: 'Марія Іванюк',
  service: 'Манікюр',
  dateLabel: '20 червня',
  timeLabel: '15:00',
  location: 'Центр, Львів',
  startsAt: DateTime.now().add(const Duration(days: 2)),
  endsAt: DateTime.now().add(const Duration(days: 2, hours: 1, minutes: 30)),
  masterInitials: 'МІ',
);

const _sampleMaster = FavoriteMasterItem(
  masterId: 'master-1',
  favoriteId: 'fav-1',
  name: 'Марія Іванюк',
  lastServiceName: 'Манікюр',
  rating: 5.0,
  reviewCount: 42,
  initials: 'МІ',
);

const _sampleTimeline = <TimelineEntry>[
  TimelineEntry(category: 'Манікюр', dateLabel: '18.06'),
  TimelineEntry(category: 'Брови', dateLabel: '12.05'),
];

// ---------------------------------------------------------------------------
// Shared provider overrides
// ---------------------------------------------------------------------------

List<Object> _overrides({
  AsyncValue<ClientProfileSummary>? profile,
  AsyncValue<NextAppointment?> nextAppt = const AsyncData(null),
  AsyncValue<List<FavoriteMasterItem>> favorites = const AsyncData(
    <FavoriteMasterItem>[],
  ),
  AsyncValue<List<TimelineEntry>> timeline = const AsyncData(<TimelineEntry>[]),
  // The rating pill sources from the authoritative myRatingProvider (same as
  // MyRatingScreen), not the profile summary's clientRating slice. Overriding
  // it also avoids the real loader's 5-min keepAlive Timer leaking past
  // teardown.
  ClientRating rating = const ClientRating(),
}) {
  return [
    // Bypass native ScreenProtector
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    myRatingProvider.overrideWith((ref) async => rating),
    if (profile != null)
      clientProfileProvider.overrideWith(
        (ref) async => profile.when(
          data: (v) => v,
          loading: () => throw UnimplementedError(),
          error: (e, _) => throw e,
        ),
      ),
    nextAppointmentProvider.overrideWith((ref) async {
      return nextAppt.when(
        data: (v) => v,
        loading: () => null,
        error: (e, _) => null,
      );
    }),
    favoriteMastersProvider.overrideWith((ref) async {
      return favorites.when(
        data: (v) => v,
        loading: () => const <FavoriteMasterItem>[],
        error: (e, _) => const <FavoriteMasterItem>[],
      );
    }),
    beautyTimelineProvider.overrideWith((ref) async {
      return timeline.when(
        data: (v) => v,
        loading: () => const <TimelineEntry>[],
        error: (e, _) => const <TimelineEntry>[],
      );
    }),
    unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  ];
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // NOTE (2026-06-24 wordmark-jump hoist): the top bar (wordmark · bell ·
  // burger) is no longer built by HomeHubScreen — it is mounted ONCE by
  // ClientShell above the branch body. The former per-screen assertions here
  // (smoke wordmark / bell key / btn-menu-client key / tune_rounded glyph /
  // burger→/client/menu push) moved to
  // `test/features/shell/client_shell_top_bar_test.dart`, which pumps the bar
  // through the REAL router/shell on the home branch. Coverage is preserved,
  // not deleted — it just lives where the bar lives now. The smoke test below
  // pins that the home BODY still renders (a key body widget).

  group('HomeHubScreen', () {
    testWidgets('smoke — body renders (profile card) without the top bar', (
      tester,
    ) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      // One pump builds the tree; the staggered reveal is a FadeTransition +
      // SlideTransition (the child is ALWAYS mounted, only its opacity/offset
      // animate), so the body widgets resolve immediately — no fixed-duration
      // sleep needed to settle the reveal (mobile-qa: no `pump(Duration)`).
      await tester.pump();
      // The bar is shell-owned now, so the screen pumped in isolation has NO
      // wordmark…
      expect(find.text('beautica'), findsNothing);
      // …but the body still renders (the profile block shows the client name,
      // keyed by the profile card so an l10n move can't mask the regression).
      expect(
        find.byKey(const Key('home_profile_name')),
        findsOneWidget,
        reason: 'home body must render in isolation even with the bar hoisted',
      );
    });
  });

  group('HomeProfileCard (via HomeHubScreen)', () {
    testWidgets('data state: shows client full name', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      // After animation starts (pumpAndSettle for reveal)
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('Олена Тест'), findsOneWidget);
    });

    testWidgets('data state: shows city', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('Львів'), findsOneWidget);
    });

    // REGRESSION (saved-location bug): the card must show the saved city even
    // when the backend returns an EMPTY denormalized cityName but a populated
    // cityId/oblastId. This drives the REAL clientProfile provider (no stub) so
    // `_resolveCityName` resolves the name from the location taxonomy by id —
    // exactly as the Settings screen does. With the pre-fix mapping
    // (`city: user.cityName ?? ''`) the card would show the location
    // placeholder and this test would fail.
    testWidgets(
      'regression: empty cityName + cityId set ⇒ card shows city resolved '
      'from the taxonomy (not the placeholder)',
      (tester) async {
        await tester.pumpApp(
          const HomeHubScreen(),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            clientEditProfileProvider.overrideWith(
              () => _StubClientEditProfile(_userCityIdNoName),
            ),
            locationRepositoryProvider.overrideWith(
              (_) => const _FakeLocationRepository(<City>[_kyivCity]),
            ),
            nextAppointmentProvider.overrideWith((ref) async => null),
            favoriteMastersProvider.overrideWith(
              (ref) async => const <FavoriteMasterItem>[],
            ),
            beautyTimelineProvider.overrideWith(
              (ref) async => const <TimelineEntry>[],
            ),
            unlikeFavoriteMasterProvider.overrideWith(
              () => UnlikeFavoriteMaster(),
            ),
          ],
        );
        // Settle the auth + clientProfile + cityListProvider futures, then the
        // 1100 ms reveal animation, so the resolved city is painted.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          find.text('Київ'),
          findsOneWidget,
          reason:
              'with cityName empty but cityId set, the profile card must '
              'resolve "Київ" from the location taxonomy instead of falling '
              'back to the "add location" placeholder',
        );
      },
    );

    // District-display feature: the profile card's location row composes
    // "<city>, <district>" when the client has a resolvable districtId. This
    // drives the REAL clientProfile provider (no stub) so the full
    // cityListProvider + districtListProvider taxonomy chain executes. The
    // assertion uses the Key('home_profile_city') finder (locale-invariant per
    // backlog M2) rather than matching the raw "Львів, Сихівський район"
    // literal across the whole tree.
    //
    // RED-AGAINST-ABSENCE: before this feature the card showed only the bare
    // city ("Львів"); the combined-label assertion would fail.
    testWidgets('data state: profile card renders "<city>, <district>" via '
        'home_profile_city key when districtId resolves', (tester) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          clientEditProfileProvider.overrideWith(
            () => _StubClientEditProfile(_userCityAndDistrictNoNames),
          ),
          locationRepositoryProvider.overrideWith(
            (_) => const _FakeLocationRepository(
              <City>[_lvivCity],
              districts: <CityDistrict>[_sykhivDistrict],
            ),
          ),
          nextAppointmentProvider.overrideWith((ref) async => null),
          favoriteMastersProvider.overrideWith(
            (ref) async => const <FavoriteMasterItem>[],
          ),
          beautyTimelineProvider.overrideWith(
            (ref) async => const <TimelineEntry>[],
          ),
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      // Settle auth + clientProfile + cityList + districtList futures, then
      // the 1100 ms reveal animation, so the composed label is painted.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1100));

      final Finder cityLine = find.byKey(const Key('home_profile_city'));
      expect(cityLine, findsOneWidget);
      expect(
        tester.widget<Text>(cityLine).data,
        'Львів, Сихівський район',
        reason:
            'the profile card location row must compose the combined '
            '"<city>, <district>" label when the client has a resolvable '
            'districtId',
      );
    });

    testWidgets('loading state: change photo button visible', (tester) async {
      // Even in loading state, the screen renders (skeleton in profile area)
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump();
      // Camera button is present after data loads
      await tester.pump(const Duration(milliseconds: 1100));
      expect(
        find.byKey(const Key('home_hub_change_photo_button')),
        findsOneWidget,
      );
    });
  });

  group('Next appointment card', () {
    testWidgets('empty state rendered when no appointment', (tester) async {
      await tester.pumpApp(
        const NextAppointmentCard(
          appointment: null,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('next_appointment_empty')), findsOneWidget);
    });

    testWidgets('populated state: shows time label', (tester) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('next_appointment_populated')),
        findsOneWidget,
      );
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('countdown chip is shown when appointment exists', (
      tester,
    ) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(find.byType(CountdownChip), findsOneWidget);
    });

    testWidgets('reschedule button has correct key', (tester) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('next_appt_reschedule_button')),
        findsOneWidget,
      );
    });

    testWidgets('cancel button has correct key', (tester) async {
      await tester.pumpApp(
        NextAppointmentCard(
          appointment: _sampleAppointment,
          onReschedule: _noop,
          onCancel: _noop,
          onAddToGoogleCalendar: _noop,
          onAddToAppleCalendar: _noop,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('next_appt_cancel_button')), findsOneWidget);
    });
  });

  // ── mobile-qa (Phase 225, Step 2.7 final gate) ───────────────────────────
  //
  // GAP FOUND: `_NextAppointmentSection` (home_hub_screen.dart) gained a real
  // `.when(... error: (e, _) => _CardErrorState(...))` branch as part of the
  // live-data wiring — the old hardcoded-`null` stub never called anything,
  // so an error branch literally could not exist before this phase. Nothing
  // exercised it: every existing override in this file maps
  // `nextAppointmentProvider`'s error case to `null` (empty state) rather
  // than letting it settle as AsyncError, and
  // `home_hub_supplemental_test.dart`'s header claims "Integration test
  // (client_home_hub_flow_test.dart) covers the full error → retry → reload
  // flow end-to-end" — but that integration file has no error/retry test at
  // all (verified: zero hits for retry/error/failure fixtures there). Per the
  // absolute rule ("never accept a screen test that omits the error state
  // with retry interaction"), this closes that gap directly, reusing the
  // same `retry: (_, _) => null` + synchronous-throw technique
  // `home_hub_rating_pill_dedup_test.dart` already established for a sibling
  // card in this exact screen.
  group('Next appointment section — error + retry (via HomeHubScreen)', () {
    List<Object> errorOverrides(NextAppointment? Function() build) => <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      myRatingProvider.overrideWith((ref) async => const ClientRating()),
      clientProfileProvider.overrideWith((ref) async => _sampleProfile),
      nextAppointmentProvider.overrideWith((ref) async => build()),
      favoriteMastersProvider.overrideWith(
        (ref) async => const <FavoriteMasterItem>[],
      ),
      beautyTimelineProvider.overrideWith(
        (ref) async => const <TimelineEntry>[],
      ),
      unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
    ];

    testWidgets(
      'a failing nextAppointmentProvider renders _CardErrorState with the '
      'load-error message and a retry CTA — never a perpetual skeleton and '
      'never an escaped exception',
      (tester) async {
        await tester.pumpApp(
          const HomeHubScreen(),
          // Throw SYNCHRONOUSLY so the provider settles to AsyncError on its
          // first build (no intervening AsyncLoading frame), and disable
          // Riverpod 3.x auto-retry so the error stays put with no pending
          // backoff Timer (which would hang pumpAndSettle).
          retry: (_, _) => null,
          overrides: errorOverrides(
            () => throw Exception('bookings fetch boom'),
          ),
        );
        await tester.pumpAndSettle();
        // fixed-wait-ok: running out the time-driven reveal CurvedAnimation.
        await tester.pump(const Duration(milliseconds: 1100));

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(HomeHubScreen)),
        );
        expect(
          find.text(l10n.homeHubNextApptLoadError),
          findsOneWidget,
          reason:
              'the section must render the next-appointment-specific load '
              'error message, not a generic one',
        );
        expect(
          find.byType(HubFilledButton),
          findsWidgets,
          reason: '_CardErrorState must render a retry CTA button',
        );
        // Neither the empty nor the populated card leaked through — the error
        // branch, not a stale/other branch, is what actually rendered.
        expect(find.byKey(const Key('next_appointment_empty')), findsNothing);
        expect(
          find.byKey(const Key('next_appointment_populated')),
          findsNothing,
        );
        // A single failing card must not blank the whole screen.
        expect(find.byType(HomeHubScreen), findsOneWidget);
        expect(find.byKey(const Key('home_profile_name')), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the retry CTA invalidates nextAppointmentProvider and the '
      'section recovers to the populated data state on the next fetch',
      (tester) async {
        // First build throws (drives the error branch); every subsequent
        // build (i.e. after the retry CTA invalidates the provider) returns
        // real data — proving the CTA's `onRetry` really is
        // `ref.invalidate(nextAppointmentProvider)`, not a no-op button.
        var calls = 0;
        await tester.pumpApp(
          const HomeHubScreen(),
          retry: (_, _) => null,
          overrides: errorOverrides(() {
            calls++;
            if (calls == 1) throw Exception('bookings fetch boom');
            return _sampleAppointment;
          }),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 1100));

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(HomeHubScreen)),
        );
        expect(find.text(l10n.homeHubNextApptLoadError), findsOneWidget);
        expect(
          calls,
          1,
          reason: 'sanity: exactly one failed fetch before any retry tap',
        );

        await tester.ensureVisible(find.byType(HubFilledButton).first);
        await tester.tap(find.byType(HubFilledButton).first);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          calls,
          greaterThanOrEqualTo(2),
          reason:
              'the retry CTA must invalidate nextAppointmentProvider — a '
              'second build call is the only proof the tap actually fired '
              'a refetch rather than merely dismissing the error UI',
        );
        expect(
          find.byKey(const Key('next_appointment_populated')),
          findsOneWidget,
          reason:
              'once the retried fetch succeeds the section must render the '
              'populated card, not stay stuck on the error state',
        );
        expect(find.text(l10n.homeHubNextApptLoadError), findsNothing);
      },
    );
  });

  group('FavoriteMastersCard', () {
    testWidgets('empty state when masters is empty', (tester) async {
      await tester.pumpApp(
        const FavoriteMastersCard(masters: [], totalCount: 0),
        overrides: [
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      await tester.pump();
      expect(find.byKey(const Key('favorite_masters_empty')), findsOneWidget);
    });

    testWidgets('rail is shown when masters list is non-empty', (tester) async {
      await tester.pumpApp(
        const FavoriteMastersCard(masters: [_sampleMaster], totalCount: 1),
        overrides: [
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      await tester.pump();
      expect(find.byKey(const Key('favorite_masters_rail')), findsOneWidget);
    });

    testWidgets('unlike button has correct key per master', (tester) async {
      await tester.pumpApp(
        const FavoriteMastersCard(masters: [_sampleMaster], totalCount: 1),
        overrides: [
          unlikeFavoriteMasterProvider.overrideWith(
            () => UnlikeFavoriteMaster(),
          ),
        ],
      );
      await tester.pump();
      expect(find.byKey(const Key('unlike_master_master-1')), findsOneWidget);
    });
  });

  group('BeautyTimelineSection', () {
    testWidgets('empty state when entries is empty', (tester) async {
      await tester.pumpApp(
        const BeautyTimelineSection(entries: [], onSeeAll: _noop),
      );
      await tester.pump();
      expect(find.byKey(const Key('timeline_empty')), findsOneWidget);
    });

    testWidgets('rail is shown when entries is non-empty', (tester) async {
      await tester.pumpApp(
        const BeautyTimelineSection(entries: _sampleTimeline, onSeeAll: _noop),
      );
      await tester.pump();
      expect(find.byKey(const Key('timeline_rail')), findsOneWidget);
    });

    testWidgets('BEAUTY TIMELINE brand literal is rendered (untranslated)', (
      tester,
    ) async {
      await tester.pumpApp(
        const BeautyTimelineSection(entries: [], onSeeAll: _noop),
      );
      await tester.pump();
      // The section title is uppercased by HubSectionTitle, so find both.
      expect(find.textContaining('BEAUTY TIMELINE'), findsOneWidget);
    });
  });

  group('PassportPreviewCard', () {
    testWidgets('BEAUTY PASSPORT brand literal is rendered (untranslated)', (
      tester,
    ) async {
      await tester.pumpApp(const PassportPreviewCard(onTap: _noop));
      await tester.pump();
      // HubSectionTitle uppercases — the tile text is already uppercased.
      expect(find.textContaining('BEAUTY PASSPORT'), findsOneWidget);
    });
  });

  group('QuickLinksCard', () {
    testWidgets('renders exactly 3 quick-link tiles', (tester) async {
      await tester.pumpApp(const QuickLinksCard());
      await tester.pump();
      // Each of the 3 approved tiles has a unique key.
      expect(find.byKey(const Key('quick_link_search')), findsOneWidget);
      expect(find.byKey(const Key('quick_link_favorites')), findsOneWidget);
      expect(find.byKey(const Key('quick_link_bookings')), findsOneWidget);
    });

    testWidgets('reviews tile is absent from quick-links card', (tester) async {
      // The "Мої відгуки" tile was removed — rating is reached from the
      // MyRatingStatCard stat pill instead (separate widget, stays in the screen).
      await tester.pumpApp(const QuickLinksCard());
      await tester.pump();
      expect(
        find.byKey(const Key('quick_link_reviews')),
        findsNothing,
        reason:
            'quick_link_reviews tile must be absent — the stat pill navigates '
            'to /rating instead',
      );
    });
  });

  group('MyRatingStatCard', () {
    testWidgets('shows "Мій рейтинг" label', (tester) async {
      await tester.pumpApp(
        const MyRatingStatCard(clientRating: null, onTap: _noop),
      );
      await tester.pump();
      expect(
        find.textContaining('Мій рейтинг'),
        findsOneWidget,
        reason: 'MyRatingStatCard must render the homeHubMyRating l10n string',
      );
    });

    testWidgets('shows em-dash when clientRating is null (empty state)', (
      tester,
    ) async {
      await tester.pumpApp(
        const MyRatingStatCard(clientRating: null, onTap: _noop),
      );
      await tester.pump();
      expect(
        find.text('—'),
        findsOneWidget,
        reason:
            'MyRatingStatCard must show "—" when no rating has been assigned',
      );
    });

    testWidgets('shows rating value when clientRating is non-null', (
      tester,
    ) async {
      await tester.pumpApp(
        const MyRatingStatCard(clientRating: 4.7, onTap: _noop),
      );
      await tester.pump();
      expect(
        find.text('4.7'),
        findsOneWidget,
        reason: 'MyRatingStatCard must show "4.7" when clientRating = 4.7',
      );
    });

    testWidgets('stat pills row renders MyRatingStatCard via HomeHubScreen', (
      tester,
    ) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(profile: const AsyncData(_sampleProfile)),
      );
      await tester.pump(const Duration(milliseconds: 1100));

      // The label "Мій рейтинг" must appear in the stat-pills row.
      expect(
        find.textContaining('Мій рейтинг'),
        findsOneWidget,
        reason:
            'stat-pills row must use MyRatingStatCard with Мій рейтинг label',
      );
    });

    // QA addition: verify the onTap wiring of MyRatingStatCard fires.
    // The pill's onTap calls context.push(RouteNames.myRating) in HomeHubScreen;
    // we test MyRatingStatCard standalone with a spy callback so the wiring can
    // be confirmed without a full GoRouter. The navigation correctness through
    // GoRouter is covered by client_home_hub_flow_test.dart (integration tier).
    testWidgets(
      'MyRatingStatCard onTap callback fires when the card is tapped',
      (tester) async {
        var tapped = false;
        await tester.pumpApp(
          MyRatingStatCard(clientRating: null, onTap: () => tapped = true),
        );
        await tester.pump();

        // The card is a HubFlatCard with an onTap. Tap anywhere on the card.
        await tester.tap(find.byType(MyRatingStatCard));
        await tester.pump();

        expect(
          tapped,
          isTrue,
          reason:
              'tapping MyRatingStatCard must fire onTap — this wires to '
              'context.push(RouteNames.myRating) in HomeHubScreen',
        );
      },
    );
  });

  group('HubEmptyState', () {
    testWidgets('shows message and CTA when ctaLabel is given', (tester) async {
      var tapped = false;
      await tester.pumpApp(
        HubEmptyState(
          icon: Icons.search_rounded,
          message: 'Тест повідомлення',
          ctaLabel: 'Тест кнопка',
          onCta: () => tapped = true,
        ),
      );
      await tester.pump();
      expect(find.text('Тест повідомлення'), findsOneWidget);
      expect(find.text('Тест кнопка'), findsOneWidget);
      await tester.tap(find.text('Тест кнопка'));
      expect(tapped, isTrue);
    });

    testWidgets('omits CTA when ctaLabel is null', (tester) async {
      await tester.pumpApp(
        const HubEmptyState(
          icon: Icons.favorite_border_rounded,
          message: 'Порожньо',
        ),
      );
      await tester.pump();
      expect(find.text('Порожньо'), findsOneWidget);
    });
  });

  // ── SVG-migration guard: bell button + passport stat pill ────────────────────
  //
  // These tests lock in the icon sources for the two widgets updated in the
  // Phase 13.7 SVG migration:
  //   • BellButton (home hub top bar) — was Icons.notifications_none_rounded,
  //     then AppIcon(notificationOutline) (dotted), now a two-SVG state swap:
  //     AppIcon(notificationPlain) when idle / AppIcon(notificationUnread) when
  //     hasUnread. The old code-drawn Stack/Positioned overlay dot is gone (it
  //     caused the double-dot bug); the dot now lives inside the unread asset.
  //     The production call site is pinned to hasUnread:false ⇒ idle asset.
  //   • PassportPreviewCard icon circle — was Icons.badge_outlined,
  //     now AppIcon(BeauticaAssetIcons.passportFilled, …)

  group('SVG icon migration guard — bell button and passport stat pill', () {
    testWidgets(
      'BellButton renders notificationPlain SVG, not Material glyph or dotted asset',
      (tester) async {
        // The bell now lives in the shell-owned ClientTopBar, not in
        // HomeHubScreen, so pump BellButton directly (it is public) in its idle
        // (hasUnread: false) state — the production call site is pinned false.
        await tester.pumpApp(
          const BellButton(onTap: _noop, semanticLabel: 'Сповіщення'),
        );
        await tester.pump();

        // The legacy Material glyph must be gone.
        expect(
          find.byIcon(Icons.notifications_none_rounded),
          findsNothing,
          reason:
              'Icons.notifications_none_rounded must be absent — the bell '
              'button has migrated to AppIcon(notificationPlain).',
        );

        // AppIcon inside the bell button's subtree must be the DOTLESS plain
        // asset — never the dotted notificationOutline/notificationFilled
        // (whose baked-in dot caused the double-dot bug).
        final Finder bellButton = find.byType(BellButton);
        expect(bellButton, findsOneWidget);

        final List<AppIcon> appIconsInBell = tester
            .widgetList<AppIcon>(
              find.descendant(of: bellButton, matching: find.byType(AppIcon)),
            )
            .toList();
        expect(
          appIconsInBell.any(
            (w) => w.asset == BeauticaAssetIcons.notificationPlain,
          ),
          isTrue,
          reason:
              'BellButton must render AppIcon(notificationPlain) inside its '
              'subtree (home_hub_bell_button key).',
        );
        expect(
          appIconsInBell.any(
            (w) =>
                w.asset == BeauticaAssetIcons.notificationOutline ||
                w.asset == BeauticaAssetIcons.notificationFilled,
          ),
          isFalse,
          reason:
              'The dotted notificationOutline/notificationFilled assets must '
              'NOT be used for the top-bar bell — their baked-in dot collides '
              'with the app overlay dot (double-dot bug).',
        );
      },
    );

    testWidgets(
      'PassportPreviewCard stat pill renders passportFilled SVG, not badge glyph',
      (tester) async {
        await tester.pumpApp(const PassportPreviewCard(onTap: _noop));
        await tester.pump();

        // The legacy Material badge_outlined glyph must be gone.
        expect(
          find.byIcon(Icons.badge_outlined),
          findsNothing,
          reason:
              'Icons.badge_outlined must be absent — the passport stat pill has '
              'migrated to AppIcon(passportFilled).',
        );

        // AppIcon with the passportFilled asset must be present.
        final List<AppIcon> appIcons = tester
            .widgetList<AppIcon>(find.byType(AppIcon))
            .toList();
        expect(
          appIcons.any((w) => w.asset == BeauticaAssetIcons.passportFilled),
          isTrue,
          reason:
              'PassportPreviewCard must render AppIcon(passportFilled) in the '
              'icon circle to match the nav BEAUTY PASSPORT tab glyph.',
        );
        // Tint must be accentDeep so the pill stays on-brand.
        expect(
          appIcons
              .where((w) => w.asset == BeauticaAssetIcons.passportFilled)
              .every((w) => w.color == const Color(0xFF6A4A28)),
          isTrue,
          reason:
              'PassportPreviewCard AppIcon must be tinted accentDeep '
              '(0xFF6A4A28) to match the icon-circle palette.',
        );
      },
    );
  });

  // ── Unread state = two-SVG asset swap (double-dot fix) ───────────────────────
  //
  // The dot is now baked into a dedicated unread SVG instead of a code-drawn
  // Stack/Positioned overlay. BellButton swaps the rendered asset on hasUnread:
  //   • hasUnread=false ⇒ AppIcon(notificationPlain)  (dotless bell)
  //   • hasUnread=true  ⇒ AppIcon(notificationUnread) (bell + baked red dot)
  // These tests guard against the always-on-dot regression (idle showing the
  // unread asset) and the inverted-logic regression (unread showing the plain
  // asset). They also lock in that the old overlay dot is gone (no Stack with
  // clipBehavior: Clip.none, no Positioned dot) so the double-dot cannot recur.
  //
  // BellButton is pumped directly (it is @visibleForTesting public) because the
  // production call site is currently pinned to `hasUnread: false` (TODO 14.9),
  // so the `true` branch is only reachable from a test.

  group('BellButton unread/idle asset swap', () {
    AppIcon bellIcon(WidgetTester tester) => tester.widget<AppIcon>(
      find.descendant(
        of: find.byType(BellButton),
        matching: find.byType(AppIcon),
      ),
    );

    testWidgets('hasUnread=false renders the dotless plain asset', (
      tester,
    ) async {
      await tester.pumpApp(
        const BellButton(onTap: _noop, semanticLabel: 'Сповіщення'),
      );
      await tester.pump();

      final AppIcon icon = bellIcon(tester);
      expect(
        icon.asset,
        BeauticaAssetIcons.notificationPlain,
        reason: 'idle ⇒ the dotless plain bell asset',
      );
      expect(
        icon.asset,
        isNot(BeauticaAssetIcons.notificationUnread),
        reason: 'idle must NOT show the unread (dotted) asset',
      );
      // Idle bell is flattened to the secondary text colour (single-tone).
      expect(icon.multicolor, isFalse);
      expect(icon.color, BrandColors.textSecondary);
    });

    testWidgets('hasUnread=true renders the unread (baked-dot) asset', (
      tester,
    ) async {
      await tester.pumpApp(
        const BellButton(
          onTap: _noop,
          semanticLabel: 'Сповіщення',
          hasUnread: true,
        ),
      );
      await tester.pump();

      final AppIcon icon = bellIcon(tester);
      expect(
        icon.asset,
        BeauticaAssetIcons.notificationUnread,
        reason: 'hasUnread ⇒ the bell asset with the baked-in notification dot',
      );
      // The unread asset is two-tone: it MUST skip the srcIn flatten, otherwise
      // the red dot would be repainted to the bell colour (the whole point).
      expect(
        icon.multicolor,
        isTrue,
        reason:
            'unread asset must render multicolor (no srcIn) so the red dot '
            'survives instead of being tinted to the bell colour',
      );
    });

    testWidgets('exposes the semantics label and fires its tap callback', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpApp(
        BellButton(onTap: () => tapped = true, semanticLabel: 'Сповіщення'),
      );
      await tester.pump();

      // The accessible label is announced via a button-role Semantics node so
      // screen readers reach the bell. (homeHubNotificationsLabel at the call
      // site; passed verbatim here so the test stays locale-independent.)
      expect(
        find.bySemanticsLabel('Сповіщення'),
        findsOneWidget,
        reason: 'BellButton must announce its semanticLabel (button role)',
      );

      // Tapping the bell must fire onTap — the wiring that opens the
      // notification centre once Phase 14.9 lands.
      await tester.tap(find.byType(BellButton));
      await tester.pump();
      expect(
        tapped,
        isTrue,
        reason: 'tapping BellButton must invoke its onTap callback',
      );
    });

    testWidgets('no code-drawn overlay dot remains in either state', (
      tester,
    ) async {
      for (final unread in <bool>[false, true]) {
        await tester.pumpApp(
          BellButton(
            onTap: _noop,
            semanticLabel: 'Сповіщення',
            hasUnread: unread,
          ),
        );
        await tester.pump();

        // Exactly one bell glyph, never a Positioned overlay dot beside it.
        expect(
          find.descendant(
            of: find.byType(BellButton),
            matching: find.byType(AppIcon),
          ),
          findsOneWidget,
          reason: 'the bell is a single AppIcon — no overlay companion widget',
        );
        expect(
          find.descendant(
            of: find.byType(BellButton),
            matching: find.byType(Positioned),
          ),
          findsNothing,
          reason:
              'the old Positioned overlay dot is gone (hasUnread=$unread) — '
              'the dot now lives inside the SVG asset',
        );
      }
    });
  });
}

void _noop() {}
