// Phase 071 — image source sheet behaviour.

import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ValueNotifier<Object?>> _open(
  WidgetTester tester, {
  bool canRemove = false,
}) async {
  final ValueNotifier<Object?> result = ValueNotifier<Object?>('unset');
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('uk'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () async => result.value = await showImageSourceSheet(
                context,
                canRemove: canRemove,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('two rows by default, title shown', (WidgetTester tester) async {
    await _open(tester);
    expect(find.byKey(const Key('image-source-gallery')), findsOneWidget);
    expect(find.byKey(const Key('image-source-camera')), findsOneWidget);
    expect(find.byKey(const Key('image-source-remove')), findsNothing);
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('open'))),
    );
    expect(find.text(l10n.imageSourceTitle), findsOneWidget);
    expect(find.text(l10n.imageSourceGallery), findsOneWidget);
    expect(find.text(l10n.imageSourceCamera), findsOneWidget);
  });

  testWidgets('three rows with canRemove', (WidgetTester tester) async {
    await _open(tester, canRemove: true);
    expect(find.byKey(const Key('image-source-remove')), findsOneWidget);
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byKey(const Key('open'))),
        ).imageSourceRemove,
      ),
      findsOneWidget,
    );
  });

  for (final (String, ImageSourceChoice) c in <(String, ImageSourceChoice)>[
    ('image-source-gallery', ImageSourceChoice.gallery),
    ('image-source-camera', ImageSourceChoice.camera),
    ('image-source-remove', ImageSourceChoice.remove),
  ]) {
    testWidgets('tapping ${c.$1} pops ${c.$2}', (WidgetTester tester) async {
      final ValueNotifier<Object?> result = await _open(
        tester,
        canRemove: true,
      );
      await tester.tap(find.byKey(Key(c.$1)));
      await tester.pumpAndSettle();
      expect(result.value, c.$2);
      expect(find.byKey(const Key('image-source-gallery')), findsNothing);
    });
  }

  testWidgets('barrier tap -> null', (WidgetTester tester) async {
    final ValueNotifier<Object?> result = await _open(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
    expect(find.byKey(const Key('image-source-gallery')), findsNothing);
  });

  testWidgets('rows expose a semantics label equal to their text', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle h = tester.ensureSemantics();
    await _open(tester, canRemove: true);
    expect(find.bySemanticsLabel('Обрати з галереї'), findsOneWidget);
    expect(find.bySemanticsLabel('Зробити фото'), findsOneWidget);
    expect(find.bySemanticsLabel('Видалити фото'), findsOneWidget);
    h.dispose();
  });
}
