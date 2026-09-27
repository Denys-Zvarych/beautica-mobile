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
//   5. «Надіслані запрошення» pushes `RouteNames.salonPendingInvites` —
//      wired in Phase 21.11, which replaced the Phase-21.9 no-op placeholder
//      this row shipped with. It is the ONLY all-viewer navigational row
//      whose destination is owner+admin (not owner-only), so the assertion
//      pins the resolved `:salonId` too.
//   6. «Загальне» forwards `AccountSettingsExtras(salonId, showDeleteSalon:
//      isOwner)` — asserted via the pushed screen's own resolved payload,
//      for both the owner (flag true) and the admin (flag false) case.
//   7. «Видалити салон» (`row-salon-delete`) and the superseded «Редагувати
//      профіль» (`row-salon-edit-profile`) are BOTH absent — regression pin
//      so a future edit cannot quietly reintroduce either.
//   8. The close button falls back to `RouteNames.salonManage` when there is
//      no history to pop (this router has none).
//   9. The context subheading (salon logo + name) renders the name off the
//      already-warm `salonManagementProfileProvider`, and DEGRADES SILENTLY —
//      a still-loading or errored family renders nothing at all (no spinner,
//      no error line, no orphan logo) and, critically, never displaces the
//      rows below it.
//  10. The logout row still raises the shared confirm dialog — proving the
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
import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/features/settings/domain/account_settings_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';

/// Deliberately Latin: the subheading renders the salon's own NAME — backend
/// data, identical in every locale — so a `find.text` on it is locale-safe.
/// A Cyrillic fixture here would read as a localized-copy finder and trip
/// `forbid_cyrillic_finder` for no benefit.
const String _kSalonName = 'Velvet Studio';

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
      path: '/salons/:salonId/pending-invites',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-pending-invites-${state.pathParameters['salonId']}'),
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

/// [SalonManagementProfile] stub resolving immediately to a named salon —
/// the state the context subheading renders from. Keeps the whole suite off
/// the real Dio stack: without it, watching the family from the subheading
/// would drive a live repository read in every test in this file.
class _SettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async => (
    const Salon(id: _kSalonId, name: _kSalonName),
    const <SalonStaffMember>[],
  );
}

/// [SalonManagementProfile] stub that never resolves — pins the subheading's
/// degradation contract against a family stuck in `AsyncLoading` (the
/// deep-link cold-start case), which must render nothing rather than a
/// spinner, a placeholder, or a reserved gap.
class _PendingSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) =>
      Completer<SalonManagementProfileData>().future;
}

/// [SalonManagementProfile] stub that fails — the subheading must swallow it
/// exactly like the loading case. `AsyncValue.value` (not `hasError`) is what
/// the widget reads, so this also pins that an errored family cannot leak an
/// error surface into a decorative row.
class _FailedSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      throw const NetworkFailure();
}

/// [SalonManagementProfile] stub resolving to a salon whose name is
/// WHITESPACE ONLY — the third absent-path branch
/// (`salon_settings_screen.dart:374`), and the only one that exercises the
/// `.trim()` guard rather than the `AsyncValue` shape: the family is a clean
/// `AsyncData` here, so `valueOrNull` hands the widget a real String and the
/// blankness check is the ONLY thing standing between it and a subheading
/// rendering a space as its monogram. Whitespace, not `''`, deliberately:
/// dropping the `.trim()` makes `'   '.isEmpty` false and this test RED,
/// whereas an empty-string fixture would stay green either way.
class _BlankNamedSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (const Salon(id: _kSalonId, name: '   '), const <SalonStaffMember>[]);
}

/// [SalonManagementProfile] stub whose resolution the test drives, so the
/// loading→resolved transition can be observed inside ONE mounted app.
class _ControlledSalonManagementProfile extends SalonManagementProfile {
  _ControlledSalonManagementProfile(this._future);

  final Future<SalonManagementProfileData> _future;

  @override
  Future<SalonManagementProfileData> build(String salonId) => _future;
}

List<Object> _overrides(
  User user, {
  SalonManagementProfile Function() profile =
      _SettledSalonManagementProfile.new,
}) => <Object>[
  authProvider.overrideWith(() => _StubAuthNotifier(user)),
  salonManagementProfileProvider(_kSalonId).overrideWith(profile),
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

  group('navigation — «Надіслані запрошення»', () {
    // Phase 21.11 wired this row; before that it was a deliberate no-op. The
    // sentinel key embeds the captured `:salonId`, so this pins the SPECIFIC
    // resolved route rather than merely "some screen appeared".
    testWidgets('owner: pushes the pending-invites route with this salonId', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-sent-invites')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stub-pending-invites-$_kSalonId')),
        findsOneWidget,
      );
    });

    // The row sits OUTSIDE the hub's owner-only block and its route is gated
    // by `salonManageGuard` (owner + admin), not the owner-only guard the
    // three edit-form rows use — so an admin must reach it too.
    testWidgets('admin: pushes the same route', (tester) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubAdmin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('row-salon-sent-invites')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stub-pending-invites-$_kSalonId')),
        findsOneWidget,
      );
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

  group('context subheading', () {
    testWidgets('renders the salon logo + name ABOVE the first row', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubOwner));
      await tester.pumpAndSettle();

      final Finder subheading = find.byKey(const Key('salon-settings-context'));
      expect(subheading, findsOneWidget);
      expect(
        find.descendant(of: subheading, matching: find.byType(SalonLogo)),
        findsOneWidget,
        reason: 'the subheading reuses the shared SalonLogo, not a fork',
      );
      expect(
        find.descendant(of: subheading, matching: find.text(_kSalonName)),
        findsOneWidget,
        reason: 'the name comes off salonManagementProfileProvider',
      );
      expect(
        tester.getTopLeft(subheading).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('row-my-salons'))).dy),
        reason: 'the subheading heads the list, above the first row',
      );
    });

    testWidgets('renders for an admin too (it is not owner-gated)', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router, overrides: _overrides(_stubAdmin));
      await tester.pumpAndSettle();

      // Asserts the same rendered PAYLOAD the owner case pins, not merely
      // that the key is present: an admin subheading that resolved to a bare
      // logo, or to a logo beside an empty label, is a real regression the
      // key alone cannot see.
      final Finder subheading = find.byKey(const Key('salon-settings-context'));
      expect(subheading, findsOneWidget);
      expect(
        find.descendant(of: subheading, matching: find.byType(SalonLogo)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: subheading, matching: find.text(_kSalonName)),
        findsOneWidget,
        reason:
            'the admin sees the salon NAME, not an unlabelled mark — the '
            'row is owner-ungated in its content as well as its presence',
      );
    });

    // The degradation contract: the row is decorative, so a family that has
    // not resolved (or has failed) renders NOTHING — no spinner, no skeleton,
    // no reserved gap — and never blocks the rows below.
    //
    // ONE app per test, deliberately: pumping a second `ProviderScope` into
    // the same tester reuses the first scope's Element and does NOT re-apply
    // a changed family override, so a "resolved app then degraded app"
    // comparison silently measures the resolved tree twice.
    for (final (label, stub) in <(String, SalonManagementProfile Function())>[
      ('loading', _PendingSalonManagementProfile.new),
      ('errored', _FailedSalonManagementProfile.new),
      ('blank-named', _BlankNamedSalonManagementProfile.new),
    ]) {
      testWidgets('$label: renders nothing, and every row still renders', (
        tester,
      ) async {
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(_stubOwner, profile: stub),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-settings-context')), findsNothing);

        // NOT merely "the resolved row is absent" — the absent path must
        // occupy EXACTLY zero height. `findsNothing` on the resolved key is
        // equally satisfied by a `SizedBox(height: 40)` skeleton standing in
        // its place, which is a reserved gap by any other name.
        final Finder absent = find.byKey(
          const Key('salon-settings-context-absent'),
        );
        expect(absent, findsOneWidget);
        expect(
          tester.getSize(absent).height,
          0.0,
          reason:
              'the absent path reserves NO vertical space at all — any '
              'non-zero height here is a phantom gap above the first row',
        );

        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: 'a decorative row never shows a loading affordance',
        );
        expect(
          find.byType(SalonLogo),
          findsNothing,
          reason: 'never an orphan logo with no name beside it',
        );

        // Absence never blocks the hub.
        for (final key in _ownerOrderedKeys) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
      });
    }

    // The non-vacuous half of the contract: the subheading DOES occupy real
    // height once it resolves, so "absent" above is genuinely "no reserved
    // gap" rather than "a zero-height row either way". Driven inside ONE app
    // by completing the family mid-test — which is also the real deep-link
    // cold-start sequence.
    testWidgets(
      'loading reserves NO space: the first row moves down only once the '
      'name arrives',
      (tester) async {
        final completer = Completer<SalonManagementProfileData>();
        addTearDown(() {
          if (!completer.isCompleted) {
            completer.complete((
              const Salon(id: _kSalonId, name: _kSalonName),
              const <SalonStaffMember>[],
            ));
          }
        });

        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: _overrides(
            _stubOwner,
            profile: () => _ControlledSalonManagementProfile(completer.future),
          ),
        );
        await tester.pumpAndSettle();

        final double loadingFirstRowDy = tester
            .getTopLeft(find.byKey(const Key('row-my-salons')))
            .dy;
        expect(find.byKey(const Key('salon-settings-context')), findsNothing);

        // PRIMARY pin — an absolute bound at zero, independent of every
        // other row's geometry.
        //
        // The earlier form of this test bounded the gap only RELATIVE to the
        // resolved tree (`resolvedDy > loadingDy`). That is weaker than it
        // reads: the resolved subheading is 58dp tall (34dp `SalonLogo` +
        // 24dp `VelvetSpacing.lg`), so `greaterThan` still passes for ANY
        // phantom gap below 58dp — a skeleton-sized reservation survives it
        // untouched. Mutating the absent path to `SizedBox(height: 40)` left
        // the whole suite green; only `height: 100` turned it red. Bound the
        // absent widget itself instead: `height == 0` admits nothing.
        final Finder absent = find.byKey(
          const Key('salon-settings-context-absent'),
        );
        expect(absent, findsOneWidget);
        expect(
          tester.getSize(absent).height,
          0.0,
          reason:
              'the absent path reserves NO vertical space at all — any '
              'non-zero height here is a phantom gap above the first row',
        );

        completer.complete((
          const Salon(id: _kSalonId, name: _kSalonName),
          const <SalonStaffMember>[],
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('salon-settings-context')), findsOneWidget);
        expect(absent, findsNothing);

        // SECONDARY, independent pin on the same fact, expressed as the
        // no-subheading control the absolute bound is derived from: the
        // first row's displacement must equal the resolved subheading's own
        // height EXACTLY, i.e. the loading tree contributed precisely zero.
        // Stated relationally it survives a future change to the
        // subheading's own dimensions, which a hard-coded 58.0 would not.
        expect(
          tester.getTopLeft(find.byKey(const Key('row-my-salons'))).dy -
              loadingFirstRowDy,
          moreOrLessEquals(
            tester
                .getSize(find.byKey(const Key('salon-settings-context')))
                .height,
            epsilon: 0.01,
          ),
          reason:
              'the ENTIRE downward shift of the first row is the resolved '
              'subheading itself; any smaller shift means the loading state '
              'had already reserved the difference',
        );
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
