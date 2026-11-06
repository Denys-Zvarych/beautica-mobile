// Regression guard (CI shards 6/7): the integration avatar fixture must be an
// ABSOLUTE, existing file independent of the working directory — on a device
// the relative `integration_test/fixtures/avatar.jpg` does not exist.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/fixture_avatar_gateway.dart';

void main() {
  test(
    'pickImage + compress work from a cwd that has no fixtures dir',
    () async {
      final Directory empty = Directory.systemTemp.createTempSync('empty_cwd_');
      addTearDown(() => empty.deleteSync(recursive: true));

      await IOOverrides.runZoned(() async {
        final FixtureAvatarGateway gw = FixtureAvatarGateway();
        final String? picked = await gw.pickImage(
          MediaPickSource.gallery,
          maxDimension: 1024,
        );
        expect(picked, isNotNull);
        expect(File(picked!).isAbsolute, isTrue);
        expect(File(picked).existsSync(), isTrue);
        expect(File(picked).lengthSync(), greaterThan(1000));

        final String target = '${empty.path}/out.jpg';
        final String? out = await gw.compress(
          picked,
          target,
          maxWidth: 512,
          maxHeight: 512,
          quality: 80,
          keepExif: false,
        );
        expect(out, target);
        expect(File(target).readAsBytesSync().take(2), <int>[0xFF, 0xD8]);
      }, getCurrentDirectory: () => empty);
    },
  );
}
