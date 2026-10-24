// Phase 413 — PlatformClipboardService writes through Clipboard.setData (D6).

import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];

  void handle(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, handler);
  }

  setUp(calls.clear);
  tearDown(() => handle((_) => null));

  test('copies the exact text via Clipboard.setData', () async {
    handle((MethodCall call) async {
      calls.add(call);
      return null;
    });

    final bool ok = await const PlatformClipboardService().copyText(
      'https://beautica.app/book/anna?s=c',
    );

    expect(ok, isTrue);
    final MethodCall call = calls.singleWhere(
      (MethodCall c) => c.method == 'Clipboard.setData',
    );
    expect(call.arguments, <String, dynamic>{
      'text': 'https://beautica.app/book/anna?s=c',
    });
  });

  test('a platform failure → false, never throws', () async {
    handle((MethodCall call) async {
      throw PlatformException(code: 'denied');
    });

    expect(await const PlatformClipboardService().copyText('x'), isFalse);
  });
}
