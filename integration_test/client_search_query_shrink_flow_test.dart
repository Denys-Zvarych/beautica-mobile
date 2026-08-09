// Search-query SHRINK round trip — E2E regression coverage (Step 2.7 Rule 3b).
//
// WHY THIS FILE EXISTS
// --------------------
// Every other search test types a term UP from an empty box. The defect that
// started this whole chain went the other way: a user who had already searched
// «манікюр», was looking at its results, went back and shortened the term to
// «ма». `setQuery` hit a bare `return`, so the PREVIOUS query stayed applied —
// the screen kept the old result set and the old applied-query chip, and the
// only signal that anything had been rejected was an 11 sp muted grey line that
// read as decoration. Tapping «Показати майстрів» then re-ran a search for a
// term the user had already edited away.
//
// `search_filters_screen_test.dart`'s CTA-gate group pins the gate, but it does
// so on a FRESH screen with nothing ever applied — so it proves "a short term
// cannot push", not "a short term cannot resurrect the term before it". The
// distinction is the entire bug. Only a journey that has genuinely applied a
// term, rendered its results, and come back can tell the two apart, and only an
// integration flow can carry the applied query, the keepAlive draft, the two
// screens and the HTTP boundary in one piece of state.
//
// This file drives that journey against a real Dio boundary, and pins all six
// locked decisions:
//   1. 1–2 characters is an ERROR state, not a hint       → the red inset ring
//      + the error line under the field.
//   2. an EMPTY box is valid, no error                    → test 2's escape
//      hatch re-enables the CTA.
//   3. shrinking below 3 clears the APPLIED query         → asserted directly
//      off the live keepAlive controller, and observably: the completed term
//      reaches the wire as ITSELF, never as the pre-shrink term.
//   4. the CTA is BLOCKED below 3                         → `onPressed == null`,
//      and tapping it neither navigates nor fires a request.
//   5. both escape hatches work                           → test 1 completes
//      the word, test 2 empties the box.
//   6. the typed 1–2 characters SURVIVE and are never overwritten → the draft
//      and the box both still read «ма» after the shrink, not «манікюр».
//
// WHAT FAILS WITHOUT THE FIX
// --------------------------
// Under the pre-fix code the shrink leaves `query == 'манікюр'` applied, the CTA
// stays live, and tapping it pushes the results screen and fires a fresh
// `/search/masters?q=манікюр`. Four assertions in test 1 fail on that:
// `appliedQuery` is not null, `cta.onPressed` is not null, `searchMastersCalls`
// increases, and the router leaves the Пошук screen. The pre-fix code also had
// no red ring to find (`hasError` was never passed), so the tone assertion fails
// too.
//
// LOCALITY IS SEEDED, NOT PICKED
// ------------------------------
// The saved profile locality (Київська → Київ) is seeded on the FakeBackend so
// the Пошук screen's own prefill resolves the cascade. That keeps the CTA out of
// its OTHER disabled state (region chosen without a city) without driving the
// picker sheets, so a disabled CTA in this file can only mean the query gate —
// which is the thing being measured. `expectCtaEnabled` guards that
// interpretation explicitly at the start of each journey.
//
// PUMPING POLICY (measured — do not "simplify" back to pumpAndSettle)
// -------------------------------------------------------------------
// `pumpAndSettle` HANGS once the results screen is mounted: something in that
// subtree keeps the frame pipeline non-quiescent, so settling never completes
// and the test dies with `_pendingFrame == null`. Every wait that spans a
// mounted results screen — including the POP back off it — therefore uses
// bounded `pump(Duration)` calls via [settleResults]. This is not the banned
// pump-as-sleep idiom; a bounded pump is the only deterministic way to advance a
// screen that never goes quiescent.
//
// KEY POLICY: every interaction is key-based. The error line is asserted through
// its `Key('search_query_min_length_hint')` and the inset's `hasError` flag,
// never through its UA copy.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

const Key _queryField = Key('search_query_field');
const Key _cta = Key('search_show_masters_cta');
const Key _minLengthError = Key('search_query_min_length_hint');
const Key _resultsScreen = Key('client-search-results');
const Key _resultsBack = Key('results_back_button');
const Key _queryChip = Key('results_query_chip');

/// The term the journey applies BEFORE shrinking. Cyrillic on purpose — the
/// shrink must not be a Latin-only code path.
const String _appliedTerm = 'манікюр';

/// What the user shortens it to. Two characters: inside the error window
/// (1 … kSearchMinQueryLength-1) and a genuine PREFIX of [_appliedTerm], so a
/// naive "did the term change" check cannot pass this by accident.
const String _shrunkTerm = 'ма';

/// The completed term for escape hatch 2 — deliberately NOT [_appliedTerm], so
/// the wire assertion can tell "the term the user finished typing" from "the
/// term that was applied before the shrink".
const String _completedTerm = 'ман';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Bounded replacement for `pumpAndSettle` while a results screen is mounted
  /// (see header). Also used across the pop back off it, since the outgoing
  /// screen is still in the tree for the whole transition.
  Future<void> settleResults(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      // pumpAndSettle HANGS here: the results-screen subtree keeps the frame
      // pipeline non-quiescent, so settling never completes (measured).
      // fixed-wait-ok: bounded step is the only way to advance this screen.
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// The root [ProviderContainer], reached through the always-mounted
  /// [ClientShell]. Reading a keepAlive provider through it does not re-seed it.
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ClientShell)));

  /// The APPLIED query on the live keepAlive controller — the wire model, which
  /// by contract is null or a term the backend will honour.
  String? appliedQuery(WidgetTester tester) =>
      containerOf(tester).read(searchFiltersControllerProvider).query;

  /// The RAW term the user typed, which is where a below-minimum term lives.
  String draft(WidgetTester tester) =>
      containerOf(tester).read(searchQueryDraftControllerProvider);

  /// What the search box is actually showing.
  String boxText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(_queryField)).controller!.text;

  NeumorphicButton ctaOf(WidgetTester tester) =>
      tester.widget<NeumorphicButton>(find.byKey(_cta));

  /// The recessed well the search field sits in — its `hasError` flag is what
  /// paints the 2 dp [BrandColors.error] ring.
  NeumorphicInset insetOf(WidgetTester tester) =>
      tester.widget<NeumorphicInset>(
        find
            .ancestor(
              of: find.byKey(_queryField),
              matching: find.byType(NeumorphicInset),
            )
            .first,
      );

  /// Asserts the field is in its BLOCKING error state: red ring + error line.
  void expectErrorShown(WidgetTester tester) {
    expect(
      insetOf(tester).hasError,
      isTrue,
      reason:
          'a rejected term must LOOK rejected — the pre-fix field passed no '
          'hasError at all, so the well looked identical either way',
    );
    expect(
      find.byKey(_minLengthError),
      findsOneWidget,
      reason: 'the error line explains why the CTA has gone dead',
    );
  }

  void expectNoErrorShown(WidgetTester tester) {
    expect(insetOf(tester).hasError, isFalse);
    expect(find.byKey(_minLengthError), findsNothing);
  }

  void expectCtaBlocked(WidgetTester tester) {
    expect(
      ctaOf(tester).onPressed,
      isNull,
      reason:
          'results must be UNREACHABLE with a sub-minimum term — this gate is '
          'what guarantees the results screen never sees one',
    );
  }

  void expectCtaEnabled(WidgetTester tester, String because) {
    expect(ctaOf(tester).onPressed, isNotNull, reason: because);
  }

  /// Boots the app as a CLIENT whose saved profile locality is Київська → Київ,
  /// logs in, and lands on the Пошук screen with that locality prefilled.
  Future<({FakeBackend fb, GoRouter router})> openSearch(
    WidgetTester tester,
  ) async {
    final fb = FakeBackend()
      ..currentRole = UserRole.client
      // Seeded so the screen's own prefill resolves a complete locality
      // cascade — the CTA's require-a-city gate is then satisfied and cannot be
      // confused with the query gate this file measures.
      ..clientOblastId = 'oblast-kyiv'
      ..clientOblastName = 'Київська'
      ..clientCityId = 'city-kyiv'
      ..clientCityName = 'Київ';

    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.client);
    // Real-async app boot: FakeBackend socket + secure storage + router
    // redirect, with no single settle condition to key a pump-until off.
    // fixed-wait-ok: real-async boot; no single pump-until condition exists.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('client-nav-search-center')));
    // The shell-branch switch fans out to the real locality + approved-category
    // fetches, and then to the saved-locality prefill, before Пошук settles.
    // fixed-wait-ok: multi-endpoint fan-out precedes an interactive screen.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    AppHarness.expectLocation(router, RouteNames.clientSearch);

    return (fb: fb, router: router);
  }

  /// Types [term] into the one search box the app has and settles.
  Future<void> type(WidgetTester tester, String term) async {
    await tester.enterText(find.byKey(_queryField), term);
    await tester.pumpAndSettle();
  }

  /// Taps «Показати майстрів» and advances far enough for the results screen to
  /// mount and its two GETs to land.
  Future<void> tapCta(WidgetTester tester) async {
    await tester.tap(find.byKey(_cta), warnIfMissed: false);
    await settleResults(tester);
  }

  /// Pops back off the results screen to the still-mounted Пошук screen.
  Future<void> backToFilters(WidgetTester tester, GoRouter router) async {
    await tester.tap(find.byKey(_resultsBack));
    await settleResults(tester);
    expect(
      find.byType(SearchResultsScreen),
      findsNothing,
      reason: 'the back affordance must actually leave the results screen',
    );
    AppHarness.expectLocation(router, RouteNames.clientSearch);
  }

  testWidgets(
    'SHRINKING an applied term below the minimum errors, blocks the CTA, keeps '
    'the typed characters, and makes the stale results unreachable',
    (tester) async {
      final (:FakeBackend fb, :GoRouter router) = await openSearch(tester);

      // ── 1. Apply a real term and see its results ──────────────────────────
      expectCtaEnabled(
        tester,
        'the seeded locality satisfies the require-a-city gate, so a disabled '
        'CTA later in this test can only be the query gate',
      );
      await type(tester, _appliedTerm);
      expectNoErrorShown(tester);
      expect(appliedQuery(tester), _appliedTerm);

      await tapCta(tester);

      expect(
        find.byKey(_resultsScreen),
        findsOneWidget,
        reason: 'the baseline journey must actually reach results',
      );
      expect(
        fb.lastSearchMastersQueryMap?['q'],
        _appliedTerm,
        reason: 'the applied term must have reached the wire at least once',
      );
      expect(
        find.byKey(_queryChip),
        findsOneWidget,
        reason:
            'the chip is the only on-page record of which term produced these '
            'results — it is what used to go stale',
      );

      final int callsAfterFirstSearch = fb.searchMastersCalls;
      expect(
        callsAfterFirstSearch,
        greaterThan(0),
        reason:
            'without a real first search the "no SECOND search" assertion '
            'below would pass vacuously',
      );

      // ── 2. Go back and SHRINK the term ────────────────────────────────────
      await backToFilters(tester, router);
      expect(
        boxText(tester),
        _appliedTerm,
        reason:
            'the round trip must bring the term back — the user shortens what '
            'they see, so this is the precondition for the whole regression',
      );

      await type(tester, _shrunkTerm);

      // Decision 1 — this is an ERROR, not a hint.
      expectErrorShown(tester);

      // Decision 4 — results are unreachable with a sub-minimum term.
      expectCtaBlocked(tester);

      // Decision 3 — the applied query is CLEARED, so nothing stale survives to
      // be re-searched. This is the assertion the bare `return` failed.
      expect(
        appliedQuery(tester),
        isNull,
        reason:
            'holding «манікюр» here is the defect: the user had already '
            'deleted it, yet it stayed applied and re-searchable',
      );

      // Decision 6 — the characters the user actually typed survive, in both
      // the shared draft and the box, and are NOT overwritten by the term that
      // used to be applied.
      expect(
        draft(tester),
        _shrunkTerm,
        reason: 'the rejected term must stay observable somewhere',
      );
      expect(
        boxText(tester),
        _shrunkTerm,
        reason:
            'seeding the box from the APPLIED query would restore «манікюр» '
            'over the two characters the user just typed',
      );

      // ── 3. The blocked CTA is genuinely inert ─────────────────────────────
      await tapCta(tester);

      expect(
        find.byType(SearchResultsScreen),
        findsNothing,
        reason: 'a blocked CTA must not navigate',
      );
      AppHarness.expectLocation(router, RouteNames.clientSearch);
      expect(
        fb.searchMastersCalls,
        callsAfterFirstSearch,
        reason:
            'THE regression: tapping through used to re-issue a search for the '
            'pre-shrink term, putting stale results back on screen',
      );
      expect(
        fb.lastSearchMastersQueryMap?['q'],
        _appliedTerm,
        reason:
            'the last request on the wire is still the FIRST one — no new '
            'request was made, so its captured map is untouched',
      );

      // ── 4. Escape hatch: finish the word ──────────────────────────────────
      await type(tester, _completedTerm);
      expectNoErrorShown(tester);
      expectCtaEnabled(tester, 'a complete term must un-block the CTA');
      expect(appliedQuery(tester), _completedTerm);

      await tapCta(tester);

      expect(find.byKey(_resultsScreen), findsOneWidget);
      expect(
        fb.searchMastersCalls,
        greaterThan(callsAfterFirstSearch),
        reason: 'completing the term must actually run a new search',
      );
      expect(
        fb.lastSearchMastersQueryMap?['q'],
        _completedTerm,
        reason:
            'the wire must carry the term the user FINISHED typing, never the '
            'one that was applied before the shrink',
      );
      expect(
        fb.lastSearchMastersQueryMap?['location.cityId'],
        'city-kyiv',
        reason:
            'recovering from the error must not cost the other facets — the '
            '"search resets my filters" regression class',
      );
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  testWidgets(
    'EMPTYING the box is the other escape hatch: no error, CTA live, and the '
    'search runs with no term at all',
    (tester) async {
      final (:FakeBackend fb, :GoRouter router) = await openSearch(tester);

      await type(tester, _appliedTerm);
      await tapCta(tester);
      expect(find.byKey(_resultsScreen), findsOneWidget);
      final int callsAfterFirstSearch = fb.searchMastersCalls;

      await backToFilters(tester, router);
      await type(tester, _shrunkTerm);
      expectErrorShown(tester);
      expectCtaBlocked(tester);

      // Decision 2 + 5 — an empty box is a legitimate filters-only search, so
      // clearing must lift both the error and the block. If `cleared` were
      // collapsed into `belowMinimum` this would leave a red ring under an
      // empty field and a permanently dead CTA.
      await type(tester, '');

      expectNoErrorShown(tester);
      expectCtaEnabled(
        tester,
        'an empty box is not an error — searching on locality / category / '
        'price alone is legitimate',
      );
      expect(appliedQuery(tester), isNull);
      expect(draft(tester), '');

      await tapCta(tester);

      expect(find.byKey(_resultsScreen), findsOneWidget);
      expect(
        fb.searchMastersCalls,
        greaterThan(callsAfterFirstSearch),
        reason: 'the query-less search must actually run',
      );
      expect(
        fb.lastSearchMastersQueryMap?.containsKey('q') == true &&
            fb.lastSearchMastersQueryMap?['q'] != null,
        isFalse,
        reason:
            'a cleared term must be OMITTED from the wire, not sent as the '
            'previous value or as an empty string',
      );
      expect(
        fb.lastSearchMastersQueryMap?['location.cityId'],
        'city-kyiv',
        reason: 'the locality facet still rides the query-less request',
      );
      expect(
        find.byKey(_queryChip),
        findsNothing,
        reason:
            'no applied term means no chip — a chip here would be the stale '
            'affordance the original defect left behind',
      );
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );
}
