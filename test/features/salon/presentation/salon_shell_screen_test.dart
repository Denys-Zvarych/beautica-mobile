// Phase 21.8 QA follow-up — widget tests for [SalonShellScreen].
//
// Before this file the shell had almost no direct coverage: only the
// router-tier `role_landing_chrome_test.dart` mounted it, and only through
// ONE fixture (a salon the owner already owns) that never exercises tab
// switching, the LAZY TABS mechanism, or the provider's per-salonId reset.
//
// NAV INDEX vs STACK SLOT (mobile-perf LOW follow-up, 2026-08-30)
// ---------------------------------------------------------------
// The shell no longer mounts one `IndexedStack` child per nav destination.
// «Салон» (nav 0) and «Команда» (nav 2) used to be two byte-identical
// `SalonManagementProfileScreen` configurations differing only by `Key`, so
// one of them was always offstage re-rendering what the user was already
// looking at. They now share ONE host, and the stack has 3 children:
//
//   nav 0 «Салон» ─┬─> stack slot 0 (the one profile host)
//   nav 2 «Команда»┘
//   nav 1 «Записи» ──> stack slot 1
//   nav 3 «Профіль»──> stack slot 2
//
// Assertions below therefore distinguish the two index spaces explicitly:
// `SalonBottomNav.currentIndex` is a NAV index (0..3), `IndexedStack.index`
// is a STACK SLOT (0..2). Conflating them is the bug this note exists to
// prevent a future reader from reintroducing.
//
// Covers:
//   1. Салон renders by default; Записи/Профіль are lazy (`SizedBox.shrink`)
//      until first visited.
//   2. Tapping each `SalonBottomNav` tile switches the visible body to the
//      MAPPED `IndexedStack.index`, while the nav highlight keeps the nav
//      index.
//   3. Exactly ONE `SalonManagementProfileScreen` exists in the tree, serving
//      both «Салон» and «Команда», controlled from the shared
//      `salonManageTabProvider` value (the dedupe itself).
//   4. Once visited, a slot's real widget REPLACES the lazy placeholder
//      permanently (not just for the one frame it was selected).
//   5. Switching away and back to a visited slot preserves that slot's State
//      object — the whole point of the lazy-but-never-disposed design
//      (`IndexedStack` never uses Offstage/TickerMode for its non-current
//      children, so nothing here needs `AutomaticKeepAliveClientMixin`) —
//      and, since «Салон»/«Команда» are now one child, moving between THOSE
//      two destinations must not re-mount anything at all.
//   6. `salonShellProvider` is family-keyed on `salonId` — selecting a tab
//      for one salon leaves a DIFFERENT salon's provider instance untouched
//      at its default (0).
//
// Ownership-bounce coverage (the H1b double-mount hazard + the AsyncData
// concrete-subtype gate) lives in `role_landing_chrome_test.dart` (H1b) and
// its own regression group below — see that file and
// `salon_management_profile_screen_test.dart` for the sibling gate.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_shell_provider.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/owner_own_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_shell_tab_placeholder.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kSalonId = 'shell-salon-1';
const String _kOtherSalonId = 'shell-salon-2';

const _stubOwner = User(
  id: 'owner-shell-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власник',
);

const _stubAdmin = User(
  id: 'admin-shell-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Адміністратор',
  salonId: _kSalonId,
);

const _stubSalon = Salon(id: _kSalonId, name: 'Salon Shell Test');

class _OwnerAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

class _AdminAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubAdmin, accessToken: 'tok');
}

/// [MySalons] stub that resolves immediately to a list CONTAINING
/// [_kSalonId] — the owner genuinely owns the shell's salon, so
/// `_bounceIfNotOwned` never fires and does not interfere with the tab
/// mechanics under test here.
class _OwnedMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_stubSalon];
}

/// [SalonManagementProfile] stub that resolves immediately — settles both
/// the Салон and Команда tabs (same family key, `_kSalonId`) off the real
/// Dio stack.
class _SettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_stubSalon, const <SalonStaffMember>[]);
}

List<Object> _ownerOverrides() => <Object>[
  authProvider.overrideWith(_OwnerAuthNotifier.new),
  mySalonsProvider.overrideWith(_OwnedMySalons.new),
  salonManagementProfileProvider(
    _kSalonId,
  ).overrideWith(_SettledSalonManagementProfile.new),
];

List<Object> _adminOverrides() => <Object>[
  authProvider.overrideWith(_AdminAuthNotifier.new),
  salonManagementProfileProvider(
    _kSalonId,
  ).overrideWith(_SettledSalonManagementProfile.new),
];

/// The shell's `IndexedStack` — its `index` is a STACK SLOT, never a nav
/// index (see the file-header mapping note).
IndexedStack _stack(WidgetTester tester) =>
    tester.widget<IndexedStack>(find.byType(IndexedStack));

/// The shell's current bottom-nav highlight — a NAV index (0..3).
int _navIndex(WidgetTester tester) => tester
    .widget<SalonBottomNav>(find.byKey(const Key('salon-shell-bottom-nav')))
    .currentIndex;

void main() {
  group('nav index -> stack slot mapping (the 2026-08-30 dedupe)', () {
    testWidgets('the stack holds exactly 3 children and exactly ONE '
        'SalonManagementProfileScreen, shared by «Салон» and «Команда»', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _ownerOverrides(),
      );
      await tester.pumpAndSettle();

      // 3, not 4: «Салон» and «Команда» collapsed onto one child. If a
      // future edit re-forks them this goes to 4 and fails here first.
      expect(_stack(tester).children, hasLength(3));

      // THE DEDUPE ASSERTION. `skipOffstage: false` is what makes it real:
      // the old shape kept its duplicate host OFFSTAGE, so a default finder
      // would have reported `findsOneWidget` for the two-instance tree too
      // (mobile-qa M14 — a finder that cannot see the thing it is checking
      // is a vacuous assertion in disguise).
      expect(
        find.byType(SalonManagementProfileScreen, skipOffstage: false),
        findsOneWidget,
        reason:
            'nav 0 and nav 2 must be two views of ONE hosted screen — a '
            'second, offstage instance is a full duplicate render of what '
            'the user is already looking at',
      );

      // Both destinations resolve to the SAME stack slot, while the nav
      // highlight keeps the destination the user actually chose.
      expect(_stack(tester).index, 0);
      expect(_navIndex(tester), 0);

      await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
      await tester.pumpAndSettle();

      expect(
        _stack(tester).index,
        0,
        reason: '«Команда» (nav 2) maps to stack slot 0 — the shared host',
      );
      expect(
        _navIndex(tester),
        2,
        reason:
            'the nav highlight must stay the NAV index; passing the stack '
            'slot here would light «Салон» while standing on «Команда»',
      );
      expect(
        find.byType(SalonManagementProfileScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'and visiting «Команда» must not construct a second host',
      );

      // The other two destinations map to their own slots.
      await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
      await tester.pumpAndSettle();
      expect(_stack(tester).index, 1);
      expect(_navIndex(tester), 1);

      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(_stack(tester).index, 2);
      expect(
        _navIndex(tester),
        3,
        reason: 'nav 3 renders stack slot 2 — the two indices diverge here',
      );
    });
  });

  group('default tab + lazy construction', () {
    testWidgets('Салон renders by default; the Записи/Профіль slots are lazy '
        'placeholders until visited', (tester) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _ownerOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SalonBottomNav), findsOneWidget);
      expect(find.byKey(const Key('salon-shell-slot-profile')), findsOneWidget);
      // The other 2 slots are still the trivial lazy placeholder — the real
      // hosts have never been built. `skipOffstage: false` is REQUIRED here:
      // `IndexedStack` keeps its non-current children mounted but marks them
      // offstage, and `find.byKey`'s default `skipOffstage: true` silently
      // excludes them — without this the assertion would pass (or fail)
      // for the wrong reason regardless of whether the lazy child is really
      // there (mobile-qa M14: a finder that can't see the thing it is
      // checking is a vacuous assertion in disguise).
      //
      // These keys say `slot`, not `tab`: they are indexed by STACK SLOT, so
      // slot 1 is «Записи» (nav 1) and slot 2 is «Профіль» (nav 3).
      expect(
        find.byKey(const Key('salon-shell-slot-1-lazy'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-shell-slot-2-lazy'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byType(SalonShellTabPlaceholder, skipOffstage: false),
        findsNothing,
      );
      // Slot 0 is NOT lazy on the first frame — it is the seeded destination,
      // exactly as it was before the dedupe (which removed a build, not added
      // one).
      expect(
        find.byKey(const Key('salon-shell-slot-0-lazy'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
      'visiting «Команда» does NOT build the «Записи»/«Профіль» slots — the '
      'shared host must not make its siblings eager',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-shell-slot-1-lazy'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-shell-slot-2-lazy'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(SalonShellTabPlaceholder, skipOffstage: false),
          findsNothing,
        );
      },
    );
  });

  group('tab switching (IndexedStack via SalonBottomNav taps)', () {
    testWidgets('tapping each nav item switches the visible body', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _ownerOverrides(),
      );
      await tester.pumpAndSettle();

      // Nav 1 — Записи (stack slot 1).
      await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-shell-tab-bookings')), findsOneWidget);
      // The lazy placeholder key is GONE (not merely offstage) — visiting a
      // slot replaces it permanently, per the file-header LAZY SLOTS note.
      expect(
        find.byKey(const Key('salon-shell-slot-1-lazy'), skipOffstage: false),
        findsNothing,
      );

      // Nav 2 — Команда (stack slot 0, the shared host).
      await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-shell-slot-profile')), findsOneWidget);
      expect(_stack(tester).index, 0);

      // Nav 3 — Профіль (owner suffix, stack slot 2).
      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-shell-tab-profile-owner')),
        findsOneWidget,
      );

      // Back to nav 0 — Салон. The point of the lazy-but-never-disposed
      // design: both previously-visited placeholder slots must STILL be
      // mounted (offstage, not removed) — `skipOffstage: false` proves
      // presence rather than accepting the vacuous "not currently visible"
      // reading `findsNothing` would give by default.
      await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-shell-slot-profile')), findsOneWidget);
      expect(
        find.byKey(const Key('salon-shell-tab-bookings'), skipOffstage: false),
        findsOneWidget,
        reason: 'a previously-visited slot must remain MOUNTED, just offstage',
      );
      expect(
        find.byKey(
          const Key('salon-shell-tab-profile-owner'),
          skipOffstage: false,
        ),
        findsOneWidget,
        reason: 'a previously-visited slot must remain MOUNTED, just offstage',
      );
      // …and there is still only the one profile host behind all of it.
      expect(
        find.byType(SalonManagementProfileScreen, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('the owner Профіль slot is told whether it is the VISIBLE '
        'one', (tester) async {
      // mobile-perf MEDIUM + LOW (2026-08-31). A raw `IndexedStack` sets
      // neither `Offstage` nor `TickerMode` on its non-current children, so
      // the retained slot-2 screen has no way to learn it went off-screen —
      // it kept ticking its 950 ms entrance on an unpainted subtree (burning
      // the one-shot guard, so the FIRST REAL VIEW had no entrance) and kept
      // holding the PII screen-protection refcount across every other salon
      // tab. The shell owns the index, so the shell passes the signal down.
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _ownerOverrides(),
      );
      await tester.pumpAndSettle();

      // Visit Профіль — the slot is built and is the current one.
      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OwnerOwnProfileScreen>(
              find.byKey(const Key('salon-shell-tab-profile-owner')),
            )
            .visible,
        isTrue,
      );

      // Tab away. The slot stays MOUNTED (never disposed) — and must now be
      // told it is not the visible one.
      await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OwnerOwnProfileScreen>(
              find.byKey(
                const Key('salon-shell-tab-profile-owner'),
                skipOffstage: false,
              ),
            )
            .visible,
        isFalse,
        reason:
            'the retained off-screen slot must be told it is off-screen — '
            'see OwnerOwnProfileScreen.visible for the two defects this '
            'closes',
      );

      // …and told again when the user comes back.
      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OwnerOwnProfileScreen>(
              find.byKey(const Key('salon-shell-tab-profile-owner')),
            )
            .visible,
        isTrue,
      );
    });

    testWidgets('admin Профіль tab uses the admin key suffix', (tester) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _adminOverrides(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-shell-tab-profile-admin')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-shell-tab-profile-owner')),
        findsNothing,
      );
    });
  });

  group('Салон vs Команда controlled sub-tab', () {
    testWidgets(
      'the ONE hosted SalonManagementProfileScreen is CONTROLLED from the '
      'shared salonManageTabProvider value, and the nav destination is what '
      'moves it (the former one-way initialTab seed is gone)',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        final host = tester.widget<SalonManagementProfileScreen>(
          find.byKey(const Key('salon-shell-slot-profile')),
        );
        expect(host.tab, equals(0));
        expect(host.onTabSelected, isNotNull);
        expect(host.embedded, isTrue);
        expect(host.salonId, equals(_kSalonId));

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();

        // The SAME child — nav 2 maps to the same stack slot — now driven to
        // the staff sub-tab. There is no second widget to read here any more,
        // which is the dedupe: the two destinations cannot disagree about the
        // sub-tab because there is only one of them to disagree.
        final hostOnTeam = tester.widget<SalonManagementProfileScreen>(
          find.byKey(const Key('salon-shell-slot-profile')),
        );
        expect(hostOnTeam.tab, equals(1));
        expect(hostOnTeam.onTabSelected, isNotNull);
        expect(hostOnTeam.embedded, isTrue);
        expect(hostOnTeam.salonId, equals(_kSalonId));
        expect(
          find.byType(SalonManagementProfileScreen, skipOffstage: false),
          findsOneWidget,
          reason:
              'no offstage twin may be left behind holding the previous '
              'sub-tab — that twin was FINDING 1',
        );

        // Back to «Салон»: the same child is re-driven to «Про салон». Under
        // the old two-instance shape this is where slot 0 could come back
        // still showing the staff grid.
        await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SalonManagementProfileScreen>(
                find.byKey(const Key('salon-shell-slot-profile')),
              )
              .tab,
          equals(0),
        );
      },
    );
  });

  group('in-screen tab row <-> bottom nav sync', () {
    /// Alias for the file-level helper — the shell's current bottom-nav
    /// highlight, a NAV index.
    int navIndex(WidgetTester tester) => _navIndex(tester);

    testWidgets(
      'tapping the IN-SCREEN «Команда» tab moves the bottom-nav highlight to '
      'the «Команда» destination (the reported bug: it used to stay put)',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();
        expect(navIndex(tester), equals(0));

        // The in-screen switcher of the one hosted profile screen. There is
        // only ever one `salon-tab-1` in the tree now, so the default
        // `skipOffstage: true` is belt-and-braces rather than load-bearing.
        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();

        expect(navIndex(tester), equals(2));
        // The STACK does not move: nav 2 renders the same slot 0 as nav 0
        // (see the file-header mapping). Asserting `2` here would be reading
        // the nav index off the wrong object — precisely the conflation the
        // dedupe makes possible to get wrong.
        expect(_stack(tester).index, equals(0));
      },
    );

    testWidgets(
      'the mirror case: from «Команда», tapping an in-screen non-staff tab '
      'moves the nav highlight back to «Салон»',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();
        expect(navIndex(tester), equals(2));

        // «Послуги» (sub-tab 2) — not «Про салон», to prove the rule is
        // "anything but the staff sub-tab", not "sub-tab 0".
        await tester.tap(find.byKey(const Key('salon-tab-2')));
        await tester.pumpAndSettle();

        expect(navIndex(tester), equals(0));
        expect(
          ProviderScope.containerOf(
            tester.element(find.byKey(const Key('salon-shell-screen'))),
          ).read(salonManageTabProvider(_kSalonId)),
          equals(2),
        );
      },
    );

    testWidgets(
      'a round trip through «Команда» leaves the «Салон» destination on its '
      'own «Про салон» sub-tab (IndexedStack never disposes slot 0, so an '
      'UNCONTROLLED host would have kept the staff grid)',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-tab-1')));
        await tester.pumpAndSettle();
        expect(navIndex(tester), equals(2));

        await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(navIndex(tester), equals(0));
        expect(
          tester
              .widget<SalonManagementProfileScreen>(
                find.byKey(const Key('salon-shell-slot-profile')),
              )
              .tab,
          equals(0),
        );
      },
    );
  });

  group('lazy child state survives switching away and back', () {
    /// The `State` of the one hosted profile screen, wherever it currently
    /// sits in the stack. `skipOffstage: false` because the caller may be
    /// standing on a placeholder destination at the time.
    State hostState(WidgetTester tester) => tester.state(
      find.byKey(const Key('salon-shell-slot-profile'), skipOffstage: false),
    );

    testWidgets(
      'the profile host keeps the SAME State instance after switching to '
      'another destination and back — proving IndexedStack never disposes it',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();
        final State before = hostState(tester);

        // Switch away to Салон, then to Записи, then BACK to Команда.
        await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(
          identical(before, hostState(tester)),
          isTrue,
          reason:
              'the profile host\'s State must be the SAME object across a '
              'round trip through two other destinations — a fresh State '
              'here would mean the lazy child was rebuilt/disposed, '
              'defeating the documented "survives every subsequent switch" '
              'guarantee.',
        );
      },
    );

    testWidgets(
      'moving between «Салон» and «Команда» does not re-mount the shared host '
      'at all — same State object, same stack slot, no dispose/re-create',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        final State onSalon = hostState(tester);
        expect(_stack(tester).index, 0);

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();
        final State onTeam = hostState(tester);

        await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
        await tester.pumpAndSettle();
        final State backOnSalon = hostState(tester);

        expect(
          identical(onSalon, onTeam) && identical(onTeam, backOnSalon),
          isTrue,
          reason:
              'the two destinations share ONE child at ONE stack position '
              'under ONE const Key, so switching between them must be a '
              'prop change only — a new State object here would mean lost '
              'scroll position and re-triggered provider fetches on every '
              '«Салон»<->«Команда» tap.',
        );
        expect(
          _stack(tester).index,
          0,
          reason: 'and the stack slot never moved across the round trip',
        );
      },
    );
  });

  group('salonShellProvider family isolation', () {
    testWidgets('selecting a tab for one salonId leaves a DIFFERENT salonId\'s '
        'provider instance at its default (0)', (tester) async {
      final container = ProviderContainer(
        // ignore: avoid_dynamic_calls
        overrides: _ownerOverrides().cast(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('uk'),
            home: SalonShellScreen(salonId: _kSalonId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
      await tester.pumpAndSettle();

      expect(container.read(salonShellProvider(_kSalonId)), equals(2));
      expect(
        container.read(salonShellProvider(_kOtherSalonId)),
        equals(0),
        reason:
            'salonShellProvider is family-keyed on salonId — selecting a '
            'tab for $_kSalonId must never leak into a different salon\'s '
            'provider instance.',
      );
    });
  });

  // -------------------------------------------------------------------
  // mobile-qa gap-closure (2026-08-28) — the shell's OWN `_bounceIfNotOwned`
  // (`salon_shell_screen.dart:141`) gates on the SAME concrete `AsyncData`
  // subtype as `salon_management_profile_screen.dart`'s sibling listener
  // (see that file's own mutation-verified regression group) and
  // `app_router.dart`'s `salonManageGuard`. Pinned here with the identical
  // technique (driving `mySalonsProvider` directly via the notifier's own
  // `state` setter, bypassing `build()`, so the listener is never exposed to
  // an intermediate genuinely-resolved mismatched frame — see the sibling
  // file's group doc for why that intermediate shape is not the interesting
  // case).
  //
  // Sanity mutation-checked (not re-run as part of this suite): replacing
  // `if (next is! AsyncData<List<Salon>>) return;` with a bare
  // `final salons = next.value; if (salons == null) return;` in
  // `salon_shell_screen.dart` turns this test RED for the same reason the
  // sibling screen's mutation does.
  group('shell _bounceIfNotOwned does not trust a stale .value '
      '(mobile-security MEDIUM follow-up gap-closure)', () {
    testWidgets('AsyncError with a previous .value that does NOT contain the '
        'shell\'s salonId is treated as UNRESOLVED -> the shell stays '
        'mounted, never bounced on stale/wrong data', (tester) async {
      final container = ProviderContainer(
        // ignore: avoid_dynamic_calls
        overrides: _ownerOverrides().cast(),
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: RouteNames.salonShell(_kSalonId),
        routes: <RouteBase>[
          GoRoute(
            path: '/salons/:salonId/shell',
            builder: (context, state) =>
                SalonShellScreen(salonId: state.pathParameters['salonId']!),
          ),
          GoRoute(
            path: RouteNames.salonHome,
            builder: (context, state) =>
                const Scaffold(key: Key('shell-bounce-target')),
          ),
        ],
      );
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
      await tester.pumpAndSettle();

      expect(find.byType(SalonShellScreen), findsOneWidget);

      // Drive mySalonsProvider DIRECTLY into an AsyncError carrying a
      // stale, MISMATCHED .value via copyWithPrevious — see the sibling
      // regression group in `salon_management_profile_screen_test.dart`
      // for why this is the only public-API-reachable way to construct
      // this exact state shape, and why `copyWithPrevious` (`@internal`
      // to the riverpod package) is deliberately used here regardless.
      final AsyncError<List<Salon>> staleError = AsyncError<List<Salon>>(
        const NetworkFailure(),
        StackTrace.current,
      );
      const AsyncData<List<Salon>> stalePrevious = AsyncData<List<Salon>>(
        <Salon>[Salon(id: 'a-different-salon-entirely', name: 'Different')],
      );
      // ignore: invalid_use_of_internal_member
      container.read(mySalonsProvider.notifier).state = staleError
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(stalePrevious);
      await tester.pumpAndSettle();

      expect(
        container.read(mySalonsProvider),
        isA<AsyncError<List<Salon>>>(),
        reason:
            'the state must actually BE an AsyncError for this test to '
            'exercise the concrete-subtype gate at all',
      );
      expect(
        find.byType(SalonShellScreen),
        findsOneWidget,
        reason:
            'an AsyncError state — even one carrying a stale, '
            'non-owning .value — must be treated as UNRESOLVED and '
            'never bounce the shell away',
      );
      expect(find.byKey(const Key('shell-bounce-target')), findsNothing);
    });
  });
}
