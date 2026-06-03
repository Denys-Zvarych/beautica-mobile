// Regression safety net (2026-06-02) — Fix 4.
//
// END-TO-END integration test for the critical edit-profile flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget tests mock the repository; even the transport tests exercise only
// the data layer in isolation. This test drives the REAL app widget tree — the
// real MasterEditScreen, the real MasterProfileScreen, the real MasterProfile
// notifier, the real HttpMasterRepository, the real generated MasterControllerApi
// and the real built_value serialization — wired through a single real GoRouter.
//
// Only the network SOCKET is faked, via http_mock_adapter's DioAdapter acting as
// a tiny stateful "fake backend": it serves GET /masters/me from an in-memory
// master record and mutates that record on PATCH .../me/profile, exactly like a
// real round-trip. So this runs headless in CI with no live server, via
//   flutter test integration_test/edit_profile_flow_test.dart
//
// FLOW: launch on the edit screen → edit firstName → tap Save → the edit screen
// PATCHes the fake backend, invalidates masterProfileProvider, and navigates to
// the profile screen, whose notifier GETs the (now-mutated) record. We assert
// the displayed profile name reflects the change.
//
// If the save/refresh path is broken (no invalidate, stale read, or a contract
// mismatch in the real serialization), the profile screen renders the OLD name
// and this test FAILS — the intended regression signal. No production code is
// modified to make it pass.

import 'dart:convert';

import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:integration_test/integration_test.dart';

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

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterEdit,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEdit,
      pageBuilder: (context, state) =>
          const NoTransitionPage<void>(child: MasterEditScreen()),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      pageBuilder: (context, state) =>
          const NoTransitionPage<void>(child: MasterProfileScreen()),
    ),
  ],
);

/// A tiny stateful "fake backend" over the Dio socket. Holds one in-memory
/// master record, serves it on GET /masters/me, and mutates firstName/lastName/
/// bio/instagram/phoneNumber on PATCH .../me/profile — a real round-trip shape.
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
  // Phone is REQUIRED by the edit form's validation (a real master always has
  // one). Seed a valid value so Save passes validation and the PATCH fires;
  // a null phone would block Save on the required-phone rule and the firstName
  // mutation under test would never reach the fake backend.
  String? phoneNumber = '+380501234567';
  String? instagram;
  int getMeCalls = 0;

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
    // GET /api/v1/masters/me — serves the CURRENT in-memory record. MUST use
    // replyCallback (not reply) so _detailEnvelope() is re-evaluated on EVERY
    // request: a plain reply(200, _detailEnvelope()) would freeze the envelope
    // at wire time (firstName='Олена') and a post-mutation GET would return
    // stale data — a harness false-positive, not the product behaviour.
    adapter.onRoute(
      '/api/v1/masters/me',
      (server) => server.replyCallback(200, (_) => _detailEnvelope()),
      request: const Request(method: RequestMethods.get),
    );

    // PATCH /api/v1/independent-masters/me/profile — mutate the record from the
    // request body, then 200 OK. The interceptor below captures the body.
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

  testWidgets(
    'edit-profile e2e: launch → edit firstName → Save → profile screen shows '
    'the persisted change (real screens + real notifier + faked transport)',
    (tester) async {
      // Real Dio with no interceptor chain (the app's interceptors need cert
      // pinning / token store that are out of scope here); the DioAdapter fakes
      // the socket. The generated MasterControllerApi and HttpMasterRepository
      // run for real on top of it.
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

      // Edit screen pre-populated from the fake backend's GET /masters/me.
      final firstNameField = find.descendant(
        of: find.byKey(const Key('field-firstName')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(firstNameField).controller?.text,
        'Олена',
      );

      // Edit firstName and Save.
      await tester.enterText(firstNameField, 'Оксана');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-master')));
      await tester.pumpAndSettle();
      // Give the post-invalidate re-GET time to complete on a real device, then
      // settle the rebuilt profile screen. (No-op under the fake clock; needed
      // for the on-device integration binding where the socket is real-async.)
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // The fake backend recorded the mutation.
      expect(backend.firstName, 'Оксана', reason: 'PATCH must mutate backend');

      // The profile screen must have re-fetched after invalidation (initial GET
      // for the edit screen + at least one more after Save).
      expect(
        backend.getMeCalls,
        greaterThanOrEqualTo(2),
        reason:
            'masterProfileProvider must be invalidated + refetched after Save '
            '(one GET to populate the edit screen, one after save).',
      );

      // Navigated to the profile screen.
      expect(find.byKey(const Key('master-profile-name')), findsOneWidget);

      // The displayed profile reflects the persisted change.
      expect(
        find.text('Оксана Ковальчук'),
        findsOneWidget,
        reason:
            'After Save, the profile screen must re-GET /masters/me and render '
            'the new name. If it still shows the old name, the save→refresh→'
            'display path is broken (the "save → nothing persists" bug).',
      );
    },
  );
}
