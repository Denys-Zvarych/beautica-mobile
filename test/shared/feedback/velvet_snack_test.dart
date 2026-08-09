// Widget-tier contract tests for the PRESENTATIONAL `VelvetSnack` widget
// itself (`lib/shared/feedback/velvet_snack.dart`) — mobile-qa, 2026-08-06.
//
// WHY THIS FILE EXISTS
// ---------------------
// `VelvetSnack` is deliberately a pure `StatelessWidget` — no timers, no
// overlay, no animation — specifically so its own visual/semantic contract
// can be pumped and asserted directly, without going through
// `velvet_snack_host.dart`'s `Overlay` machinery. Before this file, every
// existing test either drove the HOST (via `showVelvetSnack` in a consuming
// screen) or was the single same-tick race guard
// (`velvet_snack_host_race_test.dart`) — nothing asserted the WIDGET's own
// promises: that each variant carries its OWN glyph (never another
// variant's), that `maxLines` genuinely bounds the rendered text rather than
// being a decorative default, that the action affordance meets its 32dp tap
// target regardless of label length, and that the `Semantics` node speaks
// the localized severity prefix ahead of the message.
//
// These are pumped directly — no `pumpApp` overlay, no dwell Timer, no
// `pumpPastVelvetSnack` drain needed. Finders here are UNSCOPED but that is
// not the root-overlay rule from `velvet_snack_matchers.dart` — there is no
// host/overlay in play at all in this file, just a single pumped widget.
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

/// Wraps [child] in the same [MaterialType.transparency] `Material` ancestor
/// `velvet_snack_host.dart` provides in production — required so the action
/// / close `InkWell`s can resolve an ink-splash host without asserting.
///
/// Also wraps in [Align]: `pumpApp`'s `home:` slot hands its child TIGHT
/// constraints equal to the full (stress-knob-inflated, up to 2400dp tall)
/// viewport — the real host never does this (`velvet_snack_host.dart`
/// positions the snack via a bottom-anchored `Positioned` with no `top:`,
/// which is loose). Without `Align` here, `VelvetSnack`'s outer
/// `DecoratedBox` is forced to fill that tight height instead of sizing to
/// its own content, which silently made an early version of the maxLines
/// test compare two identical 2400dp heights and pass for the wrong reason.
Widget _harness(Widget child) => Material(
  type: MaterialType.transparency,
  child: Align(alignment: Alignment.topCenter, child: child),
);

void main() {
  group('variant identity — glyph + accent spine', () {
    for (final VelvetSnackVariant variant in VelvetSnackVariant.values) {
      testWidgets(
        '${variant.name} renders its OWN glyph and accent spine, never '
        "another variant's",
        (tester) async {
          await tester.pumpApp(
            _harness(VelvetSnack(variant: variant, message: 'Повідомлення')),
          );

          // The glyph: present, and tinted with THIS variant's accent — not
          // a shared/default color.
          final Finder iconFinder = find.byIcon(variant.icon);
          expect(iconFinder, findsOneWidget);
          final Icon icon = tester.widget<Icon>(iconFinder);
          expect(
            icon.color,
            variant.accent,
            reason: 'the glyph must be tinted with its OWN variant accent',
          );

          // No OTHER variant's glyph leaked in alongside it — this is what
          // makes the "own glyph" claim meaningful rather than "a glyph
          // happens to be present".
          for (final VelvetSnackVariant other in VelvetSnackVariant.values) {
            if (other == variant) continue;
            expect(
              find.byIcon(other.icon),
              findsNothing,
              reason:
                  '${variant.name} must not also render ${other.name}\'s '
                  'glyph',
            );
          }

          // The 4dp leading accent spine — the component's signature
          // element, the one saturated hue that survives truncation.
          final Finder spine = find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.color == variant.accent &&
                w.constraints?.maxWidth == VelvetSizes.snackSpine,
            description:
                'the ${variant.name} spine Container (width '
                '${VelvetSizes.snackSpine}, color ${variant.accent})',
          );
          expect(spine, findsOneWidget);
        },
      );
    }
  });

  group('message truncation', () {
    // Long enough to overflow 2 lines at a 320dp-constrained snack width
    // regardless of the exact font metrics — Ukrainian runs ~25% longer
    // than English per the widget's own doc comment.
    const String longMessage =
        'Це дуже довге повідомлення про статус вашого запису, яке в жодному '
        'разі не повинно поміститися в один чи навіть у два рядки цього '
        'компонента незалежно від ширини екрана мобільного пристрою';

    testWidgets(
      'maxLines genuinely bounds the rendered line count — not a decorative '
      'default the widget ignores',
      (tester) async {
        // Default maxLines (2).
        await tester.pumpApp(
          _harness(
            const VelvetSnack(
              variant: VelvetSnackVariant.info,
              message: longMessage,
            ),
          ),
          width: 320,
        );
        final double twoLineHeight = tester
            .getSize(find.byType(VelvetSnack))
            .height;
        final RenderParagraph twoLineParagraph = tester
            .renderObject<RenderParagraph>(find.text(longMessage));
        expect(
          twoLineParagraph.didExceedMaxLines,
          isTrue,
          reason:
              'the fixture message must be long enough to actually clip at '
              '2 lines, or this test proves nothing',
        );

        // maxLines: 1 — same message, same width.
        await tester.pumpApp(
          _harness(
            const VelvetSnack(
              variant: VelvetSnackVariant.info,
              message: longMessage,
              maxLines: 1,
            ),
          ),
          width: 320,
        );
        final double oneLineHeight = tester
            .getSize(find.byType(VelvetSnack))
            .height;
        final RenderParagraph oneLineParagraph = tester
            .renderObject<RenderParagraph>(find.text(longMessage));
        expect(oneLineParagraph.didExceedMaxLines, isTrue);

        // The whole point: a widget that hardcoded/ignored the passed-in
        // maxLines would render the SAME height for both pumps. A shorter
        // rendered box for maxLines:1 is the only direct evidence the prop
        // is wired through to the underlying Text, not just accepted and
        // dropped.
        expect(
          oneLineHeight,
          lessThan(twoLineHeight),
          reason:
              'maxLines:1 must render a visibly shorter snack than the '
              'maxLines:2 default for the SAME long message — equal heights '
              'would mean maxLines is not actually reaching the Text widget',
        );
      },
    );
  });

  group('action affordance', () {
    testWidgets(
      'the action button honors a >=32dp tap target regardless of label '
      'length',
      (tester) async {
        await tester.pumpApp(
          _harness(
            VelvetSnack(
              variant: VelvetSnackVariant.error,
              message: 'Помилка',
              actionLabel: 'Ок',
              onAction: () {},
            ),
          ),
        );
        final Size actionSize = tester.getSize(
          find.byKey(const Key('velvet_snack_action')),
        );
        expect(
          actionSize.height,
          greaterThanOrEqualTo(32),
          reason:
              "VelvetSnack's own doc comment promises the action tap target "
              'is padded out even though the visual weight is a bare text '
              'button — the rendered hit area must never come in under '
              '32dp',
        );

        // The rendered-size check above is NOT mutation-discriminating on
        // its own: this label's own text + padding already clears 32dp
        // without any `minHeight` constraint helping at all (verified: the
        // check above still passed with the source's `BoxConstraints(
        // minHeight: 32)` temporarily replaced by an unconstrained
        // `BoxConstraints()`). The constraint exists precisely for content
        // SHORT enough that padding alone would not reach 32dp, which a
        // fixed test string can't force without also changing the type
        // scale — so assert the constraint structurally instead: the
        // `Container` wrapping the action must declare `minHeight: 32`
        // verbatim, regardless of what its content happens to measure.
        final Container actionContainer = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const Key('velvet_snack_action')),
            matching: find.byType(Container),
          ),
        );
        expect(actionContainer.constraints?.minHeight, 32);
      },
    );
  });

  group('dismiss affordance', () {
    testWidgets('onDismiss null omits the close button entirely', (
      tester,
    ) async {
      await tester.pumpApp(
        _harness(
          const VelvetSnack(
            variant: VelvetSnackVariant.warning,
            message: 'Увага',
          ),
        ),
      );
      expect(find.byKey(const Key('velvet_snack_close')), findsNothing);
    });

    testWidgets(
      'onDismiss non-null renders the close button and invokes the callback '
      'on tap',
      (tester) async {
        bool dismissed = false;
        await tester.pumpApp(
          _harness(
            VelvetSnack(
              variant: VelvetSnackVariant.warning,
              message: 'Увага',
              onDismiss: () => dismissed = true,
            ),
          ),
        );
        final Finder closeButton = find.byKey(const Key('velvet_snack_close'));
        expect(closeButton, findsOneWidget);

        await tester.tap(closeButton);
        expect(dismissed, isTrue);
      },
    );
  });

  group('semantics', () {
    testWidgets(
      'the liveRegion Semantics node speaks the localized severity prefix '
      'ahead of the message, so the register survives when colour/glyph do '
      'not',
      (tester) async {
        // Disposed inline, NOT via `addTearDown` — the framework's "a
        // SemanticsHandle was active at the end of the test" verification
        // runs BEFORE tear-downs (see
        // `master_booking_card_client_avatar_test.dart` for the identical
        // pattern/rationale).
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          const String message = 'Зміни збережено';
          await tester.pumpApp(
            _harness(
              const VelvetSnack(
                variant: VelvetSnackVariant.success,
                message: message,
              ),
            ),
          );

          final AppLocalizationsUk l10n = AppLocalizationsUk();
          expect(
            tester.getSemantics(find.byType(VelvetSnack)),
            matchesSemantics(
              label: '${l10n.velvetSnackPrefixSuccess}. $message',
              isLiveRegion: true,
            ),
          );
        } finally {
          handle.dispose();
        }
      },
    );
  });
}
