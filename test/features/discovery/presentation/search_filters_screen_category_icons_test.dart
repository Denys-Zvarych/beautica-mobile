// Phase 110 Part 2 gap-closure (mobile-qa) — [ClientSearchScreen]'s category
// rail resolves the CORRECT SVG glyph per category slug.
//
// `search_filters_screen.dart:951` wires every rail tile through
// `categoryIconFor(categoryKey: c.name, categoryName: c.displayName)`
// (`lib/core/icons/category_icons.dart`) instead of the old Material
// `serviceTypeIcon` substring mapper
// (`lib/features/discovery/presentation/widgets/service_type_tile.dart`).
// That migration is otherwise UNGUARDED end to end — no test pumps the real
// screen and reads back which asset a given slug resolved to.
//
// Spot-checks the three slugs the OLD `serviceTypeIcon` mapper got wrong
// (see its doc comment / `has()` chain):
//   • TRICHOLOGY — matched no `has()` token → fell through to the generic
//     `Icons.spa_outlined` fallback (same as SPA/PEDICURE). Now resolves to
//     the dedicated `category_trichology.svg`.
//   • PODOLOGY — also matched no token (does NOT contain "PEDICURE") → same
//     generic spa fallback. Now resolves to `category_podology.svg`.
//   • BARBERING — matched `has('BARBER')` → `Icons.content_cut_outlined`,
//     the SAME glyph shared with HAIRDRESSING, HAIR_COLORING,
//     HAIR_TREATMENT, HAIR_EXTENSIONS and BEARD_CARE (6 unrelated
//     categories, one scissors icon). Now resolves to its OWN
//     `category_barbering.svg`, distinct from HAIRDRESSING's
//     `category_hairdressing.svg`.
//
// Reads `AppIcon.asset` off the pumped tree — a legitimate use of a
// constructor-field read here: this test's subject is DATA ROUTING (which
// asset string the slug resolved to), not geometry, so it isn't the
// `AppIcon.size` layout-clobber trap category_rail_test.dart guards against
// with `tester.getSize`.
//
// `approvedCategoriesProvider` is overridden DIRECTLY (not via
// `serviceRepositoryProvider`) — the family bypasses the repository provider
// entirely, a documented footgun (see `search_filters_screen_rail_test.dart`
// and MEMORY `project_approved_categories_provider_override_footgun`).

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_filters_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

const _testUser = User(
  id: 'u-client-icons',
  email: 'client-icons@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

class _MockServiceRepository extends Mock implements ServiceRepository {}

/// Categories spot-checking the three slugs the retired `serviceTypeIcon`
/// mapper resolved wrong or ambiguously — see file header.
const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'TRICHOLOGY', displayName: 'Трихологія'),
  ServiceCategoryOption(name: 'PODOLOGY', displayName: 'Подологія'),
  ServiceCategoryOption(name: 'BARBERING', displayName: 'Барберинг'),
  ServiceCategoryOption(name: 'HAIRDRESSING', displayName: 'Перукарня'),
];

Future<void> _pumpScreen(WidgetTester tester) async {
  installOverflowGuard();
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final List<Object> overrides = <Object>[
    authProvider.overrideWith(_FixedAuthNotifier.new),
    authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
    secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
    // DIRECT override — approvedCategoriesProvider bypasses
    // serviceRepositoryProvider entirely (the footgun documented above).
    approvedCategoriesProvider.overrideWith((ref) async => _categories),
  ];

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: overrides.cast(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: ClientSearchScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The [AppIcon] rendered inside the rail tile keyed `search_service_type_$slug`.
AppIcon _railIcon(WidgetTester tester, String slug) {
  return tester.widget<AppIcon>(
    find.descendant(
      of: find.byKey(Key('search_service_type_$slug')),
      matching: find.byType(AppIcon),
    ),
  );
}

void main() {
  group('ClientSearchScreen — category rail resolves the correct SVG glyph '
      'per slug', () {
    testWidgets(
      'TRICHOLOGY resolves to its OWN glyph, not the generic spa fallback '
      'the old serviceTypeIcon mapper gave it',
      (tester) async {
        await _pumpScreen(tester);

        expect(
          _railIcon(tester, 'TRICHOLOGY').asset,
          BeauticaAssetIcons.categoryTrichology,
        );
      },
    );

    testWidgets(
      'PODOLOGY resolves to its OWN glyph, not the generic spa fallback the '
      'old serviceTypeIcon mapper gave it',
      (tester) async {
        await _pumpScreen(tester);

        expect(
          _railIcon(tester, 'PODOLOGY').asset,
          BeauticaAssetIcons.categoryPodology,
        );
      },
    );

    testWidgets(
      'BARBERING resolves to its OWN glyph, distinct from HAIRDRESSING — '
      'the old mapper shared one scissors glyph across 6 categories',
      (tester) async {
        await _pumpScreen(tester);

        final AppIcon barbering = _railIcon(tester, 'BARBERING');
        final AppIcon hairdressing = _railIcon(tester, 'HAIRDRESSING');

        expect(barbering.asset, BeauticaAssetIcons.categoryBarbering);
        expect(hairdressing.asset, BeauticaAssetIcons.categoryHairdressing);
        expect(
          barbering.asset,
          isNot(hairdressing.asset),
          reason:
              'BARBERING must no longer share HAIRDRESSING\'s scissors glyph',
        );
      },
    );

    testWidgets(
      'every rendered rail tile carries a distinct AppIcon (no accidental '
      'collapse onto the fallback for the four spot-checked slugs)',
      (tester) async {
        await _pumpScreen(tester);

        final Set<String> assets = <String>{
          for (final c in _categories) _railIcon(tester, c.name).asset,
        };

        expect(
          assets.length,
          _categories.length,
          reason:
              'each of the 4 spot-checked slugs must resolve to its own '
              'dedicated glyph, none sharing the generic fallback',
        );
      },
    );
  });
}
