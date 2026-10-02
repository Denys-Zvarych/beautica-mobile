// Phase 361 audit fix (perf P2) — the unread flag flip must rebuild the BELL
// only, never the top bar or its burger.
//
// `ClientTopBar.bell` takes a self-watching `ConnectedNotificationBell`; the
// flag is watched inside it. `debugOnRebuildDirtyWidget` records every element
// rebuilt by the pump that follows the flip.

import 'dart:async';

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../../../helpers/test_container.dart';

class _ControllableUnread extends UnreadNotifications {
  @override
  FutureOr<int> build() => 0;

  void set(int n) => state = AsyncData<int>(n);
}

void main() {
  testWidgets('should_rebuildBellOnly_when_unreadFlagFlips', (tester) async {
    final container = makeTestContainer(
      overrides: <Object>[
        unreadNotificationsProvider.overrideWith(_ControllableUnread.new),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ClientTopBar(
              key: const Key('bar'),
              onBell: () {},
              bellSemanticLabel: 'bell',
              onBurger: () {},
              burgerSemanticLabel: 'burger',
              burgerKey: const Key('burger'),
              bell: const ConnectedNotificationBell(buttonKey: Key('bell')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('burger')), findsOneWidget);

    final Set<Type> rebuilt = <Type>{};
    final oldHook = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (Element e, bool builtOnce) =>
        rebuilt.add(e.widget.runtimeType);
    addTearDown(() => debugOnRebuildDirtyWidget = oldHook);

    (container.read(unreadNotificationsProvider.notifier)
            as _ControllableUnread)
        .set(3);
    await tester.pump();

    expect(rebuilt, contains(NotificationBellButton));
    expect(rebuilt, isNot(contains(ClientTopBar)));
    expect(rebuilt, isNot(contains(NeumorphicIconButton)));
  });
}
