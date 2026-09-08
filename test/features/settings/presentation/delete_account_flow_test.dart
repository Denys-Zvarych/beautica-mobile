// Widget test for `runDeleteAccountFlow`
// (`lib/features/settings/presentation/delete_account_flow.dart`) covering
// the ONE branch that cannot be exercised through the real caller screen.
//
// WHY THIS FILE IS DELIBERATELY THIN
// -----------------------------------
// `runDeleteAccountFlow` has exactly ONE production call site — the
// «Акаунт» page, `SettingsScreen`
// (`lib/features/settings/presentation/settings_screen.dart`; relocated
// there 2026-09-08 from `ClientSettingsHubScreen`, which was the wrong
// screen — verified via `grep -a -rln "runDeleteAccountFlow" lib/`, unlike
// `runDeleteSalonFlow`'s two entry points).
// `settings_screen_delete_account_row_test.dart`'s "SettingsScreen
// delete-account row interaction" group already drives the flow through
// that real caller and covers: row position, the no-digit dialog copy
// (locked product decision), cancel / barrier-tap / OS-back all resetting
// `inFlight`, a successful confirm calling `deleteMyAccount()` once +
// tearing auth down + landing on `/login`, the spinner being post-consent
// only, the double-tap guard, the 422/429 failure surfaces, and both flags
// resetting on failure. Re-deriving all of that against a second, synthetic
// harness here would be pure duplication (REUSE-FIRST / Step 2.7 Rule 2 —
// scope proportional to the change), not new coverage.
//
// What THIS file proves instead: the caller-unmounted-WHILE-the-DELETE-call-
// is-still-in-flight path (`delete_account_flow.dart`, the
// `if (!context.mounted) return;` immediately after the
// `deleteMyAccount()` await succeeds). That branch needs a harness because
// it requires unmounting the CALLER widget at a precise mid-await point —
// nothing in the real `SettingsScreen` navigates itself away while its own
// delete-account row is mid-flight in a way this suite can drive
// deterministically, and driving that race through the full screen adds
// machinery without adding assurance over the isolated version here.
// Mirrors `delete_salon_flow_test.dart`'s "invalidation survives caller
// unmount" test's proven technique for the equivalent salon-delete branch.
//
// Finders use widget Keys — never Cyrillic literals (M2).
// Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/settings/presentation/delete_account_flow.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_user_repository.dart';
import '../../../helpers/pump_app.dart';

const Key _kRunButtonKey = Key('btn-run-delete-account-flow');
const Key _kHarnessKey = Key('harness-screen');

/// AuthNotifier tracking `logout()` calls — a call here would be the
/// regression symptom (session torn down for a caller that already left).
class _TrackingAuthNotifier extends AuthNotifier {
  int logoutCalls = 0;

  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();

  @override
  Future<void> logout() async {
    logoutCalls++;
  }
}

/// Minimal harness: one button whose `onPressed` invokes
/// `runDeleteAccountFlow` directly — mirrors
/// `delete_salon_flow_test.dart`'s `_HarnessScreen` shape.
class _HarnessScreen extends ConsumerStatefulWidget {
  const _HarnessScreen();

  @override
  ConsumerState<_HarnessScreen> createState() => _HarnessScreenState();
}

class _HarnessScreenState extends ConsumerState<_HarnessScreen> {
  final ValueNotifier<bool> inFlight = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  @override
  void dispose() {
    inFlight.dispose();
    loading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Warms authProvider on this widget's own build — same race-avoidance
    // rationale as `delete_salon_flow_test.dart`'s `_HarnessScreen` (a bare
    // `ref.read` inside the button handler would be the FIRST read of the
    // provider, returning `AsyncLoading` synchronously and never settling
    // under a bare `pumpAndSettle`).
    ref.watch(authProvider);
    return Scaffold(
      key: _kHarnessKey,
      body: Center(
        child: ElevatedButton(
          key: _kRunButtonKey,
          onPressed: () => runDeleteAccountFlow(
            context,
            ref,
            inFlight: inFlight,
            loading: loading,
          ),
          child: const Text('run'),
        ),
      ),
    );
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/harness',
  routes: <RouteBase>[
    GoRoute(path: '/harness', builder: (_, _) => const _HarnessScreen()),
    GoRoute(
      path: '/elsewhere',
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('elsewhere-stub'))),
    ),
  ],
);

void main() {
  testWidgets(
    'the inFlight guard alone blocks a second invocation issued before the '
    'first showDialog await returns',
    (tester) async {
      // `settings_screen_delete_account_row_test.dart`'s own "double-tap
      // guard" test proves two rapid ROW TAPS yield one `deleteMyAccount()`
      // call, but a
      // mutation probe there (removing `inFlight.value = true;` entirely)
      // stayed GREEN — the row's OWN `loading`-driven `AbsorbPointer`
      // (`SettingsRow`) already blocks the second tap by itself once
      // `loading` flips true, so that test does not actually pin `inFlight`
      // in isolation. THIS test does: it drives `runDeleteAccountFlow`'s
      // `onPressed` callback directly, TWICE, with no `await`/pump between
      // the two calls — before EITHER call's `showDialog` await has a
      // chance to resolve, which is the actual race the guard exists for.
      // A `tester.tap()`-based double-tap cannot reproduce this at all:
      // `showDialog` synchronously inserts a modal barrier that a SECOND
      // `tester.tap()` at the same coordinates legitimately refuses to
      // reach.
      final fakeRepo = FakeUserRepository();
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[userRepositoryProvider.overrideWithValue(fakeRepo)],
      );
      await tester.pumpAndSettle();

      final VoidCallback onPressed = tester
          .widget<ElevatedButton>(find.byKey(_kRunButtonKey))
          .onPressed!;

      onPressed();
      onPressed();
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason:
            'a second synchronous invocation before the first showDialog '
            'resolves must not stack a second dialog',
      );

      await tester.tap(find.byKey(const Key('btn-delete-account-cancel')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a delete that SUCCEEDS while the caller unmounts mid-await does NOT '
    'tear auth down for the departed caller',
    (tester) async {
      final fakeRepo = FakeUserRepository()
        ..deleteMyAccountGate = Completer<void>();
      final auth = _TrackingAuthNotifier();
      final router = _router();
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          authProvider.overrideWith(() => auth),
          userRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_kRunButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-delete-account-confirm')));
      // Advance only up to the gated `deleteMyAccount()` await — the dialog
      // has already popped (confirm resolved synchronously), and the
      // network call is genuinely in flight, gated.
      await tester.pump();

      expect(fakeRepo.deleteMyAccountCalls, 1, reason: 'the call is in flight');
      expect(auth.logoutCalls, 0);

      // Navigate the CALLER away mid-await — unmounts `_HarnessScreen` (and
      // its BuildContext) exactly as a user leaving mid-delete would.
      // `runDeleteAccountFlow` itself is still suspended on the gated
      // `deleteMyAccount()` await below and plays no part in this
      // navigation.
      router.go('/elsewhere');
      await tester.pumpAndSettle();
      expect(
        find.byKey(_kHarnessKey),
        findsNothing,
        reason: 'the caller must have genuinely unmounted',
      );

      // Unblock the DELETE — it succeeds server-side AFTER the caller is
      // already gone.
      fakeRepo.deleteMyAccountGate!.complete();
      await tester.pumpAndSettle();

      expect(
        auth.logoutCalls,
        0,
        reason:
            'the `context.mounted` guard must stop the flow from tearing '
            'auth down (or navigating) for a caller that already left — a '
            'call here would mean the guard was skipped',
      );
      expect(
        find.byKey(const Key('elsewhere-stub')),
        findsOneWidget,
        reason: 'the caller\'s own navigation must be left untouched',
      );
    },
  );
}
