// Phase 413 — PlatformShareService delegates to share_plus (D6).

import 'package:beautica_mobile/core/share/share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';

class _MockSharePlus extends Mock implements SharePlus {}

void main() {
  late _MockSharePlus sharePlus;
  late PlatformShareService service;

  setUpAll(() => registerFallbackValue(ShareParams(text: 'fallback')));

  setUp(() {
    sharePlus = _MockSharePlus();
    service = PlatformShareService(sharePlus);
  });

  test('passes text + subject through to SharePlus.share', () async {
    when(() => sharePlus.share(any())).thenAnswer(
      (_) async => const ShareResult('x', ShareResultStatus.success),
    );

    final ShareOutcome out = await service.shareText(
      'https://beautica.app/book/anna',
      subject: 'Anna',
    );

    final ShareParams params =
        verify(() => sharePlus.share(captureAny())).captured.single
            as ShareParams;
    expect(params.text, 'https://beautica.app/book/anna');
    expect(params.subject, 'Anna');
    expect(params.files, isNull);
    expect(params.uri, isNull);
    expect(out, ShareOutcome.shared);
  });

  test('subject is optional', () async {
    when(
      () => sharePlus.share(any()),
    ).thenAnswer((_) async => ShareResult.unavailable);

    expect(await service.shareText('t'), ShareOutcome.unavailable);
    final ShareParams params =
        verify(() => sharePlus.share(captureAny())).captured.single
            as ShareParams;
    expect(params.subject, isNull);
  });

  test('dismissed sheet → ShareOutcome.dismissed', () async {
    when(() => sharePlus.share(any())).thenAnswer(
      (_) async => const ShareResult('', ShareResultStatus.dismissed),
    );

    expect(await service.shareText('t'), ShareOutcome.dismissed);
  });

  test('a platform failure → ShareOutcome.failed, never throws', () async {
    when(
      () => sharePlus.share(any()),
    ).thenAnswer((_) async => throw PlatformException(code: 'boom'));

    expect(await service.shareText('t'), ShareOutcome.failed);
  });
}
