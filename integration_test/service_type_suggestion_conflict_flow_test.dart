// E2E — the suggest-a-service-type dialog maps a 409's typed `data.code`
// (docs/specs/services.md § 10) to its own copy instead of «Помилка сервера»,
// stays open, and lets the master resubmit (Step 2.7 Rule 3b end-to-end
// coverage for the fix/suggestion-conflict-messages fix).
//
// Journey (INDEPENDENT_MASTER with ZERO services):
//   1. Login → «Послуги» tab → zero-services «Додати послуги» CTA → setup.
//   2. Expand NAILS → scroll to its «suggest a type» prompt → open the dialog.
//   3. Arm the fake backend's ONE-SHOT 409 → type a name → submit.
//   4. The code's localized copy renders; errServer does not; dialog open.
//   5. (CATEGORY_BUSY only) resubmit the intact input → 200 → dialog pops,
//      success snack, exactly two POSTs with the same name.
//
// Unlike the widget test (which hands the dialog a pre-built ServerFailure),
// this drives the REAL wire: Dio → ErrorMapperInterceptor → repository →
// `ServerFailure.errorCode` reading `data.code` off the 409 envelope.
//
// KEY POLICY: key-based finders; copy read from a live context's
// AppLocalizations (ARB source), never retyped literals.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

const String _kSuggestedName = 'Ламінування нігтів';
const Key _kDialogNameField = Key('field-service-type-suggest-name');
const Key _kDialogSubmit = Key('btn-submit-suggest-service-type');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // Bounded pumps — ServiceSetupScreen holds a never-settling loading
  // animation, so pumpAndSettle would hang (same as
  // service_setup_field_error_flow_test.dart); pumpAndSettle also fires no
  // Timer, and the VelvetSnack dwell is a Timer.
  Future<void> pumpFor(WidgetTester tester, {int frames = 12}) async {
    for (int i = 0; i < frames; i++) {
      // fixed-wait-ok: ServiceSetupScreen holds a never-settling in-flight loading animation (pumpAndSettle hangs) and the VelvetSnack dwell is a Timer pumpAndSettle never fires — advance bounded fixed frames.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder nameField() => find.descendant(
    of: find.byKey(_kDialogNameField),
    matching: find.byType(TextField),
  );

  /// Boots, logs in as a zero-services INDEPENDENT_MASTER, opens the setup
  /// screen, expands NAILS and opens the suggest-a-type dialog for it.
  Future<void> openSuggestDialog(WidgetTester tester, FakeBackend fb) async {
    await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    final Finder servicesTab = find.byKey(const Key('master-profile-tab-1'));
    await tester.ensureVisible(servicesTab);
    await tester.tap(servicesTab);
    await tester.pumpAndSettle();

    final Finder cta = find.byKey(const Key('btn-master-add-services'));
    await tester.scrollUntilVisible(
      cta,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpUntilFound(cta);
    await tester.ensureVisible(cta);
    await tester.tap(cta);
    await pumpFor(tester, frames: 20);
    expect(find.byKey(const Key('btn-setup-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('cat_NAILS')));
    await pumpFor(tester, frames: 16);

    // 800x600 headless: the prompt closes the expanded category's list and
    // is off-screen until scrolled.
    final Finder prompt = find.byKey(
      const ValueKey<String>('suggest_type_NAILS'),
    );
    await tester.scrollUntilVisible(
      prompt,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(prompt);
    await tester.tap(prompt);
    await pumpFor(tester);
    await tester.pumpUntilFound(find.byKey(_kDialogSubmit));
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(_kDialogSubmit));
    await pumpFor(tester);
  }

  testWidgets(
    '409 CATEGORY_BUSY shows the category-busy copy (not errServer), keeps '
    'the dialog open, and resubmitting the intact name succeeds',
    (tester) async {
      final fb = FakeBackend()..clearServices();
      await openSuggestDialog(tester, fb);

      fb.forceSuggestServiceTypeFailure(409, errorCode: 'CATEGORY_BUSY');
      await tester.enterText(nameField(), _kSuggestedName);
      await tester.pump();
      await submit(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(_kDialogSubmit)),
      );
      expect(fb.suggestServiceTypeCalls, 1);
      expect(fb.lastSuggestServiceTypeBody?['categoryName'], 'NAILS');
      expect(
        find.text(l10n.serviceTypeSuggestErrCategoryBusy),
        findsOneWidget,
        reason: 'the 409 CATEGORY_BUSY must surface its own copy',
      );
      expect(find.text(l10n.errServer), findsNothing);
      expect(find.byKey(_kDialogSubmit), findsOneWidget);
      expect(
        tester.widget<TextField>(nameField()).controller?.text,
        _kSuggestedName,
      );

      // Wait the error snack out (Timer dwell), then resubmit WITHOUT retyping.
      await tester.pumpUntilGone(find.byType(VelvetSnack));
      await submit(tester);

      expect(fb.suggestServiceTypeCalls, 2);
      expect(fb.lastSuggestServiceTypeBody?['name'], _kSuggestedName);
      await tester.pumpUntilGone(find.byKey(_kDialogSubmit));
      await tester.pumpUntilFound(find.text(l10n.serviceTypeSuggestSuccess));
      await tester.pumpUntilGone(find.byType(VelvetSnack));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    '409 DUPLICATE_PENDING shows the already-pending copy (not errServer) and '
    'keeps the dialog open',
    (tester) async {
      final fb = FakeBackend()..clearServices();
      await openSuggestDialog(tester, fb);

      fb.forceSuggestServiceTypeFailure(409, errorCode: 'DUPLICATE_PENDING');
      await tester.enterText(nameField(), _kSuggestedName);
      await tester.pump();
      await submit(tester);

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(_kDialogSubmit)),
      );
      expect(fb.suggestServiceTypeCalls, 1);
      expect(
        find.text(l10n.serviceTypeSuggestErrDuplicatePending),
        findsOneWidget,
        reason: 'the 409 DUPLICATE_PENDING must surface its own copy',
      );
      expect(find.text(l10n.errServer), findsNothing);
      expect(find.byKey(_kDialogSubmit), findsOneWidget);
      await tester.pumpUntilGone(find.byType(VelvetSnack));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
