// M544 — the client actions sheet's additive «Прибрати зі списку» item:
// shown only with `canRemove`, picked as [ClientAction.remove], and the
// existing items unchanged without it.

import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const Key _openKey = Key('open-client-actions');

Future<List<ClientAction?>> _pump(
  WidgetTester tester, {
  bool canReport = true,
  bool canBlock = true,
  bool canRemove = false,
}) async {
  final List<ClientAction?> picked = <ClientAction?>[];
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (BuildContext context) => TextButton(
          key: _openKey,
          onPressed: () async => picked.add(
            await showClientActionsSheet(
              context,
              name: 'Оксана',
              canReport: canReport,
              canBlock: canBlock,
              canRemove: canRemove,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_openKey));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('without canRemove: the existing items only', (tester) async {
    await _pump(tester);
    expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.blockKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.removeKey), findsNothing);
  });

  testWidgets('canRemove adds «Прибрати зі списку» last and picks remove', (
    tester,
  ) async {
    final List<ClientAction?> picked = await _pump(tester, canRemove: true);
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(ClientActionsSheet)),
    );
    expect(find.byKey(ClientActionsSheet.reportKey), findsOneWidget);
    expect(find.byKey(ClientActionsSheet.blockKey), findsOneWidget);
    expect(find.text(l10n.clientsRemoveAction), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(ClientActionsSheet.removeKey)).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(ClientActionsSheet.blockKey)).dy,
      ),
    );
    await tester.tap(find.byKey(ClientActionsSheet.removeKey));
    await tester.pumpAndSettle();
    expect(picked, <ClientAction?>[ClientAction.remove]);
  });

  testWidgets('remove only (a salon master on a guest card)', (tester) async {
    await _pump(tester, canReport: false, canBlock: false, canRemove: true);
    expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
    expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
    expect(find.byKey(ClientActionsSheet.removeKey), findsOneWidget);
  });
}
