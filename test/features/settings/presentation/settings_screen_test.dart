// Widget tests for the Account page (SettingsScreen).
//
// The «Акаунт» page is reached from the settings hub's Account row. It carries a
// language placeholder row (Key('row-language')) and a notifications toggle
// (Key('row-notifications')). There is NO Save button; controls act inline.
//
// Logout was REMOVED from this page — it now lives ONLY on the settings hub
// (settings_hub_screen.dart, row-logout → runLogoutFlow). The Account page must
// surface no logout control. Coverage:
//   A1 — Account-page controls render (language + notifications) and there is
//        NO logout control (regression guard against the row being reintroduced).
//   A8 — notifications toggle flips local state.
//
// The logout confirm/cancel/double-tap/failure/secure-storage-clear flow is
// covered on the hub test (settings_hub_screen_test.dart) — that is the only
// surface that triggers logout now.
//
// ScreenProtector native calls are kDebugMode-suppressed in the test runner.
// Navigation is driven by a minimal GoRouter (initial route = /settings).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/features/settings/presentation/settings_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.settings,
  redirect: (context, state) => null,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (_, _) => const Scaffold(body: Text('login')),
    ),
    // Beautica OTP task Phase B5 — "Change password" row destination.
    GoRoute(
      path: RouteNames.changePassword,
      builder: (_, _) =>
          const Scaffold(body: Center(child: Text('change-password'))),
    ),
  ],
);

Widget _buildApp({
  required GoRouter router,
  required FakeAuthRepository repo,
  required FakeSecureStorage storage,
}) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWith((_) => repo),
    secureStorageProvider.overrideWith((_) => storage),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  ),
);

void main() {
  group('SettingsScreen (Account page)', () {
    // A1 -----------------------------------------------------------------------
    testWidgets(
      'A1. account controls render (language + notifications) and NO logout '
      'control is present',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(
            router: router,
            repo: FakeAuthRepository(),
            storage: FakeSecureStorage(),
          ),
        );
        await tester.pumpAndSettle();

        // The placeholder rows remain.
        expect(find.byKey(const Key('row-language')), findsOneWidget);
        expect(find.byKey(const Key('row-notifications')), findsOneWidget);

        // Regression guard: logout was removed from the Account page — it lives
        // only on the settings hub now. Neither the row nor its label may
        // appear here.
        expect(
          find.byKey(const Key('btn-logout')),
          findsNothing,
          reason:
              'logout was removed from the Account page; reintroducing it here '
              'would resurrect two logout entry points',
        );
        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(
          find.text(l10n.logout),
          findsNothing,
          reason: 'no logout label may render on the Account page',
        );
      },
    );

    // A8 -----------------------------------------------------------------------
    testWidgets('A8. notifications toggle flips its local state', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(
          router: router,
          repo: FakeAuthRepository(),
          storage: FakeSecureStorage(),
        ),
      );
      await tester.pumpAndSettle();

      // WHAT CHANGED (2026-07-22 vacuous-assertion audit)
      // -------------------------------------------------
      // This test used to read `row.initialValue` BEFORE the tap and then
      // assert only that the switch widget still existed AFTER it.
      // `initialValue` is a constructor parameter, not live state — it cannot
      // change — so the whole test passed with a completely no-op `onChanged`.
      // A test named "flips its local state" verified no flip at all.
      //
      // The switch is `_NeumorphicSwitch` (private, so unreachable by type) and
      // is NOT a Material `Switch`, so there is no `Switch.value` to read. The
      // live state IS exposed as the `Semantics(toggled: _on)` wrapper on
      // SettingsToggleRow — the same signal a screen reader consumes — so the
      // assertion reads that, before and after.
      //
      // MUTATION-VERIFIED: replacing `_NeumorphicSwitch.onChanged` with a no-op
      // in lib/features/master/presentation/widgets/settings_row.dart turns
      // this test red. Restored immediately; not committed.
      // Disposed inline at the end of the body, NOT via addTearDown —
      // flutter_test's end-of-test semantics-handle verification runs BEFORE
      // tearDown callbacks and would fail the test.
      final SemanticsHandle handle = tester.ensureSemantics();

      final toggle = find.byKey(const Key('row-notifications'));
      expect(toggle, findsOneWidget);

      // Initial state is ON.
      expect(tester.getSemantics(toggle), isSemantics(isToggled: true));

      await tester.tap(find.byKey(const Key('switch-notifications')));
      await tester.pumpAndSettle();

      // The observable toggle state must actually have flipped.
      expect(
        tester.getSemantics(toggle),
        isSemantics(isToggled: false),
        reason:
            'tapping switch-notifications must flip the row\'s toggled state; '
            'a no-op onChanged must not pass this test',
      );

      // And back again — pins that the flip is a real toggle, not a one-way
      // latch that happens to satisfy the assertion above.
      await tester.tap(find.byKey(const Key('switch-notifications')));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(toggle), isSemantics(isToggled: true));

      handle.dispose();
    });

    // Beautica OTP task Phase B5 -----------------------------------------------
    testWidgets(
      'A9. "Change password" row sends the initial OTP then navigates to '
      'RouteNames.changePassword',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);
        final repo = FakeAuthRepository();

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: FakeSecureStorage()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('row-change-password')), findsOneWidget);

        await tester.ensureVisible(
          find.byKey(const Key('row-change-password')),
        );
        await tester.tap(find.byKey(const Key('row-change-password')));
        await tester.pumpAndSettle();

        // The OTP was sent BEFORE navigating — never navigate the user onto an
        // OTP entry screen for a code that was never actually dispatched.
        expect(repo.requestChangePasswordOtpCallCount, 1);
        expect(find.text('change-password'), findsOneWidget);
      },
    );

    testWidgets('A10. "Change password" row shows an inline error and does NOT '
        'navigate when requestChangePasswordOtp fails (e.g. 429 cooldown)', (
      tester,
    ) async {
      final router = _makeRouter();
      addTearDown(router.dispose);
      final repo = FakeAuthRepository()
        ..requestChangePasswordOtpResult = const ResendThrottledFailure(
          retryAfterSeconds: 42,
        );

      await tester.pumpWidget(
        _buildApp(router: router, repo: repo, storage: FakeSecureStorage()),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('row-change-password'))),
      );

      await tester.ensureVisible(find.byKey(const Key('row-change-password')));
      await tester.tap(find.byKey(const Key('row-change-password')));
      await tester.pumpAndSettle();

      expect(repo.requestChangePasswordOtpCallCount, 1);
      // Stayed on /settings — never navigated to a dead OTP screen.
      expect(find.text('change-password'), findsNothing);
      expect(
        find.text(l10n.verificationErrResendThrottled(42)),
        findsOneWidget,
      );
    });

    // mobile-perf MEDIUM fix — the change-password row now surfaces the
    // in-flight OTP request visually (dimmed row + spinner instead of the
    // chevron) via SettingsRow.loading, instead of giving zero feedback while
    // `_requestingChangePasswordOtp` silently guards against a double-tap.
    testWidgets(
      'settings_change_password_row_shows_loading_during_otp_request',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);
        final completer = Completer<void>();
        final repo = FakeAuthRepository()
          ..requestChangePasswordOtpDelay = completer.future;

        await tester.pumpWidget(
          _buildApp(router: router, repo: repo, storage: FakeSecureStorage()),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('row-change-password')),
        );

        // No loading indicator before the tap — chevron shown instead.
        expect(
          find.byKey(const ValueKey<String>('settings_row_loading')),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('row-change-password')));
        await tester.pump(); // begin the async requestChangePasswordOtp call

        // Loading spinner visible + the row itself reports loading:true while
        // the request is in flight.
        expect(
          find.byKey(const ValueKey<String>('settings_row_loading')),
          findsOneWidget,
        );
        final SettingsRow row = tester.widget(
          find.byKey(const Key('row-change-password')),
        );
        expect(row.loading, isTrue);

        // A second tap while loading is visibly absorbed — no second call.
        await tester.tap(find.byKey(const Key('row-change-password')));
        await tester.pump();
        expect(repo.requestChangePasswordOtpCallCount, 1);

        // Resolve the pending request and let the screen navigate onward.
        completer.complete();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('settings_row_loading')),
          findsNothing,
        );
        expect(find.text('change-password'), findsOneWidget);
      },
    );
  });

  // ANB — notification-bell icon swap guard --------------------------------
  //
  // The notifications toggle row's glyph was swapped from a Material
  // Icon(Icons.notifications_none_rounded) to the dotless bell SVG
  // AppIcon(BeauticaAssetIcons.notificationPlain), 19px / accentDeep — the SAME
  // bell the top-bar BellButton renders, so the two sit identically.
  //
  // Red-against-revert: with the old Material icon the notificationPlain
  // predicate finds 0 (Icon is not AppIcon) → ANB1 fails. With the swap it finds
  // the single bell SVG inside row-notifications → passes. Rule 3 (previously
  // unguarded site — the existing A1/A8 tests assert the row by Key only).
  //
  // Finders are robust Key-scoped widget predicates — never localized strings.
  group('SettingsScreen notification-bell icon (swap guard)', () {
    Finder bell() => find.byWidgetPredicate(
      (w) => w is AppIcon && w.asset == BeauticaAssetIcons.notificationPlain,
    );

    testWidgets(
      'ANB1. row-notifications renders the notificationPlain bell SVG and no '
      'Material notifications Icon remains',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(
            router: router,
            repo: FakeAuthRepository(),
            storage: FakeSecureStorage(),
          ),
        );
        await tester.pumpAndSettle();

        // Exactly one bell SVG on the screen, scoped inside the notifications
        // row (red-against-revert: 0 if reverted to the Material bell).
        expect(
          find.descendant(
            of: find.byKey(const Key('row-notifications')),
            matching: bell(),
          ),
          findsOneWidget,
          reason:
              'the notifications row must render the dotless notificationPlain '
              'bell SVG (matching the top-bar BellButton)',
        );

        // The swap is complete, not doubled: the old Material bell must be gone
        // from inside the row.
        expect(
          find.descendant(
            of: find.byKey(const Key('row-notifications')),
            matching: find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.notifications_none_rounded,
            ),
          ),
          findsNothing,
          reason:
              'the old Material Icons.notifications_none_rounded must not remain '
              'alongside the SVG (the swap replaces, not stacks)',
        );
      },
    );

    testWidgets(
      'ANB2. notification bell keeps the 19px / accentDeep tint and size '
      '(parity with the top-bar bell and sibling settings rows)',
      (tester) async {
        final router = _makeRouter();
        addTearDown(router.dispose);

        await tester.pumpWidget(
          _buildApp(
            router: router,
            repo: FakeAuthRepository(),
            storage: FakeSecureStorage(),
          ),
        );
        await tester.pumpAndSettle();

        final icon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const Key('row-notifications')),
            matching: bell(),
          ),
        );
        expect(
          icon.size,
          19,
          reason: 'settings notification bell must stay 19px',
        );
        expect(
          icon.color,
          BrandColors.accentDeep,
          reason: 'settings notification bell must stay BrandColors.accentDeep',
        );
      },
    );
  });
}
