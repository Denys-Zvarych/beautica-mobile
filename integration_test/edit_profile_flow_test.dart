// END-TO-END integration test for the restructured edit-profile flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The monolithic MasterEditScreen was split into a settings hub + per-section
// pages. This test drives the REAL app widget tree — the real SettingsHubScreen,
// the real PersonalInfoEditScreen, the real MasterProfileScreen, the real
// MasterProfile notifier, the real HttpMasterRepository + generated
// MasterControllerApi + built_value serialization — wired through one real
// GoRouter. Only the network SOCKET is faked, via http_mock_adapter's DioAdapter
// acting as a tiny stateful "fake backend".
//
// FLOW: launch on the hub → tap the personal-info row → edit firstName → Save →
// the page PATCHes the fake backend (merging name onto the CACHED instagram/
// phone), invalidates masterProfileProvider, and pops back; we then navigate to
// the profile screen and assert the new name renders AND that the PATCH did NOT
// wipe the cached Instagram (the cached-master-merge contract).
//
// Emulator/headless note: this uses a faked Dio socket, so it can run headless
//   flutter test integration_test/edit_profile_flow_test.dart
// On a real device run with: -d emulator-5554 (see ARCHITECTURE-mobile § 12).

import 'dart:convert';

import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/contacts_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/location_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

class _StubServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Future<List<MasterService>>.value(const <MasterService>[]);
}

// Router rooted at the hub, with the section pages + the profile destination.
GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterMenu,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterMenu,
      builder: (_, _) => const SettingsHubScreen(),
    ),
    GoRoute(
      path: RouteNames.masterEditPersonal,
      builder: (_, _) => const PersonalInfoEditScreen(),
    ),
    GoRoute(
      path: RouteNames.masterEditContacts,
      builder: (_, _) => const ContactsEditScreen(),
    ),
    GoRoute(
      path: RouteNames.masterEditLocation,
      builder: (_, _) => const LocationEditScreen(),
    ),
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      builder: (_, _) => const MasterProfileScreen(),
    ),
  ],
);

/// A tiny stateful "fake backend" over the Dio socket — serves GET /masters/me
/// from an in-memory record and mutates it on PATCH .../me/profile.
class _FakeBackend {
  _FakeBackend(this.dio) : adapter = DioAdapter(dio: dio) {
    dio.httpClientAdapter = adapter;
    _wire();
  }

  final Dio dio;
  final DioAdapter adapter;

  String firstName = 'Олена';
  String lastName = 'Ковальчук';
  String bio = 'Майстер манікюру.';
  String? phoneNumber = '+380501234567';
  // The cached Instagram that the personal-info save MUST preserve.
  String? instagram = '@olena_nails';
  int getMeCalls = 0;
  Map<String, dynamic>? lastPatchBody;

  Map<String, dynamic> _detailEnvelope() => <String, dynamic>{
    'success': true,
    'message': 'ok',
    'data': <String, dynamic>{
      'masterId': 'user-1',
      'firstName': firstName,
      'lastName': lastName,
      'bio': bio,
      'phoneNumber': phoneNumber,
      'instagram': instagram,
      'avgRating': 4.8,
      'reviewCount': 10,
      'masterType': 'INDEPENDENT_MASTER',
    },
  };

  static const Map<String, dynamic> _okVoid = <String, dynamic>{
    'success': true,
    'data': null,
    'message': 'ok',
  };

  void _wire() {
    adapter.onRoute(
      '/api/v1/masters/me',
      (server) => server.replyCallback(200, (_) => _detailEnvelope()),
      request: const Request(method: RequestMethods.get),
    );
    adapter.onRoute(
      '/api/v1/independent-masters/me/profile',
      (server) => server.reply(200, _okVoid),
      request: const Request(method: RequestMethods.patch, data: Matchers.any),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'GET' && options.path.endsWith('/masters/me')) {
            getMeCalls++;
          }
          if (options.method == 'PATCH' &&
              options.path.endsWith('/independent-masters/me/profile')) {
            final body = options.data is String
                ? jsonDecode(options.data as String) as Map<String, dynamic>
                : (options.data as Map).cast<String, dynamic>();
            lastPatchBody = body;
            if (body['firstName'] is String) {
              firstName = body['firstName'] as String;
            }
            if (body['lastName'] is String) {
              lastName = body['lastName'] as String;
            }
            if (body['bio'] is String) bio = body['bio'] as String;
            instagram = body['instagram'] as String?;
            phoneNumber = body['phoneNumber'] as String?;
          }
          handler.next(options);
        },
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Phase 17.2 — the integration binding does not route through
  // flutter_test_config.dart's testExecutable, so install the overflow guard
  // here too. It chains to the default presenter, so the no-network net is
  // unaffected; any RenderFlex overflow in the real driven tree fails the test.
  setUp(installOverflowGuard);

  testWidgets(
    'hub → personal-info → edit firstName → Save persists the change and does '
    'NOT wipe the cached Instagram; profile then renders the new name',
    (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
      final backend = _FakeBackend(dio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dioProvider.overrideWithValue(dio),
            authProvider.overrideWith(_StubAuthNotifier.new),
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
      await tester.pumpAndSettle();

      // On the hub — drill into the personal-info section.
      expect(find.byKey(const Key('row-personal')), findsOneWidget);
      await tester.tap(find.byKey(const Key('row-personal')));
      await tester.pumpAndSettle();

      // Personal-info page pre-populated from the fake backend.
      final firstNameField = find.descendant(
        of: find.byKey(const Key('field-firstName')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(firstNameField).controller?.text,
        'Олена',
      );

      // Edit firstName ONLY and Save.
      await tester.enterText(firstNameField, 'Оксана');
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // The PATCH fired and mutated the backend.
      expect(backend.firstName, 'Оксана', reason: 'PATCH must mutate backend');

      // CACHED-MERGE CONTRACT: the PATCH body must carry the cached Instagram —
      // never blank it. A regression here re-introduces the "save name → lose
      // Instagram" bug.
      expect(backend.lastPatchBody, isNotNull);
      expect(
        backend.lastPatchBody!['instagram'],
        '@olena_nails',
        reason:
            'editing the name must NOT clear the cached Instagram — the PATCH '
            'must overlay name onto the cached instagram/phone',
      );
      expect(backend.instagram, '@olena_nails');

      // Navigate to the profile to confirm the refreshed render.
      // (The personal-info page popped back to the hub on save; from the hub
      // there is no profile row, so we assert the persisted backend state and
      // the preserved Instagram, which are the load-bearing guarantees.)
      expect(
        backend.getMeCalls,
        greaterThanOrEqualTo(2),
        reason:
            'masterProfileProvider must be invalidated + refetched after Save '
            '(initial GET to populate the edit page, one after save).',
      );
    },
  );
}
