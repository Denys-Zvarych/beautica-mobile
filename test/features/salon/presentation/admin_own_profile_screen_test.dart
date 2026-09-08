// Phase 21.16 — widget tests for [AdminOwnProfileScreen].
//
// WHAT IS COVERED WHERE, so the next reader does not duplicate:
//   • the four render states (data / loading / error / retry target), the
//     three conditional sections, the inert tune and the `embedded` back
//     affordance — HERE;
//   • `visible` threading from the shell, and the affiliation card's
//     return-to-«Салон» nav move — `salon_shell_screen_test.dart` (the shell
//     owns both, and a test that pumps this screen directly cannot observe
//     either);
//   • the pixels of the PROMOTED [StaffIdentityCard] this screen shares with
//     the owner and staff profiles — `test/golden/
//     staff_identity_card_golden_test.dart`.
//
// The salon section reads through ONE OF TWO providers, chosen by whether a
// host warmed the family (see `AdminOwnProfileScreen.hostSalonId`):
//   • no `hostSalonId` (the STAND-ALONE route, and every direct pump below) —
//     `salonDetailProvider(salonId)`, the single `GET /salons/{id}`;
//   • with `hostSalonId` (inside `SalonShellScreen`) —
//     `salonManagementProfileProvider(hostSalonId)`, already warm in slot 0.
// The fixtures below override whichever one the pump under test actually
// reaches, and the 'the family key comes from the HOST' group pins that the
// two never cross.

import 'dart:async';

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/login_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/splash_screen.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_detail_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/admin_own_profile_screen.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_master_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/fakes/fake_service_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/reveal_boundary.dart';

const String _kSalonId = 'salon-admin-1';

const User _admin = User(
  id: 'u-admin-1',
  email: 'admin@beautica.test',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Адміністратор',
  phoneNumber: '+380 97 111 11 11',
  // Present on the fixture on purpose: the admin profile must NOT render an
  // Instagram tile even when a handle exists (see the deny assertion below).
  instagram: '@iryna',
  professionalTitle: 'Старший адміністратор',
  salonId: _kSalonId,
);

const Salon _salon = Salon(id: _kSalonId, name: 'Вельвет');

/// Resolves the identity read immediately, off the real Dio stack.
class _SettledClientEditProfile extends ClientEditProfile {
  _SettledClientEditProfile(this.user);

  final User user;

  @override
  Future<User> build() async => user;
}

/// `/users/me` that FAILS the first time and succeeds afterwards — the exact
/// shape the retry affordance exists for. Records every attempt so the test
/// can count them.
///
/// The failure is thrown from an `async` body, never synchronously: a
/// Dio-backed repository always fails asynchronously, and a sync throw during
/// a provider build bypasses Riverpod's retry machinery entirely.
class _FlakyClientEditProfile extends ClientEditProfile {
  _FlakyClientEditProfile(this.log);

  final List<String> log;
  int _attempts = 0;

  @override
  Future<User> build() async {
    log.add('users/me');
    if (_attempts++ == 0) throw const ServerFailure();
    return _admin;
  }
}

/// How the STAND-ALONE `salonDetailProvider` read behaves in a given fixture.
///
/// `settled` is the happy path; the other two are the degradations the
/// section must swallow into an ABSENT card rather than a spinner or an error
/// box (see the screen's own header).
enum _SalonRead { settled, pending, failing }

/// The stand-alone single-salon override — `GET /salons/{id}` and nothing
/// else. This is what every DIRECT pump below reaches, because a direct pump
/// passes no `hostSalonId`.
Object _salonDetailOverride(_SalonRead read) =>
    salonDetailProvider(_kSalonId).overrideWith((Ref ref) {
      switch (read) {
        case _SalonRead.settled:
          return Future<Salon>.value(_salon);
        case _SalonRead.pending:
          final completer = Completer<Salon>();
          ref.onDispose(() {
            if (!completer.isCompleted) completer.complete(_salon);
          });
          return completer.future;
        case _SalonRead.failing:
          return Future<Salon>.error(const ServerFailure(), StackTrace.empty);
      }
    });

/// A management-family fixture that RECORDS the key it was built on.
///
/// The whole point of the host-key group below: a family element that is never
/// built leaves no entry, so the log is a direct read of WHICH element the
/// screen resolved.
class _LoggingSalonManagementProfile extends SalonManagementProfile {
  _LoggingSalonManagementProfile(this.log);

  final List<String> log;

  @override
  Future<SalonManagementProfileData> build(String salonId) async {
    log.add(salonId);
    return (_salon, const <SalonStaffMember>[]);
  }
}

List<Object> _overrides(
  User user, {
  _SalonRead salon = _SalonRead.settled,
}) => <Object>[
  clientEditProfileProvider.overrideWith(() => _SettledClientEditProfile(user)),
  _salonDetailOverride(salon),
];

// ---------------------------------------------------------------------------
// Router-group personas. Distinct from [_admin] (which is the PROFILE the
// screen renders) because a guard is about the SESSION's role.
// ---------------------------------------------------------------------------

const User _routerAdmin = User(
  id: 'u-admin-1',
  email: 'admin@beautica.test',
  role: UserRole.salonAdmin,
  salonId: _kSalonId,
);
const User _routerOwner = User(
  id: 'u-owner-1',
  email: 'owner@beautica.test',
  role: UserRole.salonOwner,
);

// mobile-qa Phase 21.16 gap closure (2026-09-05) — the three roles the
// original two-case group left unpinned. `salonAdminOnlyGuard` is a single
// `!=` against ONE role, so every non-admin role travels the SAME line; what
// differs per role is the DESTINATION `roleHomePath` computes, and a
// destination is exactly what a role-dispatch regression gets wrong while the
// guard itself still "works". See the group header for the full statement.
const User _routerSalonMaster = User(
  id: 'u-salon-master-1',
  email: 'salonmaster@beautica.test',
  role: UserRole.salonMaster,
);
const User _routerIndependentMaster = User(
  id: 'u-master-1',
  email: 'master@beautica.test',
  role: UserRole.independentMaster,
);
const User _routerClient = User(
  id: 'u-client-1',
  email: 'client@beautica.test',
  role: UserRole.client,
);

/// Pins the session to a fixed [AsyncValue] without touching platform channels.
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [AuthNotifier] whose session NEVER settles — the cold-start window in which
/// `authProvider` is `AsyncLoading`.
///
/// [_FixedAuthNotifier] cannot express this: its `build()` is an `async` body
/// that RETURNS, so Riverpod overwrites the `AsyncLoading` it assigns to
/// `state` with an `AsyncData` on the very next microtask, and the loading
/// branch under test would never be the state the redirect sees.
class _NeverSettlingAuthNotifier extends AuthNotifier {
  static final List<Completer<AuthSession>> pending =
      <Completer<AuthSession>>[];

  @override
  Future<AuthSession> build() {
    final completer = Completer<AuthSession>();
    pending.add(completer);
    return completer.future;
  }
}

/// [MySalons] stub that resolves IMMEDIATELY, so the OWNER bounce destination
/// never reaches the real Dio-backed repository.
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_salon];
}

/// [MasterProfile] stub that resolves immediately — settles the
/// INDEPENDENT_MASTER and SALON_MASTER bounce destinations without a real
/// `GET /masters/me`.
class _SettledMasterProfile extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: 'master-row-1',
    firstName: 'Тест',
    lastName: 'Майстер',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );
}

class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  // ---------------------------------------------------------------------
  // mobile-qa re-audit (cycle 2, 2026-09-05) — the REAL-TREE half of the
  // `RevealTransition` pin.
  //
  // `test/core/widgets/reveal_transition_test.dart` pins the widget's shape in
  // isolation. This group is the other claim its header makes: that a
  // per-call-site [Key] makes ONE section of a REAL, fully-loaded profile
  // addressable, so the boundary placement survives contact with a screen that
  // carries its own scrollables, heroes and page-route transitions.
  //
  // Before this existed, none of the 27 `*-profile-reveal-*` keys appeared in
  // any test — they were dead weight, and hoisting the boundary back outside
  // `SlideTransition` left the whole 1845-test suite green.
  //
  // The three admin keys are asserted by NAME rather than by counting
  // `find.byType(RevealTransition)`: a count would be a cardinality ledger
  // that fires on every future section added to the screen while saying
  // nothing about placement.
  // ---------------------------------------------------------------------
  group('the staggered entrance keeps its RepaintBoundary inside the '
      'transitions', () {
    testWidgets('every keyed reveal on the loaded screen', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: _overrides(_admin),
      );
      await tester.pumpAndSettle();

      for (final String key in <String>[
        'admin-own-profile-reveal-0',
        'admin-own-profile-reveal-1',
        'admin-own-profile-reveal-2',
      ]) {
        final Finder reveal = find.byKey(Key(key));
        expect(
          reveal,
          findsOneWidget,
          reason:
              '$key must exist and be unique — the key is what lets a single '
              'section be addressed at all. A renamed or dropped key silently '
              'un-pins the boundary placement for that section.',
        );
        expectBoundaryInsideTransitions(tester, reveal, reason: key);
      }
    });
  });

  group('loaded body', () {
    testWidgets('renders identity, salon affiliation and phone — and no '
        'Instagram tile even when a handle is set', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: _overrides(_admin),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-own-profile-name')), findsOneWidget);
      expect(
        find.byKey(const Key('admin-own-profile-role-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin-own-profile-professional-title')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-own-profile-salon')), findsOneWidget);
      expect(
        find.byKey(const Key('salon-affiliation-card-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('admin-own-profile-contact-phone')),
        findsOneWidget,
      );
      // The «Адмін» chip carries the SHORT role noun the approved preview
      // draws, not the roster's «Адміністратор» — read from l10n so the
      // assertion survives an EN build (no Cyrillic literal).
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(AdminOwnProfileScreen)),
      );
      expect(find.text(l10n.adminOwnProfileRoleLabel), findsOneWidget);
      expect(find.text(l10n.salonStaffRoleAdmin), findsNothing);
      // Instagram is a public-marketing handle, not staff-internal data. The
      // fixture HAS one, so this deny arm is real rather than vacuous — the
      // owner profile renders exactly such a tile from the same [User] field.
      expect(find.byIcon(Icons.alternate_email), findsNothing);
      // Embedded: nothing to pop.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    });

    testWidgets(
      'professionalTitle is omitted when unset; stand-alone keeps a back '
      'affordance; the tune renders ENABLED — 2026-09-08, it now opens the '
      'shared Account page rather than sitting inert',
      (tester) async {
        await tester.pumpApp(
          const AdminOwnProfileScreen(),
          overrides: _overrides(_admin.copyWith(professionalTitle: null)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('admin-own-profile-professional-title')),
          findsNothing,
        );
        // …but the chip that the title supplements is still there. Without
        // this the assertion above would also pass on a card that rendered
        // nothing.
        expect(
          find.byKey(const Key('admin-own-profile-role-chip')),
          findsOneWidget,
        );

        final tune = find.byKey(const Key('btn-admin-own-profile-settings'));
        expect(tune, findsOneWidget);
        // Enabled (2026-09-08): NeumorphicIconButton's `enabled` default is
        // `true`, which is additive-by-omission — no Opacity/AbsorbPointer
        // wrapper at all (see `neumorphic.dart`'s own doc on that branch), so
        // the absence of both is the enabled signal, not a 1.0 opacity value.
        expect(
          find.descendant(of: tune, matching: find.byType(Opacity)),
          findsNothing,
          reason:
              'the dimmed-and-absorbed treatment was Phase 21.17\'s '
              'inert-stub styling; the button is a real, tappable action now.',
        );
        expect(
          find.descendant(of: tune, matching: find.byType(AbsorbPointer)),
          findsNothing,
        );

        expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      },
    );

    testWidgets('no phone on file — the whole «Контакти» section is absent, '
        'not an em-dash tile', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: _overrides(_admin.copyWith(phoneNumber: null)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-own-profile-contacts')),
        findsNothing,
        reason:
            'the approved preview gates the whole block on a phone existing. '
            'This deliberately differs from the OWNER screen, which always '
            'renders a phone tile because its block may also carry Instagram '
            '— here an em-dash would be the section\'s only content.',
      );
      expect(
        find.byKey(const Key('admin-own-profile-contact-phone')),
        findsNothing,
      );
      // The rest of the body is unaffected.
      expect(find.byKey(const Key('admin-own-profile-name')), findsOneWidget);
      expect(find.byKey(const Key('admin-own-profile-salon')), findsOneWidget);
    });
  });

  group('the salon section degrades, it does not error', () {
    testWidgets('admin with no salonId — the section is absent and the rest '
        'of the profile still renders', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: _overrides(_admin.copyWith(salonId: null)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-own-profile-salon')), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(const Key('admin-own-profile-name')), findsOneWidget);
      expect(
        find.byKey(const Key('admin-own-profile-contact-phone')),
        findsOneWidget,
      );
    });

    testWidgets('salon read still unresolved — the section is absent (no '
        'header stranded above nothing)', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: _overrides(_admin, salon: _SalonRead.pending),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin-own-profile-salon')), findsNothing);
      expect(
        find.byKey(const Key('salon-affiliation-card-name')),
        findsNothing,
      );
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byKey(const Key('admin-own-profile-name')), findsOneWidget);
    });

    testWidgets('salon read FAILED — the section is absent, and the profile is '
        'NOT put into an error state', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: _overrides(_admin, salon: _SalonRead.failing),
        // Disabled so the read settles on its TERMINAL error instead of
        // parking in `AsyncLoading(retrying: true)` for ~38 s — a ServerFailure
        // is transient under the production predicate.
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-own-profile-salon')),
        findsNothing,
        reason: 'an optional context card that failed renders as ABSENT',
      );
      expect(
        find.byType(ErrorState),
        findsNothing,
        reason:
            'erroring an entire profile because a context card raced is a '
            'strictly worse failure than omitting it — only the identity read '
            'may error this screen.',
      );
      expect(find.byKey(const Key('admin-own-profile-name')), findsOneWidget);
    });
  });

  // ── mobile-perf + mobile-security LOW (2026-09-05) ───────────────────────
  // Two defects with one root: WHICH provider element the «Салон» card
  // resolves.
  //
  //  • The key used to be re-derived from `User.salonId` (a `GET /users/me`
  //    field) while the shell's slot 0 keys the SAME family on the go_router
  //    PATH PARAM. Any casing/formatting divergence between two UUID strings
  //    resolved a DIFFERENT family element, so the shell paid for a second
  //    cold copy of `GET /salons/{id}` + `GET /salons/{id}/staff` where the
  //    correct cost is zero.
  //  • On the stand-alone route there is nothing warm at all, so that family
  //    ALWAYS cold-started — dragging in the unmasked staff roster this
  //    screen destructures away unread.
  //
  // Both are pinned by BUILD LOGS rather than by rendering alone: a family
  // element that is never built leaves no entry, which is exactly the claim.
  group('the «Салон» read resolves the right provider element', () {
    // Case-divergent from [_kSalonId] on purpose — the whole failure mode.
    const String divergentSalonId = 'SALON-ADMIN-1';

    testWidgets('embedded with a hostSalonId — the card resolves the HOST\'s '
        'family element, never one keyed off /users/me, and never the '
        'stand-alone read', (tester) async {
      final List<String> managementBuilds = <String>[];
      final List<String> detailBuilds = <String>[];

      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true, hostSalonId: _kSalonId),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            // The identity read disagrees with the host on CASE — the exact
            // divergence that used to split the family in two.
            () => _SettledClientEditProfile(
              _admin.copyWith(salonId: divergentSalonId),
            ),
          ),
          salonManagementProfileProvider(_kSalonId).overrideWith(
            () => _LoggingSalonManagementProfile(managementBuilds),
          ),
          salonManagementProfileProvider(divergentSalonId).overrideWith(
            () => _LoggingSalonManagementProfile(managementBuilds),
          ),
          salonDetailProvider(_kSalonId).overrideWith((Ref ref) async {
            detailBuilds.add(_kSalonId);
            return _salon;
          }),
          salonDetailProvider(divergentSalonId).overrideWith((Ref ref) async {
            detailBuilds.add(divergentSalonId);
            return _salon;
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-own-profile-salon-card')),
        findsOneWidget,
        reason: 'sanity: the section really did resolve a salon',
      );
      expect(
        managementBuilds,
        <String>[_kSalonId],
        reason:
            'exactly ONE family element may be built, and it must be the one '
            'the shell warmed (the path param), not the one /users/me would '
            'have keyed.',
      );
      expect(
        detailBuilds,
        isEmpty,
        reason:
            'the warm path must not ALSO fire the stand-alone single-salon '
            'read — that would trade one wasted request for another.',
      );
    });

    testWidgets('stand-alone with no hostSalonId — the single-salon read is '
        'used and the management family (and its unmasked staff roster) is '
        'never touched at all', (tester) async {
      final List<String> managementBuilds = <String>[];
      final List<String> detailBuilds = <String>[];

      await tester.pumpApp(
        const AdminOwnProfileScreen(),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            () => _SettledClientEditProfile(_admin),
          ),
          salonManagementProfileProvider(_kSalonId).overrideWith(
            () => _LoggingSalonManagementProfile(managementBuilds),
          ),
          salonDetailProvider(_kSalonId).overrideWith((Ref ref) async {
            detailBuilds.add(_kSalonId);
            return _salon;
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-own-profile-salon-card')),
        findsOneWidget,
      );
      expect(
        detailBuilds,
        <String>[_kSalonId],
        reason: 'the stand-alone path reads GET /salons/{id} exactly once',
      );
      expect(
        managementBuilds,
        isEmpty,
        reason:
            'GET /salons/{id}/staff is the management-scoped, UNMASKED staff '
            'contacts list. This screen renders none of it, so the '
            'stand-alone path must never issue it — data minimisation, not '
            'just a spare round trip.',
      );
    });

    // -----------------------------------------------------------------------
    // mobile-qa re-audit (cycle 2, 2026-09-05) — the OWNERSHIP half of the
    // host-key logic (`admin_own_profile_screen.dart:443-491`).
    //
    // The two tests above pin which family element is READ. Neither can fail
    // when the `hostDisagrees` guard is deleted: `divergentSalonId` differs
    // from `_kSalonId` only in CASE, which the guard deliberately treats as
    // the SAME salon (salon ids are UUIDs; comparing raw would turn that
    // documented benign divergence into a false ownership violation and undo
    // the sibling perf fix). So the case-insensitive branch is covered and the
    // disagreement branch was not covered at all.
    //
    // What is being defended: `AdminOwnProfileScreen` renders the VIEWER'S OWN
    // profile. Mounted off a route that is not ownership-bound, a foreign
    // `hostSalonId` would put another salon's name, logo and address on it,
    // silently. The binding otherwise lives only in `salonManageGuard`
    // (`app_router.dart`), three layers up and a different file.
    //
    // The RELEASE fallback to `selfKey` is deliberately not asserted here:
    // `assert` is always enabled under `flutter test`, so the fallback branch
    // is unreachable in a widget test. The assert firing is the testable half,
    // and it is the half that stops the wiring mistake reaching a build at all.
    //
    // MUTATION-VERIFIED (2026-09-05) — deleting the `assert(!hostDisagrees, …)`
    // turns this test RED (no exception is thrown); restoring turns it GREEN.
    // -----------------------------------------------------------------------
    testWidgets('a hostSalonId naming a DIFFERENT salon than the signed-in '
        'admin\'s own trips the ownership assert', (tester) async {
      const String foreignSalonId = 'someone-elses-salon';

      await tester.pumpApp(
        // `_admin.salonId` is `_kSalonId`; the host claims another salon
        // entirely — not a case variant of it.
        const AdminOwnProfileScreen(
          embedded: true,
          hostSalonId: foreignSalonId,
        ),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            () => _SettledClientEditProfile(_admin),
          ),
          // Overridden so that, WITHOUT the assert, the screen renders the
          // foreign salon happily and this test fails on the missing
          // exception — not on a live Dio call.
          salonManagementProfileProvider(
            foreignSalonId,
          ).overrideWith(() => _LoggingSalonManagementProfile(<String>[])),
          salonDetailProvider(
            foreignSalonId,
          ).overrideWith((Ref ref) async => _salon),
        ],
      );
      // The identity read settles on the next microtask, so the loaded body —
      // the only build that sees `admin.salonId` at all — has not run yet.
      // `pumpAndSettle` is deliberately NOT used: the assert aborts the build
      // and the frame never quiesces.
      await tester.pump();

      expect(
        tester.takeException(),
        isA<AssertionError>().having(
          (AssertionError e) => e.message.toString(),
          'message',
          contains('renders the viewer\'s OWN profile'),
        ),
        reason:
            'the widget must defend its own identity rather than trust the '
            'host key. No exception here means AdminOwnProfileScreen will '
            'render ANOTHER salon on the viewer\'s profile page whenever it is '
            'mounted off a route that is not ownership-bound.',
      );
    });
  });

  group('AsyncValue states of the identity read', () {
    testWidgets('loading — the neumorphic skeleton renders, and neither the '
        'body nor an error does', (tester) async {
      final Completer<User> pending = Completer<User>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(_admin);
      });

      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            () => _PendingClientEditProfile(pending.future),
          ),
          _salonDetailOverride(_SalonRead.settled),
        ],
      );
      // `pump`, never `pumpAndSettle`: the skeleton runs
      // `SkeletonShimmerScope`'s REPEATING shimmer, which never settles — a
      // settle here would hang the test rather than fail it.
      await tester.pump();

      expect(
        find.byType(SkeletonBlock),
        findsWidgets,
        reason:
            'the loading state must be the shaped 3-section skeleton, not a '
            'bare spinner that would relayout under the user on arrival.',
      );
      expect(find.byKey(const Key('admin-own-profile-name')), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('error — an ErrorState with a working retry affordance renders '
        'in place of the body', (tester) async {
      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            _AlwaysFailingClientEditProfile.new,
          ),
          _salonDetailOverride(_SalonRead.settled),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(
        find.byKey(const Key('error_state_retry_button')),
        findsOneWidget,
        reason:
            'an error the admin cannot act on is a dead end — the retry '
            'affordance is part of the contract, not decoration.',
      );
      expect(find.byKey(const Key('admin-own-profile-name')), findsNothing);
      expect(find.byType(SkeletonBlock), findsNothing);
    });

    testWidgets('error — tapping retry re-invokes the identity read, and the '
        'recovered body renders', (tester) async {
      final List<String> log = <String>[];

      await tester.pumpApp(
        const AdminOwnProfileScreen(embedded: true),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            () => _FlakyClientEditProfile(log),
          ),
          _salonDetailOverride(_SalonRead.settled),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(ErrorState),
        findsOneWidget,
        reason: 'sanity: the first /users/me attempt really did fail',
      );
      expect(log.where((String e) => e == 'users/me').length, 1);

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(
        log.where((String e) => e == 'users/me').length,
        2,
        reason:
            'retry must genuinely re-invoke the identity read — '
            '`ref.invalidate(clientEditProfileProvider)`, not a repaint of the '
            'same stale error.',
      );
      expect(
        find.byKey(const Key('admin-own-profile-name')),
        findsOneWidget,
        reason: 'the recovered attempt must actually render the body',
      );
      expect(find.byType(ErrorState), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // `visible` — the same two `IndexedStack` defects `OwnerOwnProfileScreen`
  // documents. Pumped inside a host that flips `visible` exactly as
  // `SalonShellScreen` does, with the screen staying MOUNTED throughout: a raw
  // `IndexedStack` never disposes a visited child and gives it neither
  // `Offstage` nor `TickerMode`, so "not visible" is a state the screen can
  // only learn from its parent.
  // -------------------------------------------------------------------------
  group('visible', () {
    /// Current opacity of the identity card's entrance fade — the observable
    /// the reveal actually drives. Reading the widget's own `visible` FIELD
    /// instead would be vacuous: a field cannot say whether the reveal ran.
    ///
    /// `skipOffstage: false` throughout: the default finders SKIP the
    /// non-current child of an `IndexedStack`, and the off-screen phase of
    /// these tests is exactly where the assertion has to look.
    double revealOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(
                  const Key('admin-own-profile-name'),
                  skipOffstage: false,
                ),
                matching: find.byType(FadeTransition, skipOffstage: false),
              )
              // NEAREST ancestor — `.last` would pick the outermost, which is
              // the MaterialApp page-route transition sitting at 1.0.
              .first,
        )
        .opacity
        .value;

    testWidgets('the entrance reveal is SPENT on the first VISIBLE build, not '
        'burned off-screen', (tester) async {
      await tester.pumpApp(
        const _VisibilityHost(),
        overrides: _overrides(_admin),
      );
      // Resolve the loader while the tab is OFF-SCREEN, then let a full
      // entrance's worth of time pass.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('admin-own-profile-name'), skipOffstage: false),
        findsOneWidget,
        reason:
            'sanity: the loaded body must really be built while off-screen — '
            'an IndexedStack lays out its non-current children, so if this is '
            'absent the test is not reproducing the situation under test.',
      );
      expect(
        revealOpacity(tester),
        0.0,
        reason:
            'the one-shot entrance must NOT have run while the tab was '
            'off-screen, or the user\'s FIRST REAL VIEW of the tab has no '
            'entrance at all.',
      );

      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pump();
      // fixed-wait-ok: this IS the assertion. The claim is that the entrance
      // is PARTWAY THROUGH 200 ms after the tab became visible — i.e. that it
      // animates from 0 rather than having been spent off-screen and jumped to
      // 1.0. "Pump until it appears" cannot express a mid-animation value; any
      // settle-based wait would land at 1.0 and make the bug and the fix
      // indistinguishable.
      await tester.pump(const Duration(milliseconds: 200));

      final double midway = revealOpacity(tester);
      expect(midway, greaterThan(0.0));
      expect(
        midway,
        lessThan(1.0),
        reason:
            'a value already pinned at 1.0 200 ms in means the controller was '
            'spent off-screen and merely jumped.',
      );

      await tester.pumpAndSettle();
      expect(revealOpacity(tester), 1.0);
    });

    testWidgets('a reveal interrupted mid-flight is PAUSED, then RESUMES — it '
        'neither keeps ticking off-screen nor freezes half-faded', (
      tester,
    ) async {
      await tester.pumpApp(
        const _VisibilityHost(),
        overrides: _overrides(_admin),
      );
      await tester.pumpAndSettle();

      // Show the tab and let the entrance get under way…
      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pump();
      // fixed-wait-ok: same reason as the test above — the assertion is about
      // a MID-animation value, which no settle-based wait can express.
      await tester.pump(const Duration(milliseconds: 200));
      final double atInterrupt = revealOpacity(tester);
      expect(atInterrupt, greaterThan(0.0));
      expect(atInterrupt, lessThan(1.0));

      // …then tab away mid-reveal.
      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pump();
      // fixed-wait-ok: the claim is that MORE THAN a full entrance's worth of
      // time passing off-screen advances the reveal by NOTHING. That is a
      // statement about elapsed time, so time is what has to be advanced.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(
        revealOpacity(tester),
        atInterrupt,
        reason:
            'the controller must be stop()ped when the slot goes off-screen — '
            'otherwise a Ticker keeps scheduling frames for up to a second, '
            'driving three transition pairs on a subtree the IndexedStack is '
            'not painting.',
      );

      // …and coming back must RESUME rather than leave it frozen. This is the
      // half of the pair a bare `stop()` breaks: under a `value == 0` restart
      // guard the entrance could never leave this fractional value.
      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pumpAndSettle();
      expect(revealOpacity(tester), 1.0);
    });

    // -----------------------------------------------------------------------
    // mobile-qa re-audit (cycle 2, 2026-09-05) — the OTHER half of the
    // off-screen ticker fix, which the two reveal tests above cannot reach.
    //
    // `didUpdateWidget`'s `stop()`/resume pair governs `_controller`, this
    // State's OWN entrance controller — and the tests above pin exactly that,
    // in the LOADED state. `TickerMode(enabled: widget.visible)`
    // (`admin_own_profile_screen.dart:357`) exists for a ticker this State
    // does not own: `SkeletonShimmerScope`'s `..repeat(reverse: true)`
    // controller in the LOADING state. Tapping «Профіль» and away again before
    // `GET /users/me` returns leaves that shimmer scheduling a vsync frame
    // every ~16 ms on a subtree a raw `IndexedStack` never paints (it inserts
    // neither `Offstage` nor `TickerMode`).
    //
    // Deleting the `TickerMode` wrapper leaves every reveal test above GREEN,
    // because in the loaded state `_controller.stop()` has already muted the
    // only ticker they observe. This is the assertion that goes red instead.
    //
    // The observable is `transientCallbackCount` — the count of frame
    // callbacks the scheduler currently holds, which is what a running
    // `Ticker` registers and a muted one unregisters. A widget-field read
    // (`TickerMode.of(context)`, or the screen's own `visible`) would be
    // vacuous: it reports what was CONFIGURED, never whether a ticker stopped
    // asking for frames.
    //
    // MUTATION-VERIFIED (2026-09-05) — replacing the `TickerMode(enabled:
    // widget.visible, child: …)` wrapper with its bare `child` makes the
    // off-screen count non-zero and turns this test RED.
    // -----------------------------------------------------------------------
    testWidgets('the LOADING skeleton\'s shimmer schedules NO frames while '
        'the tab is off-screen, and resumes when it is shown', (tester) async {
      final Completer<User> pending = Completer<User>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(_admin);
      });

      await tester.pumpApp(
        const _VisibilityHost(),
        overrides: <Object>[
          clientEditProfileProvider.overrideWith(
            () => _PendingClientEditProfile(pending.future),
          ),
          _salonDetailOverride(_SalonRead.settled),
        ],
      );
      // `pump`, never `pumpAndSettle`: the shimmer REPEATS, so a settle can
      // never return.
      await tester.pump();

      expect(
        find.byType(SkeletonBlock, skipOffstage: false),
        findsWidgets,
        reason:
            'sanity: the off-screen slot must really be in the LOADING state '
            '— an IndexedStack lays out its non-current children, so if the '
            'skeleton is absent this test is not reproducing the situation '
            'under test and the count below would be zero for free.',
      );
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason:
            'a muted Ticker unregisters its frame callback. Any non-zero '
            'count here is the shimmer driving ~60 fps of vsync work on a '
            'subtree the IndexedStack is not painting.',
      );

      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pump();

      expect(
        tester.binding.transientCallbackCount,
        greaterThan(0),
        reason:
            'and it must ACTUALLY TICK once shown — without this half, a '
            'skeleton that never animates at all (or a fixture that never '
            'reached the loading state) would satisfy the zero above and the '
            'test would pin nothing.',
      );
    });

    testWidgets('screen protection is held only while the tab is VISIBLE', (
      tester,
    ) async {
      final manager = ScreenProtectionManager();
      await tester.pumpApp(
        const _VisibilityHost(),
        overrides: <Object>[
          ..._overrides(_admin),
          screenProtectionProvider.overrideWithValue(manager),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        manager.acquirerCount,
        0,
        reason:
            'an off-screen tab renders no PII to the app switcher, so it must '
            'not hold the guard',
      );

      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pumpAndSettle();
      expect(manager.acquirerCount, 1);

      // Tab away again. `IndexedStack` never disposes the child, so an
      // initState-acquire / dispose-release pair would latch the app-switcher
      // blur across every OTHER salon tab for the rest of the shell visit.
      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pumpAndSettle();
      expect(manager.acquirerCount, 0);

      // And the pair must survive repeated flips.
      await tester.tap(find.byKey(const Key('toggle-visible')));
      await tester.pumpAndSettle();
      expect(manager.acquirerCount, 1);
    });
  });

  // -------------------------------------------------------------------------
  // The `/profile/admin` route's `salonAdminOnlyGuard` gate.
  //
  // Nothing links to this route today (it is the stand-alone entry only), so
  // without a test the guard is exactly the kind of line a refactor removes
  // silently. Driven through the REAL `appRouterProvider`, because a guard
  // that is not run by the real router is not a guard.
  // -------------------------------------------------------------------------
  group('/profile/admin — salonAdminOnlyGuard', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    // `Object`, not `Override`: Riverpod 3.x does not export the `Override`
    // type from `flutter_riverpod`, so the list is built loosely and `.cast()`
    // at the `ProviderContainer` boundary infers the target — the same dodge
    // `test/helpers/pump_app.dart` documents for `ProviderScope.overrides`.
    ProviderContainer makeRouterContainer(Object authOverride) {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: <Object>[
          authOverride,
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // Resolves IMMEDIATELY — keeps the OWNER bounce destination off the
          // real Dio-backed repository and off a never-settling shimmer.
          mySalonsProvider.overrideWith(_SettledMySalons.new),
          clientEditProfileProvider.overrideWith(
            () => _SettledClientEditProfile(_admin),
          ),
          _salonDetailOverride(_SalonRead.settled),
          // ── The BOUNCE DESTINATIONS ────────────────────────────────────
          // Every denial below lands the router on a REAL landing screen, and
          // an unsettled one fires live Dio and leaves a connect-timeout Timer
          // outliving the test (`!timersPending`). Settled exactly as
          // `role_landing_chrome_test.dart` and `salon_manage_route_guard_test
          // .dart` settle the identical set — see their docs for each.
          //
          // INDEPENDENT_MASTER -> /master/profile (MasterProfileScreen) and
          // SALON_MASTER -> /staff/profile (SalonMasterProfileScreen).
          masterProfileProvider.overrideWith(_SettledMasterProfile.new),
          masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
          serviceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // A SEPARATE provider from `serviceRepositoryProvider` — it is what
          // `salonMasterOwnProfileProvider` reads.
          publicServiceRepositoryProvider.overrideWith(
            (_) => FakeServiceRepository(),
          ),
          // MasterProfileScreen's categories section bypasses
          // `serviceRepositoryProvider` and builds on the real authenticated
          // Dio, so it needs its own settle.
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          // CLIENT -> /home (HomeHubScreen), which watches five async
          // providers; `myRatingProvider`'s real build also starts a 5-minute
          // keepAlive TTL Timer that outlives the binding's timer check.
          clientProfileProvider.overrideWith(
            (ref) async => const ClientProfileSummary(
              firstName: 'Тест',
              lastName: 'Клієнт',
              city: '',
              phone: '',
              clientRating: null,
              memberSinceYear: 2026,
            ),
          ),
          nextAppointmentProvider.overrideWith((ref) async => null),
          favoriteMastersProvider.overrideWith(
            (ref) async => const <FavoriteMasterItem>[],
          ),
          beautyTimelineProvider.overrideWith(
            (ref) async => const <TimelineEntry>[],
          ),
          myRatingProvider.overrideWith((ref) async => const ClientRating()),
        ].cast(),
      );
      addTearDown(container.dispose);
      return container;
    }

    Object authAs(User user) => authProvider.overrideWith(
      () => _FixedAuthNotifier(
        AsyncData<AuthSession>(
          AuthSession.authenticated(user: user, accessToken: 'token'),
        ),
      ),
    );

    /// Pumps the REAL router for [authOverride]'s session.
    ///
    /// [settle] is `false` for the two destinations that run a REPEATING
    /// entrance animation — `LoginScreen` and `SplashScreen` — where
    /// `pumpAndSettle` never quiesces and would hang the test rather than fail
    /// it. Those cases take bounded `pump`s instead, which is enough to build
    /// and mount the destination page.
    Future<GoRouter> pumpRouterWith(
      WidgetTester tester,
      Object authOverride, {
      bool settle = true,
    }) async {
      final ProviderContainer container = makeRouterContainer(authOverride);
      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // pump-bounded-ok: the destination runs a repeating animation, so a
        // settle can never return. Two frames are enough to run the redirect
        // and mount the page — the assertion is the resolved page TYPE, not a
        // steady animation value.
        await tester.pump();
        await tester.pump();
      }
      return router;
    }

    Future<GoRouter> pumpRouterAs(WidgetTester tester, User user) =>
        pumpRouterWith(tester, authAs(user));

    /// Drives `/profile/admin` and returns the router. Split out so every
    /// denial case below travels the IDENTICAL navigation path and can only
    /// differ by session.
    Future<void> goToAdminProfile(
      WidgetTester tester,
      GoRouter router, {
      bool settle = true,
    }) async {
      router.go(RouteNames.adminOwnProfile);
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // pump-bounded-ok — see pumpRouterWith.
        await tester.pump();
        await tester.pump();
      }
    }

    testWidgets('a SALON_ADMIN is ADMITTED and gets the stand-alone screen '
        '(back chevron, not the embedded tab)', (tester) async {
      final GoRouter router = await pumpRouterAs(tester, _routerAdmin);

      router.go(RouteNames.adminOwnProfile);
      await tester.pumpAndSettle();

      expect(
        find.byType(AdminOwnProfileScreen),
        findsOneWidget,
        reason:
            'the resolved PAGE TYPE, not merely a matching location string — '
            '`/profile/admin` is a literal sibling of `/profile/owner`, and a '
            'future `/profile/:id` declared before either would shadow both.',
      );
      expect(
        find.byIcon(Icons.arrow_back_ios_new_rounded),
        findsOneWidget,
        reason:
            'the stand-alone registration passes `embedded: false`, so unlike '
            'the shell tab it must keep a way back.',
      );
    });

    testWidgets(
      'the tune button pushes the shared Account page (RouteNames.settings) '
      '— 2026-09-08, replacing the unbuilt Phase 21.17 inert stub',
      (tester) async {
        final GoRouter router = await pumpRouterAs(tester, _routerAdmin);

        router.go(RouteNames.adminOwnProfile);
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('btn-admin-own-profile-settings')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(SettingsScreen),
          findsOneWidget,
          reason:
              'a bare context.push(RouteNames.settings), no `extra` — the '
              'same shape the master menu\'s own row-account push already '
              'uses — must resolve to the Account page.',
        );
      },
    );

    testWidgets('a SALON_OWNER is BOUNCED — this is the ADMIN profile, and the '
        'owner has one of their own', (tester) async {
      final GoRouter router = await pumpRouterAs(tester, _routerOwner);

      router.go(RouteNames.adminOwnProfile);
      await tester.pumpAndSettle();

      expect(
        find.byType(AdminOwnProfileScreen),
        findsNothing,
        reason:
            'SALON_OWNER is the one role a naive "both salon roles" guard '
            'would have let through — `salonHomeGuard` admits it, which is '
            'why this route could not reuse that closure.',
      );
      // This test only ever calls `router.go`, never `context.push`, so no
      // `ImperativeRouteMatch` is on the stack and the raw read reports the
      // real post-redirect location. The push-safe `AppHarness.location`
      // helper lives in the integration_test tier, which a `test/` file must
      // not import.
      expect(
        // router-location-ok: `.go` only in this test — see the note above.
        router.routerDelegate.currentConfiguration.uri.toString(),
        isNot(RouteNames.adminOwnProfile),
        reason: 'the guard must REDIRECT, not merely render something else',
      );
    });

    // -----------------------------------------------------------------------
    // mobile-qa Phase 21.16 gap closure (2026-09-05) — the remaining FOUR of
    // the six reachable guard states. mobile-security's LOW finding: the group
    // above pinned only SALON_ADMIN-admitted and SALON_OWNER-bounced, which
    // is 2/6 of what `/profile/admin` actually answers.
    //
    // WHY EACH ONE IS ITS OWN TEST, AND NOT A LOOP OVER ROLES
    // ------------------------------------------------------
    // `salonAdminOnlyGuard` is a single `!=`, so on the GUARD line every
    // non-admin role is the same case. What is NOT the same is the
    // DESTINATION: `roleHomePath` dispatches five ways, and every landing but
    // the admin's own is reached by a DIFFERENT route subtree with a different
    // page type. Asserting the resolved TYPE per role is therefore the only
    // form that can catch a role-dispatch regression (a role silently falling
    // through to the wrong landing) rather than merely "not the admin
    // profile".
    //
    // WHY THE LAST TWO ARE THE LOAD-BEARING ONES
    // ------------------------------------------
    // Anonymous and still-loading are NOT decided by `salonAdminOnlyGuard` at
    // all — it returns `null` for a non-`Authenticated` session. They are
    // decided by the TOP-LEVEL `GoRouter.redirect` in `auth_redirect.dart`
    // (the `session.isLoading -> /splash` branch and the settled-unauth
    // `-> /login` branch). That is a DIFFERENT FILE, so a refactor there can
    // sever `/profile/admin`'s anonymous fence without turning a single
    // assertion in `salonAdminOnlyGuard`'s own group red. These two tests are
    // what makes that impossible.
    //
    // The assertion is always the resolved page TYPE, never the location
    // string: `/profile/admin` is a LITERAL, and a dynamic sibling declared
    // before it would absorb the path while `currentConfiguration.uri` went on
    // reporting `/profile/admin` verbatim.
    // -----------------------------------------------------------------------

    testWidgets('a SALON_MASTER is BOUNCED to their own read-only staff '
        'profile (/staff/profile)', (tester) async {
      final GoRouter router = await pumpRouterAs(tester, _routerSalonMaster);
      await goToAdminProfile(tester, router);

      expect(find.byType(AdminOwnProfileScreen), findsNothing);
      expect(
        find.byType(SalonMasterProfileScreen),
        findsOneWidget,
        reason:
            'the resolved landing PAGE, not just "something other than the '
            'admin profile" — SALON_MASTER used to fall through roleHomePath\'s '
            'wildcard onto a blank home, and a findsNothing-only assertion '
            'would have been green for that too.',
      );
    });

    testWidgets('an INDEPENDENT_MASTER is BOUNCED to /master/profile', (
      tester,
    ) async {
      final GoRouter router = await pumpRouterAs(
        tester,
        _routerIndependentMaster,
      );
      await goToAdminProfile(tester, router);

      expect(find.byType(AdminOwnProfileScreen), findsNothing);
      expect(find.byType(MasterProfileScreen), findsOneWidget);
    });

    testWidgets('a CLIENT is BOUNCED to the client home hub (/home)', (
      tester,
    ) async {
      final GoRouter router = await pumpRouterAs(tester, _routerClient);
      await goToAdminProfile(tester, router);

      expect(
        find.byType(AdminOwnProfileScreen),
        findsNothing,
        reason:
            'the admin profile renders the admin\'s own phone number — a '
            'CLIENT reaching it is a PII exposure, not merely a wrong screen.',
      );
      expect(find.byType(HomeHubScreen), findsOneWidget);
    });

    testWidgets('an UNAUTHENTICATED session is fenced to /login — the denial '
        'that lives in auth_redirect.dart, not in salonAdminOnlyGuard', (
      tester,
    ) async {
      final GoRouter router = await pumpRouterWith(
        tester,
        authProvider.overrideWith(
          () => _FixedAuthNotifier(
            const AsyncData<AuthSession>(AuthSession.unauthenticated()),
          ),
        ),
        settle: false,
      );
      await goToAdminProfile(tester, router, settle: false);

      expect(
        find.byType(AdminOwnProfileScreen),
        findsNothing,
        reason:
            'salonAdminOnlyGuard returns null for a non-Authenticated session '
            '— it does NOT fence anonymous access. Only the top-level '
            'authRedirect does, and this is the assertion that says so.',
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('a still-RESOLVING session parks on /splash, never on the '
        'admin profile', (tester) async {
      _NeverSettlingAuthNotifier.pending.clear();
      addTearDown(_NeverSettlingAuthNotifier.pending.clear);

      final GoRouter router = await pumpRouterWith(
        tester,
        authProvider.overrideWith(_NeverSettlingAuthNotifier.new),
        settle: false,
      );
      await goToAdminProfile(tester, router, settle: false);

      expect(
        find.byType(AdminOwnProfileScreen),
        findsNothing,
        reason:
            'AsyncLoading is not Authenticated, so salonAdminOnlyGuard waves '
            'it through — the cold-start fence is authRedirect\'s isLoading '
            'branch alone. Without this, a deep link opened before the stored '
            'session resolves would flash the admin profile to whoever holds '
            'the phone.',
      );
      expect(
        find.byType(SplashScreen),
        findsOneWidget,
        reason:
            'and the parked page is the branded splash, which is what the '
            'isLoading branch returns — this is the page TYPE that goes '
            'missing the moment that branch is severed.',
      );
    });

    // -----------------------------------------------------------------------
    // mobile-qa re-audit (cycle 2, 2026-09-05) — the state `resolvedSession()`
    // WAS WRITTEN FOR, and the one state no test constructed.
    //
    // `app_router.dart:236` reads the session as
    // `auth is AsyncData<AuthSession> ? auth.value : null` rather than a bare
    // `.value`. That distinction is only observable in ONE state: an
    // `AsyncError` (or mid-retry `AsyncLoading`) that Riverpod's own
    // `copyWithPrevious` left a PRIOR `AsyncData`'s value attached to — the
    // shape a same-device account switch leaves for a frame (user A logs out,
    // user B logs in, `/users/me` refetch fails). Every other test in this
    // group feeds the router an `AsyncData` or a value-less `AsyncLoading`,
    // for which `auth.value` and `resolvedSession()` return the IDENTICAL
    // thing — so before this test the whole helper could be reverted to
    // `ref.read(authProvider).value` with the entire suite still green.
    //
    // WHY THE STALE ROLE MUST BE ONE THE GUARD BOUNCES
    // ------------------------------------------------
    // If the carried-forward session were a SALON_ADMIN, the bare `.value`
    // read would ADMIT too — same outcome, different (one wrong, one right)
    // reason, and no router-outcome assertion could tell them apart. The
    // fixture therefore carries an INDEPENDENT_MASTER: `salonAdminOnlyGuard`
    // bounces that role to `/master/profile`, so the buggy read and the fixed
    // read land on visibly different pages. The shape and the role are both
    // asserted BEFORE the navigation, so this test can never pass by failing
    // to reproduce its own premise.
    //
    // WHY ADMITTING IS THE RIGHT ANSWER (and not a hole): see the helper's own
    // note — the global `authRedirect` runs on the SAME evaluation and
    // `refreshListenable` re-evaluates the moment the session settles, so an
    // admitted frame is a frame. A bounce decided on ANOTHER ACCOUNT's role is
    // a wrong decision no later re-evaluation can un-make.
    //
    // MUTATION-VERIFIED (2026-09-05) — reverting `resolvedSession()`'s body to
    // `return ref.read(authProvider).value;` turns this test RED
    // (`AdminOwnProfileScreen` findsNothing; `MasterProfileScreen` renders
    // instead). Restoring it turns it back GREEN.
    // -----------------------------------------------------------------------
    testWidgets('an AsyncError that still carries a stale AsyncData session is '
        'treated as UNRESOLVED — the admin is ADMITTED, never bounced on the '
        'previous account\'s role', (tester) async {
      final notifier = _TransitionableAuthNotifier(_routerIndependentMaster);
      final ProviderContainer container = makeRouterContainer(
        authProvider.overrideWith(() => notifier),
      );
      final GoRouter router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      // Settle to AsyncData FIRST — this is the "previous account" snapshot
      // that `copyWithPrevious` will carry forward. Without a settled value to
      // carry, the AsyncError below would have a null `.value` and the two
      // reads would agree again.
      await container.read(authProvider.future);
      expect(container.read(authProvider), isA<AsyncData<AuthSession>>());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      // The PRODUCTION trigger, not a simulation of it: `AuthNotifier` itself
      // assigns `state = AsyncError(e, st)`, and Riverpod's `asyncTransition`
      // does the carry-forward.
      notifier.forceError(const ServerFailure());
      await tester.pumpAndSettle();

      final AsyncValue<AuthSession> stale = container.read(authProvider);
      expect(
        stale,
        isA<AsyncError<AuthSession>>(),
        reason:
            'the transition must actually land on AsyncError — `hasError` '
            'alone would also be satisfied by a mid-retry AsyncLoading and '
            'could not pin the terminal shape.',
      );
      expect(
        stale.value,
        isA<Authenticated>(),
        reason:
            'copyWithPrevious must retain the settled session on .value — '
            'this IS the shape resolvedSession() exists to reject. If it were '
            'null the guard would admit for a DIFFERENT reason and this test '
            'would pin nothing.',
      );
      expect(
        (stale.value! as Authenticated).user.role,
        UserRole.independentMaster,
        reason:
            'and the stale role must be one salonAdminOnlyGuard BOUNCES, or '
            'the buggy `.value` read would admit too and the test could not '
            'go red under mutation.',
      );

      router.go(RouteNames.adminOwnProfile);
      await tester.pumpAndSettle();

      expect(
        find.byType(AdminOwnProfileScreen),
        findsOneWidget,
        reason:
            'an unresolved session is not a role — the guard must wave the '
            'frame through and let the settled re-evaluation decide.',
      );
      expect(
        find.byType(MasterProfileScreen),
        findsNothing,
        reason:
            'this is where a bare `.value` read lands: it reads the previous '
            'account\'s INDEPENDENT_MASTER role as current and bounces to '
            'roleHomePath(independentMaster).',
      );
    });
  });
}

/// Settles to an [Authenticated] session for [user], then lets the test body
/// drive a REAL post-settle transition.
///
/// [_FixedAuthNotifier] cannot express this: its `build()` is an `async` body
/// that RETURNS, so Riverpod overwrites whatever `state` it assigned with an
/// `AsyncData` on the next microtask. The `AsyncError`-carrying-a-stale-value
/// shape can only be produced the way production produces it — by assigning
/// `state` AFTER the build has settled, which is exactly what
/// `AuthNotifier` does on a failed refresh (`auth_notifier.dart`).
///
/// Mirrors `test/features/auth/presentation/auth_selectors_test.dart`'s
/// `_TransitionableAuthNotifier` — same mechanism, one layer up (the router
/// guard instead of the role selector).
class _TransitionableAuthNotifier extends AuthNotifier {
  _TransitionableAuthNotifier(this.user);

  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 'token');

  /// The SAME `state = AsyncError(e, st)` shape production `AuthNotifier`
  /// uses. Riverpod's own `asyncTransition` (`onError`, `seamless: false`)
  /// carries the previously settled `.value` FORWARD onto the resulting
  /// `AsyncError`.
  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }
}

/// `/users/me` pinned to a caller-supplied future — used for the loading state.
class _PendingClientEditProfile extends ClientEditProfile {
  _PendingClientEditProfile(this.pending);

  // NOT named `future` — `ClientEditProfile` inherits a `.future` member from
  // its Riverpod base, and shadowing it here silently changes what
  // `provider.future` resolves to.
  final Future<User> pending;

  @override
  Future<User> build() => pending;
}

/// `/users/me` that always fails — used for the terminal error state.
class _AlwaysFailingClientEditProfile extends ClientEditProfile {
  @override
  Future<User> build() async => throw const ServerFailure();
}

/// Mounts [AdminOwnProfileScreen] inside a raw [IndexedStack] and flips which
/// slot is current — the exact shape `SalonShellScreen` uses, including the
/// `visible: stackSlot == 2` hand-off. Starts OFF-SCREEN.
class _VisibilityHost extends StatefulWidget {
  const _VisibilityHost();

  @override
  State<_VisibilityHost> createState() => _VisibilityHostState();
}

class _VisibilityHostState extends State<_VisibilityHost> {
  int _slot = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _slot,
        children: <Widget>[
          const SizedBox.shrink(),
          AdminOwnProfileScreen(embedded: true, visible: _slot == 1),
        ],
      ),
      bottomNavigationBar: TextButton(
        key: const Key('toggle-visible'),
        onPressed: () => setState(() => _slot = _slot == 0 ? 1 : 0),
        child: const Text('toggle'),
      ),
    );
  }
}
