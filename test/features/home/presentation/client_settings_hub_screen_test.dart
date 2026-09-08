// Widget tests for the CLIENT settings hub (ClientSettingsHubScreen).
//
// The hub is the screen the home-hub burger icon pushes. It mirrors the master
// settings hub: six rows — five navigational (personal / contacts / location /
// account / help) plus a terminal logout row that raises the confirm dialog.
//
// Coverage:
//   • all six rows render;
//   • each navigational row tap pushes the correct CLIENT route (asserted via a
//     stub destination sentinel keyed per route);
//   • the logout row raises the confirm dialog and confirming calls logout().
//
// Finders use widget Keys (row-personal, …) — never localized strings (M2).
// Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/presentation/client_settings_hub_screen.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_user_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

/// AuthNotifier whose logout() never resolves — lets a test confirm the dialog
/// without the tree tearing down before assertions run. Tracks invocation.
class _TrackingAuthNotifier extends AuthNotifier {
  int logoutCalls = 0;

  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> logout() async {
    logoutCalls++;
    await Completer<void>().future; // block forever
  }
}

/// AuthNotifier whose logout() resolves immediately — used by the
/// delete-account tests below, which (unlike the logout-row test) must
/// observe the flow's post-success navigation actually land on `/login`.
class _ResolvingAuthNotifier extends AuthNotifier {
  int logoutCalls = 0;

  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

/// Builds a router rooted at the CLIENT hub with stub sentinel destinations for
/// every route the hub can push, so navigation can be asserted by Key.
GoRouter _hubRouter() => GoRouter(
  initialLocation: RouteNames.clientMenu,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.clientMenu,
      builder: (_, _) => const ClientSettingsHubScreen(),
    ),
    GoRoute(
      path: RouteNames.clientEditPersonal,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-personal'))),
    ),
    GoRoute(
      path: RouteNames.clientEditContacts,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-contacts'))),
    ),
    GoRoute(
      path: RouteNames.clientEditLocation,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-location'))),
    ),
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-account'))),
    ),
    GoRoute(
      path: RouteNames.contactSupport,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-help'))),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-home'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-login'))),
    ),
  ],
);

void main() {
  group('ClientSettingsHubScreen navigation rows', () {
    testWidgets('all six rows render', (tester) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-personal')), findsOneWidget);
      expect(find.byKey(const Key('row-contacts')), findsOneWidget);
      expect(find.byKey(const Key('row-location')), findsOneWidget);
      expect(find.byKey(const Key('row-account')), findsOneWidget);
      expect(find.byKey(const Key('row-help')), findsOneWidget);
      expect(find.byKey(const Key('row-logout')), findsOneWidget);
    });

    // (rowKey, destinationSentinelKey) — the locked CLIENT destinations.
    const cases = <(String, String)>[
      ('row-personal', 'stub-personal'),
      ('row-contacts', 'stub-contacts'),
      ('row-location', 'stub-location'),
      ('row-account', 'stub-account'),
      ('row-help', 'stub-help'),
    ];

    for (final (rowKey, destKey) in cases) {
      testWidgets('tapping $rowKey pushes to $destKey', (tester) async {
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(Key(rowKey)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(rowKey)));
        await tester.pumpAndSettle();

        expect(
          find.byKey(Key(destKey)),
          findsOneWidget,
          reason: '$rowKey must push the CLIENT route carrying $destKey',
        );
      });
    }

    testWidgets('close button navigates home when canPop false', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-close-hub')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-home')), findsOneWidget);
    });
  });

  group('ClientSettingsHubScreen location-marker icon (swap guard)', () {
    // The location row's glyph was swapped from a Material
    // Icon(Icons.location_on_outlined) to AppIcon(locationMarker), 19px /
    // accentDeep. Red-against-revert: the predicate finds 0 if reverted to the
    // Material icon (Icon is not AppIcon) → fails; with the swap it finds the
    // single location-marker SVG → passes. Rule 3 (previously unguarded site).
    Finder locationMarker() => find.byWidgetPredicate(
      (w) => w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker,
    );

    testWidgets('row-location renders the locationMarker AppIcon', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      // Exactly one location-marker SVG in the hub, inside the location row.
      expect(locationMarker(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('row-location')),
          matching: locationMarker(),
        ),
        findsOneWidget,
      );
    });

    testWidgets('location marker keeps the 19px / accentDeep tint and size', (
      tester,
    ) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      final icon = tester.widget<AppIcon>(locationMarker());
      expect(icon.size, 19, reason: 'settings location marker must stay 19px');
      expect(
        icon.color,
        BrandColors.accentDeep,
        reason: 'settings location marker must stay BrandColors.accentDeep',
      );
    });
  });

  group('ClientSettingsHubScreen logout row', () {
    testWidgets('confirming the logout calls logout() exactly once', (
      tester,
    ) async {
      final auth = _TrackingAuthNotifier();
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[authProvider.overrideWith(() => auth)],
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-logout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-logout')));
      // mobile-perf MEDIUM fix (2026-09-08) — `_loggingOut` (the re-entrancy
      // guard) flips synchronously on this tap, but it is no longer bound to
      // `SettingsRow(loading:)`; only `_loggingOutLoading` drives the
      // spinner, and it flips true only AFTER confirm, immediately before
      // `logout()`. So nothing is ticking yet here — a real `pumpAndSettle`
      // works again (stronger sync than the bounded pump it replaced).
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(auth.logoutCalls, 0);

      await tester.tap(find.byKey(const Key('btn-logout-confirm')));
      // From here `logout()` blocks forever (`_TrackingAuthNotifier`), which
      // means `_loggingOutLoading` — now true — drives an indeterminate
      // spinner for the rest of this test. `pumpAndSettle` can never settle
      // while that ticks, so bounded pumps stay required past this point.
      await tester.pump(); // apply pop(true) + start logout()
      await tester.pump(const Duration(milliseconds: 300)); // dialog dismiss

      expect(
        auth.logoutCalls,
        1,
        reason: 'confirming must invoke authProvider.logout() exactly once',
      );
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('ClientSettingsHubScreen delete-account row', () {
    testWidgets('renders below row-logout', (tester) async {
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(router);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('row-delete-account')), findsOneWidget);

      final double logoutY = tester
          .getTopLeft(find.byKey(const Key('row-logout')))
          .dy;
      final double deleteY = tester
          .getTopLeft(find.byKey(const Key('row-delete-account')))
          .dy;
      expect(
        deleteY,
        greaterThan(logoutY),
        reason: 'row-delete-account must render below row-logout',
      );
    });

    testWidgets(
      'tapping raises a confirm dialog whose copy carries no digits — no '
      'booking count is fetched or shown (locked product decision)',
      (tester) async {
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(router);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.byKey(const Key('btn-delete-account-cancel')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('btn-delete-account-confirm')),
          findsOneWidget,
        );

        final l10n = lookupAppLocalizations(const Locale('uk'));
        expect(find.text(l10n.deleteAccountConfirmBody), findsOneWidget);
        expect(
          RegExp(r'\d').hasMatch(l10n.deleteAccountConfirmBody),
          isFalse,
          reason:
              'the dialog body must never surface a booking COUNT — a '
              'locked product decision (see delete_account_flow.dart header)',
        );

        // Dismiss so pumpAndSettle at teardown does not hang on an open
        // dialog.
        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'cancel does not call deleteMyAccount and resets inFlight so the row '
      'is tappable again',
      (tester) async {
        final fakeRepo = FakeUserRepository();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            userRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(fakeRepo.deleteMyAccountCalls, 0);

        // inFlight must be reset — a second tap must raise the dialog again,
        // never silently no-op.
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a barrier-tap dismiss does not call deleteMyAccount and resets '
      'inFlight',
      (tester) async {
        final fakeRepo = FakeUserRepository();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            userRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();

        // Tap a corner well outside the centred, width-capped dialog card.
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(fakeRepo.deleteMyAccountCalls, 0);

        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsOneWidget,
          reason: 'inFlight must be reset after a barrier dismiss',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the OS back gesture does not call deleteMyAccount and resets '
        'inFlight', (tester) async {
      final fakeRepo = FakeUserRepository();
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[userRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();

      final bool handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue, reason: 'the dialog route must consume back');
      expect(find.byType(AlertDialog), findsNothing);
      expect(fakeRepo.deleteMyAccountCalls, 0);

      await tester.tap(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'inFlight must be reset after the OS back gesture',
      );

      await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'confirming calls deleteMyAccount exactly once, tears auth down, and '
      'lands on login',
      (tester) async {
        final fakeRepo = FakeUserRepository();
        final auth = _ResolvingAuthNotifier();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            authProvider.overrideWith(() => auth),
            userRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pumpAndSettle();

        expect(fakeRepo.deleteMyAccountCalls, 1);
        expect(
          auth.logoutCalls,
          1,
          reason:
              'a successful delete must tear the session down via '
              'AuthNotifier.logout(), same as runLogoutFlow',
        );
        expect(find.byKey(const Key('stub-login')), findsOneWidget);
      },
    );

    testWidgets(
      'the spinner is post-consent only — the row is not loading while the '
      'confirm dialog is open, only after confirming',
      (tester) async {
        final fakeRepo = FakeUserRepository()
          ..deleteMyAccountGate = Completer<void>();
        final auth = _ResolvingAuthNotifier();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            authProvider.overrideWith(() => auth),
            userRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();

        Finder rowSpinner() => find.descendant(
          of: find.byKey(const Key('row-delete-account')),
          matching: find.byType(CircularProgressIndicator),
        );
        // `find.ancestor` walks from the descendant OUTWARD
        // (`Element.visitAncestorElements`), so index 0 is the NEAREST
        // IgnorePointer ancestor — the one `client_settings_hub_screen.dart`
        // wraps directly around the navigational-rows Column. There can be
        // other IgnorePointer instances further up the tree (framework
        // internals), so this must stay index-scoped, never a bare
        // `findsOneWidget`.
        final Finder navIgnorePointer = find
            .ancestor(
              of: find.byKey(const Key('row-personal')),
              matching: find.byType(IgnorePointer),
            )
            .at(0);

        expect(
          rowSpinner(),
          findsNothing,
          reason: 'the row must not be loading while consent is pending',
        );
        expect(
          tester.widget<IgnorePointer>(navIgnorePointer).ignoring,
          isFalse,
          reason: 'sibling rows must stay reachable while the dialog is open',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pump(); // apply pop(true) + flip loading + start the call
        await tester.pump(const Duration(milliseconds: 300)); // dialog dismiss

        expect(
          rowSpinner(),
          findsOneWidget,
          reason:
              'the row must show loading only AFTER consent, before the '
              'network call resolves',
        );
        expect(
          tester.widget<IgnorePointer>(navIgnorePointer).ignoring,
          isTrue,
          reason:
              'sibling rows must be locked out while the delete is in '
              'flight',
        );

        fakeRepo.deleteMyAccountGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'double-tap guard: a second confirm while the delete call is still '
      'in flight does not fire a second deleteMyAccount call',
      (tester) async {
        // Mirrors `settings_hub_screen_test.dart`'s own logout double-tap
        // guard test exactly (same production bug class, same shared-idiom
        // sibling flow): a genuine two-taps-before-either-await-returns race
        // cannot be reproduced through two consecutive `tester.tap()` calls
        // on the SAME coordinates — `showDialog` synchronously inserts a
        // modal barrier that the SECOND `tester.tap()` call's own
        // pre-flight hit-test check refuses to tap through (a faithful, not
        // a spurious, refusal). The re-entrancy guard is instead proven by
        // holding the FIRST call in flight (gated) and re-tapping the row
        // while it is still there.
        //
        // MUTATION-VERIFIED HONESTY NOTE (mobile-qa): removing
        // `inFlight.value = true;` entirely from `delete_account_flow.dart`
        // leaves THIS test GREEN — at this point in the flow `loading` is
        // already true, and `SettingsRow`'s own `loading`-driven
        // `AbsorbPointer` independently blocks the re-tap before it ever
        // reaches `onTap`. So this test pins the REAL, user-visible
        // behaviour (two taps → one call) but does NOT, by itself, prove
        // `inFlight` is load-bearing. `inFlight` specifically is isolated
        // and mutation-verified in
        // `delete_account_flow_test.dart`'s "the inFlight guard alone …"
        // test, which drives two SYNCHRONOUS invocations before either
        // `showDialog` await returns — the actual race `inFlight` exists
        // for, and a shape `AbsorbPointer` cannot substitute for since
        // `loading` is still false at that point.
        final fakeRepo = FakeUserRepository()
          ..deleteMyAccountGate = Completer<void>();
        final auth = _ResolvingAuthNotifier();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            authProvider.overrideWith(() => auth),
            userRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pump(); // the DELETE call is now in flight (gated)

        expect(fakeRepo.deleteMyAccountCalls, 1);

        // Re-tap while still in flight: absorbed by the row's own `loading`
        // AbsorbPointer AND short-circuited by `inFlight` if it somehow
        // reached the handler — either way, no second call and no second
        // dialog.
        await tester.tap(
          find.byKey(const Key('row-delete-account')),
          warnIfMissed: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const Key('btn-delete-account-confirm')),
          findsNothing,
          reason: 'a second tap while in flight must not raise a new dialog',
        );
        expect(
          fakeRepo.deleteMyAccountCalls,
          1,
          reason: 'the in-flight guard must prevent a second concurrent call',
        );

        fakeRepo.deleteMyAccountGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a 422 booking-limit failure renders the backend serverMessage '
        'verbatim', (tester) async {
      const String marker =
          'QA-422-MARKER: спочатку скасуйте бронювання №A1B2C3';
      final fakeRepo = FakeUserRepository()
        ..deleteMyAccountError = const AccountDeleteBookingLimitFailure(
          serverMessage: marker,
        );
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[userRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expectVelvetSnack(marker, variant: VelvetSnackVariant.error);
      expect(find.byKey(const Key('stub-login')), findsNothing);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a 429 rate-limit failure renders the rate-limit message', (
      tester,
    ) async {
      final fakeRepo = FakeUserRepository()
        ..deleteMyAccountError = const AccountDeleteRateLimitedFailure();
      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[userRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('row-delete-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      final l10n = lookupAppLocalizations(const Locale('uk'));
      expectVelvetSnack(
        l10n.accountDeleteErrRateLimited,
        variant: VelvetSnackVariant.error,
      );
      expect(find.byKey(const Key('stub-login')), findsNothing);

      await pumpPastVelvetSnack(tester);
    });

    testWidgets(
      'on failure both flags reset — the row is usable again and the hub '
      'is not left inert',
      (tester) async {
        final fakeRepo = FakeUserRepository()
          ..deleteMyAccountError = const NetworkFailure();
        final router = _hubRouter();
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            userRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
        await tester.pump();
        await pumpVelvetSnackIn(tester);
        await pumpPastVelvetSnack(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('row-delete-account')),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
          reason: 'loading must reset on failure',
        );
        expect(
          tester
              .widget<IgnorePointer>(
                // Nearest ancestor only — see the identical note in the
                // spinner test above.
                find
                    .ancestor(
                      of: find.byKey(const Key('row-personal')),
                      matching: find.byType(IgnorePointer),
                    )
                    .at(0),
              )
              .ignoring,
          isFalse,
          reason: 'the hub must not stay locked out after a failed delete',
        );

        // inFlight reset — the row raises the dialog again.
        await tester.tap(find.byKey(const Key('row-delete-account')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          fakeRepo.deleteMyAccountCalls,
          1,
          reason: 'only the first tap should have reached the network',
        );

        await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
        await tester.pumpAndSettle();
      },
    );
  });
}
