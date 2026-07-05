// Regression tests for `MasterStrip`'s `Material(type: transparency)` wrapper
// (`lib/features/booking/presentation/widgets/master_strip.dart`).
//
// BUG THIS GUARDS AGAINST: `MasterStrip` is shared across
// `SlotDateScreen`/`SlotTimeScreen`/`BookingConfirmScreen` via a single
// `Hero(tag: 'master-strip-${master.id}')` (see `slot_picker_screen.dart` +
// `booking_confirm_screen.dart`). During the Hero flight between two of those
// screens, the framework mounts a COPY of `MasterStrip` directly under the
// Navigator's `Overlay` — outside either screen's `Scaffold`/`Material`
// ancestor. Before the fix, `MasterStrip.build()` returned `NeumorphicCard`
// directly with no `Material` of its own, so every `Text` inside the flying
// shuttle resolved its `DefaultTextStyle` against the app-root fallback
// (`WidgetsApp`'s debug "no Material ancestor" style — underlined, no
// explicit height) for the ~300ms duration of the flight: a visible flash of
// underlined, tighter-line-height text on the master's name that
// self-corrected the instant the flight ended. The fix wraps the card's
// content in `Material(type: MaterialType.transparency, ...)`, which installs
// an ambient (non-painting) `DefaultTextStyle`/`Theme` for every `Text`
// beneath it regardless of where in the tree that copy is mounted.
//
// TWO tests, deliberately NOT alternatives — see the second test's own
// comment for why the first isn't sufficient on its own:
//
// 1. Structural (robust, always-on): whenever `MasterStrip` is pumped
//    anywhere, it must contain its OWN `Material` descendant (the one it
//    installs in `build()`) — checked with `MasterStrip` mounted bare (no
//    enclosing `Scaffold`), so the only possible `Material` in scope is the
//    one `MasterStrip` itself provides. This alone would NOT have caught the
//    original bug
//    faithfully — `SlotDateScreen`/`SlotTimeScreen` already wrap `MasterStrip`
//    in their own `Scaffold` (which itself provides a `Material` ancestor via
//    `ScaffoldMessenger`/`Scaffold`'s internal `Material`), so this check
//    passes on both the buggy and fixed code when `MasterStrip` is mounted
//    inside its normal screen. It DOES catch a regression where the
//    `Material(type: transparency)` wrapper is removed from `MasterStrip`
//    itself, IF this test pumps `MasterStrip` bare (no enclosing `Scaffold`)
//    — which is what it does below.
//
// 2. Hero-flight (direct reproduction): mounts two real routes on the same
//    `go_router`-shaped `Navigator`, sharing the exact `master-strip-<id>`
//    Hero tag production uses, pushes from one to the other, and inspects the
//    RESOLVED text style (via the built `RichText`, not the source `Text`
//    widget's own `style` field — the bug is entirely in the AMBIENT
//    `DefaultTextStyle` merge, which only shows up post-resolution) of the
//    master-name text mid-flight (`tester.pump(Duration(milliseconds: 150))`,
//    well before the ~300ms Cupertino transition settles). This is the test
//    that actually reproduces the reported symptom end-to-end; test 1 is kept
//    as a cheap, non-timing-dependent backstop for the same fix.

import 'dart:async';

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/pump_app.dart';

const _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

/// Mirrors the two production call sites' shared Hero tag exactly
/// (`slot_picker_screen.dart`, `booking_confirm_screen.dart`).
String _heroTag(Master master) => 'master-strip-${master.id}';

/// Minimal stand-ins for `SlotDateScreen`/`SlotTimeScreen` — a bare `Scaffold`
/// wrapping a `Hero`-wrapped `MasterStrip`, just enough to drive a real
/// Hero flight between two routes without pulling in the booking feature's
/// full provider/repository graph (out of scope for this regression test).
class _FromScreen extends StatelessWidget {
  const _FromScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Hero(
          tag: _heroTag(_kMaster),
          child: const MasterStrip(
            master: _kMaster,
            showRole: true,
            showRating: true,
          ),
        ),
      ),
    );
  }
}

class _ToScreen extends StatelessWidget {
  const _ToScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: Hero(
          tag: _heroTag(_kMaster),
          child: const MasterStrip(
            master: _kMaster,
            showRole: true,
            showRating: true,
          ),
        ),
      ),
    );
  }
}

void main() {
  group('MasterStrip', () {
    testWidgets(
      'always renders with a Material ancestor, even when pumped bare with '
      'no enclosing Scaffold',
      (tester) async {
        await tester.pumpApp(
          // Deliberately NOT wrapped in a Scaffold — a bare Center, so the
          // only possible Material ancestor is the one MasterStrip itself
          // installs. This is exactly the situation the Hero-flight shuttle
          // reproduces (mounted directly under the Overlay, no Scaffold).
          const Center(child: MasterStrip(master: _kMaster)),
        );
        await tester.pumpAndSettle();

        final Finder masterStrip = find.byType(MasterStrip);
        expect(masterStrip, findsOneWidget);
        expect(
          find.descendant(of: masterStrip, matching: find.byType(Material)),
          findsWidgets,
          reason:
              'MasterStrip must install its own Material ancestor '
              '(type: transparency) — without it, every Text beneath it '
              'resolves against the WidgetsApp debug fallback style whenever '
              'MasterStrip is mounted with no enclosing Scaffold, which is '
              'exactly what happens during its Hero-flight shuttle.',
        );
      },
    );

    testWidgets('the master-name text keeps its normal (non-underlined) style '
        'mid-flight during the shared Hero transition between two routes', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/from',
        routes: <RouteBase>[
          GoRoute(
            path: '/from',
            builder: (context, state) => const _FromScreen(),
          ),
          GoRoute(path: '/to', builder: (context, state) => const _ToScreen()),
        ],
      );
      addTearDown(router.dispose);

      // `theme: velvetTheme()` matters here (unlike most other widget tests
      // in this suite, which use `pumpApp`'s plain default MaterialApp):
      // production installs `CupertinoPageTransitionsBuilder` for every
      // platform via this theme (`app_theme.dart`), which is what the
      // debugger's original report described the flight running under.
      await tester.pumpWidget(
        MaterialApp.router(
          theme: velvetTheme(),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(_FromScreen), findsOneWidget);

      // Fire-and-forget: this Future only resolves once the pushed route
      // is later popped, which this test never does — deliberately not
      // awaited, but explicitly marked so via `unawaited` rather than
      // silently ignored.
      unawaited(router.push('/to'));
      // Start the push transition, then sample it mid-flight — well before
      // the ~300ms Cupertino transition settles, and after Hero has swapped
      // both routes' own copies out for empty placeholders (see this file's
      // header), so exactly one master-name text is mounted: the flying
      // shuttle's.
      //
      // This genuinely needs a fixed wait, not pump-until-condition: the
      // assertion below requires catching the transition WHILE it is still
      // running (an in-progress state), not once some end-state condition
      // becomes true. There is no discrete "mid-flight" event to poll for —
      // only elapsed time into a known ~300ms animation lets us sample it
      // part-way through.
      await tester.pump();
      // fixed-wait-ok: sampling deliberately mid-flight (150ms into a known ~300ms Cupertino transition) — no settled/discrete condition to pump-until, the test needs the transition still in progress, which is inherently time-based.
      await tester.pump(const Duration(milliseconds: 150));

      final String masterName = '${_kMaster.firstName} ${_kMaster.lastName}'
          .trim();
      final Finder nameText = find.text(masterName);
      expect(
        nameText,
        findsOneWidget,
        reason:
            'exactly one instance of the master-name text should be '
            'mounted mid-flight — the Hero shuttle copy — since both '
            "routes' own Heroes are swapped out for empty placeholders "
            'while the flight is in progress',
      );

      // The bug is entirely in the RESOLVED style (the ambient
      // DefaultTextStyle merged in), not the source Text widget's own
      // literal `style:` argument — so this reads the built RichText, not
      // `tester.widget<Text>(nameText).style`.
      final Finder richText = find.descendant(
        of: nameText,
        matching: find.byType(RichText),
      );
      expect(richText, findsOneWidget);
      final RichText resolved = tester.widget<RichText>(richText);
      final TextStyle? resolvedStyle = resolved.text.style;

      expect(
        resolvedStyle,
        isNotNull,
        reason:
            'a resolved style of null would mean this Text has no ambient '
            'DefaultTextStyle at all, which should be impossible once '
            'MaterialApp installs its own root DefaultTextStyle',
      );
      expect(
        resolvedStyle!.decoration == null ||
            resolvedStyle.decoration == TextDecoration.none,
        isTrue,
        reason:
            'mid-flight, the master-name text must NOT pick up the '
            'WidgetsApp "no Material ancestor" debug fallback style '
            '(TextDecoration.underline) — that flash is exactly the bug '
            "`Material(type: transparency)` in MasterStrip.build() fixes. "
            'Resolved decoration was: ${resolvedStyle.decoration}',
      );

      await tester.pumpAndSettle();
    });
  });
}
