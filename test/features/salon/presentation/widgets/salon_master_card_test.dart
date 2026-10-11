// Phase 9.7 — SalonMasterCard renders the master's photo through RemoteImage;
// null / disallowed / failed loads keep today's gradient + glyph.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_master_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fake_media_cache.dart';
import '../../../../helpers/pump_app.dart';
import '../../../../helpers/rendered_image_url.dart';

const String _url = 'https://media.test/avatars/m1.png';

Widget _card({String? imageUrl}) => SizedBox(
  width: 170,
  height: kSalonMasterCardHeight,
  child: SalonMasterCard(
    key: const Key('card'),
    name: 'Олена',
    role: 'Майстер',
    ratingLabel: '4.9',
    avatarIndex: 0,
    imageUrl: imageUrl,
    onTap: () {},
  ),
);

void main() {
  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoaded);
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  testWidgets('imageUrl renders the photo through RemoteImage', (tester) async {
    await tester.pumpApp(_card(imageUrl: _url));
    await tester.pump();
    expect(find.byType(RemoteImage), findsOneWidget);
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('null imageUrl keeps the gradient glyph and renders no image', (
    tester,
  ) async {
    await tester.pumpApp(_card());
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('a non-allow-listed host falls back to the glyph, no fetch', (
    tester,
  ) async {
    await tester.pumpApp(_card(imageUrl: 'https://evil.test/p.png'));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('a failed load falls back to the glyph', (tester) async {
    debugMediaCacheManager = FakeMediaCacheManager(mediaFetchError);
    await tester.pumpApp(_card(imageUrl: _url));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  group('salonMasterCardHeight', () {
    test('is exactly kSalonMasterCardHeight at 1.0x and below', () {
      expect(
        salonMasterCardHeight(TextScaler.noScaling),
        kSalonMasterCardHeight,
      );
      expect(
        salonMasterCardHeight(const TextScaler.linear(0.85)),
        kSalonMasterCardHeight,
      );
    });

    test('grows only the 71dp text budget with the scale', () {
      expect(
        salonMasterCardHeight(const TextScaler.linear(1.3)),
        moreOrLessEquals(kSalonMasterCardHeight + 71 * 0.3),
      );
    });

    for (final double width in const <double>[128, 148, 175]) {
      testWidgets('worst-case card fits at 1.3x in a ${width}dp column', (
        tester,
      ) async {
        await tester.pumpApp(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: SalonMasterCard(
                key: const Key('card'),
                name: 'Олександрина-Емілія',
                role: 'Топ-стиліст з фарбування та догляду за волоссям',
                ratingLabel: '4.8',
                avatarIndex: 0,
                imageUrl: _url,
                onTap: () {},
              ),
            ),
          ),
          textScaleFactor: 1.3,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const Key('card'))).height,
          moreOrLessEquals(salonMasterCardHeight(const TextScaler.linear(1.3))),
        );
      });
    }
  });
}
