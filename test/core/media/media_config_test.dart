// MediaConfig — the media-origin allowlist parsing + override seam.
//
// The build-time `BEAUTICA_MEDIA_ORIGIN` define cannot be varied under
// `flutter test`, so the parsing is exercised through [MediaConfig.parseForTest]
// and the runtime gate through the [MediaConfig.debugAllowedHosts] override.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/media/media_config.dart';

void main() {
  group('parseForTest — comma-separated host allowlist', () {
    test('splits, trims and lower-cases bare hosts', () {
      expect(
        MediaConfig.parseForTest(' pub-abc.r2.dev , Media.Beautica.App '),
        <String>{'pub-abc.r2.dev', 'media.beautica.app'},
      );
    });

    test(
      'an empty / whitespace string yields no hosts (fail-closed default)',
      () {
        expect(MediaConfig.parseForTest(''), isEmpty);
        expect(MediaConfig.parseForTest('   ,  , '), isEmpty);
      },
    );

    test('a full URL slipped into the define is reduced to its host', () {
      expect(
        MediaConfig.parseForTest('https://pub-abc.r2.dev/avatars/x.png'),
        <String>{'pub-abc.r2.dev'},
      );
    });

    test('duplicates collapse', () {
      expect(
        MediaConfig.parseForTest('pub-abc.r2.dev,pub-abc.r2.dev'),
        <String>{'pub-abc.r2.dev'},
      );
    });
  });

  group('debugAllowedHosts override drives effectiveAllowedHosts', () {
    tearDown(() => MediaConfig.debugAllowedHosts = null);

    test('default (no define, no override) is empty — closed', () {
      // The test build passes no BEAUTICA_MEDIA_ORIGIN, so the compile-time
      // allowlist is empty and nothing is allowed until configured.
      expect(MediaConfig.effectiveAllowedHosts, isEmpty);
    });

    test('an override replaces the effective set and is lower-cased', () {
      MediaConfig.debugAllowedHosts = <String>{'Pub-ABC.r2.dev'};
      expect(MediaConfig.effectiveAllowedHosts, <String>{'pub-abc.r2.dev'});
    });

    test('clearing the override restores the build-time set', () {
      MediaConfig.debugAllowedHosts = <String>{'pub-abc.r2.dev'};
      MediaConfig.debugAllowedHosts = null;
      expect(MediaConfig.effectiveAllowedHosts, isEmpty);
    });
  });
}
