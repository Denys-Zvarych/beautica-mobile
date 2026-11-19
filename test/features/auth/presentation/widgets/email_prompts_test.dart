// M517 (AUTH-D17, CLI-D09) — the «Email для сповіщень» prompts:
//
//   (a) NotificationEmailSettingsRow: «Додати» until an email is confirmed,
//       then the address, ellipsized; tap opens the email entry.
//   (b) claimClientEmailPrompt: CLIENT with an explicitly unconfirmed email,
//       once ever (claimed on first show); never a provider / unknown state.
//
// The provider home card (former (c)) was removed 2026-11-19.

import 'package:beautica_mobile/core/diagnostics/crash_reporting_enabled_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/email_prompts.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      ],
    );
  }

  final FakeDiagnosticsStore store;
  late final ProviderContainer container;
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

  group('(a) row geometry matches a neighbouring SettingsRow', () {
    const Key neighbourKey = Key('row-neighbour');

    Widget column() => Column(
      children: <Widget>[
        SettingsRow(
          key: neighbourKey,
          icon: Icons.language,
          label: 'Language',
          value: 'Ukrainian',
          onTap: () {},
        ),
        const SizedBox(height: 12),
        const NotificationEmailSettingsRow(),
      ],
    );

    for (final (String name, User u) in <(String, User)>[
      ('client, no email', _client),
      ('independent master, no email', _master),
      ('salon master, no email', _master.copyWith(role: UserRole.salonMaster)),
      ('owner, no email', _master.copyWith(role: UserRole.salonOwner)),
      (
        'master, long confirmed email',
        _master.copyWith(
          email: 'olena.kovalenko.beauty.studio@gmail.com',
          emailVerified: true,
        ),
      ),
    ]) {
      testWidgets('$name: same height, value + chevron right-aligned', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 800);
        addTearDown(tester.view.reset);
        final _H h = _H(u);
        addTearDown(h.container.dispose);
        await _pump(tester, h, column());

        expect(find.byKey(rowKey), findsOneWidget);
        expect(
          tester.widget(find.byKey(rowKey)),
          isA<SettingsRow>(),
          reason: 'the shared row widget, never a bespoke card',
        );
        expect(
          tester.getSize(find.byKey(rowKey)),
          tester.getSize(find.byKey(neighbourKey)),
        );

        Finder chevronIn(Key k) => find.descendant(
          of: find.byKey(k),
          matching: find.byIcon(Icons.chevron_right_rounded),
        );
        expect(
          tester.getTopRight(chevronIn(rowKey)).dx,
          tester.getTopRight(chevronIn(neighbourKey)).dx,
          reason: 'chevron at the far right like every row',
        );
        final String value = tester
            .widget<SettingsRow>(find.byKey(rowKey))
            .value!;
        final Finder valueText = find.descendant(
          of: find.byKey(rowKey),
          matching: find.text(value),
        );
        expect(
          tester.getRect(valueText).right,
          moreOrLessEquals(
            tester
                .getRect(
                  find.descendant(
                    of: find.byKey(neighbourKey),
                    matching: find.text('Ukrainian'),
                  ),
                )
                .right,
          ),
          reason: 'trailing value aligned like the neighbour',
        );
        expect(tester.takeException(), isNull, reason: 'no overflow');
      });
    }
  });

  group('(a) long label at textScaler 1.3 (main.dart cap) never overflows', () {
    const Key scaledKey = Key('row-scaled');
    for (final String lang in <String>['uk', 'en']) {
      for (final double width in <double>[320, 360]) {
        for (final String value in <String>[
          'Додати',
          'olena.kovalenko.beauty.studio@gmail.com',
        ]) {
          testWidgets('$lang @ ${width.toInt()} dp, value «$value»', (
            tester,
          ) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 800);
            addTearDown(tester.view.reset);
            final AppLocalizations t = lookupAppLocalizations(Locale(lang));
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(lang),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (BuildContext context, Widget? child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SettingsRow(
                      key: scaledKey,
                      icon: Icons.mail_outline,
                      label: t.profileNotificationEmailTitle,
                      value: value,
                      ellipsizeValue: true,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull, reason: 'no overflow');
            final Finder labelText = find.descendant(
              of: find.byKey(scaledKey),
              matching: find.text(t.profileNotificationEmailTitle),
            );
            final Finder valueText = find.descendant(
              of: find.byKey(scaledKey),
              matching: find.text(value),
            );
            expect(
              tester.getRect(labelText).right,
              lessThan(tester.getRect(valueText).left),
              reason: 'label and value never overlap',
            );
            expect(
              tester.getSize(valueText).width,
              greaterThanOrEqualTo(
                (tester.getRect(valueText).right -
                        tester.getRect(labelText).right) *
                    0.5,
              ),
              reason: 'value keeps a real share of the row, not «Д…»',
            );
            if (value == 'Додати') {
              expect(
                tester
                    .renderObject<RenderParagraph>(valueText)
                    .didExceedMaxLines,
                isFalse,
                reason: 'short value renders in full, never «Додат…»',
              );
            }
          });
        }
      }
    }
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
}
