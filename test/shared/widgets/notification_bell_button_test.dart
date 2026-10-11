// Phase 361 — NotificationBellButton (pure) + ConnectedNotificationBell.

import 'dart:async';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('uk'),
  home: Scaffold(body: Center(child: child)),
);

String _asset(WidgetTester tester) => tester
    .widget<AppIcon>(find.byKey(NotificationBellButton.bellIconKey))
    .asset;

class _Unread extends UnreadNotifications {
  _Unread(this._count);
  final int _count;

  @override
  FutureOr<int> build() => _count;
}

Widget _connectedApp(int count) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: Center(child: ConnectedNotificationBell(buttonKey: Key('b'))),
        ),
      ),
      GoRoute(
        path: RouteNames.notifications,
        builder: (context, state) => const Scaffold(key: Key('feed-marker')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [unreadNotificationsProvider.overrideWith(() => _Unread(count))],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
    ),
  );
}

void main() {
  group('NotificationBellButton', () {
    testWidgets('idle renders the plain (dotless) asset', (tester) async {
      await tester.pumpWidget(
        _host(NotificationBellButton(onTap: () {}, semanticLabel: 'x')),
      );
      expect(_asset(tester), BeauticaAssetIcons.notificationPlain);
    });

    testWidgets('hasUnread renders the unread (dotted) asset', (tester) async {
      await tester.pumpWidget(
        _host(
          NotificationBellButton(
            onTap: () {},
            semanticLabel: 'x',
            hasUnread: true,
          ),
        ),
      );
      expect(_asset(tester), BeauticaAssetIcons.notificationUnread);
    });

    testWidgets('announces its label with the button role', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          NotificationBellButton(
            key: const Key('bell'),
            onTap: () {},
            semanticLabel: 'Сповіщення',
          ),
        ),
      );
      final data = tester
          .getSemantics(find.byKey(const Key('bell')))
          .getSemanticsData();
      expect(data.label, 'Сповіщення');
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('tap fires onTap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _host(
          NotificationBellButton(
            key: const Key('bell'),
            onTap: () => taps++,
            semanticLabel: 'x',
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('bell')));
      expect(taps, 1);
    });
  });

  group('ConnectedNotificationBell', () {
    testWidgets('unread > 0 shows the dot and the unread label', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_connectedApp(2));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(_asset(tester), BeauticaAssetIcons.notificationUnread);
      expect(
        tester
            .getSemantics(find.byKey(const Key('b')))
            .getSemanticsData()
            .label,
        l10n.notificationBellUnreadLabel,
      );
      handle.dispose();
    });

    testWidgets('unread == 0 shows the plain bell and the plain label', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_connectedApp(0));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(_asset(tester), BeauticaAssetIcons.notificationPlain);
      expect(
        tester
            .getSemantics(find.byKey(const Key('b')))
            .getSemanticsData()
            .label,
        l10n.notificationBellLabel,
      );
      handle.dispose();
    });

    testWidgets('tap pushes the notifications route', (tester) async {
      await tester.pumpWidget(_connectedApp(0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('b')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feed-marker')), findsOneWidget);
    });
  });
}
