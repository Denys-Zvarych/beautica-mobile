// Widget tests for the shared post-submit celebration scaffold
// `BookingSuccessScaffold`
// (`lib/features/booking/presentation/widgets/booking_success_scaffold.dart`).
//
// Extracted from the ~90%-identical success structure in BOTH
// `booking_success_screen.dart` (independent flow — ONE recap card, default
// `homeGap`) and `salon_booking_success_screen.dart` (salon flow — N recap
// cards, tighter `homeGap`). The scaffold owns the PopScope back-block, the
// staggered reveal, the Lottie badge and the pinned "На головну" CTA.
//
// These pin the contract BOTH composition sites depend on:
//   • N recap cards render, staggered — none dropped (salon N≥2 path);
//   • PopScope(canPop:false) blocks back (both flows);
//   • `disableAnimations` jumps the reveal straight to its resting state;
//   • the optional `homeGap` param path.
//
// Recap cards are keyed test stand-ins (`recap-0…`) — the real recap widgets
// have their own tests (`booking_summary_cards_test.dart`,
// `salon_booking_success_screen_test.dart`); here we exercise the SCAFFOLD.

import 'package:beautica_mobile/features/booking/presentation/widgets/booking_success_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _kHomeKey = Key('booking-success-home-cta');

Widget _card(int i) => SizedBox(
  key: ValueKey<String>('recap-$i'),
  height: 120,
  child: const ColoredBox(color: Color(0xFF222222)),
);

/// Wraps [scaffold] in a MediaQuery that forces `disableAnimations` on, so the
/// staggered reveal jumps straight to its resting state (all opacity == 1) on
/// the first frame — deterministic, no Lottie/animation timing to settle.
Widget _reducedMotion(Widget scaffold) => Builder(
  builder: (BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: scaffold,
  ),
);

BookingSuccessScaffold _scaffold({
  required int cardCount,
  double? homeGap,
  VoidCallback? onHome,
}) {
  return BookingSuccessScaffold(
    // i18n-finder-ok: fixture copy — the real screens pass their own l10n keys;
    // this test exercises the scaffold, not the copy.
    title: 'Записано!',
    subline: 'Тестовий підзаголовок',
    // A bare tappable stand-in for the real screens' `SuccessSecondaryButton`
    // — the scaffold's `actions` list accepts arbitrary widgets, and this
    // test exercises the SCAFFOLD's reveal/gap/footer plumbing, not the
    // button's own chrome (that lives in `booking_success_screen_test.dart`
    // equivalents).
    actions: <Widget>[
      GestureDetector(
        key: _kHomeKey,
        onTap: onHome ?? () {},
        child: const SizedBox(
          height: 48,
          child: ColoredBox(color: Color(0xFF111111)),
        ),
      ),
    ],
    recapCards: <Widget>[for (int i = 0; i < cardCount; i++) _card(i)],
    homeGap: homeGap ?? 16,
  );
}

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('BookingSuccessScaffold — recap cards', () {
    testWidgets('renders every recap card (salon N≥2 path) — none dropped', (
      tester,
    ) async {
      await _pumpTall(tester);
      // 3 cards proves the loop keeps ALL of them, not just first/last.
      await tester.pumpApp(_reducedMotion(_scaffold(cardCount: 3)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('recap-0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('recap-1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('recap-2')), findsOneWidget);
    });

    testWidgets('renders a single recap card (independent path)', (
      tester,
    ) async {
      await _pumpTall(tester);
      await tester.pumpApp(_reducedMotion(_scaffold(cardCount: 1)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('recap-0')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('recap-1')), findsNothing);
    });
  });

  group('BookingSuccessScaffold — back block', () {
    testWidgets('wraps the tree in PopScope(canPop: false)', (tester) async {
      await _pumpTall(tester);
      await tester.pumpApp(_reducedMotion(_scaffold(cardCount: 2)));
      await tester.pumpAndSettle();

      final PopScope popScope = tester.widget<PopScope>(
        find.byType(PopScope).first,
      );
      expect(popScope.canPop, isFalse);
    });
  });

  group('BookingSuccessScaffold — home CTA', () {
    testWidgets('the pinned "На головну" button fires onHome', (tester) async {
      await _pumpTall(tester);
      int homeTaps = 0;
      await tester.pumpApp(
        _reducedMotion(_scaffold(cardCount: 2, onHome: () => homeTaps++)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kHomeKey));
      await tester.pumpAndSettle();

      expect(homeTaps, 1);
    });
  });

  group('BookingSuccessScaffold — reduced motion', () {
    testWidgets(
      'disableAnimations jumps the reveal to its resting state — the home CTA '
      'is at full opacity on the first frame (no settle needed)',
      (tester) async {
        await _pumpTall(tester);
        await tester.pumpApp(_reducedMotion(_scaffold(cardCount: 2)));
        // Deliberately NO pumpAndSettle — with reduced motion the reveal must
        // already be resting after didChangeDependencies pins the controller.
        await tester.pump();

        // The reveal fades through a `FadeTransition`, not a raw `Opacity`
        // rebuilt per frame (mobile-perf P1 — see `_reveal`'s doc). The claim
        // under test is unchanged: at rest the CTA is at FULL opacity on the
        // first frame. Read it off the transition's own animation.
        final Finder revealFade = find
            .ancestor(
              of: find.byKey(_kHomeKey),
              matching: find.byType(FadeTransition),
            )
            .first;
        final FadeTransition fade = tester.widget<FadeTransition>(revealFade);
        expect(
          fade.opacity.value,
          1.0,
          reason:
              'reduced motion must pin the staggered-reveal controller to its '
              'end (value == 1) so the CTA is fully visible immediately — not '
              'faded in over 1350ms.',
        );
      },
    );
  });

  group('BookingSuccessScaffold — optional param paths', () {
    testWidgets(
      'homeGap sets the gap between the scrolling recap and the pinned CTA',
      (tester) async {
        await _pumpTall(tester);

        // The CTA is bottom-anchored (the Flexible scroll above it absorbs
        // slack), so homeGap does NOT move the CTA — it sets the gap between
        // the scroll viewport's bottom edge and the CTA's top. Measure THAT.
        Future<double> gapFor(double homeGap) async {
          await tester.pumpApp(
            _reducedMotion(_scaffold(cardCount: 1, homeGap: homeGap)),
          );
          await tester.pumpAndSettle();
          final double scrollBottom = tester
              .getBottomLeft(find.byType(SingleChildScrollView))
              .dy;
          final double ctaTop = tester.getTopLeft(find.byKey(_kHomeKey)).dy;
          return ctaTop - scrollBottom;
        }

        final double smallGap = await gapFor(8);
        final double largeGap = await gapFor(32);

        expect(smallGap, closeTo(8, 0.5));
        expect(largeGap, closeTo(32, 0.5));
        expect(
          largeGap,
          greaterThan(smallGap),
          reason:
              'homeGap is the only spacing the two success screens differ on '
              '(md independent / sm salon) — it must drive the gap above the '
              'pinned CTA.',
        );
      },
    );
  });

  group(
    'BookingSuccessScaffold — pagedRecap width (FIX 2, mobile-qa 2026-08-23)',
    () {
      testWidgets(
        'pagedRecap receives the FULL pumped width — no extra horizontal '
        'inset stacked on top of its own self-padding',
        (tester) async {
          await _pumpTall(tester);

          // Captures the BoxConstraints the scaffold hands its `pagedRecap`
          // slot. `LayoutBuilder` reports the incoming constraint regardless
          // of what the child asks for, so this is independent of whatever
          // AppointmentPager (the real caller) does internally — the
          // question under test is purely "how much width does the SLOT
          // itself give its child", which is exactly where FIX 2's bug lived
          // (see `booking_success_scaffold.dart`'s `build()` FIX 2 comment).
          double? probedWidth;
          final Widget probe = LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              probedWidth = constraints.maxWidth;
              return const SizedBox.expand();
            },
          );

          await tester.pumpApp(
            _reducedMotion(
              BookingSuccessScaffold(
                // i18n-finder-ok: fixture copy, mirrors `_scaffold()`'s own
                // title/subline stand-ins above — this test exercises layout,
                // not copy.
                title: 'Записано!',
                subline: 'Тестовий підзаголовок',
                recapCards: const <Widget>[],
                pagedRecap: probe,
              ),
            ),
            width: 400,
          );
          await tester.pumpAndSettle();

          // The confirm screen's OWN `Expanded(child: AppointmentPager(...))`
          // (`salon_booking_confirm_screen.dart`) has NO wrapping Padding
          // either — AppointmentPager always receives the full body width on
          // BOTH the confirm and success screens, and self-pads internally by
          // its own single `lg` inset (`appointment_pager.dart`'s
          // `itemBuilder`). Asserting the pumped width itself is therefore
          // the numeric parity check: the pre-fix double-padded scaffold
          // would have reported `400 - 2 * VelvetSpacing.lg` (352) here
          // instead — see the mutation note on this test in the QA report.
          expect(
            probedWidth,
            400,
            reason:
                'the scaffold must apply NO horizontal inset around '
                'pagedRecap — a reintroduced outer horizontal Padding '
                'wrapping the whole content column (the FIX 2 regression) '
                'would shrink this below the full pumped width',
          );
        },
      );
    },
  );
}
