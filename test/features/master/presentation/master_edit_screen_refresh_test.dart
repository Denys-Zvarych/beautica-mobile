// Regression safety net (2026-06-02) — Fix 2.
//
// PERSISTENCE-VISIBLE provider-refresh test for the edit-profile flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The existing master_edit_screen_test.dart asserts that updateMyProfile is
// CALLED and that masterProfileProvider receives "an extra emission" after
// save. Neither proves the user actually SEES the new value — the exact gap
// behind "save profile → nothing persists". A screen could call the repo, fire
// invalidate, and STILL show stale data if the refetch path is broken.
//
// This test closes that gap by driving the REAL provider + screen wiring:
//   • REAL MasterProfile AsyncNotifier (NOT a stub build()).
//   • REAL MasterEditScreen AND REAL MasterProfileScreen, wired in one router.
//   • A STATEFUL fake MasterRepository (not a mock): getMyProfile returns the
//     CURRENT persisted master, and updateMyProfile MUTATES that persisted
//     state — exactly like a real backend round-trip. Returns a synchronous
//     future so the widget tree settles deterministically (no runAsync hang).
//
// FLOW: pump MasterEditScreen → edit firstName → Save. The screen invalidates
// masterProfileProvider and navigates to MasterProfileScreen, whose REAL
// notifier re-runs build() → getMyProfile() → returns the NEW persisted value.
// We then assert the rendered identity-card name (Key('master-profile-name'))
// shows the EDITED name. If the edit flow never invalidated the provider (or
// the notifier read a stale cache), the profile screen would still render the
// OLD name and this test FAILS — the desired regression signal. We do NOT touch
// production code to make it pass.

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/master_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

Master _seedMaster() => const Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
);

/// A STATEFUL fake repository that behaves like a real backend round-trip:
/// updateMyProfile persists the new values, and getMyProfile returns whatever
/// is currently persisted. A fixed-return mock could never catch a stale-read
/// bug — the mutation is the whole point. Returns synchronous futures so the
/// widget tree settles under flutter_test's fake clock with no hang.
class _StatefulFakeMasterRepository implements MasterRepository {
  _StatefulFakeMasterRepository(this._persisted);

  Master _persisted;
  int updateCalls = 0;

  @override
  Future<Master> getMyProfile(String masterId) =>
      Future<Master>.value(_persisted);

  @override
  Future<void> updateMyProfile(MasterUpdate update) {
    updateCalls++;
    _persisted = _persisted.copyWith(
      firstName: update.firstName,
      lastName: update.lastName,
      bio: update.bio,
      phoneNumber: update.contactPhone.isEmpty ? null : update.contactPhone,
      instagram: update.instagram.isEmpty ? null : update.instagram,
    );
    return Future<void>.value();
  }

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  }) {
    _persisted = _persisted.copyWith(
      cityId: cityId,
      districtId: districtId,
      street: street,
      buildingNo: buildingNo,
      locationNote: locationNote,
    );
    return Future<void>.value();
  }
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

/// Stub services notifier so the profile screen's services section resolves to
/// an empty list without touching the network (it watches servicesListProvider).
class _StubServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Future<List<MasterService>>.value(const <MasterService>[]);
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterEdit,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEdit,
      pageBuilder: (context, state) =>
          const NoTransitionPage<void>(child: MasterEditScreen()),
    ),
    // The REAL profile screen is the save-success destination, so the
    // persisted change is asserted through the actually-rendered UI.
    GoRoute(
      path: RouteNames.masterProfile,
      pageBuilder: (context, state) =>
          const NoTransitionPage<void>(child: MasterProfileScreen()),
    ),
  ],
);

void main() {
  testWidgets(
    'after a successful Save, the profile screen renders the NEW firstName — '
    'the change is actually reflected in the UI, not just requested',
    (tester) async {
      final fakeRepo = _StatefulFakeMasterRepository(_seedMaster());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_StubAuthNotifier.new),
            masterRepositoryProvider.overrideWithValue(fakeRepo),
            servicesListProvider.overrideWith(_StubServicesList.new),
          ],
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      // Settle the edit screen + the masterProfileProvider first resolution.
      await tester.pump();
      await tester.pump();

      // Sanity: edit screen pre-populated with the seed name.
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('field-firstName')),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        'Олена',
      );

      // Edit firstName and Save through the REAL screen logic.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.byType(TextField),
        ),
        'Оксана',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();

      // The repo round-trip happened exactly once.
      expect(fakeRepo.updateCalls, 1, reason: 'Save must call updateMyProfile');

      // We must have navigated to the profile screen.
      expect(
        find.byKey(const Key('master-profile-name')),
        findsOneWidget,
        reason: 'Save success must navigate to the profile screen.',
      );

      // THE PERSISTENCE ASSERTION: the rendered identity-card name must carry
      // the EDITED firstName. Because the edit screen invalidated
      // masterProfileProvider, the REAL notifier refetched getMyProfile() which
      // returned the now-persisted master. A broken refresh (no invalidate, or
      // a stale-cache read) would still render "Олена Ковальчук".
      expect(
        find.text('Оксана Ковальчук'),
        findsOneWidget,
        reason:
            'The profile screen must display the new firstName after Save. '
            'If it still shows "Олена Ковальчук", the edit flow does not '
            'refetch the profile after persisting — the "save → nothing '
            'persists" bug.',
      );
      expect(
        find.text('Олена Ковальчук'),
        findsNothing,
        reason: 'Stale pre-edit name must not remain on screen after Save.',
      );
    },
  );
}
