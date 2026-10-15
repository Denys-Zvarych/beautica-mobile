// «Акаунт» → «Сповіщення» switch mirrors the REAL Android notification
// permission ("Mirror Android"):
//   N1 — granted → ON (default subtitle); denied / notDetermined → OFF («off»
//        subtitle).
//   N2 — a tap (either direction) calls the settings opener exactly once and
//        never flips the switch by itself.
//   N3 — after a simulated resume with a changed permission, the switch
//        follows; without a resume it does not.
//   N4 — re-read on every visit to the screen.
//   N5 — push unavailable → OFF, inert (semantics disabled), opener never
//        called.
//   N6 — SettingsToggleRow without `value` keeps its local-state flip (every
//        other caller's behaviour is unchanged).
//   N7 — a revisit shows the last known reading at once (inert) while the
//        fresh read runs — no OFF flash — then the fresh read confirms it.
//   N8 — a resume while the Account page is covered by another route does not
//        re-read; it is replayed once when Account is current again.
//
// The permission reader and the settings opener are faked through their
// providers — no platform channel, no Firebase.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/push/notification_permission_provider.dart';
import 'package:beautica_mobile/core/push/notification_tray_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
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

const Key _row = Key('row-notifications');
const Key _switch = Key('switch-notifications');
const String _elsewhere = '/elsewhere';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

class _Os {
  _Os(this.status);

  NotificationPermissionStatus status;
  int reads = 0;
  int opens = 0;

  /// When set, reads hang until it completes (a slow platform read).
  Completer<NotificationPermissionStatus>? gate;

  Future<NotificationPermissionStatus> read() async {
    reads++;
    final Completer<NotificationPermissionStatus>? g = gate;
    if (g != null) return g.future;
    return status;
  }

  Future<void> open() async => opens++;
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.settings,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.settings,
      builder: (_, _) => const SettingsScreen(),
    ),
    GoRoute(
      path: RouteNames.changePassword,
      builder: (_, _) => const Scaffold(body: Text('change-password')),
    ),
    GoRoute(
      path: _elsewhere,
      builder: (_, _) => const Scaffold(body: Text('elsewhere')),
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester tester, _Os os) async {
  final GoRouter router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        notificationPermissionReaderProvider.overrideWithValue(os.read),
        notificationSettingsOpenerProvider.overrideWithValue(os.open),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

/// Where the switch thumb is heading (right = ON) — the rendered target that
/// would animate on a flip.
AlignmentGeometry _thumbTarget(WidgetTester tester) => tester
    .widget<AnimatedAlign>(
      find.descendant(
        of: find.byKey(_switch),
        matching: find.byType(AnimatedAlign),
      ),
    )
    .alignment;

Finder _subtitle(String text) =>
    find.descendant(of: find.byKey(_row), matching: find.text(text));

void main() {
  group('«Сповіщення» switch mirrors the Android permission', () {
    testWidgets('N1a. granted → ON with the default subtitle', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, _Os(NotificationPermissionStatus.granted));

      expect(
        tester.getSemantics(find.byKey(_row)),
        isSemantics(isToggled: true),
      );
      expect(_subtitle(_l10n.accountNotificationsSubtitle), findsOneWidget);
      handle.dispose();
    });

    for (final NotificationPermissionStatus s in <NotificationPermissionStatus>[
      NotificationPermissionStatus.denied,
      NotificationPermissionStatus.notDetermined,
    ]) {
      testWidgets('N1b. ${s.name} → OFF with the «off» subtitle', (
        tester,
      ) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pump(tester, _Os(s));

        expect(
          tester.getSemantics(find.byKey(_row)),
          isSemantics(isToggled: false),
        );
        expect(
          _subtitle(_l10n.accountNotificationsOffSubtitle),
          findsOneWidget,
        );
        handle.dispose();
      });
    }

    for (final NotificationPermissionStatus s in <NotificationPermissionStatus>[
      NotificationPermissionStatus.granted,
      NotificationPermissionStatus.denied,
    ]) {
      testWidgets(
        'N2. tap while ${s.name} opens settings once and does NOT flip',
        (tester) async {
          final SemanticsHandle handle = tester.ensureSemantics();
          final _Os os = _Os(s);
          await _pump(tester, os);
          final bool before = s == NotificationPermissionStatus.granted;

          await tester.tap(find.byKey(_switch));
          await tester.pumpAndSettle();

          expect(os.opens, 1);
          expect(
            tester.getSemantics(find.byKey(_row)),
            isSemantics(isToggled: before),
            reason:
                'an app cannot change its own permission — no optimistic '
                'flip',
          );
          handle.dispose();
        },
      );
    }

    testWidgets('N3. a resume re-reads the permission and the switch follows', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final _Os os = _Os(NotificationPermissionStatus.denied);
      await _pump(tester, os);

      await tester.tap(find.byKey(_switch));
      await tester.pumpAndSettle();
      // The user enables notifications in Android settings…
      os.status = NotificationPermissionStatus.granted;
      await tester.pumpAndSettle();
      // …but nothing re-reads until the app resumes.
      expect(
        tester.getSemantics(find.byKey(_row)),
        isSemantics(isToggled: false),
      );

      await _resume(tester);
      expect(
        tester.getSemantics(find.byKey(_row)),
        isSemantics(isToggled: true),
      );
      expect(_subtitle(_l10n.accountNotificationsSubtitle), findsOneWidget);

      // And back off again.
      os.status = NotificationPermissionStatus.denied;
      await _resume(tester);
      expect(
        tester.getSemantics(find.byKey(_row)),
        isSemantics(isToggled: false),
      );
      handle.dispose();
    });

    testWidgets('N4. every visit to the screen re-reads the permission', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final _Os os = _Os(NotificationPermissionStatus.denied);
      final GoRouter router = await _pump(tester, os);
      final int firstReads = os.reads;

      router.go(_elsewhere);
      await tester.pumpAndSettle();
      os.status = NotificationPermissionStatus.granted;
      router.go(RouteNames.settings);
      await tester.pumpAndSettle();

      expect(os.reads, greaterThan(firstReads));
      expect(
        tester.getSemantics(find.byKey(_row)),
        isSemantics(isToggled: true),
      );
      handle.dispose();
    });

    testWidgets(
      'N5. push unavailable → OFF, inert, opener never called, no crash',
      (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        final _Os os = _Os(NotificationPermissionStatus.unavailable);
        await _pump(tester, os);

        expect(find.byKey(_row), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(_row)),
          isSemantics(isToggled: false, isEnabled: false),
        );

        await tester.tap(find.byKey(_switch));
        await tester.pumpAndSettle();

        expect(os.opens, 0);
        expect(
          tester.getSemantics(find.byKey(_row)),
          isSemantics(isToggled: false),
        );
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );
  });

  testWidgets('N7. revisit shows the cached reading with no OFF flash', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final _Os os = _Os(NotificationPermissionStatus.granted);
    final GoRouter router = await _pump(tester, os);
    expect(tester.getSemantics(find.byKey(_row)), isSemantics(isToggled: true));

    router.go(_elsewhere);
    await tester.pumpAndSettle();
    final Completer<NotificationPermissionStatus> gate =
        Completer<NotificationPermissionStatus>();
    os.gate = gate;
    router.go(RouteNames.settings);

    // Every frame while the fresh read is pending — from the first frame the
    // switch exists, while the row is still fading in (semantics not yet
    // exposed): the thumb's target is ON (cached) and the row is inert.
    int framesChecked = 0;
    for (int i = 0; i < 12; i++) {
      await tester.pump(
        i == 0 ? Duration.zero : const Duration(milliseconds: 50),
      );
      if (find.byKey(_switch).evaluate().isEmpty) {
        expect(framesChecked, 0, reason: 'the switch must not disappear');
        continue;
      }
      framesChecked++;
      expect(
        _thumbTarget(tester),
        Alignment.centerRight,
        reason: 'frame $i: a revisit must not flash OFF while re-reading',
      );
      expect(
        tester.widget<SettingsToggleRow>(find.byKey(_row)).onChanged,
        isNull,
        reason: 'frame $i: inert until the fresh read lands',
      );
    }
    expect(framesChecked, greaterThanOrEqualTo(10));

    gate.complete(NotificationPermissionStatus.granted);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byKey(_row)), isSemantics(isToggled: true));
    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();
    expect(os.opens, 1, reason: 'interactive again once the read landed');
    handle.dispose();
  });

  testWidgets('N8. a resume while covered is replayed when Account is current '
      'again (Account → change-password → leave → change → return → pop)', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final _Os os = _Os(NotificationPermissionStatus.denied);
    final GoRouter router = await _pump(tester, os);

    // Account → «Змінити пароль» (the real row, real push).
    await tester.ensureVisible(find.byKey(const Key('row-change-password')));
    await tester.tap(find.byKey(const Key('row-change-password')));
    await tester.pumpAndSettle();
    expect(find.text('change-password'), findsOneWidget);
    final int readsWhileCovered = os.reads;

    // Leave the app, enable notifications in Android settings, come back.
    os.status = NotificationPermissionStatus.granted;
    await _resume(tester);
    expect(os.reads, readsWhileCovered, reason: 'covered → no re-read yet');

    // Pop back to Account → the dropped resume is replayed exactly once.
    router.pop();
    await tester.pumpAndSettle();
    expect(os.reads, readsWhileCovered + 1);
    expect(
      tester.getSemantics(find.byKey(_row)),
      isSemantics(isToggled: true),
      reason: 'the switch must not stay stale after popping back',
    );

    // No further reads from route-status churn without a new resume.
    unawaited(router.push<void>(_elsewhere));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(os.reads, readsWhileCovered + 1);
    handle.dispose();
  });

  testWidgets('N6. SettingsToggleRow without `value` still flips locally', (
    tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final List<bool> changes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsToggleRow(
            key: _row,
            switchKey: _switch,
            icon: Icons.notifications_none_rounded,
            label: 'label',
            initialValue: true,
            onChanged: changes.add,
          ),
        ),
      ),
    );

    expect(tester.getSemantics(find.byKey(_row)), isSemantics(isToggled: true));
    await tester.tap(find.byKey(_switch));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(_row)),
      isSemantics(isToggled: false),
    );
    expect(changes, <bool>[false]);
    handle.dispose();
  });
}
