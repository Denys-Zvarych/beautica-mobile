// Phase 069 (audit L1) — the tray clearer is a no-op off Android and never
// throws, even when the native channel fails.

import 'package:beautica_mobile/core/push/notification_tray_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _ch = MethodChannel(
  'com.beautica.beautica_mobile/notification_tray',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, null);
  });

  test('is a no-op off Android (channel never called)', () async {
    int calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (_) async {
          calls++;
          return null;
        });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(notificationTrayClearerProvider)();
    expect(calls, 0);
  });

  test('invokes cancelAll on Android', () async {
    final List<String> methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (MethodCall m) async {
          methods.add(m.method);
          return null;
        });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(notificationTrayClearerProvider)();
    expect(methods, <String>['cancelAll']);
  });

  test('never throws when the channel fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (_) async {
          throw PlatformException(code: 'tray');
        });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await expectLater(c.read(notificationTrayClearerProvider)(), completes);
  });
}
