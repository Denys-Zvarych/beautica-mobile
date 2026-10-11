// Phase 071 QA — sheet -> service -> file, headless via the injectable gateway.
// (The real avatar flow lands in phase 073; this is the seam it will use.)

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scripted_pick_gateway.dart';

class _Harness {
  _Harness(this.gw, this.service);
  final ScriptedPickGateway gw;
  final MediaPickService service;
  PickedImage? picked;
  ImageSourceChoice? choice;
}

Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
  bool canRemove = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imagePickGatewayProvider.overrideWithValue(h.gw),
        mediaPickServiceProvider.overrideWithValue(h.service),
      ],
      child: MaterialApp(
        locale: const Locale('uk'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext c, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () async {
                  h.choice = await showImageSourceSheet(
                    context,
                    canRemove: canRemove,
                  );
                  final MediaPickSource? source = switch (h.choice) {
                    ImageSourceChoice.gallery => MediaPickSource.gallery,
                    ImageSourceChoice.camera => MediaPickSource.camera,
                    _ => null,
                  };
                  if (source != null) {
                    h.picked = await ref
                        .read(mediaPickServiceProvider)
                        .pick(MediaKind.avatar, source);
                  }
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

/// Real file IO completes on the real event loop; the awaiting continuations
/// live in the fake-async zone. Alternate the two until [until] holds.
Future<void> _drainIo(
  WidgetTester tester, {
  required bool Function() until,
}) async {
  for (var i = 0; i < 50 && !until(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  late Directory scratch;
  late Directory outside;
  late _Harness h;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('flow_scratch');
    outside = Directory.systemTemp.createTempSync('flow_gallery');
    final ScriptedPickGateway gw = ScriptedPickGateway(
      scratch: scratch,
      outside: outside,
    );
    h = _Harness(gw, MediaPickService(gw, tempDir: () async => scratch));
  });
  tearDown(() {
    scratch.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  for (final (String, MediaPickSource) c in <(String, MediaPickSource)>[
    ('image-source-gallery', MediaPickSource.gallery),
    ('image-source-camera', MediaPickSource.camera),
  ]) {
    testWidgets('${c.$1} -> service picks from ${c.$2} -> stripped JPEG file', (
      WidgetTester tester,
    ) async {
      await _pump(tester, h);

      await tester.tap(find.byKey(Key(c.$1)));
      await tester.pump();
      await _drainIo(tester, until: () => h.picked != null);

      expect(h.gw.pickSources, <MediaPickSource>[c.$2]);
      expect(h.picked, isNotNull);
      expect(h.picked!.file.existsSync(), isTrue);
      expect(h.picked!.file.path.endsWith('.jpg'), isTrue);
      expect(h.gw.compressCalls.single.keepExif, isFalse);
    });
  }

  testWidgets('remove choice never reaches the picker', (
    WidgetTester tester,
  ) async {
    await _pump(tester, h, canRemove: true);
    await tester.tap(find.byKey(const Key('image-source-remove')));
    await tester.pumpAndSettle();

    expect(h.choice, ImageSourceChoice.remove);
    expect(h.gw.pickSources, isEmpty);
    expect(h.picked, isNull);
  });

  testWidgets('user cancels the native picker -> sheet closed, no file', (
    WidgetTester tester,
  ) async {
    h.gw.cancelPick = true;
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('image-source-gallery')));
    await tester.pump();
    await _drainIo(tester, until: () => h.gw.pickSources.isNotEmpty);
    await tester.pumpAndSettle();

    expect(h.picked, isNull);
    expect(h.gw.compressCalls, isEmpty);
    expect(find.byKey(const Key('image-source-gallery')), findsNothing);
  });

  testWidgets('text scale 2.0 on a small phone: no overflow, rows tappable', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, h, canRemove: true, textScale: 2);

    expect(tester.takeException(), isNull);
    for (final String k in <String>[
      'image-source-gallery',
      'image-source-camera',
      'image-source-remove',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget);
      expect(
        tester.getRect(find.byKey(Key(k))).height,
        greaterThanOrEqualTo(48),
        reason: '$k must keep a >=48dp touch target',
      );
    }
    await tester.tap(find.byKey(const Key('image-source-remove')));
    await tester.pumpAndSettle();
    expect(h.choice, ImageSourceChoice.remove);
  });
}
