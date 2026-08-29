// Phase 21.9 — widget tests for the REBUILT SalonSettingsScreen (the full
// 8-row settings hub the salon management profile's top-right
// `Icons.tune_rounded` cover control opens). SUPERSEDES the Phase 21.2 2-row
// suite this file used to hold («Редагувати профіль» + owner-only «Видалити
// салон») — see git history for that version. See the screen's own header
// doc-comment (`salon_settings_screen.dart`) for the full design rationale;
// this file only re-derives what each test needs to make its assertion
// meaningful.
//
// Covers:
//   1. All 8 rows (+ terminal hairline) render, in the design's order, for
//      the owner.
//   2. Owner gating: an admin viewer sees NEITHER the four owner-only rows
//      NOR the row order shifts — only the four all-viewer rows + hairline
//      render.
//   3. Each of the three newly-wired edit rows («Про салон» / «Локація» /
//      «Контакти») pushes its OWN distinct route — the headline case: these
//      routes had no entry point at all before this rebuild, so a swapped
//      wiring here would leave one permanently unreachable while looking
//      identical on screen (all three rows render, all three navigate
//      *somewhere*).
//   4. «Мої салони» and «Допомога» push their routes too (owner-only /
//      all-viewer respectively).
//   5. «Надіслані запрошення» renders but its `onTap` is a deliberate
//      Phase-21.11 no-op — tapping it must change no route.
//   6. «Загальне» forwards `AccountSettingsExtras(salonId, showDeleteSalon:
//      isOwner)` — asserted via the pushed screen's own resolved payload,
//      for both the owner (flag true) and the admin (flag false) case.
//   7. «Видалити салон» (`row-salon-delete`) and the superseded «Редагувати
//      профіль» (`row-salon-edit-profile`) are BOTH absent — regression pin
//      so a future edit cannot quietly reintroduce either.
//   8. The close button falls back to `RouteNames.salonManage` when there is
//      no history to pop (this router has none).
//   9. The logout row still raises the shared confirm dialog — proving the
//      row is wired to `runLogoutFlow`. The full logout mechanics (secure
//      storage wipe, double-tap guard, failure snack, …) are exhaustively
//      covered by `settings_hub_screen_test.dart` and
//      `settings_screen_test.dart` against the SAME shared helper; repeating
//      that whole suite here would be pure duplication, not new coverage.
//
// Finders use widget Keys — never Cyrillic literals (M2 / `forbid_cyrillic_
// finder`). Layer: Widget.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/settings/domain/account_settings_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';

const _stubOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

const _stubAdmin = User(
  id: 'admin-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Бойко',
);

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: _user, accessToken: 'tok');
}

/// Router rooted at the salon settings hub with sentinel stub destinations
/// for every route the hub can push — mirrors `settings_hub_screen_test.dart`'s
/// proven shape. Each sentinel key embeds the captured `:salonId` so a test
/// pins the SPECIFIC route resolved, not merely "some screen appeared".
GoRouter _router() => GoRouter(
  initialLocation: '/salons/$_kSalonId/manage/settings',
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/manage/settings',
      builder: (context, state) =>
          SalonSettingsScreen(salonId: state.pathParameters['salonId']!),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/profile-edit',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-about-${state.pathParameters['salonId']}'),
        ),
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/address-edit',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-location-${state.pathParameters['salonId']}'),
        ),
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings/contacts-edit',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-contacts-${state.pathParameters['salonId']}'),
        ),
      ),
    ),
    GoRoute(
      path: '/salons/mine',
      builder: (context, state) =>
          const Scaffold(body: SizedBox(key: Key('stub-my-salons'))),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) {
        final Object? extra = state.extra;
        final AccountSettingsExtras? typed = extra is AccountSettingsExtras
            ? extra
            : null;
        return Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(key: Key('stub-account')),
              SizedBox(key: Key('stub-account-salonId-${typed?.salonId}')),
              if (typed?.showDeleteSalon ?? false)
                const SizedBox(key: Key('stub-account-show-delete-salon')),
            ],
          ),
        );
      },
    ),
    GoRoute(
      path: '/support/contact',
      builder: (context, state) =>
          const Scaffold(body: SizedBox(key: Key('stub-help'))),
    ),
    GoRoute(
      path: '/salons/:salonId/manage',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-manage-${state.pathParameters['salonId']}'),
        ),
      ),
    ),
  ],
);

List<Object> _overrides(User user) => <Object>[
  authProvider.overrideWith(() => _StubAuthNotifier(user)),
];

/// The eight row keys the screen renders for an OWNER, in the design's
/// declared order (plus the terminal hairline divider).
const List<String> _ownerOrderedKeys = <String>[
  'row-my-salons',
  'row-salon-about',
  'row-salon-location',
  'row-salon-contacts',
  'row-salon-sent-invites',
  'row-salon-general',
  'row-salon-help',
  'salon-settings-divider',
  'row-logout',
];

/// The rows an ADMIN sees — the owner-only quartet dropped, same relative
/// order for the rest.
const List<String> _adminOrderedKeys = <String>[
  'row-salon-sent-invites',
  'row-salon-general',
  'row-salon-help',
  'salon-settings-divider',
  'row-logout',
];

void main() {
  group('SalonSettingsScreen — owner view', () {
    testWidgets('all eight rows + the hairline render in design order', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      for (final key in _ownerOrderedKeys) {
        expect(
          find.byKey(Key(key)),
          findsOneWidget,
          reason: '$key must render for the owner',
        );
      }

      // Order: each row's top edge must sit strictly below the previous
      // row's — a vacuous "all present" check cannot catch a reordered list.
      double previousDy = -1;
      for (final key in _ownerOrderedKeys) {
        final double dy = tester.getTopLeft(find.byKey(Key(key))).dy;
        expect(
          dy,
          greaterThan(previousDy),
          reason: '$key must render BELOW the preceding row (design order)',
        );
        previousDy = dy;
      }
    });
  });

  group('SalonSettingsScreen — admin view (owner gating)', () {
    testWidgets(
      'owner-only rows (my-salons / about / location / contacts) are absent',
      (tester) async {
        final router = _router();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router, overrides: _overrides(_stubAdmin));
        await tester.pumpAndSettle();

        for (final key in <String>[
          'row-my-salons',
          'row-salon-about',
          'row-salon-location',
          'row-salon-contacts',
        ]) {
          expect(
            find.byKey(Key(key)),
            findsNothing,
            reason: '$key is owner-only and must not render for an admin',
          );
        }
      },
    );

    testWidgets('the four all-viewer rows still render for an admin', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubAdmin));
      await tester.pumpAndSettle();

      for (final key in _adminOrderedKeys) {
        expect(
          find.byKey(Key(key)),
          findsOneWidget,
          reason: '$key must still render for an admin',
        );
      }
    });
  });

  group('navigation — owner-only edit rows push distinct routes', () {
    // (rowKey, destinationSentinelKey) — the three edit rows are the
    // headline case: wired to the SAME target by mistake, this table would
    // still show three green rows while two of the three edit screens stay
    // unreachable.
    const cases = <(String, String)>[
      ('row-my-salons', 'stub-my-salons'),
      ('row-salon-about', 'stub-about-$_kSalonId'),
      ('row-salon-location', 'stub-location-$_kSalonId'),
      ('row-salon-contacts', 'stub-contacts-$_kSalonId'),
    ];

    for (final (rowKey, destKey) in cases) {
      testWidgets('tapping $rowKey pushes to $destKey', (tester) async {
        final router = _router();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(Key(rowKey)));
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key(destKey)),
          findsOneWidget,
          reason: '$rowKey must push the route whose screen carries $destKey',
        );
      });
    }
  });

  group('navigation — «Допомога»', () {
    testWidgets('tapping row-salon-help pushes to contactSupport', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-salon-help')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-salon-help')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-help')), findsOneWidget);
    });
  });

  group('navigation — «Надіслані запрошення» placeholder', () {
    testWidgets('renders but tapping it changes no route (Phase 21.11 no-op)', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-salon-sent-invites')), findsOneWidget);
      final String before = router.routeInformationProvider.value.uri
          .toString();

      await tester.tap(find.byKey(const Key('row-salon-sent-invites')));
      await tester.pumpAndSettle();

      final String after = router.routeInformationProvider.value.uri.toString();
      expect(
        after,
        before,
        reason:
            'the invites row is a Phase 21.11 placeholder — tapping it must '
            'not change the resolved route',
      );
      // Still on the hub — none of the sentinel destinations were reached.
      expect(find.byKey(const Key('row-salon-general')), findsOneWidget);
    });
  });

  group('navigation — «Загальне» forwards showDeleteSalon', () {
    testWidgets('owner: forwards salonId AND showDeleteSalon: true', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-general')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-account')), findsOneWidget);
      expect(
        find.byKey(const Key('stub-account-salonId-$_kSalonId')),
        findsOneWidget,
        reason: 'the account page must receive the salon id regardless of role',
      );
      expect(
        find.byKey(const Key('stub-account-show-delete-salon')),
        findsOneWidget,
        reason: 'an owner must forward showDeleteSalon: true',
      );
    });

    testWidgets('admin: forwards salonId but showDeleteSalon: false', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubAdmin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-general')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-account')), findsOneWidget);
      expect(
        find.byKey(const Key('stub-account-salonId-$_kSalonId')),
        findsOneWidget,
        reason: 'the account page must receive the salon id regardless of role',
      );
      expect(
        find.byKey(const Key('stub-account-show-delete-salon')),
        findsNothing,
        reason: 'an admin must NOT forward showDeleteSalon: true',
      );
    });
  });

  group('regression — superseded rows never come back', () {
    testWidgets(
      'row-salon-delete and row-salon-edit-profile are absent for the owner',
      (tester) async {
        final router = _router();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('row-salon-delete')), findsNothing);
        expect(find.byKey(const Key('row-salon-edit-profile')), findsNothing);
      },
    );

    testWidgets(
      'row-salon-delete and row-salon-edit-profile are absent for an admin',
      (tester) async {
        final router = _router();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router, overrides: _overrides(_stubAdmin));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('row-salon-delete')), findsNothing);
        expect(find.byKey(const Key('row-salon-edit-profile')), findsNothing);
      },
    );
  });

  group('close button', () {
    testWidgets(
      'falls back to RouteNames.salonManage when there is no history to pop',
      (tester) async {
        final router = _router();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-close-salon-settings')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stub-manage-$_kSalonId')), findsOneWidget);
      },
    );
  });

  group('logout row', () {
    testWidgets('tapping row-logout raises the shared confirm dialog', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byKey(const Key('btn-logout-cancel')), findsOneWidget);
      expect(find.byKey(const Key('btn-logout-confirm')), findsOneWidget);
    });
  });
}
