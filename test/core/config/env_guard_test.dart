import 'package:beautica_mobile/core/config/env_guard.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
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

  group('BEAUTICA_MEDIA_ORIGIN per-flavor allow-list (phase 430)', () {
    EnvCheckResult media(String flavor, String raw, EnvBuildMode m) =>
        checkEnvConsistency(
          flavor: flavor,
          env: flavor,
          baseUrl: flavor == 'prod' ? _prodUrl : _stagingUrl,
          mode: m,
          mediaHosts: MediaConfig.parseForTest(raw),
        );

    for (final m in [EnvBuildMode.release, EnvBuildMode.profile]) {
      test('${m.name}: prod flavor + staging media host -> throws', () {
        final r = media('prod', 'media-staging.beautica.app', m);
        expect(r.ok, isFalse);
        expect(r.errors.single, contains('BEAUTICA_MEDIA_ORIGIN'));
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: prod flavor + prod media host -> ok', () {
        expect(media('prod', 'media.beautica.app', m).ok, isTrue);
      });

      test('${m.name}: staging flavor + both staging hosts -> ok', () {
        final r = media(
          'staging',
          'media-staging.beautica.app,'
              'pub-6d1bb68a80bf4d5da719f8154f3c1c4c.r2.dev',
          m,
        );
        expect(r.errors, isEmpty);
      });

      test('${m.name}: staging flavor + unknown media host -> throws', () {
        final r = media(
          'staging',
          'media-staging.beautica.app,evil.example',
          m,
        );
        expect(r.errors.single, contains('evil.example'));
        expect(() => _run(r, m), throwsStateError);
      });

      test('${m.name}: staging flavor + full URL form (deploy script '
          'STAGING_MEDIA_ORIGIN) -> ok', () {
        final r = media('staging', 'https://media-staging.beautica.app', m);
        expect(r.errors, isEmpty);
      });

      test('${m.name}: empty media set (no define) -> ok', () {
        expect(media('staging', '', m).ok, isTrue);
      });
    }

    test('debug: off-list media host is not reported (local overrides)', () {
      final r = media('staging', 'pub-devbucket.r2.dev', EnvBuildMode.debug);
      expect(r.ok, isTrue);
    });

    test('debug: prod flavor + staging media host -> fatal, throws', () {
      final r = media('prod', 'media-staging.beautica.app', EnvBuildMode.debug);
      expect(r.errors.single, contains('BEAUTICA_MEDIA_ORIGIN'));
      expect(r.fatalInEveryMode, isTrue);
      expect(() => _run(r, EnvBuildMode.debug), throwsStateError);
    });

    test('debug: prod flavor + prod media host -> ok', () {
      expect(
        media('prod', 'media.beautica.app', EnvBuildMode.debug).ok,
        isTrue,
      );
    });

    test('debug: staging flavor + unknown media host -> allowed, no throw', () {
      final r = media('staging', 'evil.example', EnvBuildMode.debug);
      expect(r.ok, isTrue);
      expect(r.fatalInEveryMode, isFalse);
      expect(() => _run(r, EnvBuildMode.debug), returnsNormally);
    });
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
