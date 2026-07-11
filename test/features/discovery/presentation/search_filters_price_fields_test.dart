// Phase 13.4 — Widget tests for the MIN/MAX price-field ↔ controller-state sync
// on [ClientSearchScreen]'s `_PriceSection`.
//
// The sibling search_filters_screen_test.dart already covers: entering a MAX
// value, entering MIN+MAX (range readout), the default «будь-яка» readout, and
// the CTA handoff. THIS file owns the gaps the redesign opened that those four
// do NOT exercise:
//
//   3. empty = unbounded — clearing a populated MIN / MAX field text drops the
//      corresponding bound back to null, and the readout reflects it.
//   4. field → state sync — entering a MIN value drives the controller's
//      minPrice (the field is the deterministic way to set the lower bound;
//      a raw RangeSlider drag is ambiguous between its two thumbs).
//   5. four-state readout — the «від X грн» (MIN-only) branch, which neither of
//      the dev's two price tests covers (they cover MAX-only and MIN+MAX).
//
// House patterns followed from the sibling screen test: plain `MaterialApp
// home:` (NOT .router) for a clean first-frame settle; a tall surface so the
// price section near the bottom of the scrollable column is on-screen and
// hit-testable; all finders key-based; UA strings asserted via l10n, never
// hardcoded.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'NAILS', displayName: 'Манікюр'),
];

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

/// Pumps [ClientSearchScreen] with the category provider resolved (so the body
/// settles) on a tall surface so the price section is on-screen. Plain
/// MaterialApp `home:` — the price-field sync tests need no router.
Future<void> _pumpScreen(WidgetTester tester) async {
  installOverflowGuard();

  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        approvedCategoriesProvider.overrideWith((ref) async => _categories),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: ClientSearchScreen(),
      ),
    ),
  );
}

SearchFilters _filters(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ClientSearchScreen)),
).read(searchFiltersControllerProvider);

Text _readout(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('search_price_readout')));

void main() {
  group('ClientSearchScreen — price field → state sync', () {
    testWidgets(
      'entering a MIN value drives the controller minPrice (field → state)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        // Precondition: no lower bound yet.
        expect(_filters(tester).minPrice, isNull);

        await tester.enterText(
          find.byKey(const Key('search_price_min_field')),
          '300',
        );
        await tester.pumpAndSettle();

        expect(_filters(tester).minPrice, 300);
        expect(
          _filters(tester).maxPrice,
          isNull,
          reason: 'a MIN-only entry must not invent an upper bound',
        );
      },
    );

    testWidgets(
      'MIN-only entry renders the «від X грн» four-state readout branch',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('search_price_min_field')),
          '450',
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();
        expect(
          _readout(tester).data,
          l10n.searchPriceFrom(450),
          reason: 'min set + max null → «від X грн» (the MIN-only branch)',
        );
      },
    );
  });

  group('ClientSearchScreen — empty field = unbounded', () {
    testWidgets(
      'clearing the MAX field text drops maxPrice back to null (readout → '
      '«будь-яка»)',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        // Establish an upper bound first.
        await tester.enterText(
          find.byKey(const Key('search_price_max_field')),
          '800',
        );
        await tester.pumpAndSettle();
        expect(_filters(tester).maxPrice, 800);

        // Now clear it — empty field means "no upper bound".
        await tester.enterText(
          find.byKey(const Key('search_price_max_field')),
          '',
        );
        await tester.pumpAndSettle();

        expect(
          _filters(tester).maxPrice,
          isNull,
          reason: 'an empty MAX field is unbounded — maxPrice must clear',
        );
        final AppLocalizations l10n = await _uk();
        expect(_readout(tester).data, l10n.searchPriceAny);
      },
    );

    testWidgets('clearing the MIN field text drops minPrice back to null', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('search_price_min_field')),
        '350',
      );
      await tester.pumpAndSettle();
      expect(_filters(tester).minPrice, 350);

      await tester.enterText(
        find.byKey(const Key('search_price_min_field')),
        '',
      );
      await tester.pumpAndSettle();

      expect(
        _filters(tester).minPrice,
        isNull,
        reason: 'an empty MIN field is unbounded — minPrice must clear',
      );
    });
  });

  group('ClientSearchScreen — 5-digit price entry (cap raised 4 → 5)', () {
    testWidgets(
      'entering a 5-digit MAX value (12000) is accepted in FULL and drives '
      'maxPrice=12000 — under the old 4-char cap this truncated to «1200»',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('search_price_max_field')),
          '12000',
        );
        await tester.pumpAndSettle();

        // The field itself must retain all five digits (the raised
        // LengthLimitingTextInputFormatter(5) cap — a regression here would
        // truncate the visible text to "1200").
        final TextField maxField = tester.widget<TextField>(
          find.byKey(const Key('search_price_max_field')),
        );
        expect(
          maxField.controller!.text,
          '12000',
          reason: 'the 5-char length cap must keep all five digits on screen',
        );

        // And the parsed value flows into the controller as a finite 12000 max
        // (12000 < 20000 ceiling → not collapsed to null).
        expect(
          _filters(tester).maxPrice,
          12000,
          reason:
              'a full 5-digit entry drives the raised-ceiling finite max; the '
              'old 4-digit cap would have parsed only 1200',
        );
      },
    );
  });

  group('ClientSearchScreen — slider ↔ field reflection', () {
    testWidgets(
      'a MAX-field entry reflects back into the slider thumb position '
      '(state → slider) without disturbing the field text',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('search_price_max_field')),
          '1200',
        );
        await tester.pumpAndSettle();

        // The controller is the single source of truth that flows into the
        // slider thumbs: maxPrice 1200 (min null → left thumb pinned to 0).
        final RangeSlider slider = tester.widget<RangeSlider>(
          find.byKey(const Key('search_price_slider')),
        );
        expect(slider.values.start, 0, reason: 'no lower bound → left thumb 0');
        expect(
          slider.values.end,
          1200,
          reason: 'maxPrice flows into the right thumb position',
        );

        // The MAX field text is preserved (no caret-stomping rewrite loop).
        final TextField maxField = tester.widget<TextField>(
          find.byKey(const Key('search_price_max_field')),
        );
        expect(maxField.controller!.text, '1200');
      },
    );
  });

  group('ClientSearchScreen — price slider tick-mark regression', () {
    // Regression guard for the "................" bug: the price RangeSlider
    // painted a visible dot at every division. The fix hides the ticks via the
    // local SliderThemeData (radius 0 + transparent colours) while KEEPING
    // `divisions` so the 500-грн snapping UX survives. This test asserts BOTH
    // halves so neither can silently regress: the dots can never return, and
    // the snapping can never be silently dropped by "just deleting divisions".
    testWidgets(
      'price slider hides the per-division tick dots yet keeps 500-грн snapping',
      (tester) async {
        await _pumpScreen(tester);
        await tester.pumpAndSettle();

        final Finder sliderFinder = find.byKey(
          const Key('search_price_slider'),
        );

        // Half 1 — ticks hidden. Resolve the SliderThemeData actually applied
        // to the slider via its enclosing SliderTheme ancestor.
        final SliderTheme sliderTheme = tester.widget<SliderTheme>(
          find.ancestor(of: sliderFinder, matching: find.byType(SliderTheme)),
        );
        final SliderThemeData themeData = sliderTheme.data;

        expect(
          themeData.rangeTickMarkShape,
          isA<RoundRangeSliderTickMarkShape>(),
          reason: 'the tick-mark shape must be the round shape we zero out',
        );
        expect(
          (themeData.rangeTickMarkShape as RoundRangeSliderTickMarkShape)
              .tickMarkRadius,
          0,
          reason: 'a non-zero radius repaints the "................" dot row',
        );
        expect(
          themeData.activeTickMarkColor,
          Colors.transparent,
          reason: 'active tick colour must be transparent so no dot shows',
        );
        expect(
          themeData.inactiveTickMarkColor,
          Colors.transparent,
          reason: 'inactive tick colour must be transparent so no dot shows',
        );

        // Half 2 — snapping preserved. `divisions` must stay non-null and equal
        // the 40-step (500-грн) constant; dropping it would lose the snap UX.
        final RangeSlider slider = tester.widget<RangeSlider>(sliderFinder);
        expect(
          slider.divisions,
          isNotNull,
          reason:
              'divisions must remain set — the fix hides dots, not snapping',
        );
        expect(
          slider.divisions,
          kSearchPriceDivisions,
          reason: 'snapping stays at the 40-division (500-грн) step',
        );
      },
    );
  });
}
