// END-TO-END integration test for the support / "Напишіть нам" contact flow.
//
// WHY THIS FILE EXISTS
// --------------------
// The Step 2.7 QA gate requires a fake-backed integration flow for any feature
// that touches a screen / route / navigation / provider–repository wiring /
// form submit / API contract. The support feature touches ALL of these: a new
// settings-hub row, a new route, a real SupportController → HttpSupportRepository
// → raw multipart POST. This drives the REAL app tree — the real
// SettingsHubScreen, the real ContactSupportScreen, the real SupportController,
// the real HttpSupportRepository — through one real GoRouter. Only the network
// SOCKET is faked, via the shared Phase 17.3 FakeBackend (a DioAdapter acting as
// a tiny stateful fake backend), now wired with `POST /api/v1/support/contact`.
//
// FLOW: log in as the master → open the settings hub → tap row-help → fill the
// message → tap Send → assert the success card renders AND the fake backend
// received exactly one support POST.
//
// KEY-BASED NAVIGATION POLICY (enforced, see app_harness.dart):
//   ALL navigation taps use find.byKey() — no raw Ukrainian find.text() tap
//   drivers. Content may be asserted by key.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

class _StubServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Future<List<MasterService>>.value(const <MasterService>[]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'master → settings hub → help row → fill message → Send → success card '
    'renders and the backend received exactly one support POST',
    (tester) async {
      final fb = FakeBackend();

      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: [
          // cycle-stub-ok: the support-contact flow never invokes a cyclic teardown entrypoint (no logout / auth-cascade), so stubbing the top-of-chain servicesListProvider cannot hide the cycle. logout_flow_test.dart guards that path on the REAL graph.
          servicesListProvider.overrideWith(_StubServicesList.new),
        ],
      );

      // Authenticate as the independent master, then open the settings hub.
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      router.go(RouteNames.masterMenu);
      await tester.pumpAndSettle();

      // On the hub — drill into the help / contact-us row.
      expect(find.byKey(const Key('row-help')), findsOneWidget);
      await tester.tap(find.byKey(const Key('row-help')));
      await tester.pumpAndSettle();

      // On the contact screen — the form is editable, Send not yet fired.
      expect(find.byKey(const Key('support-message')), findsOneWidget);
      expect(find.byKey(const Key('support-success-card')), findsNothing);

      // Fill a valid message and (optionally) a subject.
      await tester.enterText(
        find.byKey(const Key('support-subject')),
        'Питання щодо запису',
      );
      await tester.enterText(
        find.byKey(const Key('support-message')),
        'Доброго дня! Маю питання щодо роботи застосунку.',
      );
      await tester.pumpAndSettle();

      // Send.
      await tester.tap(find.byKey(const Key('support-send')));
      await tester.pumpAndSettle();

      // The success card replaces the form.
      expect(
        find.byKey(const Key('support-success-card')),
        findsOneWidget,
        reason: 'a successful send must swap the form for the success card',
      );
      expect(find.byKey(const Key('support-success-done')), findsOneWidget);

      // The fake backend received exactly one support POST.
      expect(
        fb.supportContactCalls,
        1,
        reason: 'Send must POST the contact message to the backend once',
      );

      // The success-card "Готово" CTA returns to the hub (canPop path).
      await tester.tap(find.byKey(const Key('support-success-done')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('row-help')),
        findsOneWidget,
        reason: 'Done must pop back to the settings hub',
      );
    },
  );
}
