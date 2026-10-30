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

  // Phase 430: prod allows exactly ONE media host; so does staging, now that
  // every staging photo row points at the custom domain (legacy r2.dev dropped).
  test('prod media allow-list is exactly one host', () {
    expect(MediaConfig.parseForTest(prod['BEAUTICA_MEDIA_ORIGIN']!), <String>{
      'media.beautica.app',
    });
  });

  test('staging media allow-list is exactly the custom domain', () {
    expect(
      MediaConfig.parseForTest(staging['BEAUTICA_MEDIA_ORIGIN']!),
      <String>{'media-staging.beautica.app'},
    );
  });

  // Phase 430: each file's media list and kEnvMediaHosts must be the SAME set.
  // The "passes the env guard" tests below only catch a file host missing from
  // the guard; this also catches a guard host the file no longer ships.
  for (final MapEntry<String, Map<String, String>> e
      in <String, Map<String, String>>{
        'staging': staging,
        'prod': prod,
      }.entries) {
    test('${e.key} media list equals kEnvMediaHosts[${e.key}]', () {
      expect(
        MediaConfig.parseForTest(e.value['BEAUTICA_MEDIA_ORIGIN']!),
        kEnvMediaHosts[e.key],
      );
    });
  }

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

  // Phase 430: the REAL file values — base URL and the media list parsed the
  // way MediaConfig parses it at runtime — must clear the strict guard in
  // both strict build modes. Catches drift between staging.json/prod.json and
  // kEnvMediaHosts before a release build dies at boot.
  for (final EnvBuildMode mode in <EnvBuildMode>[
    EnvBuildMode.release,
    EnvBuildMode.profile,
  ]) {
    for (final MapEntry<String, Map<String, String>> e
        in <String, Map<String, String>>{
          'staging': staging,
          'prod': prod,
        }.entries) {
      test('${e.key} file (API + media) passes the env guard in '
          '${mode.name} mode', () {
        final EnvCheckResult result = checkEnvConsistency(
          flavor: e.key,
          env: e.value['BEAUTICA_ENV']!,
          baseUrl: e.value['BEAUTICA_BASE_URL']!,
          mode: mode,
          mediaHosts: MediaConfig.parseForTest(
            e.value['BEAUTICA_MEDIA_ORIGIN']!,
          ),
        );

        expect(result.errors, isEmpty);
        expect(result.ok, isTrue);
      });
    }

    test('prod flavor with staging.json media list is rejected in '
        '${mode.name} mode', () {
      final EnvCheckResult result = checkEnvConsistency(
        flavor: 'prod',
        env: prod['BEAUTICA_ENV']!,
        baseUrl: prod['BEAUTICA_BASE_URL']!,
        mode: mode,
        mediaHosts: MediaConfig.parseForTest(staging['BEAUTICA_MEDIA_ORIGIN']!),
      );

      expect(result.ok, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('BEAUTICA_MEDIA_ORIGIN'));
      expect(result.errors.single, contains('media-staging.beautica.app'));
      expect(() => EnvGuard.apply(result, mode), throwsA(isA<StateError>()));
    });
  }
}
