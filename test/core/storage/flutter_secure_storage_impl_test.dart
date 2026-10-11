// MEDIUM-1 remediation — tests for the PRODUCTION FlutterSecureStorageImpl.
//
// secure_storage_test.dart only covers the in-memory FakeSecureStorage. The
// production impl's key→method mapping (readRefreshToken → StorageKeys.refreshToken,
// writeUserJson → StorageKeys.userJson, deleteAll, etc.) and its iOS
// accessibility option were untested — a swapped key or wrong accessibility
// option would have shipped green.
//
// Strategy: mock the flutter_secure_storage platform channel
// (`plugins.it_nomads.com/flutter_secure_storage`) and assert each method
// invokes read/write/delete with the exact StorageKeys constant. Accessibility
// is verified by forcing the iOS target platform so the iOS options surface in
// the channel `options` map (the option only appears for the iOS platform).

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  // Captured method calls in invocation order.
  late List<MethodCall> calls;
  // Backing store the mock handler reads from (so read can return values).
  late Map<String, String> store;

  void installHandler() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          switch (call.method) {
            case 'read':
              return store[args['key'] as String];
            case 'write':
              store[args['key'] as String] = args['value'] as String;
              return null;
            case 'delete':
              store.remove(args['key'] as String);
              return null;
            case 'deleteAll':
              store.clear();
              return null;
            case 'containsKey':
              return store.containsKey(args['key'] as String);
            case 'readAll':
              return Map<String, String>.from(store);
            default:
              return null;
          }
        });
  }

  setUp(() {
    calls = [];
    store = {};
    installHandler();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Returns the args map of the single captured call for [method].
  Map<String, dynamic> argsOf(String method) {
    final call = calls.firstWhere((c) => c.method == method);
    return (call.arguments as Map).cast<String, dynamic>();
  }

  group('FlutterSecureStorageImpl key → channel mapping', () {
    test('readRefreshToken reads StorageKeys.refreshToken', () async {
      store[StorageKeys.refreshToken] = 'rt-stored';
      final storage = FlutterSecureStorageImpl();

      final value = await storage.readRefreshToken();

      expect(value, 'rt-stored');
      expect(argsOf('read')['key'], StorageKeys.refreshToken);
    });

    test(
      'writeRefreshToken writes value under StorageKeys.refreshToken',
      () async {
        final storage = FlutterSecureStorageImpl();

        await storage.writeRefreshToken('rt-new');

        final args = argsOf('write');
        expect(args['key'], StorageKeys.refreshToken);
        expect(args['value'], 'rt-new');
        expect(store[StorageKeys.refreshToken], 'rt-new');
      },
    );

    test('readUserJson reads StorageKeys.userJson', () async {
      store[StorageKeys.userJson] = '{"id":"u1"}';
      final storage = FlutterSecureStorageImpl();

      final value = await storage.readUserJson();

      expect(value, '{"id":"u1"}');
      expect(argsOf('read')['key'], StorageKeys.userJson);
    });

    test('writeUserJson writes value under StorageKeys.userJson', () async {
      final storage = FlutterSecureStorageImpl();

      await storage.writeUserJson('{"id":"u2"}');

      final args = argsOf('write');
      expect(args['key'], StorageKeys.userJson);
      expect(args['value'], '{"id":"u2"}');
    });

    test('refreshToken and userJson are distinct channel keys', () async {
      final storage = FlutterSecureStorageImpl();

      await storage.writeRefreshToken('rt');
      await storage.writeUserJson('{"u":1}');

      // Neither key collides with the other on the underlying channel.
      expect(store[StorageKeys.refreshToken], 'rt');
      expect(store[StorageKeys.userJson], '{"u":1}');
      expect(StorageKeys.refreshToken, isNot(equals(StorageKeys.userJson)));
    });

    test('deleteAll invokes the deleteAll channel method', () async {
      store[StorageKeys.refreshToken] = 'rt';
      store[StorageKeys.userJson] = '{"u":1}';
      final storage = FlutterSecureStorageImpl();

      await storage.deleteAll();

      expect(calls.where((c) => c.method == 'deleteAll'), hasLength(1));
      expect(store, isEmpty);
    });

    test('deleteAll keeps the per-device push-permission flag', () async {
      final storage = FlutterSecureStorageImpl();
      await storage.writePushPermissionAsked();
      store[StorageKeys.refreshToken] = 'rt';

      await storage.deleteAll();

      expect(store.keys, [StorageKeys.pushPermissionAsked]);
      expect(await storage.readPushPermissionAsked(), isTrue);
    });

    test(
      'deleteAll keeps the push-revoke-pending flag; clear removes it',
      () async {
        final storage = FlutterSecureStorageImpl();
        await storage.writePushRevokePending();
        store[StorageKeys.refreshToken] = 'rt';

        await storage.deleteAll();

        expect(store.keys, [StorageKeys.pushRevokePending]);
        expect(await storage.readPushRevokePending(), isTrue);

        await storage.clearPushRevokePending();
        expect(await storage.readPushRevokePending(), isFalse);
        expect(store, isEmpty);
      },
    );

    test('deleteAll keeps BOTH device-scoped flags together', () async {
      final storage = FlutterSecureStorageImpl();
      await storage.writePushPermissionAsked();
      await storage.writePushRevokePending();
      store[StorageKeys.userJson] = '{}';

      await storage.deleteAll();

      expect(store.keys.toSet(), {
        StorageKeys.pushPermissionAsked,
        StorageKeys.pushRevokePending,
      });
    });

    test('deleteAll leaves the flag absent when it was never set', () async {
      final storage = FlutterSecureStorageImpl();
      store[StorageKeys.refreshToken] = 'rt';
      await storage.deleteAll();
      expect(store, isEmpty);
      expect(await storage.readPushPermissionAsked(), isFalse);
    });

    test('read returns null when key is absent', () async {
      final storage = FlutterSecureStorageImpl();

      expect(await storage.readRefreshToken(), isNull);
      expect(await storage.readUserJson(), isNull);
    });
  });

  group('FlutterSecureStorageImpl lastSalon (Phase 286)', () {
    test('readLastSalon reads StorageKeys.lastSalon', () async {
      store[StorageKeys.lastSalon] = '{"userId":"u1","salonId":"s1"}';
      final storage = FlutterSecureStorageImpl();

      final value = await storage.readLastSalon();

      expect(value, '{"userId":"u1","salonId":"s1"}');
      expect(argsOf('read')['key'], StorageKeys.lastSalon);
    });

    test('writeLastSalon writes value under StorageKeys.lastSalon', () async {
      final storage = FlutterSecureStorageImpl();

      await storage.writeLastSalon('{"userId":"u1","salonId":"s2"}');

      final args = argsOf('write');
      expect(args['key'], StorageKeys.lastSalon);
      expect(args['value'], '{"userId":"u1","salonId":"s2"}');
      expect(store[StorageKeys.lastSalon], '{"userId":"u1","salonId":"s2"}');
    });

    test('deleteLastSalon deletes StorageKeys.lastSalon', () async {
      store[StorageKeys.lastSalon] = '{"userId":"u1","salonId":"s1"}';
      final storage = FlutterSecureStorageImpl();

      await storage.deleteLastSalon();

      expect(argsOf('delete')['key'], StorageKeys.lastSalon);
      expect(store.containsKey(StorageKeys.lastSalon), isFalse);
    });

    test('deleteAll wipes lastSalon alongside the other keys', () async {
      store[StorageKeys.refreshToken] = 'rt';
      store[StorageKeys.lastSalon] = '{"userId":"u1","salonId":"s1"}';
      final storage = FlutterSecureStorageImpl();

      await storage.deleteAll();

      expect(calls.where((c) => c.method == 'deleteAll'), hasLength(1));
      expect(store, isEmpty);
    });

    // Phase 288 D6 (mobile-security INFO) — the restore loop for
    // `StorageKeys.deviceScoped` runs on the SAME call; lastSalon must not
    // ride it back in while the device flags (which DO survive) are present.
    test(
      'deleteAll removes lastSalon even while device-scoped flags survive',
      () async {
        store[StorageKeys.lastSalon] = '{"userId":"u1","salonId":"s1"}';
        store[StorageKeys.pushPermissionAsked] = '1';
        store[StorageKeys.pushRevokePending] = '1';
        final storage = FlutterSecureStorageImpl();

        await storage.deleteAll();

        expect(await storage.readLastSalon(), isNull);
        expect(store.containsKey(StorageKeys.lastSalon), isFalse);
        expect(await storage.readPushPermissionAsked(), isTrue);
      },
    );

    test('read returns null for lastSalon when key is absent', () async {
      final storage = FlutterSecureStorageImpl();

      expect(await storage.readLastSalon(), isNull);
    });
  });

  // Phase 288 D10 — SecureStorage carries no per-key cache, queue or ordering:
  // deleteAll() (logout) must never wait on another storage operation, so a
  // hung lastSalon write can never block the wipe of the session tokens.
  group('FlutterSecureStorageImpl deleteAll independence (Phase 288 D10)', () {
    test(
      'should_completeDeleteAll_when_aLastSalonWriteIsHung',
      () async {
        store[StorageKeys.refreshToken] = 'rt';
        final Completer<void> neverCompletes = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              final args =
                  (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
              final String? key = args['key'] as String?;
              switch (call.method) {
                case 'read':
                  return store[key];
                case 'write':
                  if (key == StorageKeys.lastSalon) {
                    await neverCompletes.future;
                  }
                  store[key!] = args['value'] as String;
                  return null;
                case 'delete':
                  store.remove(key);
                  return null;
                case 'deleteAll':
                  store.clear();
                  return null;
                default:
                  return null;
              }
            });
        final storage = FlutterSecureStorageImpl();

        unawaited(storage.writeLastSalon('{"userId":"u1","salonId":"s1"}'));
        await storage.deleteAll();

        expect(calls.where((c) => c.method == 'deleteAll'), hasLength(1));
        expect(store.containsKey(StorageKeys.refreshToken), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });

  group('FlutterSecureStorageImpl iOS accessibility option', () {
    // The iOS accessibility option only surfaces in the channel `options` map
    // when the active target platform is iOS, so force it for this group.
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'write carries first_unlock_this_device accessibility on iOS',
      () async {
        final storage = FlutterSecureStorageImpl();

        await storage.writeRefreshToken('rt');

        final options = (argsOf('write')['options'] as Map)
            .cast<String, dynamic>();
        expect(options['accessibility'], 'first_unlock_this_device');
      },
    );

    test(
      'read carries first_unlock_this_device accessibility on iOS',
      () async {
        store[StorageKeys.refreshToken] = 'rt';
        final storage = FlutterSecureStorageImpl();

        await storage.readRefreshToken();

        final options = (argsOf('read')['options'] as Map)
            .cast<String, dynamic>();
        expect(options['accessibility'], 'first_unlock_this_device');
      },
    );
  });
}
