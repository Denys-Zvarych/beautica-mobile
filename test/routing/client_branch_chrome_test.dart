// Router-driven persistent-chrome stability net — the durable guard for the
// "wordmark-jump" bug class on the CLIENT shell.
//
// WHAT IT DOES
// ------------
// Boots the REAL [appRouter] as an authenticated CLIENT, drives the
// [StatefulShellRoute.indexedStack] through every branch by tapping the actual
// [ClientBottomNav] tiles (no synthetic widget config), and for EACH branch root
// captures:
//   • the `beautica` wordmark's global top-left `dy` (RenderBox.localToGlobal),
//   • the [ClientBottomNav]'s top global Y.
// It then asserts both are BYTE-IDENTICAL (within a sub-pixel epsilon) across all
// branches. A per-screen Padding / re-added AppBar / double SafeArea that shifts
// EITHER value on a single branch makes this test FAIL — which is exactly the
// regression the two old synthetic [ClientTopBar] tests could not see (they pumped
// the bar in isolation, never the real branch screens through the real router).
//
// WHY THE WORDMARK INVARIANT IS REAL HERE
// ---------------------------------------
// [ClientTopBar] is mounted ONCE by [ClientShell] (above `navigationShell`),
// exactly like [ClientBottomNav] — so the top chrome is byte-identical across
// branches BY CONSTRUCTION (2026-06-24 hoist). This net pins that invariant at
// the router tier so a future regression — a branch root re-introducing its own
// bar / an AppBar / a stray top inset that shifts the shell bar — is caught.
//
// HARNESS NOTES (generalised from role_landing_chrome_test.dart)
// --------------------------------------------------------------
//   • Authenticated CLIENT session via a fixed AuthNotifier + fake repos; the
//     suite-wide no-network HttpOverrides (flutter_test_config.dart) refuses real
//     sockets, so the home/passport data providers settle to AsyncError — the
//     CHROME (top bar + bottom nav) renders regardless of data state, same as the
//     role-landing net relies on.
//   • Pumps are BOUNDED. The branch roots run a one-shot 1s staggered-reveal
//     (SlideTransition), so the wordmark `dy` is only final once the reveal
//     completes. We never use a fixed `pump(Duration)` sleep — instead
//     [_settleChrome] pumps frames until the measured wordmark `dy` stops moving
//     across two consecutive frames (pump-until-stable), which is robust to the
//     reveal duration and to any non-quiescing animation elsewhere on the page.
//   • Finders key off route constants + widget Types + nav-tile Keys — never raw
//     Ukrainian text (mobile-qa M2).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'client_branch_chrome_matrix.dart';

// Sub-pixel tolerance for the cross-branch equality assertions. The wordmark and
// bottom-nav positions are driven by the SAME constants on every branch, so the
// expected delta is exactly 0; the epsilon only absorbs floating-point noise.
const double _kEpsilon = 0.01;

void main() {
  // Park the splash gate in the past so authRedirect does not pin the router on
  // /splash waiting for the minimum splash duration to elapse.
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  group('CLIENT branch chrome registry', () {
    test('matrix covers every CLIENT shell branch exactly once', () {
      assertMatrixCoversAllClientBranches();
    });

    test('every live branch sits beneath the shell-owned ClientTopBar', () {
      // The ClientTopBar is now SHELL-owned (2026-06-24 hoist): ClientShell
      // mounts ONE bar above navigationShell, so ALL FIVE branches — Home,
      // Favorites, Search, Bookings, Passport — share it and join the
      // wordmark-dy invariant. (Before the hoist only the three non-placeholder
      // branches that each mounted their own bar were in the set.)
      expect(
        topBarBranches.map((b) => b.branchIndex).toSet(),
        equals(<int>{
          kClientHomeBranch,
          kClientFavoritesBranch,
          kClientSearchBranch,
          kClientBookingsBranch,
          kClientPassportBranch,
        }),
        reason:
            'all five CLIENT branches sit beneath the single shell-owned '
            'ClientTopBar, so every branch joins the wordmark-dy invariant.',
      );
    });

    // ── Visible-but-skipped deferred rows ─────────────────────────────────────
    // Each deferred matrix row surfaces as its own skipped test so it shows in
    // the run output and can never be silently forgotten. When the dependency
    // ships, flip `pending` → false in the matrix and wire the real assertion.
    for (final row in clientBranchChromeMatrix.where((b) => b.pending)) {
      test(
        'DEFERRED — ${row.branchName} chrome pin (${row.expectedRoute})',
        () {
          // Intentionally skipped: documents the deferred chrome scope.
        },
        skip: row.deferredReason,
      );
    }
  });

  group('persistent chrome is byte-identical across every CLIENT branch', () {
    testWidgets(
      'wordmark dy + bottom-nav top-Y do not move when hopping branches',
      (tester) async {
        final harness = await _ClientShellHarness.boot(tester);

        // Sanity: we actually landed inside the CLIENT shell on /home.
        expect(find.byType(ClientShell), findsOneWidget);
        expect(harness.currentLocation, equals('/home'));

        // Walk every LIVE branch via the real bottom-nav tiles and record both
        // chrome anchors at each.
        final samples = <int, _ChromeSample>{};
        for (final row in liveClientBranches) {
          await harness.goBranch(row.branchIndex);

          // The branch root must be the one the matrix declares (router built
          // the right screen) and the location must match.
          expect(
            harness.currentLocation,
            equals(row.expectedRoute),
            reason:
                '${row.branchName}: tapping its nav tile must land on '
                '${row.expectedRoute}; landed on ${harness.currentLocation}.',
          );
          expect(
            find.byType(row.expectedRootType),
            findsOneWidget,
            reason:
                '${row.branchName}: router must build '
                '${row.expectedRootType} at ${row.expectedRoute}.',
          );

          samples[row.branchIndex] = harness.sampleChrome(
            measureTopBar: row.hasTopBar,
          );
        }

        // ── Bottom nav top-Y: byte-identical across ALL five branches ─────────
        // The bottom nav is shell-hosted, so its top edge must never move. A
        // branch root that grows past the viewport (or a stray bottom inset)
        // would shift it — caught here.
        final navYs = samples.values.map((s) => s.bottomNavTopY).toList();
        final baselineNavY = navYs.first;
        for (final entry in samples.entries) {
          expect(
            (entry.value.bottomNavTopY - baselineNavY).abs(),
            lessThan(_kEpsilon),
            reason:
                'ClientBottomNav top-Y moved on branch ${entry.key} '
                '(${entry.value.bottomNavTopY}) vs baseline ($baselineNavY). '
                'The shell-hosted bottom bar must sit at the SAME Y on every '
                'branch — a branch root overflowing or adding a bottom inset is '
                'the regression.',
          );
        }

        // ── Wordmark dy: byte-identical across ALL branches ───────────────────
        // The ClientTopBar is shell-owned now (one bar above navigationShell),
        // so the wordmark dy is identical across branches by construction. If a
        // branch root re-introduces its own bar, re-adds an AppBar, or adds a
        // stray top inset that pushes the shell bar down, the wordmark `dy` on
        // THAT branch diverges → this fails (the wordmark-jump regression).
        final dys = <int, double>{
          for (final e in samples.entries)
            if (e.value.wordmarkDy != null) e.key: e.value.wordmarkDy!,
        };
        expect(
          dys.length,
          equals(topBarBranches.length),
          reason:
              'every top-bar branch must have produced a wordmark dy sample; '
              'got ${dys.length} of ${topBarBranches.length}.',
        );
        final baselineDy = dys.values.first;
        for (final entry in dys.entries) {
          expect(
            (entry.value - baselineDy).abs(),
            lessThan(_kEpsilon),
            reason:
                'beautica wordmark dy moved on branch ${entry.key} '
                '(${entry.value}) vs baseline ($baselineDy). The shared '
                'ClientTopBar must sit at the SAME vertical offset on Головна / '
                'Пошук / BEAUTY PASSPORT — a per-screen Padding / AppBar / '
                'double-SafeArea drift is the wordmark-jump regression.',
          );
        }

        harness.dispose();
      },
    );
  });

  // ── [P1] Chrome under stress — the regime where jumps actually hide ─────────
  group('chrome stays stable across branches under stress', () {
    for (final variant in _stressVariants) {
      testWidgets('${variant.name}: wordmark dy stable + nav renders cleanly', (
        tester,
      ) async {
        final harness = await _ClientShellHarness.boot(
          tester,
          width: variant.width,
          textScale: variant.textScale,
          mediaPadding: variant.padding,
        );

        final dys = <int, double>{};
        for (final row in topBarBranches) {
          await harness.goBranch(row.branchIndex);
          expect(
            find.byType(row.expectedRootType),
            findsOneWidget,
            reason: '${variant.name}: ${row.branchName} root must build.',
          );
          final sample = harness.sampleChrome(measureTopBar: true);
          if (sample.wordmarkDy != null) {
            dys[row.branchIndex] = sample.wordmarkDy!;
          }
        }

        expect(
          dys.length,
          equals(topBarBranches.length),
          reason: '${variant.name}: every top-bar branch must yield a dy.',
        );
        final baselineDy = dys.values.first;
        for (final entry in dys.entries) {
          expect(
            (entry.value - baselineDy).abs(),
            lessThan(_kEpsilon),
            reason:
                '${variant.name}: wordmark dy moved on branch ${entry.key} '
                '(${entry.value}) vs baseline ($baselineDy) — chrome jump under '
                'the stress regime where regressions hide.',
          );
        }

        // Bottom-nav labels must render without a RenderFlex overflow at this
        // regime. The suite-wide overflow guard (flutter_test_config.dart)
        // records any overflow and fails the test in tearDown — so reaching here
        // with the nav present is the assertion that the cluster did not break.
        expect(
          find.byType(ClientBottomNav),
          findsOneWidget,
          reason:
              '${variant.name}: ClientBottomNav must render (labels laid out '
              'without overflow — the overflow guard fails the test otherwise).',
        );

        harness.dispose();
      });
    }
  });
}

// ---------------------------------------------------------------------------
// Stress regimes
// ---------------------------------------------------------------------------

/// One stress regime: a narrow width, an elevated text scale, and/or notch
/// insets — the conditions under which a per-screen chrome offset bug actually
/// surfaces (large fonts push content down; notch padding shifts SafeArea; the
/// narrowest phone tightens the bottom-nav cluster).
class _StressVariant {
  const _StressVariant({
    required this.name,
    required this.width,
    required this.textScale,
    required this.padding,
  });

  final String name;
  final double width;
  final double textScale;
  final EdgeInsets padding;
}

const List<_StressVariant> _stressVariants = <_StressVariant>[
  _StressVariant(
    name: 'textScale 1.3x',
    width: 390,
    textScale: 1.3,
    padding: EdgeInsets.zero,
  ),
  _StressVariant(
    name: '320dp narrow',
    width: 320,
    textScale: 1.0,
    padding: EdgeInsets.zero,
  ),
  _StressVariant(
    name: 'notch insets (top 44 / bottom 34)',
    width: 390,
    textScale: 1.0,
    padding: EdgeInsets.only(top: 44, bottom: 34),
  ),
];

// ---------------------------------------------------------------------------
// Chrome sample
// ---------------------------------------------------------------------------

class _ChromeSample {
  const _ChromeSample({required this.bottomNavTopY, required this.wordmarkDy});

  /// Global Y of the [ClientBottomNav]'s top edge.
  final double bottomNavTopY;

  /// Global `dy` of the `beautica` wordmark's top-left, or null when the branch
  /// root does not mount a [ClientTopBar] (placeholder branches).
  final double? wordmarkDy;
}

// ---------------------------------------------------------------------------
// Harness — boots the real router as an authenticated CLIENT and drives the
// StatefulShellRoute via the real bottom-nav tiles.
// ---------------------------------------------------------------------------

class _ClientShellHarness {
  _ClientShellHarness._(this.tester, this.container, this.router);

  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;

  static Future<_ClientShellHarness> boot(
    WidgetTester tester, {
    double? width,
    double textScale = 1.0,
    EdgeInsets mediaPadding = EdgeInsets.zero,
  }) async {
    final container = _authedClientContainer();
    final router = container.read(appRouterProvider);

    if (width != null) {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _RouterApp(
          router: router,
          textScale: textScale,
          mediaPadding: mediaPadding,
        ),
      ),
    );

    final harness = _ClientShellHarness._(tester, container, router);
    await harness._settleChrome();
    return harness;
  }

  String get currentLocation =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// Hops to [branchIndex] using the REAL bottom-nav control (tile or center
  /// disc), then settles the chrome. Driving the production widget (not
  /// `goBranch` directly) keeps the test honest about the nav wiring.
  Future<void> goBranch(int branchIndex) async {
    final Finder control = branchIndex == kClientSearchBranch
        ? find.byKey(const Key('client-nav-search-center'))
        : find.byKey(Key('client-nav-tile-$branchIndex'));
    expect(
      control,
      findsOneWidget,
      reason: 'bottom-nav control for branch $branchIndex must be present',
    );
    await tester.tap(control);
    await _settleChrome();
  }

  /// Captures the chrome anchors for the CURRENT branch.
  _ChromeSample sampleChrome({required bool measureTopBar}) {
    final navBox = tester.renderObject<RenderBox>(find.byType(ClientBottomNav));
    final double navTopY = navBox.localToGlobal(Offset.zero).dy;

    double? wordmarkDy;
    if (measureTopBar) {
      // The wordmark is the `beautica` Text inside the on-screen ClientTopBar.
      // Several ClientTopBars exist in the indexedStack (one per kept-alive
      // branch), but only the visible branch's is hit-testable / on-screen; we
      // scope the finder to the wordmark that is a descendant of a ClientTopBar
      // and currently laid out at the visible branch. Using the first painted
      // RenderParagraph for 'beautica' that belongs to the active branch.
      final paragraph = _activeWordmarkBox();
      wordmarkDy = paragraph.localToGlobal(Offset.zero).dy;
    }
    return _ChromeSample(bottomNavTopY: navTopY, wordmarkDy: wordmarkDy);
  }

  /// Finds the `beautica` wordmark RenderBox of the CURRENTLY-VISIBLE branch.
  ///
  /// The IndexedStack keeps all branches mounted, so multiple 'beautica' Texts
  /// can exist (Home + Search + Passport top bars). Off-screen IndexedStack
  /// children are NOT painted (offstage), so we pick the wordmark whose
  /// ClientTopBar ancestor is the one in the active branch by selecting the
  /// hit-testable (on-stage) instance.
  RenderBox _activeWordmarkBox() {
    final Finder wordmark = find.descendant(
      of: find.byType(ClientTopBar),
      matching: find.text('beautica'),
      // Skip offstage instances from the other (kept-alive) branches.
    );
    final onStage = find.descendant(
      of: find.byType(ClientTopBar),
      matching: find.text('beautica', skipOffstage: true),
    );
    final Finder chosen = onStage.evaluate().isNotEmpty ? onStage : wordmark;
    return tester.renderObject<RenderBox>(chosen.first);
  }

  /// Pumps frames until the visible wordmark `dy` (or, when no top bar, the
  /// bottom-nav top-Y) stops changing across two consecutive frames — settling
  /// the one-shot staggered-reveal WITHOUT a fixed-duration sleep. Bounded by a
  /// frame cap so a genuinely perpetual animation cannot hang the test.
  Future<void> _settleChrome() async {
    double? last;
    const int maxFrames = 240; // ~4s of 16ms frames — generous, never infinite.
    int stable = 0;
    for (int i = 0; i < maxFrames; i++) {
      // fixed-wait-ok: single-frame (16ms) advance inside a pump-until-stable loop — this IS pump-until-condition, not a flaky sleep.
      await tester.pump(const Duration(milliseconds: 16));
      final double anchor = _currentAnchor();
      if (last != null && (anchor - last).abs() < _kEpsilon) {
        stable++;
        if (stable >= 2) return; // two consecutive identical frames → settled.
      } else {
        stable = 0;
      }
      last = anchor;
    }
  }

  /// The frame-stability probe: the visible wordmark dy if a ClientTopBar is on
  /// screen, else the bottom-nav top-Y (placeholder branches).
  double _currentAnchor() {
    final hasTopBar = find
        .descendant(
          of: find.byType(ClientTopBar),
          matching: find.text('beautica', skipOffstage: true),
        )
        .evaluate()
        .isNotEmpty;
    if (hasTopBar) {
      return _activeWordmarkBox().localToGlobal(Offset.zero).dy;
    }
    final navBox = tester.renderObject<RenderBox>(find.byType(ClientBottomNav));
    return navBox.localToGlobal(Offset.zero).dy;
  }

  void dispose() {
    router.dispose();
    container.dispose();
  }
}

/// Authenticated-CLIENT [ProviderContainer]. The home/passport data providers
/// are left to the suite-wide no-network override (they settle to AsyncError);
/// the chrome renders regardless of data state.
ProviderContainer _authedClientContainer() {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _FixedAuthNotifier(_clientSession())),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AsyncData<AuthSession> _clientSession() => const AsyncData<AuthSession>(
  AuthSession.authenticated(
    user: User(
      id: 'u-client',
      email: 'client@example.com',
      role: UserRole.client,
      firstName: 'Test',
      lastName: 'Client',
    ),
    accessToken: 'token',
  ),
);

/// [AuthNotifier] stub that immediately settles to a fixed [AsyncValue].
class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}

/// [MaterialApp.router] wrapper for the real [appRouter] with l10n delegates,
/// an optional text-scale override, and optional notch insets (so the stress
/// regimes are applied to the whole routed tree).
class _RouterApp extends StatelessWidget {
  const _RouterApp({
    required this.router,
    this.textScale = 1.0,
    this.mediaPadding = EdgeInsets.zero,
  });

  final GoRouter router;
  final double textScale;
  final EdgeInsets mediaPadding;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
    builder: (context, child) {
      final base = MediaQuery.of(context);
      return MediaQuery(
        data: base.copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: mediaPadding,
          viewPadding: mediaPadding,
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
  );
}
