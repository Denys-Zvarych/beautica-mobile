// E2E — MasterProfileScreen (OWN profile) identity-card address block, driven
// against a REAL `GET /masters/me` response:
//   • Phase 224 — the measured collapse/split decision (`MasterAddressBlock`);
//   • Phase 220 (C) — the split locality / street+building lines;
//   • Phase 219 (A) + 221 (B) — the tap-to-expand location note.
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
// Phase 224 then made (C) CONDITIONAL: the address collapses back onto one
// city-first line («Київ, вул. Хрещатик, 22») whenever that string measurably
// fits the identity card's right-hand column, and keeps (C)'s two-row split
// only when it does not.
//
// The widget tier (test/features/master/presentation/master_profile_screen_
// test.dart, and test/features/master/presentation/widgets/master_address_
// block_test.dart for the measurement itself) proves all of this against a
// STUBBED masterProfileProvider and a hand-sized `SizedBox`. What NOTHING else
// proves is that the decision still comes out right when the address arrives
// as JSON over the wire and the width is whatever the real identity card's
// `Expanded` column hands the block inside the real screen — the two inputs
// the widget tier substitutes. That is this file's job, and it is the reason
// Phase 224 could break this flow while every widget test stayed green: the
// short fixture below used to render the split rows and now renders the
// combined one, and only an E2E assertion on the REAL tree notices.
//
// This flow boots the REAL app via AppHarness (FakeBackend socket,
// FakeSecureStorage, fixed clock, overflow guard), logs in as
// INDEPENDENT_MASTER, and drives the block against the real MasterProfile
// notifier + HttpMasterRepository + generated MasterControllerApi stack.
//
// GROUND TRUTH, NOT A RE-DERIVATION
// ---------------------------------
// Whenever the collapsed row renders, this file reads
// `RenderParagraph.didExceedMaxLines` off the LAID-OUT render object and
// asserts it is false. That is the engine that paints pixels answering
// "was anything clipped?", not a second copy of the `TextPainter` decision
// under test. It is what turns "the collapsed key is present" (which a
// broken-but-consistent measurement would also satisfy) into "the whole
// address is actually legible on screen" — `MasterAddressBlock`'s entire
// contract.
//
// KEY POLICY: navigation/interaction taps are key-based
// (expandable-note-toggle); `find.text` is used only for content assertions on
// backend-sourced data (city/street/note strings), never as a tap driver.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

const Key _kCombinedKey = Key('master-profile-address-combined-text');
const Key _kLocalityKey = Key('master-profile-locality-text');
const Key _kStreetKey = Key('master-profile-address-text');

/// GROUND TRUTH — did the paragraph behind [key] actually overflow its line
/// budget in the laid-out tree? Read off the render object the engine painted,
/// not re-measured.
bool _overflowed(WidgetTester tester, Key key) =>
    tester.renderObject<RenderParagraph>(find.byKey(key)).didExceedMaxLines;

/// Scrolls the identity card's address row into view. Takes the finder for
/// whichever row this test expects, so a wrong expectation fails on the
/// `expect` below with a readable message rather than inside
/// `scrollUntilVisible` with `Bad state: No element`.
Future<void> _revealAddressRow(WidgetTester tester, Finder row) async {
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'Phase 224 — INDEPENDENT_MASTER opens their own profile; a SHORT REAL '
    'GET /masters/me address (city + street + buildingNo) collapses onto ONE '
    'city-first line that is provably not clipped, the split rows are gone, '
    'and the long note still clamps with a working «більше»/«згорнути» toggle '
    'beneath it',
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

      // ── Phase 224: the whole address collapses onto one row ──────────────
      final Finder combined = find.byKey(_kCombinedKey);
      await _revealAddressRow(tester, combined);
      expect(
        combined,
        findsOneWidget,
        reason:
            'a short city+street+building must render as the single combined '
            'row at this width, not as the Phase 220 two-row split',
      );
      // i18n-finder-ok: master city/street/buildingNo fixture values composed
      // by buildCombinedAddressLine — backend data, not UI copy.
      expect(find.text('Київ, вул. Хрещатик, 22'), findsOneWidget);

      // The two paths are mutually exclusive — no orphaned split row.
      expect(find.byKey(_kLocalityKey), findsNothing);
      expect(find.byKey(_kStreetKey), findsNothing);

      // The pre-Phase-220 street-first order must never reappear.
      // i18n-finder-ok: same fixture data as above, negated.
      expect(find.text('вул. Хрещатик, 22, Київ'), findsNothing);

      // ── GROUND TRUTH — collapsing did not silently truncate anything ─────
      expect(
        _overflowed(tester, _kCombinedKey),
        isFalse,
        reason:
            'the block collapsed the address but the REAL paragraph exceeded '
            'its single line — the building number is being ellipsized away, '
            'which is exactly what MasterAddressBlock promises never to do',
      );

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

      // Expanding the note must not knock the address off its collapsed row —
      // the note lives BELOW the address block, so growing it changes the
      // block's height budget but never its width.
      expect(find.byKey(_kCombinedKey), findsOneWidget);
      expect(_overflowed(tester, _kCombinedKey), isFalse);

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

  testWidgets(
    'Phase 224 — a LONG REAL GET /masters/me address at a 360dp phone width '
    'falls back to the Phase 220 two-row split: locality beside the pin, '
    'street+building indented underneath, and NO combined row',
    (tester) async {
      // A real narrow-phone surface. The collapse/split decision is made
      // against the width the identity card's `Expanded` column actually
      // hands the block, so the surface size is a genuine input to this test,
      // not decoration — the same payload collapses on a wide surface (see
      // the `width: 1200` widget-tier case).
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fb = FakeBackend()
        ..masterCity = "Кам'янець-Подільський"
        ..masterStreet = 'вул. Академіка Володимира Філатова'
        ..masterBuildingNo = '145-Б';

      final GoRouter router = await AppHarness.boot(tester, fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      AppHarness.expectLocation(router, RouteNames.masterProfile);
      expect(fb.getMasterCalls, greaterThanOrEqualTo(1));

      final Finder locality = find.byKey(_kLocalityKey);
      await _revealAddressRow(tester, locality);

      // ── No collapse — the measurement rejected it at this width ──────────
      expect(
        find.byKey(_kCombinedKey),
        findsNothing,
        reason:
            'this address cannot fit one line at 360dp; collapsing it here '
            'would ellipsize the building number away',
      );

      // ── Exactly Phase 220's split, from real backend fields ──────────────
      expect(locality, findsOneWidget);
      // i18n-finder-ok: master.city fixture value (FakeBackend), not UI copy.
      expect(find.text("Кам'янець-Подільський"), findsOneWidget);

      final Finder street = find.byKey(_kStreetKey);
      expect(street, findsOneWidget);
      // i18n-finder-ok: master.street/buildingNo fixture values, not UI copy.
      expect(
        find.text('вул. Академіка Володимира Філатова, 145-Б'),
        findsOneWidget,
      );

      // The pre-Phase-220 street-first combined string must never reappear.
      // i18n-finder-ok: same fixture data as above, negated.
      expect(
        find.text(
          "вул. Академіка Володимира Філатова, 145-Б, "
          "Кам'янець-Подільський",
        ),
        findsNothing,
      );

      // Phase 219 (A) regression guard, asserted on the REAL widget rather
      // than on the stubbed one: an explicit line budget, never
      // ellipsis-without-maxLines (which silently collapses to ONE line).
      final Text streetWidget = tester.widget<Text>(street);
      expect(streetWidget.maxLines, 2);
      expect(streetWidget.overflow, TextOverflow.ellipsis);

      // The locality row is the primary icon-bearing row and is budgeted at
      // one line — it must not be clipping either, or the split has bought
      // nothing over the collapse it rejected.
      expect(_overflowed(tester, _kLocalityKey), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
