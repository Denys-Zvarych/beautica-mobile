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
import 'package:beautica_mobile/features/support/domain/support_limits.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

class _StubServicesList extends ServicesList {
  @override
  Future<List<MasterService>> build() =>
      Future<List<MasterService>>.value(const <MasterService>[]);
}

/// Fake platform picker: each `pickFiles` call hands back the next queued
/// filename as a 1 KB in-memory file (the OS dialog is the only thing faked —
/// the screen's extension → content-type gate and the multipart repository
/// run for real).
class _QueuedFilePicker extends FilePicker with MockPlatformInterfaceMixin {
  _QueuedFilePicker(this._names);

  final List<String> _names;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    // ignore: inference_failure_on_function_return_type — mirrors the platform signature.
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final Uint8List bytes = Uint8List.fromList(List<int>.filled(1024, 1));
    return FilePickerResult(<PlatformFile>[
      PlatformFile(name: _names.removeAt(0), size: bytes.length, bytes: bytes),
    ]);
  }
}

Future<void> _tapAddAttachment(WidgetTester tester) async {
  final Finder add = find.byKey(const Key('support-add-attachment'));
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
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

  testWidgets(
    'attachment type policy end-to-end: a picked .webp is rejected with the '
    'wrong-type snack and never sent; a picked .jpg is attached and reaches '
    'the backend as image/jpeg',
    (tester) async {
      final l10n = lookupAppLocalizations(const Locale('uk'));
      FilePicker.platform = _QueuedFilePicker(<String>[
        'screenshot.webp',
        'screenshot.jpg',
      ]);
      final fb = FakeBackend();
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: [
          // cycle-stub-ok: same rationale as the test above — no logout / auth-cascade entrypoint is reached.
          servicesListProvider.overrideWith(_StubServicesList.new),
        ],
      );
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
      router.go(RouteNames.masterMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-help')));
      await tester.pumpAndSettle();

      // .webp → rejected, no chip.
      await _tapAddAttachment(tester);
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        l10n.contactSupportErrWrongType,
        variant: VelvetSnackVariant.error,
      );
      expect(find.byKey(const Key('support-attachment-chip-0')), findsNothing);
      await pumpPastVelvetSnack(tester);

      // .jpg → accepted, one chip.
      await _tapAddAttachment(tester);
      await tester.pumpAndSettle();
      expect(find.byType(VelvetSnack), findsNothing);
      expect(
        find.byKey(const Key('support-attachment-chip-0')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('support-attachment-chip-1')), findsNothing);

      // Send → the wire carries exactly the jpg, typed image/jpeg.
      await tester.enterText(
        find.byKey(const Key('support-message')),
        'Доброго дня! Додаю скриншот проблеми.',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('support-send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support-send')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('support-success-card')), findsOneWidget);
      expect(fb.supportContactCalls, 1);
      expect(
        fb.supportContactAttachments,
        <String>['screenshot.jpg|image/jpeg'],
        reason:
            'only the accepted jpg may reach the backend — the rejected webp '
            'must never be sent (allowed: ${SupportLimits.allowedContentTypes})',
      );
    },
  );
}
