import 'package:beautica_mobile/core/config/env_guard.dart';
import 'package:flutter_test/flutter_test.dart';

const String _prodUrl = 'https://api.beautica.app';
const String _stagingUrl = 'https://beautica-backend-staging.up.railway.app';

EnvCheckResult _check(
  String? flavor,
  String env,
  String url,
  EnvBuildMode mode,
) => checkEnvConsistency(flavor: flavor, env: env, baseUrl: url, mode: mode);

/// Mirrors EnvGuard.assertConsistent's throw/log decision for a given mode.
void _run(EnvCheckResult r, EnvBuildMode m) => EnvGuard.apply(r, m);

void main() {
  group('release / profile (throwing semantics)', () {
    for (final EnvBuildMode m in <EnvBuildMode>[
      EnvBuildMode.release,
      EnvBuildMode.profile,
    ]) {
      test('${m.name}: prod flavor + prod env + prod host -> ok', () {
        final r = _check('prod', 'prod', _prodUrl, m);
        expect(r.ok, isTrue);
        expect(() => _run(r, m), returnsNormally);
      });

      test('${m.name}: staging flavor + staging env + staging host -> ok', () {
        final r = _check('staging', 'staging', _stagingUrl, m);
        expect(r.ok, isTrue);
        expect(() => _run(r, m), returnsNormally);
      });

      test('${m.name}: prod flavor + staging host -> throws', () {
        final r = _check('prod', 'prod', _stagingUrl, m);
        expect(r.ok, isFalse);
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: staging flavor + prod host -> throws', () {
        final r = _check('staging', 'staging', _prodUrl, m);
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: staging flavor + prod env + prod host -> throws', () {
        final r = _check('staging', 'prod', _prodUrl, m);
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: prod flavor + staging env -> throws', () {
        final r = _check('prod', 'staging', _prodUrl, m);
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: missing appFlavor -> throws', () {
        final r = _check(null, 'staging', _stagingUrl, m);
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: unknown flavor -> throws', () {
        final r = _check('qa', 'qa', _stagingUrl, m);
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: staging flavor + private host -> throws', () {
        final r = _check('staging', 'staging', 'http://10.0.2.2:8080', m);
        expect(() => _run(r, m), throwsStateError);
      });
    }
  });

  group('prod flavor refuses dev hosts in EVERY mode', () {
    for (final EnvBuildMode m in EnvBuildMode.values) {
      for (final String url in <String>[
        'http://10.0.2.2:8080',
        'http://localhost:8080',
        'http://127.0.0.1:8080',
        'http://192.168.56.101:8080',
        'http://172.16.0.5',
        _stagingUrl,
        'https://api-staging.beautica.app',
      ]) {
        test('${m.name}: prod + $url -> throws', () {
          final r = _check('prod', 'prod', url, m);
          expect(r.ok, isFalse);
          expect(r.fatalInEveryMode, isTrue);
          expect(() => _run(r, m), throwsStateError);
        });
      }
    }
  });

  group('debug (logging semantics)', () {
    const EnvBuildMode m = EnvBuildMode.debug;

    test('missing appFlavor -> ok, nothing thrown (plain flutter run)', () {
      final r = _check(null, 'staging', 'http://localhost:8080', m);
      expect(r.ok, isTrue);
      expect(() => _run(r, m), returnsNormally);
    });

    test(
      'staging flavor + local backend override -> ok (documented dev flow)',
      () {
        final r = _check('staging', 'staging', 'http://10.0.2.2:8080', m);
        expect(r.ok, isTrue);
      },
    );

    test('staging flavor + prod host -> mismatch is logged, not thrown', () {
      final r = _check('staging', 'staging', _prodUrl, m);
      expect(r.ok, isFalse);
      expect(r.fatalInEveryMode, isFalse);
      expect(() => _run(r, m), returnsNormally);
    });

    test('env/flavor disagreement -> logged, not thrown', () {
      final r = _check('staging', 'prod', _stagingUrl, m);
      expect(r.ok, isFalse);
      expect(() => _run(r, m), returnsNormally);
    });

    test('prod + prod host -> ok', () {
      expect(_check('prod', 'prod', _prodUrl, m).ok, isTrue);
    });
  });

  test('allow-list pins exactly the two API hosts', () {
    expect(kEnvApiHosts, <String, String>{
      'staging': 'beautica-backend-staging.up.railway.app',
      'prod': 'api.beautica.app',
    });
  });
}
