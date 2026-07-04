// Regression — driving an ACTUAL push of `/masters/:masterId` through the
// REAL `appRouterProvider` must resolve to a `MaterialPage`, never a
// `CustomTransitionPage`.
//
// WHY THIS TEST EXISTS (stronger than the structural sibling)
// ---------------------------------------------------------------------------
// `salon_profile_swipe_back_test.dart` / `app_router_page_type_test.dart` both
// pin the STATIC route table (`GoRoute.builder != null`, `GoRoute.pageBuilder
// == null`). That is a real regression guard, but it never exercises an
// actual navigation call — it only inspects the route CONFIGURATION, not what
// go_router actually does with it at push time.
//
// This test instead drives `router.push(RouteNames.masterPublicProfile(...))`
// — the exact call `MasterResultCard` makes in production
// (`context.push(RouteNames.masterPublicProfile(master.masterId))`,
// `lib/features/discovery/presentation/widgets/master_result_card.dart:81`,
// where `context.push` is a thin wrapper over `GoRouter.of(context).push`) —
// through the REAL `appRouterProvider`, then inspects the actual `Page` object
// go_router handed to whichever `Navigator` mounted `PublicMasterProfileScreen`.
// It asserts that `Page` `is MaterialPage` and NOT `is CustomTransitionPage`.
//
// A revert of the fix (`pageBuilder: (context, state) => _instantPage(state,
// PublicMasterProfileScreen(...))`) makes go_router hand the Navigator a
// `CustomTransitionPage` instead — its OWN `transitionsBuilder` bypasses
// `Theme.of(context).pageTransitionsTheme`'s `CupertinoPageTransitionsBuilder`,
// the mechanism that installs Flutter's left-edge swipe-back gesture detector
// (`_CupertinoBackGestureDetector`). Manually confirmed: this test FAILS
// (both the `isA<MaterialPage>` and `isNot(isA<CustomTransitionPage>)`
// expectations flip) when the fix is reverted, and PASSES with the fix in
// place.
//
// The interactive drag-to-dismiss gesture itself is still not observable from
// a widget test (see the sibling structural test's doc comment for why) — this
// test pins the Page-type contract that gesture depends on, exercised through
// a real push rather than a static route-table read.
//
// Layer: Widget (drives a real `GoRouter.push` + inspects the resulting
// Navigator page; the screen itself is pinned to AsyncLoading via a
// never-completing Future so no repository/network wiring is needed — only
// the resolved Page type is under test, not the screen's data states, which
// are already covered by `public_master_profile_screen_test.dart`).

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

const String _kMasterId = 'master-swipe-back-1';

const User _fakeClient = User(
  id: 'client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Клієнт',
  lastName: 'Тест',
);

const AuthSession _authenticatedClientSession = AuthSession.authenticated(
  user: _fakeClient,
  accessToken: 'test-token',
);

/// Settles `authProvider` synchronously to an authenticated CLIENT session.
/// `/masters/:masterId` carries `clientOnlyGuard`, so the pushed navigation
/// must not be redirected away before the Page-type assertion runs — a
/// non-CLIENT (or unauthenticated) session would bounce the push to a
/// different route entirely and this test would fail for the wrong reason.
class _FixedClientAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = const AsyncData<AuthSession>(_authenticatedClientSession);
    return _authenticatedClientSession;
  }
}

/// The registered path pattern for `/masters/:masterId` — go_router's own
/// `_buildPlatformAdapterPage` (builder.dart) names every `builder:`-resolved
/// Page `state.name ?? state.path`, where `state.path` is exactly this raw
/// route-pattern string (NOT the substituted location). Confirmed empirically:
/// with the fix in place, the pushed Page's `.name` is precisely
/// `/masters/:masterId` (verified via a throwaway debug print during
/// authoring — go_router wraps every `builder:` route's returned widget in an
/// anonymous `Builder(...)`, so matching on the resolved CHILD WIDGET TYPE
/// doesn't work: the Page's `.child` is always a `Builder`, never
/// `PublicMasterProfileScreen` directly, regardless of page type). A REVERTED
/// route (`pageBuilder: _instantPage(...)`) never sets `.name` at all (its
/// `CustomTransitionPage` is built with no `name:` argument), so on a revert
/// this lookup returns `null` — see [_describeNavigatorPages] for the
/// diagnostic that surfaces in that failure.
const String _kMasterProfileRoutePath = '/masters/:masterId';

/// Finds the actual [Page] go_router handed to whichever [Navigator] ended up
/// hosting the pushed `/masters/:masterId` route, identified by
/// [Page.name] (see [_kMasterProfileRoutePath]). `/masters/:masterId` is a
/// top-level route (not nested in the CLIENT `StatefulShellRoute`), so it
/// lands on the root Navigator, but this scans every mounted [Navigator]
/// defensively.
Page<dynamic>? _pushedMasterProfilePage(WidgetTester tester) {
  for (final Navigator nav in tester.widgetList<Navigator>(
    find.byType(Navigator),
  )) {
    for (final Page<dynamic> page in nav.pages) {
      if (page.name == _kMasterProfileRoutePath) return page;
    }
  }
  return null;
}

/// Dumps every mounted [Navigator]'s current `(runtimeType, name)` pairs —
/// embedded in the failure `reason` so a revert to `pageBuilder:
/// _instantPage(...)` (which surfaces as [_pushedMasterProfilePage] returning
/// `null`, since `_instantPage` never sets a Page `name`) still shows a
/// `CustomTransitionPage` entry in the stack instead of a bare "not found".
String _describeNavigatorPages(WidgetTester tester) {
  final List<String> lines = <String>[];
  for (final Navigator nav in tester.widgetList<Navigator>(
    find.byType(Navigator),
  )) {
    for (final Page<dynamic> page in nav.pages) {
      lines.add('${page.runtimeType}(name: ${page.name})');
    }
  }
  return lines.join(', ');
}

void main() {
  testWidgets(
    'router.push(RouteNames.masterPublicProfile(id)) through the REAL '
    'appRouterProvider resolves to a MaterialPage, never a '
    'CustomTransitionPage',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FixedClientAuthNotifier.new),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // The screen only needs to MOUNT far enough for go_router to resolve
          // its Page — this test never asserts on rendered data, so the
          // provider is pinned to a never-completing future. No repository or
          // network wiring is needed and no Dio call can leak.
          publicMasterProfileProvider(
            _kMasterId,
          ).overrideWith((ref) => Completer<PublicMasterProfileData>().future),
        ],
      );
      addTearDown(container.dispose);

      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pump();

      // Mirrors MasterResultCard's production navigation call exactly
      // (master_result_card.dart:81): `context.push(...)` is a thin wrapper
      // over `GoRouter.of(context).push(...)`. The returned Future only
      // resolves when the pushed route is later popped, which this test never
      // does — `unawaited` documents that deliberately (not a leak: the route
      // is disposed with the widget tree in tearDown).
      unawaited(router.push(RouteNames.masterPublicProfile(_kMasterId)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final Page<dynamic>? page = _pushedMasterProfilePage(tester);
      expect(
        page,
        isNotNull,
        reason:
            'Expected a Page named $_kMasterProfileRoutePath to be present '
            'on some Navigator after pushing '
            '${RouteNames.masterPublicProfile(_kMasterId)} through the real '
            'appRouterProvider. A `pageBuilder: _instantPage(...)` revert '
            'never sets a Page `name`, so it surfaces here as "not found" '
            'rather than a type mismatch below — actual mounted pages: '
            '${_describeNavigatorPages(tester)}',
      );
      expect(
        page,
        isA<MaterialPage<dynamic>>(),
        reason:
            'A pushed /masters/:masterId must resolve to a MaterialPage so '
            "the app theme's CupertinoPageTransitionsBuilder installs the "
            'left-edge swipe-back gesture. A revert to `pageBuilder: '
            '_instantPage(...)` resolves to a CustomTransitionPage instead, '
            'silently killing swipe-back on this route again.',
      );
      expect(
        page,
        isNot(isA<CustomTransitionPage<dynamic>>()),
        reason:
            "CustomTransitionPage supplies its own transitionsBuilder, which "
            "bypasses the theme's CupertinoPageTransitionsBuilder — see the "
            'reason above.',
      );
    },
  );
}
