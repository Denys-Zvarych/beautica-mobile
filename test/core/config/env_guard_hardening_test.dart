// Phase 408 QA — hardening pins for the prod-flavor refusal in env_guard.dart.
//
// KNOWN-RED until the post-audit dev pass lands (each failing assertion is
// named in its test title):
//   SEC-LOW-1  prod flavor + non-allow-listed PUBLIC host must be fatal in
//              every build mode (debug logs only today).
//   SEC-LOW-2  AppConfig.isPrivateOrLoopbackUrl must classify 127.0.0.0/8,
//              0.0.0.0, 169.254/16, `localhost.` and IPv6 loopback / mapped
//              forms as non-public.
//   SEC-LOW-3  prod flavor base URL must be https with no explicit port.
import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:beautica_mobile/core/config/env_guard.dart';
import 'package:flutter_test/flutter_test.dart';

EnvCheckResult _prod(String url, EnvBuildMode mode) =>
    checkEnvConsistency(flavor: 'prod', env: 'prod', baseUrl: url, mode: mode);

void main() {
  group(
    'SEC-LOW-1: prod + non-allow-listed public host is fatal everywhere',
    () {
      const List<String> hosts = <String>[
        'https://evil.com',
        'https://api.beautica.app.evil.com',
        'https://beautica-backend-production.up.railway.app',
      ];
      for (final EnvBuildMode m in EnvBuildMode.values) {
        for (final String url in hosts) {
          test('${m.name}: $url -> fatalInEveryMode and apply throws', () {
            final EnvCheckResult r = _prod(url, m);
            expect(r.ok, isFalse);
            expect(
              r.fatalInEveryMode,
              isTrue,
              reason: 'SEC-LOW-1: must throw even in debug',
            );
            expect(() => EnvGuard.apply(r, m), throwsA(isA<StateError>()));
          });
        }
      }

      test('control: the allow-listed prod host is clean in every mode', () {
        for (final EnvBuildMode m in EnvBuildMode.values) {
          final EnvCheckResult r = _prod('https://api.beautica.app', m);
          expect(r.ok, isTrue, reason: m.name);
          expect(() => EnvGuard.apply(r, m), returnsNormally);
        }
      });
    },
  );

  group('SEC-LOW-2: host classification treats these as non-public', () {
    const List<String> nonPublic = <String>[
      'http://127.0.0.2',
      'http://127.1.2.3:8080',
      'http://0.0.0.0',
      'http://169.254.169.254/latest',
      'http://169.254.0.1',
      'http://localhost.',
      'http://LOCALHOST',
      'http://[::1]:8080',
      'http://[::ffff:127.0.0.1]',
      'http://[::ffff:10.0.0.5]',
    ];
    for (final String url in nonPublic) {
      test('isPrivateOrLoopbackUrl($url) is true', () {
        expect(AppConfig.isPrivateOrLoopbackUrl(url), isTrue);
      });
      test('prod flavor refuses $url in debug (fatal)', () {
        final EnvCheckResult r = _prod(url, EnvBuildMode.debug);
        expect(r.fatalInEveryMode, isTrue);
      });
    }

    const List<String> publicUrls = <String>[
      'https://api.beautica.app',
      'https://8.8.8.8',
      'https://172.32.0.1',
      'https://169.255.0.1',
      'https://[::ffff:8.8.8.8]',
    ];
    for (final String url in publicUrls) {
      test('control: isPrivateOrLoopbackUrl($url) stays false', () {
        expect(AppConfig.isPrivateOrLoopbackUrl(url), isFalse);
      });
    }
  });

  group('SEC-LOW-3: prod base URL is https with no explicit port', () {
    for (final EnvBuildMode m in EnvBuildMode.values) {
      test('${m.name}: https://api.beautica.app:8443 is rejected', () {
        final EnvCheckResult r = _prod('https://api.beautica.app:8443', m);
        expect(r.ok, isFalse, reason: 'SEC-LOW-3: explicit port accepted');
      });
      test('${m.name}: http://api.beautica.app (plain http) is rejected', () {
        final EnvCheckResult r = _prod('http://api.beautica.app', m);
        expect(r.ok, isFalse, reason: 'SEC-LOW-3: non-https accepted');
      });
    }
  });

  group('SEC-LOW-4: prod base URL carries no userinfo', () {
    for (final EnvBuildMode m in EnvBuildMode.values) {
      for (final String url in <String>[
        'https://x@api.beautica.app',
        'https://user:pw@api.beautica.app',
      ]) {
        test('${m.name}: $url is fatal and apply throws', () {
          final EnvCheckResult r = _prod(url, m);
          expect(r.ok, isFalse);
          expect(r.fatalInEveryMode, isTrue);
          expect(() => EnvGuard.apply(r, m), throwsA(isA<StateError>()));
        });
      }
    }
  });
}
