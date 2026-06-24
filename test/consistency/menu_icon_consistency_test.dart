// Cross-screen shared-icon consistency guard.
//
// PURPOSE
// -------
// The bug that prompted this file: MasterProfileScreen and HomeHubScreen
// used *different* icons for their "settings/menu" burger buttons after a
// Phase 13.7 change. Neither screen's own widget test caught it because each
// test only asserted its *own* icon in isolation — there was no test that
// pumped both screens and compared the two.
//
// This file closes that gap. It:
//   1. Pumps MasterProfileScreen, finds Key('btn-menu-master'), reads the
//      rendered Icon's IconData.
//   2. Pumps the shared ClientTopBar in its home-branch config (the burger the
//      shell-owned bar mounts on /home — 2026-06-24 wordmark-jump hoist moved
//      it out of HomeHubScreen), finds Key('btn-menu-client'), reads its Icon's
//      IconData.
//   3. Asserts both are equal to BeauticaIcons.menuBurger (Icons.tune_rounded).
//   4. Asserts they are equal to each other — so a future change to one
//      without the other fails immediately.
//
// HOW TO EXTEND
// -------------
// When a new shared icon is introduced (e.g. the notification bell that both
// the client home hub and a future master dashboard will use):
//   1. Add a `static const IconData bellIcon = ...` to BeauticaIcons in
//      `lib/core/theme/beautica_icons.dart`.
//   2. Add a test group below following the same 4-step pattern.
//   3. Update the comment above to list the new scenario.
//
// WHAT NOT TO ADD HERE
// --------------------
// Icons that are intentionally different per role (e.g. the role-select
// glyphs) do NOT belong here. This file guards *convergence*, not *identity*.

import 'package:beautica_mobile/core/theme/beautica_icons.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Stub auth notifier (INDEPENDENT_MASTER session; no network)
// ---------------------------------------------------------------------------

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Тест',
  lastName: 'Майстер',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubUser, accessToken: 'tok');
}

// ---------------------------------------------------------------------------
// Stub master-profile notifier (loads a minimal Master; no network)
// ---------------------------------------------------------------------------

const _stubMaster = Master(
  id: 'user-1',
  firstName: 'Тест',
  lastName: 'Майстер',
  avgRating: 0,
  reviewCount: 0,
  type: MasterType.independentMaster,
);

class _StubMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => _stubMaster;
}

// ---------------------------------------------------------------------------
// Stub repositories for services list (MasterProfileScreen renders live
// service counts via servicesListProvider, which depends on
// serviceRepositoryProvider)
// ---------------------------------------------------------------------------

class _FakeMasterRepository extends Fake implements MasterRepository {
  @override
  Future<Master> getMyProfile(String masterId) async => _stubMaster;
}

class _FakeServiceRepository extends Fake implements ServiceRepository {
  @override
  Future<List<MasterService>> listMyServices() async => const <MasterService>[];

  @override
  Future<List<ServiceCategoryOption>> fetchApprovedCategories() async =>
      const <ServiceCategoryOption>[];

  @override
  Future<List<ServiceTypeOption>> fetchServiceTypes(
    String categoryName,
  ) async => const <ServiceTypeOption>[];
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

/// Minimal override set for MasterProfileScreen.
///
/// The burger button is rendered in ProfileScaffold's top bar which is
/// always present (not gated on AsyncValue state), so we only need the
/// profile and service providers to be non-null.
List<Object> _masterProfileOverrides() => [
  authProvider.overrideWith(() => _StubAuthNotifier()),
  masterProfileProvider.overrideWith(() => _StubMasterProfileNotifier()),
  masterRepositoryProvider.overrideWithValue(_FakeMasterRepository()),
  serviceRepositoryProvider.overrideWithValue(_FakeServiceRepository()),
];

/// The shared [ClientTopBar] in its home-branch config — the burger the
/// shell-owned bar mounts on /home (Key 'btn-menu-client', the preserved home
/// burger Key). The 2026-06-24 wordmark-jump hoist moved the bar out of
/// HomeHubScreen into ClientShell, so the client burger icon is now sourced
/// from the bar widget directly (its config drives the same BeauticaIcons
/// constant either way — that constant identity is exactly what this file
/// pins).
Widget _clientHomeTopBar() => ClientTopBar(
  onBell: () {},
  onBurger: () {},
  bellSemanticLabel: 'Сповіщення',
  burgerSemanticLabel: 'Меню',
  bellKey: const Key('home_hub_bell_button'),
  burgerKey: const Key('btn-menu-client'),
);

// ---------------------------------------------------------------------------
// Helper: extract the IconData from the Icon inside a NeumorphicIconButton
// identified by its key. Fails loudly if the key or the Icon is not found.
//
// IMPORTANT: we scope the Icon search to the keyed NeumorphicIconButton's own
// subtree — not to all NeumorphicIconButtons in the tree (there may be several:
// back button, bell, burger). The approach:
//   1. Find the NeumorphicIconButton by key.
//   2. Find the first Icon that is a descendant of THAT specific instance.
// ---------------------------------------------------------------------------

IconData _iconDataAt(WidgetTester tester, Key key) {
  // Step 1: locate the keyed NeumorphicIconButton.
  final Finder buttonFinder = find.byKey(key);
  expect(
    buttonFinder,
    findsOneWidget,
    reason: 'Expected to find a NeumorphicIconButton with key $key in the tree',
  );

  // Step 2: within that button's subtree, find the rendered Icon widget.
  // NeumorphicIconButton.build renders: GestureDetector > Container > Icon(icon, ...)
  final Finder iconFinder = find.descendant(
    of: buttonFinder,
    matching: find.byType(Icon),
  );
  expect(
    iconFinder,
    findsOneWidget,
    reason:
        'Expected exactly one Icon widget inside the NeumorphicIconButton '
        'with key $key',
  );

  final Icon iconWidget = tester.widget<Icon>(iconFinder);
  return iconWidget.icon!;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── menuBurger icon guard ────────────────────────────────────────────────
  //
  // The "tune_rounded" icon (BeauticaIcons.menuBurger) must be rendered by
  // BOTH the master profile top bar AND the client home hub top bar.
  //
  // If either screen is changed to use a different icon without updating the
  // other (or without updating BeauticaIcons.menuBurger), exactly one of the
  // three assertions below will fail — pointing to the divergence precisely.

  group(
    'menuBurger icon consistency — MasterProfileScreen vs HomeHubScreen',
    () {
      late IconData masterBurgerIcon;
      late IconData clientBurgerIcon;

      testWidgets(
        'MasterProfileScreen btn-menu-master renders BeauticaIcons.menuBurger',
        (tester) async {
          // Arrange + Act: pump the master profile screen and settle.
          await tester.pumpApp(
            const MasterProfileScreen(),
            overrides: _masterProfileOverrides(),
          );
          // One pump is enough — the ProfileScaffold top bar is always present
          // on the first frame (not gated on AsyncValue state).
          await tester.pump();

          // Assert: the burger button is in the tree with the expected icon.
          masterBurgerIcon = _iconDataAt(tester, const Key('btn-menu-master'));
          expect(
            masterBurgerIcon,
            equals(BeauticaIcons.menuBurger),
            reason:
                'MasterProfileScreen top-bar burger (btn-menu-master) must use '
                'BeauticaIcons.menuBurger (Icons.tune_rounded). '
                'If you changed the icon on this screen, update BeauticaIcons '
                'AND the HomeHubScreen burger in the same commit.',
          );
        },
      );

      testWidgets(
        'CLIENT home top bar btn-menu-client renders BeauticaIcons.menuBurger',
        (tester) async {
          // Arrange + Act: pump the shell-owned bar in its home-branch config.
          await tester.pumpApp(_clientHomeTopBar());
          await tester.pump();

          // Assert: the burger button is in the tree with the expected icon.
          clientBurgerIcon = _iconDataAt(tester, const Key('btn-menu-client'));
          expect(
            clientBurgerIcon,
            equals(BeauticaIcons.menuBurger),
            reason:
                'CLIENT home top-bar burger (btn-menu-client) must use '
                'BeauticaIcons.menuBurger (Icons.tune_rounded). '
                'If you changed the icon on this bar, update BeauticaIcons '
                'AND the MasterProfileScreen burger in the same commit.',
          );
        },
      );

      testWidgets('master and client burger icons are equal to each other', (
        tester,
      ) async {
        // Pump master profile screen. Clear the tree between the two pumps
        // with pumpWidget(SizedBox.shrink()) so Riverpod does not complain
        // about changing the override count between consecutive pumpApp calls
        // (Riverpod asserts override count stability within a single
        // ProviderScope lifetime — clearing the tree tears down the scope).

        // --- Master profile ---
        await tester.pumpApp(
          const MasterProfileScreen(),
          overrides: _masterProfileOverrides(),
        );
        await tester.pump();
        masterBurgerIcon = _iconDataAt(tester, const Key('btn-menu-master'));

        // Tear down the current ProviderScope before pumping the next surface
        // with a different override set. Without this, Riverpod asserts
        // "_debugOverridesLength == overrides.length" and fails the test.
        await tester.pumpWidget(const SizedBox.shrink());

        // --- CLIENT home top bar (shell-owned bar, home config) ---
        await tester.pumpApp(_clientHomeTopBar());
        await tester.pump();
        clientBurgerIcon = _iconDataAt(tester, const Key('btn-menu-client'));

        // The cross-screen equality assertion: this is the test that would
        // have caught the original Phase 13.7 divergence. One icon changing
        // without the other is caught here even if BeauticaIcons is not yet
        // updated (defence-in-depth).
        expect(
          masterBurgerIcon,
          equals(clientBurgerIcon),
          reason:
              'The top-bar burger icon must be identical across MasterProfile '
              'and HomeHub. A divergence here means one screen was updated '
              'without the other. Fix by either: (a) restoring the icon in the '
              'changed screen, or (b) updating BeauticaIcons.menuBurger and '
              'both call sites together.',
        );
      });
    },
  );
}
