// Phase 306 — Widget tests for RemoveMasterDialog + showRemoveMasterDialog.
//
// This dialog is copy + widget only in this phase (D2/D3 of the phase doc):
// no endpoint call, no call site anywhere in lib/ — phase 307 wires it up.
// The tests here cover only what this phase ships: the rendered chrome, the
// four-bullet body with the interpolated name, and the confirm/cancel/
// barrier-dismiss resolution contract shared with RemoveAdminDialog.
//
// Mirrors the shape of `delete_salon_dialog_test.dart`, but the dialog under
// test routes through the shared `_DialogShell` (private to
// admin_action_dialogs.dart) rather than a bare AlertDialog, so the chrome
// assertion below checks for exactly one NeumorphicCard ancestor instead.

import 'package:beautica_mobile/core/theme/app_theme.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/admin_action_dialogs.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _masterName = 'Олена Ковальчук';

/// Pumps a widget that opens [RemoveMasterDialog] via [showRemoveMasterDialog]
/// on button tap, then waits for it to appear. Returns the [Future<bool?>]
/// the dialog resolves to.
///
/// Applies the real app theme ([velvetTheme]) — `delete_salon_dialog_test
/// .dart` found the default Material3 theme silently clips long dialog
/// bodies that the real Nunito metrics do not.
Future<Future<bool?>> _pumpDialogTrigger(
  WidgetTester tester, {
  Locale locale = const Locale('uk'),
}) async {
  late final Future<bool?> dialogFuture;

  await tester.pumpWidget(
    MaterialApp(
      theme: velvetTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (BuildContext ctx) {
          return Scaffold(
            body: ElevatedButton(
              key: const Key('trigger'),
              onPressed: () {
                dialogFuture = showRemoveMasterDialog(ctx, _masterName);
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pumpAndSettle();

  return dialogFuture;
}

AppLocalizations _l10n(Locale locale) => lookupAppLocalizations(locale);

void main() {
  testWidgets(
    'renders the title, the four-bullet body with the master\'s name, and '
    'both buttons',
    (tester) async {
      await _pumpDialogTrigger(tester);

      final l10n = _l10n(const Locale('uk'));
      // Asserted on rendered `Text.data`, not on a constructor argument off
      // RemoveMasterDialog — a field read proves nothing about what painted.
      expect(find.text(l10n.removeMasterDialogTitle), findsOneWidget);
      expect(
        find.text(l10n.removeMasterDialogBody(_masterName)),
        findsOneWidget,
      );
      expect(find.text(l10n.removeMasterConfirmCta), findsOneWidget);
      expect(find.text(l10n.actionCancel), findsOneWidget);
    },
  );

  testWidgets('confirming resolves the future to true', (tester) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    await tester.tap(find.byKey(const Key('btn-confirm-remove-master')));
    await tester.pumpAndSettle();

    expect(await dialogFuture, isTrue);
  });

  testWidgets('cancelling resolves to false-or-null and the future completes', (
    tester,
  ) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    await tester.tap(find.byKey(const Key('btn-cancel-remove-master')));
    await tester.pumpAndSettle();

    // The shell's quiet cancel dismisses via `dismissOverlay(context)`
    // with no result argument, which resolves the future to `null` — the
    // same "back out is always safe" contract RemoveAdminDialog uses.
    expect(await dialogFuture, isNot(true));
  });

  testWidgets('tapping the barrier dismisses and resolves to null', (
    tester,
  ) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    // Tap well outside the centred dialog card to hit the modal barrier.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(await dialogFuture, isNull);
  });

  testWidgets('renders inside the shared _DialogShell chrome', (tester) async {
    await _pumpDialogTrigger(tester);

    // Exactly one NeumorphicCard ancestor above the title — proves this
    // dialog routes through the same shell RemoveAdminDialog uses, rather
    // than a forked chrome. A future fork of the shell would either add a
    // second NeumorphicCard or drop this one; either way this count moves.
    expect(find.byType(NeumorphicCard), findsOneWidget);

    final l10n = _l10n(const Locale('uk'));
    final Finder titleFinder = find.text(l10n.removeMasterDialogTitle);
    expect(
      find.ancestor(of: titleFinder, matching: find.byType(NeumorphicCard)),
      findsOneWidget,
      reason:
          'the title must be painted INSIDE the shared NeumorphicCard '
          'shell, not beside a second, forked chrome',
    );
  });
}
