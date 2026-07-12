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
}
