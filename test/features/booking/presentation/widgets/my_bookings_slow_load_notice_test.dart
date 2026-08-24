// Widget tests for `MyBookingsSlowLoadNotice` — the escape hatch layered on
// top of `BookingsSkeleton` when a «Мої записи» day fetch is still pending
// after `kMyBookingsSlowLoadThreshold`.
//
// WHY THIS FILE EXISTS
// --------------------
// The widget shipped (2026-08-20) as the UI half of the stuck-skeleton fix: a
// master created a manual walk-in booking, opened that date on «Мої записи»,
// and watched the skeleton shimmer indefinitely with no message, no action and
// nothing in the backend log. `AsyncValue.when` routes
// `AsyncLoading(retrying: true)` to `loading:` as well, so every automatic
// re-attempt rendered the SAME skeleton as the first — the `error:` branch has
// always carried a retry button, `loading:` had none.
//
// Nothing asserted any of it. The properties pinned here are exactly the ones
// the widget's own doc claims and that a refactor could silently break:
//
//   1. It renders NOTHING before its delay — `SizedBox.shrink()`, zero-size,
//      no paint (so a healthy load cannot see it).
//   2. Its retry affordance is reachable, enabled and wired.
//   3. A subtree replaced before the delay elapses never shows it AND leaves
//      no pending `Timer` behind (`flutter_test` fails a test that does, so
//      the `dispose` cancel is genuinely load-bearing here).
//
// The tests drive the INJECTABLE `delay` parameter — which exists solely as
// this test seam — rather than pumping a fake eight seconds.
//
// NO `pumpAndSettle` IN THIS FILE — deliberately.
// -----------------------------------------------
// `BookingsSkeleton` drives an `AnimationController.repeat(reverse: true)`
// (`my_bookings_states.dart:57`), so a frame is permanently scheduled for as
// long as the loading branch is mounted and `pumpAndSettle` can NEVER observe
// quiescence there — it pumps until the test's own timeout, exactly the hazard
// `scripts/forbid_results_bare_pump_and_settle.sh` was written for on the
// search results screen. Every wait below is a bounded `pump` of a NAMED
// duration this test itself chose, sized to cross the injected `delay` — the
// "advancing past a known TTL" case `scripts/forbid_fixed_wait.sh`'s header
// names as legitimate, not a guess at how long some async work takes.
//
// The view-level counterparts — "a retry re-issues the day fetch" and "a fast
// load never shows the notice", driven through the real provider — live in
// `test/features/booking/presentation/bookings_discovery_view_slow_load_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../../../helpers/pump_app.dart';

/// Short enough to keep the suite fast, long enough that a single-frame
/// `pump()` cannot cross it — the "before" assertions must be real.
const Duration _kDelay = Duration(milliseconds: 400);

/// One frame past [_kDelay] — the notice's `Timer` has fired by here.
final Duration _kPastDelay = _kDelay + const Duration(milliseconds: 50);

/// Comfortably past the panel's 260 ms entry tween.
const Duration _kEntryAnimation = Duration(milliseconds: 400);

Widget _host({required VoidCallback onRetry, bool showNotice = true}) {
  return Scaffold(
    body: ListView(
      children: <Widget>[
        // One card, not the default three: the panel must sit ABOVE the fold
        // on the 800x600 test surface or `tap()` lands on whatever is painted
        // there instead (see `scripts/forbid_blind_calendar_tap.sh` for the
        // same failure mode on the calendar).
        const BookingsSkeleton(count: 1),
        if (showNotice)
          MyBookingsSlowLoadNotice(delay: _kDelay, onRetry: onRetry),
      ],
    ),
  );
}

void main() {
  group('MyBookingsSlowLoadNotice', () {
    testWidgets('renders NOTHING until its delay elapses, then the panel — the '
        'no-flash guarantee', (tester) async {
      int retries = 0;
      await tester.pumpApp(_host(onRetry: () => retries++));

      final Finder notice = find.byKey(const Key('my_bookings_slow_load'));
      final Finder retry = find.byKey(const Key('my_bookings_slow_load_retry'));

      // --- BEFORE: not merely invisible — absent from the tree entirely. ---
      expect(notice, findsNothing);
      expect(retry, findsNothing);
      expect(
        tester.getSize(find.byType(MyBookingsSlowLoadNotice)).height,
        0.0,
        reason:
            'the pre-delay build is SizedBox.shrink(): it occupies no vertical '
            "space in the list (the ListView tightens its child's WIDTH to the "
            'viewport, so only the height is the widget\'s own), and therefore '
            'cannot shift layout when it later appears',
      );
      // The skeleton it layers on top of is up the whole time — the notice
      // supplements the loading state, it never replaces it.
      expect(find.byType(BookingsSkeleton), findsOneWidget);

      // --- AFTER ---
      await tester.pump(_kPastDelay);
      await tester.pump(_kEntryAnimation);

      expect(notice, findsOneWidget);
      expect(retry, findsOneWidget);
      expect(
        find.byType(BookingsSkeleton),
        findsOneWidget,
        reason: 'the skeleton keeps shimmering — this is not an error state',
      );

      // The copy is the "still working" one, pulled from AppLocalizations
      // rather than hard-coded (see `scripts/forbid_cyrillic_finder.sh`), and
      // is NOT the error state's — no `my_bookings_error` anywhere.
      final AppLocalizations l10n = AppLocalizations.of(tester.element(notice));
      expect(find.text(l10n.bookingsStillLoadingBody), findsOneWidget);
      expect(find.byKey(const Key('my_bookings_error')), findsNothing);
      expect(
        find.descendant(
          of: notice,
          matching: find.byIcon(Icons.hourglass_bottom_rounded),
        ),
        findsOneWidget,
        reason: 'an hourglass, not the error state\'s severed cloud',
      );
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);

      expect(retries, 0, reason: 'appearing must not itself retry anything');
    });

    testWidgets('tapping the retry button fires onRetry — the affordance is '
        'wired, enabled and reachable', (tester) async {
      int retries = 0;
      await tester.pumpApp(_host(onRetry: () => retries++));

      await tester.pump(_kPastDelay);
      await tester.pump(_kEntryAnimation);

      final Finder retry = find.byKey(const Key('my_bookings_slow_load_retry'));
      expect(
        tester.widget<NeumorphicButton>(retry).onPressed,
        isNotNull,
        reason: 'a disabled escape hatch is no escape hatch',
      );

      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pump();

      expect(retries, 1);

      // Idempotent — the master may press it more than once while the fetch is
      // still in flight, and the panel must survive its own tap.
      await tester.tap(retry);
      await tester.pump();
      expect(retries, 2);
      expect(find.byKey(const Key('my_bookings_slow_load')), findsOneWidget);
    });

    testWidgets('a load that resolves BEFORE the delay never shows the notice '
        'and leaves no pending Timer', (tester) async {
      int retries = 0;
      await tester.pumpApp(_host(onRetry: () => retries++));

      // The `loading:` subtree is replaced — exactly what a healthy fetch
      // landing does — while the timer is still pending.
      await tester.pumpApp(_host(onRetry: () => retries++, showNotice: false));
      await tester.pump();

      // Advance well past the threshold the (now disposed) timer was set for.
      await tester.pump(_kPastDelay);
      await tester.pump(_kEntryAnimation);

      expect(find.byKey(const Key('my_bookings_slow_load')), findsNothing);
      expect(find.byType(MyBookingsSlowLoadNotice), findsNothing);
      expect(retries, 0);
    });

    testWidgets('disposing before the delay leaves NO pending Timer', (
      tester,
    ) async {
      await tester.pumpApp(_host(onRetry: () {}));

      // Replace the `loading:` subtree while the timer is STILL PENDING, and
      // deliberately never advance past [_kDelay] afterwards. There is no
      // `expect` here on purpose: `flutter_test`'s own teardown fails the test
      // with "A Timer is still pending…" unless `dispose` cancelled it. Pumping
      // past the delay first — as the test above does — would let the timer
      // FIRE and mask the leak, which is why this is a separate case.
      await tester.pumpApp(_host(onRetry: () {}, showNotice: false));
      await tester.pump();
    });

    testWidgets('reduced motion renders the panel with no entry animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
            home: _host(onRetry: () {}),
          ),
        ),
      );

      await tester.pump(_kPastDelay);
      // No animation pump first: with animations disabled the panel must be
      // fully present on the very frame the timer fires, not faded in over
      // 260 ms.
      expect(find.byKey(const Key('my_bookings_slow_load')), findsOneWidget);
      expect(
        find.byType(TweenAnimationBuilder<double>),
        findsNothing,
        reason: 'reduced motion is honoured, not shortened',
      );
    });
  });
}
