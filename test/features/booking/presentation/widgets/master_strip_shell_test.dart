// Widget tests for `MasterStripShell` — the slot-based frame
// (`lib/features/booking/presentation/widgets/master_strip_shell.dart`) behind
// `MasterStrip`, the ONE identity card every booking screen in BOTH flows
// (independent-master and salon) now renders.
//
// The shell owns the fixed frame (avatar + optional topLabel + name + optional
// middleLine + optional trailing); call sites differ only in which slots they
// fill. These tests drive the shell directly with stand-in slot content to
// prove no slot is dropped in any composition, and that the
// avatar is rendered through the Impeller-safe RRect badge (never a
// `BoxShape.circle`, whose blurred box-shadow rasterizes as a hard white square
// under Impeller-GLES — see `impeller_circle_shadow_guard_test.dart`).

import 'package:beautica_mobile/features/booking/presentation/widgets/master_avatar_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// Asserts the shell's avatar is the shared RRect badge, not a circle — the
/// Impeller-GLES box-shadow safety invariant, checked structurally here so the
/// shell can never route an avatar through a broken circle path.
void _expectImpellerSafeAvatar(WidgetTester tester) {
  expect(find.byType(MasterAvatarBadge), findsOneWidget);
  final Container avatarBox = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(MasterAvatarBadge),
          matching: find.byType(Container),
        )
        .first,
  );
  final BoxDecoration deco = avatarBox.decoration! as BoxDecoration;
  expect(
    deco.shape,
    BoxShape.rectangle,
    reason:
        'the shared avatar badge must be an RRect (rectangle + '
        'borderRadius), never BoxShape.circle — a blurred BoxShadow on a '
        'circle rasterizes as a hard white square under Impeller-GLES.',
  );
  expect(
    deco.borderRadius,
    isNotNull,
    reason: 'the RRect avatar must carry a borderRadius to read as a circle.',
  );
}

void main() {
  group('MasterStripShell', () {
    testWidgets(
      'independent-style composition renders every slot: topLabel + name + '
      'title middleLine + rating trailing, over an Impeller-safe avatar',
      (tester) async {
        await tester.pumpApp(
          const Center(
            child: MasterStripShell(
              // i18n-finder-ok: shell is a layout primitive; these are opaque
              // slot stand-ins, not production UI copy governed by l10n.
              semanticsLabel: 'independent-sem',
              name: 'Тарас Мельник',
              topLabel: 'Запис до майстра',
              middleLine: Text('Барбер', key: Key('mid-title')),
              trailing: Icon(Icons.star_rounded, key: Key('trail-rating')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MasterStripShell), findsOneWidget);
        // i18n-finder-ok: opaque slot stand-ins below.
        expect(find.text('Запис до майстра'), findsOneWidget); // topLabel slot
        // i18n-finder-ok: opaque slot stand-in, not app copy.
        expect(find.text('Тарас Мельник'), findsOneWidget); // name slot
        expect(find.byKey(const Key('mid-title')), findsOneWidget); // middle
        expect(find.byKey(const Key('trail-rating')), findsOneWidget); // trail
        _expectImpellerSafeAvatar(tester);
      },
    );

    testWidgets('salon-style composition renders name + services middleLine + '
        'duration-pill trailing, with NO topLabel dropped when omitted, over an '
        'Impeller-safe bordered avatar', (tester) async {
      await tester.pumpApp(
        Center(
          child: MasterStripShell(
            // i18n-finder-ok: opaque slot stand-ins, not UI copy.
            semanticsLabel: 'salon-sem',
            name: 'Ірина Бондаренко',
            avatarGradient: const <Color>[Color(0xFFD8BE9C), Color(0xFF6A4A28)],
            avatarBordered: true,
            middleGap: 4,
            middleLine: const Text(
              'Манікюр · Педикюр',
              key: Key('mid-services'),
            ),
            trailing: Container(key: const Key('trail-duration-pill')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MasterStripShell), findsOneWidget);
      // i18n-finder-ok: opaque slot stand-in.
      expect(find.text('Ірина Бондаренко'), findsOneWidget); // name slot
      expect(find.byKey(const Key('mid-services')), findsOneWidget); // middle
      expect(
        find.byKey(const Key('trail-duration-pill')),
        findsOneWidget,
      ); // trailing pill slot
      // topLabel omitted → the salon-style card renders none (proves the
      // optional slot is genuinely optional, not a required frame element).
      // i18n-finder-ok: opaque slot stand-in.
      expect(find.text('Запис до майстра'), findsNothing);

      // The salon avatar wash opts into the bordered ring — still routed
      // through the same Impeller-safe RRect badge.
      final MasterAvatarBadge badge = tester.widget<MasterAvatarBadge>(
        find.byType(MasterAvatarBadge),
      );
      expect(
        badge.bordered,
        isTrue,
        reason:
            'avatarBordered:true must reach the shared badge as its '
            'translucent-white ring flag.',
      );
      _expectImpellerSafeAvatar(tester);
    });
  });

  // ── Phase 240 — the new optional `onTap` branch ──────────────────────────
  //
  // The shell now has TWO shapes: inert (unchanged widget tree) and tappable
  // (a nested transparency `Material` + radius-clipped `InkWell` INSIDE the
  // `DecoratedBox`). The nesting is not cosmetic — ink is painted by the
  // nearest Material ancestor UNDERNEATH its child, so an `InkWell` hung off
  // the outer transparency Material would splash beneath the card's opaque
  // `_stripSurface` fill and never be seen. These tests pin that structure,
  // the a11y collapse, and — critically — that the INERT branch stays inert,
  // since half the nine screens mounting this card must not navigate.
  group('MasterStripShell — onTap branch', () {
    testWidgets('onTap:null leaves the card genuinely inert: no InkWell, no '
        'button semantics, no tap action', (tester) async {
      await tester.pumpApp(
        const Center(
          // i18n-finder-ok: opaque slot stand-in.
          child: MasterStripShell(semanticsLabel: 'inert-sem', name: 'Олена'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(MasterStripShell),
          matching: find.byType(InkWell),
        ),
        findsNothing,
        reason:
            'the three in-flight wizard steps mount this card and MUST NOT '
            'offer a tap that yanks the client out of a half-made booking.',
      );

      final SemanticsHandle handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(MasterStripShell)),
        isSemantics(isButton: false, hasTapAction: false),
        reason:
            'an inert strip is a pure identity readout — announcing it as a '
            'button would promise an action it does not have.',
      );
      handle.dispose();
    });

    testWidgets('a non-null onTap makes the whole card tappable and the tap '
        'reaches the callback', (tester) async {
      int taps = 0;
      await tester.pumpApp(
        Center(
          child: MasterStripShell(
            // i18n-finder-ok: opaque slot stand-in.
            semanticsLabel: 'tappable-sem',
            name: 'Олена',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tapped at the card's own centre, not on a child key — the affordance
      // is the WHOLE card surface, which is why the InkWell wraps the padded
      // content rather than sitting inside it.
      await tester.tap(find.byType(MasterStripShell));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('the InkWell lives INSIDE the DecoratedBox, under its own '
        'Material — hung off the outer Material the wash would paint beneath '
        'the card fill and be invisible', (tester) async {
      await tester.pumpApp(
        Center(
          child: MasterStripShell(
            // i18n-finder-ok: opaque slot stand-in.
            semanticsLabel: 'tappable-sem',
            name: 'Олена',
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder inkWell = find.descendant(
        of: find.byType(MasterStripShell),
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);

      // Structural ordering assertion: the InkWell must be a DESCENDANT of the
      // DecoratedBox (below the opaque fill), and must itself have a Material
      // between it and that box. A regression that reparents it above the
      // DecoratedBox fails the first expect; one that drops the nested
      // Material fails the second.
      final Finder decoratedBox = find.descendant(
        of: find.byType(MasterStripShell),
        matching: find.byType(DecoratedBox),
      );
      expect(
        find.descendant(of: decoratedBox, matching: find.byType(InkWell)),
        findsOneWidget,
        reason:
            'the ink layer must sit UNDER the card fill in the tree so it '
            'paints ON TOP of it — Material paints ink beneath its child.',
      );
      expect(find.ancestor(of: inkWell, matching: decoratedBox), findsWidgets);
      expect(
        find.descendant(
          of: find.ancestor(of: inkWell, matching: find.byType(Material)).first,
          matching: inkWell,
        ),
        findsOneWidget,
        reason: 'the InkWell needs its OWN Material ancestor to paint into.',
      );

      // The wash is clipped to the card's own 24dp corners, so a press cannot
      // square off the rounded card.
      expect(
        tester.widget<InkWell>(inkWell).borderRadius,
        const BorderRadius.all(Radius.circular(24)),
        reason:
            'an unclipped splash paints square corners over the rounded card '
            '— the exact class of regression the golden also guards.',
      );
    });

    testWidgets('the tappable card announces as ONE actionable button, not a '
        'labelled button plus a separate actionable node', (tester) async {
      int taps = 0;
      await tester.pumpApp(
        Center(
          child: MasterStripShell(
            // i18n-finder-ok: opaque slot stand-in.
            semanticsLabel: 'Олена Ковальчук, майстриня, 4.9',
            name: 'Олена Ковальчук',
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final SemanticsHandle handle = tester.ensureSemantics();
      final SemanticsNode node = tester.getSemantics(
        find.byType(MasterStripShell),
      );

      expect(node.label, 'Олена Ковальчук, майстриня, 4.9');
      expect(node, isSemantics(isButton: true, hasTapAction: true));

      // The subtree is EXCLUDED, so the InkWell's own button node must not
      // survive as a second announcement. Asserting the flags alone would not
      // catch the double-announce; counting the actionable descendants does.
      //
      // Drive the real assistive-tech path — not `tester.tap` — because the
      // whole failure mode is a node whose flags are right while its action
      // is missing.
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(
        taps,
        1,
        reason:
            'excludeSemantics strips the InkWell action out of the tree, so '
            'the outer node has to carry it or the card announces as a button '
            'that cannot be activated.',
      );

      handle.dispose();
    });
  });
}
