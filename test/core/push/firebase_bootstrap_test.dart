import 'dart:async';

import 'package:beautica_mobile/core/push/firebase_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initFirebaseSafely', () {
    test('returns true when the initializer succeeds', () async {
      var called = false;
      final ok = await initFirebaseSafely(
        isAndroid: true,
        initializer: () async => called = true,
      );
      expect(ok, isTrue);
      expect(called, isTrue);
    });

    test(
      'returns false and does not throw when the initializer throws',
      () async {
        final ok = await initFirebaseSafely(
          isAndroid: true,
          initializer: () async => throw StateError('no Firebase App'),
        );
        expect(ok, isFalse);
      },
    );

    test('returns false without calling the initializer off Android', () async {
      var called = false;
      final ok = await initFirebaseSafely(
        isAndroid: false,
        initializer: () async => called = true,
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('returns false when the initializer exceeds the timeout', () async {
      final ok = await initFirebaseSafely(
        isAndroid: true,
        timeout: const Duration(milliseconds: 20),
        initializer: () => Completer<void>().future,
      );
      expect(ok, isFalse);
    });

    test('a slow-but-successful init within the guard returns true', () async {
      final ok = await initFirebaseSafely(
        isAndroid: true,
        timeout: const Duration(milliseconds: 500),
        initializer: () =>
            Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      expect(ok, isTrue);
    });

    test(
      'default hang guard is 30 seconds (generous, not a startup budget)',
      () {
        expect(kFirebaseInitTimeout, const Duration(seconds: 30));
      },
    );
  });
}
