// E2E — MasterProfileScreen (OWN profile) identity-card address block:
// split locality/street lines (Phase 220 C) + the tap-to-expand location
// note (Phase 221 B), driven against a REAL `GET /masters/me` response.
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 219/220/221 shipped THREE changes to the identity card:
//   (A) an explicit `maxLines` budget on every address/note Text so the old
//       `maxLines: null` + `overflow: ellipsis` combo can never again
//       silently collapse a long note to one line;
//   (B) a tap-to-expand «більше»/«згорнути» affordance on the OWN profile's
//       location note (`ExpandableNote`, `lib/shared/widgets/
//       expandable_note.dart`) — Phase 222 later ported the same affordance
//       to the read-only public profile too;
//   (C) the combined "street, building, city" string split into independent
//       locality / street+building lines.
//
// The widget tier (test/features/master/presentation/master_profile_screen_
// test.dart) already proves all three against a STUBBED masterProfileProvider
// — but nothing previously drove them against a REAL `GET /masters/me`
// response. Before this file, `FakeBackend._masterDetailEnvelope()` did not
// even serialize city/street/buildingNo/locationNote, so the OWN-profile E2E
// journey never exercised this block at all (see the new `masterCity` /
// `masterStreet` / `masterBuildingNo` / `masterLocationNote` fields added to
// FakeBackend alongside this flow).
//
// This flow boots the REAL app via AppHarness (FakeBackend socket,
// FakeSecureStorage, fixed clock, overflow guard), logs in as
// INDEPENDENT_MASTER, and drives the full split-address + expand/collapse
// interaction against the real MasterProfile notifier + HttpMasterRepository
// + generated MasterControllerApi stack.
//
// KEY POLICY: navigation/interaction taps are key-based
// (expandable-note-toggle); `find.text` is used only for
// content assertions on backend-sourced data (city/street/note strings),
// never as a tap driver.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// A ~400-char entrance-instructions note — the same realistic long-note
/// fixture shape used by the widget-tier reproduction test, well past the
/// `maxLines: 3` (Phase 219 A) budget at any phone width.
const String _kLongLocationNote =
    'Вхід у двір з боку вулиці Хрещатик, повз кав\'ярню на розі — не '
    'плутайте з сусіднім під\'їздом, там кодовий замок не працює. Тримайтеся '
    'правої стіни, минаєте дитячий майданчик, підіймаєтесь трьома сходинками '
    'до скляних дверей із синьою наклейкою. Домофон код 45В, дзвоніть двічі '
    'коротко. Якщо домофон не відповідає — телефонуйте адміністратору, номер '
    'вказано на вивісці біля дверей. Кабінет на другому поверсі, одразу '
    'ліворуч від сходів, третій номер за рахунком.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'INDEPENDENT_MASTER opens their own profile → the identity card renders '
    'the REAL GET /masters/me city + street+building on independent lines, '
    'the long note clamps with a «більше» toggle, and tapping it reveals the '
    'FULL note text and flips the label to «згорнути»',
    (tester) async {
      final fb = FakeBackend()
        ..masterCity = 'Київ'
        ..masterStreet = 'вул. Хрещатик'
        ..masterBuildingNo = '22'
        ..masterLocationNote = _kLongLocationNote;

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      AppHarness.expectLocation(router, RouteNames.masterProfile);

      // ── The real GET /masters/me response actually fired and resolved ────
      expect(
        fb.getMasterCalls,
        greaterThanOrEqualTo(1),
        reason: 'the own-profile identity card must load from a real fetch',
      );

      // ── (C) Locality + street/building render on INDEPENDENT lines ───────
      final Finder localityText = find.byKey(
        const Key('master-profile-locality-text'),
      );
      final Finder addressText = find.byKey(
        const Key('master-profile-address-text'),
      );
      await tester.scrollUntilVisible(
        localityText,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(localityText, findsOneWidget);
      expect(addressText, findsOneWidget);
      // i18n-finder-ok: master.city fixture value (FakeBackend), not UI copy.
      expect(find.text('Київ'), findsOneWidget);
      // i18n-finder-ok: master.street/buildingNo fixture value, not UI copy.
      expect(find.text('вул. Хрещатик, 22'), findsOneWidget);
      // The pre-Phase-220 combined string must never reappear.
      // i18n-finder-ok: same fixture data as above, negated.
      expect(find.text('вул. Хрещатик, 22, Київ'), findsNothing);

      // ── (A)+(B) Long note clamps with the «більше» toggle collapsed ──────
      final Finder toggle = find.byKey(const Key('expandable-note-toggle'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(
        toggle,
        findsOneWidget,
        reason:
            'a note this long must overflow the maxLines: 3 clamp and show '
            'the expand affordance',
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(MasterProfileScreen)),
      );
      expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
      expect(find.text(l10n.expandableNoteShowLess), findsNothing);

      final Size collapsedSize = tester.getSize(find.text(_kLongLocationNote));

      // ── Tap «більше» → full text revealed, label flips to «згорнути» ─────
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.text(l10n.expandableNoteShowLess), findsOneWidget);
      expect(find.text(l10n.expandableNoteShowMore), findsNothing);
      final Size expandedSize = tester.getSize(find.text(_kLongLocationNote));
      expect(
        expandedSize.height,
        greaterThan(collapsedSize.height),
        reason: 'expanding must grow the note to its full untruncated height',
      );

      // ── Tap «згорнути» → collapses back ───────────────────────────────────
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.text(l10n.expandableNoteShowMore), findsOneWidget);
      expect(find.text(l10n.expandableNoteShowLess), findsNothing);
      final Size reCollapsedSize = tester.getSize(
        find.text(_kLongLocationNote),
      );
      expect(
        reCollapsedSize.height,
        moreOrLessEquals(collapsedSize.height, epsilon: 0.5),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
