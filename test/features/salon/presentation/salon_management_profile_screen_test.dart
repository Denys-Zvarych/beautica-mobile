// Phase 21.2 — Widget tests for SalonManagementProfileScreen.
//
// Covers:
//   1. Top-right cover control opens SalonSettingsScreen (not inline edit
//      directly).
//   2. «Редагувати профіль» round-trips: settings pops(true) → the profile
//      screen flips into edit mode (fields + Save/Cancel footer appear).
//   3. Save round-trips through the (mocked) repository's updateSalon — only
//      the DIRTY fields are sent, `street`/`buildingNo` always pass through.
//   4. Персонал tab: staff grid renders master cards + the trailing add tile.
//
// Strategy: a real GoRouter (via `pumpRoutedApp`) registering both
// `/salons/:salonId/manage` and `/salons/:salonId/manage/settings`, mirroring
// `app_router.dart`'s own registration, with `salonRepositoryProvider`
// overridden by an in-memory fake — mirrors
// `public_salon_profile_screen_test.dart`'s harness shape.

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart'
    show MasterType;
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _kSalonId = 'salon-1';

const _stubOwner = User(
  id: 'owner-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Швець',
);

const _stubSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  description: 'Затишний салон краси в серці Печерська.',
  street: 'вул. Велика Васильківська',
  buildingNo: '44',
  avgRating: 4.9,
  reviewCount: 128,
);

const _stubMasters = <SalonMasterSummary>[
  SalonMasterSummary(
    masterId: 'master-1',
    firstName: 'Олена',
    lastName: 'Ковальчук',
    avgRating: 4.9,
    reviewCount: 12,
    type: MasterType.independentMaster,
  ),
];

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

/// [SalonManagementProfile] stub whose `build()` delegates to [_onBuild] —
/// lets the loading/error test drive the family provider's attempt count
/// directly, sidestepping the `ref.watch(authProvider)` eviction-watch
/// rebuild race routing the same failure through the repository fake would
/// hit (see the error-state test's own doc for the full rationale).
class _AttemptCountingSalonManagementProfile extends SalonManagementProfile {
  _AttemptCountingSalonManagementProfile(this._onBuild);

  final SalonManagementProfileData Function() _onBuild;

  @override
  Future<SalonManagementProfileData> build(String salonId) async => _onBuild();
}

GoRouter _router(FakeSalonRepository repo) => GoRouter(
  initialLocation: RouteNames.salonManage(_kSalonId),
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/manage',
      builder: (context, state) => SalonManagementProfileScreen(
        salonId: state.pathParameters['salonId']!,
      ),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/settings',
      builder: (context, state) =>
          SalonSettingsScreen(salonId: state.pathParameters['salonId']!),
    ),
  ],
);

List<Object> _overrides(FakeSalonRepository repo) => <Object>[
  authProvider.overrideWith(_StubAuthNotifier.new),
  salonRepositoryProvider.overrideWithValue(repo),
];

void main() {
  group('top-right cover control', () {
    testWidgets('opens SalonSettingsScreen, not inline edit directly', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      // No edit fields visible yet — the profile starts read-only.
      expect(find.byKey(const Key('field-salon-name')), findsNothing);

      await tester.tap(find.byKey(const Key('salon-manage-settings')));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(find.text(l10n.settingsTitle), findsOneWidget);
      expect(find.byKey(const Key('row-salon-edit-profile')), findsOneWidget);
      // Still no inline edit fields — settings is a SEPARATE page.
      expect(find.byKey(const Key('field-salon-name')), findsNothing);
    });
  });

  group('edit mode round-trip', () {
    testWidgets(
      '«Редагувати профіль» pops back with edit mode toggled on, and Save '
      'sends only the dirty fields',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-manage-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
        await tester.pumpAndSettle();

        // Back on the profile screen, now in edit mode.
        expect(find.byKey(const Key('field-salon-name')), findsOneWidget);
        expect(
          find.byKey(const Key('field-salon-description')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('field-salon-phone')), findsOneWidget);
        expect(find.byKey(const Key('field-salon-instagram')), findsOneWidget);
        expect(find.byKey(const Key('btn-salon-save-edit')), findsOneWidget);
        expect(find.byKey(const Key('btn-salon-cancel-edit')), findsOneWidget);

        // Phone starts BLANK (Phase 21.2 gap — GET never returns it), even
        // though every other field seeds from the loaded salon.
        // `fieldKey` is forwarded straight onto VelvetField's inner
        // `TextField` (see `velvet_field.dart`'s own doc), so the key finds
        // the TextField directly — no `.descendant()` needed.
        final phoneField = tester.widget<TextField>(
          find.byKey(const Key('field-salon-phone')),
        );
        expect(phoneField.controller!.text, isEmpty);

        // Type a phone number — the ONLY field the viewer touches.
        await tester.enterText(
          find.byKey(const Key('field-salon-phone')),
          '+380501234567',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
        await tester.pumpAndSettle();

        expect(repo.updateRequests, hasLength(1));
        final UpdateSalonRequest sent = repo.updateRequests.single;
        // Untouched name/description/instagram are OMITTED (not re-sent
        // verbatim) — only phone (the field actually edited) is present.
        expect(sent.name, isNull);
        expect(sent.description, isNull);
        expect(sent.instagramUrl, isNull);
        expect(sent.phone, '+380501234567');
        // street/buildingNo are backend-REQUIRED even on a partial update —
        // always threaded through from the loaded salon.
        expect(sent.street, _stubSalon.street);
        expect(sent.buildingNo, _stubSalon.buildingNo);

        // Edit mode closes on a successful save.
        await tester.pump();
        expect(find.byKey(const Key('field-salon-name')), findsNothing);
      },
    );

    testWidgets('Cancel discards edits without calling updateSalon', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-manage-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('field-salon-name')),
        'Змінена назва',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-salon-cancel-edit')));
      await tester.pumpAndSettle();

      expect(repo.updateRequests, isEmpty);
      expect(find.byKey(const Key('field-salon-name')), findsNothing);
      // i18n-finder-ok: salon name is fixture data, not UI copy
      expect(find.text(_stubSalon.name), findsOneWidget);
    });
  });

  // mobile-security LOW follow-up (2026-08-27) — client-side field
  // validation on name/phone/instagram before Save reaches the repository.
  group('edit-form validation (mobile-security LOW follow-up)', () {
    testWidgets('a blank name blocks Save and shows an inline error', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-manage-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('field-salon-name')), '');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
      await tester.pumpAndSettle();

      expect(repo.updateRequests, isEmpty);
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      expect(find.text(l10n.errNameRequired), findsOneWidget);
      // Edit mode stays open — Save never went through.
      expect(find.byKey(const Key('field-salon-name')), findsOneWidget);
    });

    testWidgets(
      'an invalid phone value blocks Save and shows an inline error',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-manage-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-salon-phone')),
          'not-a-phone-number',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
        await tester.pumpAndSettle();

        expect(repo.updateRequests, isEmpty);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.errPhoneInvalidEdit), findsOneWidget);
      },
    );

    testWidgets(
      'an invalid Instagram value blocks Save and shows an inline error',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-manage-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-salon-instagram')),
          '!!!not valid!!!',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
        await tester.pumpAndSettle();

        expect(repo.updateRequests, isEmpty);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.masterEditInstagramError), findsOneWidget);
      },
    );

    testWidgets(
      'correcting an invalid field clears its inline error and allows Save',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-manage-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-salon-edit-profile')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('field-salon-phone')),
          'not-a-phone-number',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.errPhoneInvalidEdit), findsOneWidget);

        // The failed attempt's editValidationSummary VelvetSnack floats above
        // the footer and can still be absorbing pointer events there even
        // after pumpAndSettle — drive it through its own lifecycle (REUSE-
        // FIRST: `velvet_snack_matchers.dart`'s documented mechanism) before
        // the next tap targets the Save button underneath.
        await pumpPastVelvetSnack(tester);

        await tester.enterText(
          find.byKey(const Key('field-salon-phone')),
          '+380501234567',
        );
        await tester.pumpAndSettle();

        expect(find.text(l10n.errPhoneInvalidEdit), findsNothing);

        await tester.tap(find.byKey(const Key('btn-salon-save-edit')));
        await tester.pumpAndSettle();

        expect(repo.updateRequests, hasLength(1));
        expect(repo.updateRequests.single.phone, '+380501234567');
      },
    );
  });

  group('Персонал tab', () {
    testWidgets('renders staff cards plus the trailing add-staff tile', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _stubSalon,
        masters: _stubMasters,
      );
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-manage-staff-card-master-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-staff-empty')), findsNothing);

      // TODO(phase-21.4/21.5): tapping either does not navigate yet — both
      // callbacks are explicit no-ops until those phases ship. Assert the
      // tap is at least safe (no crash), matching the phase brief's
      // "render per the preview, leave the navigation unwired" instruction.
      await tester.tap(find.byKey(const Key('salon-manage-add-staff')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
    });

    testWidgets('shows the empty-state message when the salon has no masters', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _stubSalon,
        masters: const <SalonMasterSummary>[],
      );
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      await tester.tap(find.text(l10n.salonManageTabStaff));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-manage-staff-empty')), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-add-staff')), findsOneWidget);
    });
  });

  group('loading / error states (mobile-qa M3)', () {
    testWidgets('shows a spinner while the initial load is in flight', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _stubSalon);
      await tester.pumpRoutedApp(_router(repo), overrides: _overrides(repo));
      // ONE frame only — before the fake repo's Future settles.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('salon-manage-hero-card')), findsNothing);
    });

    testWidgets(
      'a repository Failure renders ErrorState, and tapping retry reloads',
      (tester) async {
        final repo = FakeSalonRepository(salon: _stubSalon);
        var attempt = 0;
        // Overrides [salonManagementProfileProvider] directly (bypassing
        // [salonRepositoryProvider]) — mirrors
        // `public_salon_profile_screen_test.dart`'s identical error-state
        // test. Routing the failure through the repository fake instead races
        // `authProvider`'s own async `build()` (Loading -> Data), which
        // rebuilds this family provider mid-flight and inflates the observed
        // attempt count non-deterministically (a `ref.watch(authProvider)`
        // eviction watch is what causes the rebuild — see this notifier's own
        // `build()` doc).
        await tester.pumpRoutedApp(
          _router(repo),
          overrides: <Object>[
            ..._overrides(repo),
            salonManagementProfileProvider(_kSalonId).overrideWith(() {
              return _AttemptCountingSalonManagementProfile(() {
                attempt++;
                if (attempt == 1) throw const ServerFailure(statusCode: 500);
                return (_stubSalon, _stubMasters);
              });
            }),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('error_state_retry_button')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('salon-manage-hero-card')), findsNothing);

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsNothing);
        expect(find.byKey(const Key('salon-manage-hero-card')), findsOneWidget);
      },
    );
  });
}
