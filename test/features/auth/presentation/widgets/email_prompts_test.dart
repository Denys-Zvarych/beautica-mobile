// M517 (AUTH-D17, CLI-D09) — the «Email для сповіщень» prompts:
//
//   (a) NotificationEmailSettingsRow: «Додати» until an email is confirmed,
//       then the address, ellipsized; tap opens the email entry.
//   (b) claimClientEmailPrompt: CLIENT with an explicitly unconfirmed email,
//       once ever (claimed on first show); never a provider / unknown state.
//   (c) ProviderEmailPromptCard: zero-size unless due; «Не зараз» hides it;
//       shown again once 30 days later; a second hide retires it.

import 'dart:async';

import 'package:beautica_mobile/core/diagnostics/crash_reporting_enabled_provider.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/email_prompts.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../../integration_test/support/app_harness.dart';
import '../../../../helpers/fakes/fake_diagnostics_store.dart';

class _AuthStub extends AuthNotifier {
  _AuthStub(this.user);

  final User user;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 't');
}

const User _client = User(
  id: 'c1',
  role: UserRole.client,
  emailVerified: false,
);

const User _master = User(
  id: 'm1',
  role: UserRole.independentMaster,
  emailVerified: false,
);

final class _H {
  _H(User user, {FakeDiagnosticsStore? store})
    : store = store ?? FakeDiagnosticsStore() {
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _AuthStub(user)),
        diagnosticsStoreProvider.overrideWithValue(this.store),
        clockProvider.overrideWithValue(() => now),
      ],
    );
  }

  final FakeDiagnosticsStore store;
  DateTime now = DateTime.utc(2026, 11, 18, 9);
  late final ProviderContainer container;
}

/// A store whose writes block until [gate] completes — models the keystore
/// round trip the optimistic hide must not wait for.
final class _GatedStore extends FakeDiagnosticsStore {
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    await gate.future;
    return super.write(key, value);
  }
}

/// A probe that exposes a [WidgetRef] for [claimClientEmailPrompt].
class _ClaimProbe extends ConsumerWidget {
  const _ClaimProbe(this.onRef);

  final void Function(WidgetRef ref) onRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onRef(ref);
    return const SizedBox.shrink();
  }
}

Future<GoRouter> _pump(WidgetTester tester, _H h, Widget child) async {
  await h.container.read(authProvider.future);
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
      GoRoute(
        path: RouteNames.notificationEmail,
        builder: (_, _) => const Scaffold(body: Text('email-entry')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
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

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));
  const Key rowKey = Key('row-notification-email');
  const Key cardKey = Key('provider-home-email-card');

  group('(a) NotificationEmailSettingsRow', () {
    testWidgets('no confirmed email → «Додати»; tap opens the entry', (
      tester,
    ) async {
      final _H h = _H(_client);
      addTearDown(h.container.dispose);
      final GoRouter router = await _pump(
        tester,
        h,
        const NotificationEmailSettingsRow(),
      );

      final SettingsRow row = tester.widget<SettingsRow>(find.byKey(rowKey));
      expect(row.label, l10n.profileNotificationEmailTitle);
      expect(row.subtitle, l10n.profileNotificationEmailSubtitle);
      expect(row.value, l10n.emailPromptAdd);
      expect(row.ellipsizeValue, isTrue);

      await tester.tap(find.byKey(rowKey));
      await tester.pumpAndSettle();
      expect(AppHarness.location(router), RouteNames.notificationEmail);
    });

    testWidgets('a confirmed email shows the address (ellipsized)', (
      tester,
    ) async {
      final _H h = _H(
        _master.copyWith(
          email: 'olena.kovalenko.beauty.studio@gmail.com',
          emailVerified: true,
        ),
      );
      addTearDown(h.container.dispose);
      await _pump(tester, h, const NotificationEmailSettingsRow());

      expect(
        tester.widget<SettingsRow>(find.byKey(rowKey)).value,
        'olena.kovalenko.beauty.studio@gmail.com',
      );
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });
  });

  group('(b) claimClientEmailPrompt', () {
    testWidgets('a CLIENT without a confirmed email claims it once, ever', (
      tester,
    ) async {
      final _H h = _H(_client);
      addTearDown(h.container.dispose);
      late WidgetRef ref;
      await _pump(tester, h, _ClaimProbe((r) => ref = r));

      expect(await claimClientEmailPrompt(ref), isTrue);
      expect(await claimClientEmailPrompt(ref), isFalse);
    });

    for (final (String name, User u) in <(String, User)>[
      ('a provider', _master),
      ('an unknown email state', _client.copyWith(emailVerified: null)),
      ('a confirmed email', _client.copyWith(emailVerified: true)),
    ]) {
      testWidgets('never for $name', (tester) async {
        final _H h = _H(u);
        addTearDown(h.container.dispose);
        late WidgetRef ref;
        await _pump(tester, h, _ClaimProbe((r) => ref = r));
        expect(await claimClientEmailPrompt(ref), isFalse);
      });
    }
  });

  group('(c) ProviderEmailPromptCard', () {
    testWidgets('due → shown; «Не зараз» hides; back once after 30 days; '
        'a second hide retires it', (tester) async {
      final _H h = _H(_master);
      addTearDown(h.container.dispose);
      await _pump(tester, h, const ProviderEmailPromptCard());

      expect(find.byKey(cardKey), findsOneWidget);
      expect(find.text(l10n.providerHomeEmailPromptTitle), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_secondary_action')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsNothing);

      h.now = h.now.add(const Duration(days: 29));
      h.container.invalidate(providerEmailCardDueProvider('m1'));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsNothing);

      h.now = h.now.add(const Duration(days: 1));
      h.container.invalidate(providerEmailCardDueProvider('m1'));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsOneWidget, reason: 're-shown once');

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_secondary_action')),
      );
      await tester.pumpAndSettle();
      h.now = h.now.add(const Duration(days: 400));
      h.container.invalidate(providerEmailCardDueProvider('m1'));
      await tester.pumpAndSettle();
      expect(find.byKey(cardKey), findsNothing, reason: 'then never');
    });

    // Audit LOW (item 3): the card hides at once, before the store write
    // completes — it must not linger for a keystore round trip.
    testWidgets('«Не зараз» hides it before the store write completes', (
      tester,
    ) async {
      final _GatedStore store = _GatedStore();
      final _H h = _H(_master, store: store);
      addTearDown(h.container.dispose);
      await _pump(tester, h, const ProviderEmailPromptCard());
      expect(find.byKey(cardKey), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_secondary_action')),
      );
      await tester.pump();
      expect(find.byKey(cardKey), findsNothing, reason: 'optimistic hide');
      expect(store.writes, 0, reason: 'the write is still in flight');

      store.gate.complete();
      await tester.pumpAndSettle();
      expect(store.writes, 1);
      expect(find.byKey(cardKey), findsNothing, reason: 'stays hidden');
      expect(tester.getSize(find.byType(ProviderEmailPromptCard)), Size.zero);
    });

    // Audit LOW (item 4): the async-arriving card is revealed by a size +
    // fade animation, not a one-frame jump.
    testWidgets('the card is revealed through an AnimatedSize', (tester) async {
      final _H h = _H(_master);
      addTearDown(h.container.dispose);
      await _pump(tester, h, const ProviderEmailPromptCard());
      expect(
        find.ancestor(
          of: find.byKey(cardKey),
          matching: find.byType(AnimatedSize),
        ),
        findsOneWidget,
      );
    });

    // CI fix: with animations disabled a zero-duration AnimatedSize threw
    // "A RenderAnimatedSize was mutated in its own performLayout" on any
    // relayout (reveal, hide, width change). Reduced motion must not throw.
    testWidgets('animations disabled: reveal, «Не зараз», resize — no throw', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.reset);

      final _H h = _H(_master);
      addTearDown(h.container.dispose);
      await _pump(tester, h, const ProviderEmailPromptCard());
      expect(tester.takeException(), isNull, reason: 'reveal');
      expect(find.byKey(cardKey), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_secondary_action')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'optimistic hide');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'hide settled');
      expect(find.byKey(cardKey), findsNothing);

      h.now = h.now.add(const Duration(days: 30));
      h.container.invalidate(providerEmailCardDueProvider('m1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 're-reveal');
      expect(find.byKey(cardKey), findsOneWidget);

      tester.view.physicalSize = const Size(414, 800);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width change');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width change settled');
      expect(find.byKey(cardKey), findsOneWidget);
    });

    testWidgets('«Додати» hides it and opens the email entry', (tester) async {
      final _H h = _H(_master);
      addTearDown(h.container.dispose);
      final GoRouter router = await _pump(
        tester,
        h,
        const ProviderEmailPromptCard(),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_action')),
      );
      await tester.pumpAndSettle();
      expect(AppHarness.location(router), RouteNames.notificationEmail);
      expect(h.store.writes, 1);
    });

    for (final (String name, User u) in <(String, User)>[
      ('a client', _client),
      ('a confirmed email', _master.copyWith(emailVerified: true)),
      ('an unknown email state', _master.copyWith(emailVerified: null)),
    ]) {
      testWidgets('zero-size for $name', (tester) async {
        final _H h = _H(u);
        addTearDown(h.container.dispose);
        await _pump(tester, h, const ProviderEmailPromptCard());
        expect(find.byKey(cardKey), findsNothing);
        expect(tester.getSize(find.byType(ProviderEmailPromptCard)), Size.zero);
      });
    }
  });
}
