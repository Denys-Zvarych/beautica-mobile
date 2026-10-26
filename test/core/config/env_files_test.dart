import 'dart:convert';
import 'dart:io';

import 'package:beautica_mobile/core/config/app_config.dart';
import 'package:beautica_mobile/core/config/env_guard.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads config/env/ENV.json relative to the package root (flutter test cwd).
Map<String, String> _load(String env) {
  final File f = File('config/env/$env.json');
  if (!f.existsSync()) throw StateError('missing config/env/$env.json');
  final Object? decoded = jsonDecode(f.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw StateError('config/env/$env.json is not a JSON object');
  }
  return decoded.map(
    (String k, dynamic v) => MapEntry<String, String>(k, v as String),
  );
}

void main() {
  const Set<String> keys = <String>{
    'BEAUTICA_ENV',
    'BEAUTICA_BASE_URL',
    'BEAUTICA_MEDIA_ORIGIN',
  };
  final Map<String, String> staging = _load('staging');
  final Map<String, String> prod = _load('prod');

  for (final MapEntry<String, Map<String, String>> e
      in <String, Map<String, String>>{
        'staging': staging,
        'prod': prod,
      }.entries) {
    group('config/env/${e.key}.json', () {
      final Map<String, String> m = e.value;

      test('has exactly the three keys', () {
        expect(m.keys.toSet(), keys);
      });

      test('BEAUTICA_ENV matches the file name', () {
        expect(m['BEAUTICA_ENV'], e.key);
      });

      test('base URL is https, clean, and on the env allow-list host', () {
        final String url = m['BEAUTICA_BASE_URL']!;
        expect(url.startsWith('https://'), isTrue);
        expect(AppConfig.normalizeBaseUrl(url), url, reason: 'not normalised');
        expect(Uri.parse(url).host, kEnvApiHosts[e.key]);
        expect(Uri.parse(url).path, isEmpty);
      });

      test('media origin parses via MediaConfig to non-empty bare hosts', () {
        final Set<String> hosts = MediaConfig.parseForTest(
          m['BEAUTICA_MEDIA_ORIGIN']!,
        );
        expect(hosts, isNotEmpty);
        expect(m['BEAUTICA_MEDIA_ORIGIN'], isNot(contains('://')));
        expect(hosts.join(','), m['BEAUTICA_MEDIA_ORIGIN']);
      });
    });
  }

  test('prod and staging hosts differ (API and media)', () {
    expect(prod['BEAUTICA_BASE_URL'], isNot(staging['BEAUTICA_BASE_URL']));
    expect(
      prod['BEAUTICA_MEDIA_ORIGIN'],
      isNot(staging['BEAUTICA_MEDIA_ORIGIN']),
    );
  });

  test('prod values contain no staging, localhost or private host', () {
    for (final String v in prod.values.where((String v) => v != 'prod')) {
      expect(v.toLowerCase(), isNot(contains('staging')));
      expect(v.toLowerCase(), isNot(contains('localhost')));
      expect(v.toLowerCase(), isNot(contains('r2.dev')), reason: v);
      expect(AppConfig.isPrivateOrLoopbackUrl('https://$v'), isFalse);
    }
    expect(
      AppConfig.isPrivateOrLoopbackUrl(prod['BEAUTICA_BASE_URL']!),
      isFalse,
    );
  });

  test('prod passes the env guard in release mode (file -> guard)', () {
    expect(
      checkEnvConsistency(
        flavor: 'prod',
        env: prod['BEAUTICA_ENV']!,
        baseUrl: prod['BEAUTICA_BASE_URL']!,
        mode: EnvBuildMode.release,
      ).ok,
      isTrue,
    );
  });

  test('staging passes the env guard in release mode (file -> guard)', () {
    expect(
      checkEnvConsistency(
        flavor: 'staging',
        env: staging['BEAUTICA_ENV']!,
        baseUrl: staging['BEAUTICA_BASE_URL']!,
        mode: EnvBuildMode.release,
      ).ok,
      isTrue,
    );
  });
}
