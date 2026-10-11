// Phase 072 QA — state TRANSITIONS on ONE widget instance, retry-callback
// cardinality, semantics, default-path invariance and LocalPreviewImage
// fallback. Complements photo_upload_states_test.dart (single-state renders).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/local_preview_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/upload_state_overlay.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_photo_slot.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';

const String _host = 'media.test';
const Key _retry = Key('upload-retry');
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

/// Immutable snapshot of the slot's upload inputs, driven through a notifier so
/// the SAME element/State is rebuilt (no fresh widget per pump).
class _Slot {
  const _Slot({this.url, this.progress, this.failed = false, this.retry});
  final String? url;
  final double? progress;
  final bool failed;
  final VoidCallback? retry;
}

Widget _slotHarness(ValueNotifier<_Slot> n, {VoidCallback? onTap}) =>
    ValueListenableBuilder<_Slot>(
      valueListenable: n,
      builder: (_, s, _) => SizedBox(
        width: 280,
        child: ServicePhotoSlot(
          imageUrl: s.url,
          onTap: onTap ?? () {},
          uploadProgress: s.progress,
          uploadFailed: s.failed,
          onRetry: s.retry,
        ),
      ),
    );

class _Av {
  const _Av({
    this.state = AvatarEditState.loaded,
    this.url,
    this.progress,
    this.failed = false,
    this.retry,
  });
  final AvatarEditState state;
  final String? url;
  final double? progress;
  final bool failed;
  final VoidCallback? retry;
}

Widget _avatarHarness(ValueNotifier<_Av> n) => ValueListenableBuilder<_Av>(
  valueListenable: n,
  builder: (_, a, _) => NeumorphicAvatarEditor(
    state: a.state,
    initials: 'ДЗ',
    onTap: () {},
    imageUrl: a.url,
    progress: a.progress,
    uploadFailed: a.failed,
    onRetry: a.retry,
  ),
);

Finder get _ringFinder => find.byType(CircularProgressIndicator);
double? _ringValue(WidgetTester t) =>
    t.widget<CircularProgressIndicator>(_ringFinder).value;

String? _remoteUrl(WidgetTester t) =>
    t.widget<RemoteImage>(find.byType(RemoteImage)).url;

void main() {
  late FakeMediaCacheManager fake;

  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{_host};
    fake = FakeMediaCacheManager(mediaLoadingForever);
    debugMediaCacheManager = fake;
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });

  group('ServicePhotoSlot — one instance through the full lifecycle', () {
    testWidgets('idle -> 0.3 -> 1.0 (not done) -> failed -> retry -> '
        'uploading -> idle with new image', (tester) async {
      int retries = 0;
      int taps = 0;
      final ValueNotifier<_Slot> n = ValueNotifier<_Slot>(
        const _Slot(url: 'https://$_host/old.png'),
      );
      addTearDown(n.dispose);
      await tester.pumpApp(_slotHarness(n, onTap: () => taps++));
      await tester.pump();

      // idle: chip visible, no veil/ring/retry, old image bound.
      expect(find.text(_l10n.servicePhotoChange), findsOneWidget);
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(find.byType(UploadFailedOverlay), findsNothing);
      expect(_remoteUrl(tester), 'https://$_host/old.png');
      final Element before = tester.element(find.byType(ServicePhotoSlot));

      // uploading 0.3: determinate ring, chip gone.
      n.value = const _Slot(url: 'https://$_host/old.png', progress: 0.3);
      await tester.pump();
      expect(find.byType(UploadProgressOverlay), findsOneWidget);
      expect(_ringValue(tester), 0.3);
      expect(find.text(_l10n.servicePhotoChange), findsNothing);

      // 1.0: must NOT read as done -> indeterminate ring, overlay still there.
      n.value = const _Slot(url: 'https://$_host/old.png', progress: 1.0);
      await tester.pump();
      expect(find.byType(UploadProgressOverlay), findsOneWidget);
      expect(_ringValue(tester), isNull);

      // failed: overlay swapped, ring gone, retry present.
      n.value = _Slot(
        url: 'https://$_host/old.png',
        failed: true,
        retry: () => retries++,
      );
      await tester.pump();
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(_ringFinder, findsNothing);
      expect(find.byKey(_retry), findsOneWidget);

      // retry tapped -> callback once; owner flips back to uploading.
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(retries, 1);
      n.value = const _Slot(url: 'https://$_host/old.png', progress: 0.0);
      await tester.pump();
      expect(find.byKey(_retry), findsNothing);
      expect(_ringValue(tester), 0.0);

      // done: owner stops passing progress and hands over the NEW url.
      n.value = const _Slot(url: 'https://$_host/new.png');
      await tester.pump();
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(_ringFinder, findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(_remoteUrl(tester), 'https://$_host/new.png');
      expect(find.text(_l10n.servicePhotoChange), findsOneWidget);

      // Same Element survived the whole sequence (no remount) and taps work
      // again once idle.
      expect(tester.element(find.byType(ServicePhotoSlot)), same(before));
      await tester.tap(find.byType(ServicePhotoSlot));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('retry fires exactly once per tap (2 taps -> 2 calls)', (
      tester,
    ) async {
      int retries = 0;
      final ValueNotifier<_Slot> n = ValueNotifier<_Slot>(
        _Slot(failed: true, retry: () => retries++),
      );
      addTearDown(n.dispose);
      await tester.pumpApp(_slotHarness(n));
      await tester.pump();

      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(retries, 1);
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(retries, 2);
    });

    testWidgets('no retry while uploading, even if failed+onRetry are also '
        'passed (progress wins)', (tester) async {
      int retries = 0;
      int taps = 0;
      final ValueNotifier<_Slot> n = ValueNotifier<_Slot>(
        _Slot(progress: 0.5, failed: true, retry: () => retries++),
      );
      addTearDown(n.dispose);
      await tester.pumpApp(_slotHarness(n, onTap: () => taps++));
      await tester.pump();

      expect(find.byKey(_retry), findsNothing);
      await tester.tap(find.byType(ServicePhotoSlot), warnIfMissed: false);
      await tester.pump();
      expect(retries, 0);
      expect(taps, 0);
    });

    testWidgets('failed retry target does not trigger the slot onTap', (
      tester,
    ) async {
      int taps = 0;
      int retries = 0;
      final ValueNotifier<_Slot> n = ValueNotifier<_Slot>(
        _Slot(failed: true, retry: () => retries++),
      );
      addTearDown(n.dispose);
      await tester.pumpApp(_slotHarness(n, onTap: () => taps++));
      await tester.pump();
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(retries, 1);
      expect(taps, 0);
    });
  });

  group('NeumorphicAvatarEditor — one instance through the lifecycle', () {
    testWidgets('loaded -> picking 0.3 -> 1.0 -> failed -> retry -> picking '
        '-> loaded with new url', (tester) async {
      int retries = 0;
      final ValueNotifier<_Av> n = ValueNotifier<_Av>(
        const _Av(url: 'https://$_host/a.png'),
      );
      addTearDown(n.dispose);
      await tester.pumpApp(_avatarHarness(n));
      await tester.pump();
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(_remoteUrl(tester), 'https://$_host/a.png');

      n.value = const _Av(
        state: AvatarEditState.picking,
        url: 'https://$_host/a.png',
        progress: 0.3,
      );
      await tester.pump();
      expect(_ringValue(tester), 0.3);

      n.value = const _Av(
        state: AvatarEditState.picking,
        url: 'https://$_host/a.png',
        progress: 1.0,
      );
      await tester.pump();
      expect(_ringValue(tester), isNull);
      expect(find.byType(UploadProgressOverlay), findsOneWidget);

      n.value = _Av(
        url: 'https://$_host/a.png',
        failed: true,
        retry: () => retries++,
      );
      await tester.pump();
      expect(_ringFinder, findsNothing);
      await tester.tap(find.byKey(_retry));
      await tester.pump();
      expect(retries, 1);

      n.value = const _Av(
        state: AvatarEditState.picking,
        url: 'https://$_host/a.png',
        progress: 0.0,
      );
      await tester.pump();
      expect(find.byKey(_retry), findsNothing);
      expect(_ringValue(tester), 0.0);

      n.value = const _Av(url: 'https://$_host/b.png');
      await tester.pump();
      expect(find.byType(UploadProgressOverlay), findsNothing);
      expect(find.byKey(_retry), findsNothing);
      expect(_remoteUrl(tester), 'https://$_host/b.png');
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking + uploadFailed: no retry target (ignored while '
        'picking)', (tester) async {
      int retries = 0;
      await tester.pumpApp(
        NeumorphicAvatarEditor(
          state: AvatarEditState.picking,
          initials: 'ДЗ',
          onTap: () {},
          progress: 0.2,
          uploadFailed: true,
          onRetry: () => retries++,
        ),
      );
      await tester.pump();
      expect(find.byKey(_retry), findsNothing);
      expect(retries, 0);
    });
  });

  group('semantics', () {
    final String retryLabel = '${_l10n.photoUploadFailed}. ${_l10n.retryLabel}';

    testWidgets('failed slot: retry exposed as a labelled enabled button', (
      tester,
    ) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpApp(
        SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            imageUrl: 'https://$_host/p.png',
            onTap: () {},
            uploadFailed: true,
            onRetry: () {},
          ),
        ),
      );
      await tester.pump();

      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(RegExp(RegExp.escape(retryLabel))),
      );
      final SemanticsData d = node.getSemanticsData();
      expect(d.label, contains(retryLabel));
      expect(d.flagsCollection.isButton, isTrue);
      expect(d.flagsCollection.isEnabled, ui.Tristate.isTrue);
      h.dispose();
    });

    testWidgets('failed with null onRetry: retry button reads as disabled', (
      tester,
    ) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpApp(
        const SizedBox(width: 280, child: ServicePhotoSlot(uploadFailed: true)),
      );
      await tester.pump();
      final SemanticsData d = tester
          .getSemantics(
            find.bySemanticsLabel(RegExp(RegExp.escape(retryLabel))),
          )
          .getSemanticsData();
      expect(d.flagsCollection.isEnabled, ui.Tristate.isFalse);
      h.dispose();
    });

    testWidgets('failed avatar: retry labelled in semantics (message is '
        'semantics-only on the disc)', (tester) async {
      final SemanticsHandle h = tester.ensureSemantics();
      await tester.pumpApp(
        NeumorphicAvatarEditor(
          state: AvatarEditState.loaded,
          initials: 'ДЗ',
          onTap: () {},
          uploadFailed: true,
          onRetry: () {},
        ),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(retryLabel))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('upload-failed-message')), findsNothing);
      h.dispose();
    });

    testWidgets('slot progress value is announced and capped at 99', (
      tester,
    ) async {
      final SemanticsHandle h = tester.ensureSemantics();
      final ValueNotifier<_Slot> n = ValueNotifier<_Slot>(
        const _Slot(progress: 0.3),
      );
      addTearDown(n.dispose);
      await tester.pumpApp(_slotHarness(n));
      await tester.pump();
      String? v() => tester
          .getSemantics(find.byType(ServicePhotoSlot))
          .getSemanticsData()
          .value;
      expect(v(), '30%');
      n.value = const _Slot(progress: 1.0);
      await tester.pump();
      expect(v(), '99%');
      n.value = const _Slot(progress: 0.999);
      await tester.pump();
      expect(v(), '99%');
      n.value = const _Slot();
      await tester.pump();
      expect(v(), isEmpty);
      h.dispose();
    });

    testWidgets('images are excluded from semantics (slot + avatar)', (
      tester,
    ) async {
      await tester.pumpApp(
        Column(
          children: <Widget>[
            SizedBox(
              width: 280,
              child: ServicePhotoSlot(
                imageUrl: 'https://$_host/p.png',
                onTap: () {},
              ),
            ),
            NeumorphicAvatarEditor(
              state: AvatarEditState.loaded,
              initials: 'ДЗ',
              onTap: () {},
              imageUrl: 'https://$_host/p.png',
            ),
          ],
        ),
      );
      await tester.pump();
      final Iterable<RemoteImage> imgs = tester.widgetList<RemoteImage>(
        find.byType(RemoteImage),
      );
      expect(imgs, hasLength(2));
      for (final RemoteImage i in imgs) {
        expect(i.excludeFromSemantics, isTrue);
      }
    });

    testWidgets('LocalPreviewImage excludes its Image from semantics', (
      tester,
    ) async {
      await tester.pumpApp(
        LocalPreviewImage(
          file: File('/tmp/media_upload/x.jpg'),
          width: 40,
          height: 40,
          fallback: const SizedBox.shrink(),
        ),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).excludeFromSemantics,
        isTrue,
      );
    });

    for (final double scale in <double>[1.0, 2.0]) {
      testWidgets('retry target >= 48dp at text scale $scale (slot + '
          'avatar)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpApp(
          Column(
            children: <Widget>[
              SizedBox(
                width: 280,
                child: ServicePhotoSlot(
                  imageUrl: 'https://$_host/p.png',
                  onTap: () {},
                  uploadFailed: true,
                  onRetry: () {},
                ),
              ),
              NeumorphicAvatarEditor(
                state: AvatarEditState.loaded,
                initials: 'ДЗ',
                onTap: () {},
                uploadFailed: true,
                onRetry: () {},
              ),
            ],
          ),
        );
        await tester.pump();
        final Iterable<Element> targets = find.byKey(_retry).evaluate();
        expect(targets, hasLength(2));
        for (final Element e in targets) {
          final Size s = (e.renderObject! as RenderBox).size;
          expect(s.width, greaterThanOrEqualTo(48));
          expect(s.height, greaterThanOrEqualTo(48));
        }
      });
    }
  });

  group('default-path invariance (callers passing nothing)', () {
    testWidgets('ServicePhotoSlot() empty: no veil, ring, retry or '
        'RemoteImage/Local image, no LayoutBuilder under it', (tester) async {
      await tester.pumpApp(
        SizedBox(width: 280, child: ServicePhotoSlot(onTap: () {})),
      );
      await tester.pump();
      _expectNoUploadArtifacts(tester);
      expect(find.byType(RemoteImage), findsNothing);
      expect(find.byType(LocalPreviewImage), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ServicePhotoSlot),
          matching: find.byType(LayoutBuilder),
        ),
        findsNothing,
      );
      expect(find.text(_l10n.servicePhotoAddSemantics), findsNothing);
    });

    testWidgets('NeumorphicAvatarEditor default (pristine/loaded/picking '
        'no-progress): no retry, no photo layers; ring only when picking', (
      tester,
    ) async {
      for (final AvatarEditState s in AvatarEditState.values) {
        await tester.pumpApp(
          NeumorphicAvatarEditor(state: s, initials: 'ДЗ', onTap: () {}),
        );
        await tester.pump();
        expect(find.byKey(_retry), findsNothing, reason: '$s');
        expect(find.byType(UploadFailedOverlay), findsNothing, reason: '$s');
        expect(find.byType(RemoteImage), findsNothing, reason: '$s');
        expect(find.byType(LocalPreviewImage), findsNothing, reason: '$s');
        if (s == AvatarEditState.picking) {
          expect(_ringValue(tester), isNull);
        } else {
          expect(find.byType(UploadProgressOverlay), findsNothing);
          expect(_ringFinder, findsNothing);
        }
      }
    });

    testWidgets('filled slot without upload state: image bound, still no '
        'overlay / ring / retry', (tester) async {
      await tester.pumpApp(
        SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            imageUrl: 'https://$_host/p.png',
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      _expectNoUploadArtifacts(tester);
      expect(find.byType(RemoteImage), findsOneWidget);
    });
  });

  group('LocalPreviewImage with a missing file', () {
    testWidgets('falls back, does not throw, no network call', (tester) async {
      const Key fb = Key('fallback');
      await tester.pumpApp(
        LocalPreviewImage(
          file: File('/tmp/media_upload/not-here.jpg'),
          width: 96,
          height: 96,
          fallback: const SizedBox(key: fb, width: 96, height: 96),
        ),
      );
      // File read fails off the fake-async clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(fb), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(fake.getFileStreamCalls, 0);
    });

    testWidgets('slot with a missing previewFile keeps the gradient base and '
        'throws nothing', (tester) async {
      await tester.pumpApp(
        SizedBox(
          width: 280,
          child: ServicePhotoSlot(
            previewFile: File('/tmp/media_upload/not-here.jpg'),
            onTap: () {},
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(LocalPreviewImage), findsOneWidget);
      expect(find.byType(ServicePhotoSlot), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(fake.getFileStreamCalls, 0);
    });
  });
}

void _expectNoUploadArtifacts(WidgetTester tester) {
  expect(find.byType(UploadProgressOverlay), findsNothing);
  expect(find.byType(UploadFailedOverlay), findsNothing);
  expect(find.byType(UploadProgressSpinner), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byKey(_retry), findsNothing);
  expect(find.byKey(const Key('upload-failed-message')), findsNothing);
}
