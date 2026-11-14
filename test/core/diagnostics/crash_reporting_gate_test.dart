// Phase 410 (R.3 D3) — `shouldEnableCrashReporting` matrix.
import 'package:beautica_mobile/core/diagnostics/crash_reporting.dart';
import 'package:flutter_test/flutter_test.dart';

const String _dsn = 'https://key@o1.ingest.de.sentry.io/2';
const String _https = 'https://staging-api.beautica.app/api/v1';

bool _gate({
  bool isDebug = false,
  String dsn = _dsn,
  String env = 'staging',
  String baseUrl = _https,
}) => shouldEnableCrashReporting(
  isDebug: isDebug,
  dsn: dsn,
  env: env,
  baseUrl: baseUrl,
);

void main() {
  test('release + DSN + staging + https -> enabled', () {
    expect(_gate(), isTrue);
  });

  test('release + DSN + prod + https -> enabled', () {
    expect(_gate(env: 'prod', baseUrl: 'https://api.beautica.app'), isTrue);
  });

  test('debug + DSN + staging + https -> enabled (2026-11-13)', () {
    expect(_gate(isDebug: true), isTrue);
  });

  group('disabled', () {
    test('debug + prod', () {
      expect(
        _gate(isDebug: true, env: 'prod', baseUrl: 'https://api.beautica.app'),
        isFalse,
      );
    });
    test('debug + local', () {
      expect(_gate(isDebug: true, env: 'local'), isFalse);
    });
    test('debug + unset env', () {
      expect(_gate(isDebug: true, env: ''), isFalse);
    });
    test('debug + staging + loopback http base URL', () {
      expect(_gate(isDebug: true, baseUrl: 'http://10.0.2.2:8080'), isFalse);
    });
    test('debug + staging + empty DSN', () {
      expect(_gate(isDebug: true, dsn: ''), isFalse);
    });
    test('empty DSN', () => expect(_gate(dsn: ''), isFalse));
    test('blank DSN', () => expect(_gate(dsn: '   '), isFalse));
    test('BEAUTICA_ENV missing', () => expect(_gate(env: ''), isFalse));
    test('BEAUTICA_ENV local', () => expect(_gate(env: 'local'), isFalse));
    test('BEAUTICA_ENV wrong case', () => expect(_gate(env: 'Prod'), isFalse));
    test('empty base URL', () => expect(_gate(baseUrl: ''), isFalse));
    for (final String url in <String>[
      'http://10.0.2.2:8080/api/v1',
      'http://localhost:8080',
      'https://localhost:8443',
      'https://127.0.0.1',
      'https://192.168.56.101:8080',
      'https://10.1.2.3',
      'https://172.16.0.5',
    ]) {
      test('loopback / private URL $url', () {
        expect(_gate(baseUrl: url), isFalse);
      });
    }
    test('plain http public URL', () {
      expect(_gate(baseUrl: 'http://api.beautica.app'), isFalse);
    });
  });

  group('CrashReportingConfig.dist', () {
    test('build number after +', () {
      expect(
        const CrashReportingConfig(
          dsn: _dsn,
          env: 'prod',
          release: 'beautica-mobile@1.4.0+57',
        ).dist,
        '57',
      );
    });
    test('null without a build part', () {
      expect(
        const CrashReportingConfig(dsn: _dsn, env: 'prod', release: '').dist,
        isNull,
      );
      expect(
        const CrashReportingConfig(
          dsn: _dsn,
          env: 'prod',
          release: 'beautica-mobile@1.4.0+',
        ).dist,
        isNull,
      );
    });
  });

  test('this test build (debug, no defines) is not configured', () async {
    await initCrashReporting();
    expect(CrashReporting.isConfigured, isFalse);
    expect(CrashReporting.navigatorObservers(), isEmpty);
  });
}
