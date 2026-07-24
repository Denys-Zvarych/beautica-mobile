// The row-1 client mark's IMAGE PROVIDER IDENTITY — the pin behind
// `_ClientAvatarMark`'s "CACHING" doc section (2026-07-24, mobile-perf LOW).
//
// ## WHAT IS UNPINNED WITHOUT THIS FILE
//
// `_ClientAvatarMark`'s doc makes two load-bearing performance claims, and
// `master_booking_card_client_avatar_test.dart` pins NEITHER of them — it pins
// the 16dp footprint, which is a different contract:
//
//   1. **Dedupe across cards.** "the same client on three bookings in one day
//      resolves to ONE key: one fetch, one decode, shared by all three."
//   2. **No refetch on press.** "Rebuilt on every press (`_pressed` toggles
//      `setState`), but `NetworkImage`/`ResizeImage` are value-equal, so each
//      rebuild resolves to the SAME `ImageCache` entry — never a refetch."
//
// Both reduce to ONE observable invariant, and it is the same one the
// framework itself keys off: the `ImageProvider` the widget hands `Image` must
// compare `==` across instances and across rebuilds. `ImageCache` is keyed by
// the provider, and `_ImageState.didUpdateWidget` skips `_resolveImage()`
// entirely when `widget.image == oldWidget.image`. So provider equality IS the
// mechanism; asserting it asserts the claims, without a network, a timer or a
// frame count.
//
// The failure mode this catches is silent and cheap to introduce: swap
// `Image.network` for a provider that does not implement value equality, give
// the `Image` a per-instance `key`, or derive `cacheWidth` from anything that
// varies per card, and every card on a busy day fetches and decodes its own
// copy of the same avatar. Nothing else in the suite would go red — the photo
// still renders, the footprint is still 16dp, and the cost only shows up as
// jank on a real handset scrolling a full timeline.
//
// ## THE PROVIDER IS NOW THE SHARED CACHED LOADER (2026-07-24)
//
// The inner provider is `beauticaMediaProvider(url)` — a
// `CachedNetworkImageProvider` from the shared media loader
// (core/media/beautica_image.dart) — wrapped in the same `ResizeImage`. On
// this project's cached_network_image (3.4.1) its `==`/`hashCode` key off
// `(cacheKey ?? url, scale, maxHeight, maxWidth)` and DELIBERATELY exclude the
// `cacheManager`:
//
//     bool operator ==(Object other) =>
//         other is CachedNetworkImageProvider &&
//         (cacheKey ?? url) == (other.cacheKey ?? other.url) &&
//         scale == other.scale &&
//         maxHeight == other.maxHeight &&
//         maxWidth == other.maxWidth;
//     int get hashCode => Object.hash(cacheKey ?? url, scale, maxHeight, maxWidth);
//
// So the dedup key is the URL (no `cacheKey`/`maxWidth`/`maxHeight` are passed
// by the shared provider), and — unlike the old bare `NetworkImage`, whose
// `==` folds in a `headers` map by value — there is no per-request header that
// could vary and silently fragment the cache. `clientAvatarUrl` is a PUBLIC R2
// object URL, so no auth header is attached; the "shared image loader with a
// stable key" this note used to recommend as the fix is now what's in use.
// The dedup-key assertion below pins that the URL is what decides identity.
//
// NOT ASSERTED HERE: fetch COUNTS. Counting real loads would need a stubbed
// `HttpClient` plus `runAsync`, would re-enter the shared-`_sharedHttpClient`
// trap documented in the sibling file, and would still only be measuring the
// framework's own cache. The provider key is the contract; the cache is
// Flutter's.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';

import '../../../helpers/fake_media_cache.dart';
import '../../../helpers/pump_app.dart';

const String _kHost = 'cdn.example.com';
const String _kAvatarA = 'https://$_kHost/avatars/client-1.png';
const String _kAvatarB = 'https://$_kHost/avatars/client-2.png';

Booking _booking({required String id, String? avatarUrl}) {
  // future-date-ok: pinned wall-clock fixture; nothing here reads "now".
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6); // 09:00 Kyiv
  return Booking(
    id: id,
    masterId: 'master-1',
    masterFirstName: 'Olha',
    masterLastName: 'Koval',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Mariia',
    clientLastName: 'Ivaniuk',
    clientAvatarUrl: avatarUrl,
    serviceId: 'service-1',
    serviceName: 'Haircut',
    durationMinutes: 60,
    price: 450,
    startAt: startAt,
    endAt: startAt.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

Widget _card(Booking b) => SizedBox(
  width: 226,
  child: MasterBookingCard(
    booking: b,
    onTap: () {},
    minHeight: MasterBookingCard.fullLayoutMinHeight,
  ),
);

/// The URL the inner [CachedNetworkImageProvider] keys its cache entry on —
/// the dedup key. Unwraps the [ResizeImage] the mark hands its [Image].
String _cacheKeyOf(ImageProvider<Object> provider) {
  final ResizeImage resize = provider as ResizeImage;
  final CachedNetworkImageProvider inner =
      resize.imageProvider as CachedNetworkImageProvider;
  return inner.cacheKey ?? inner.url;
}

void main() {
  setUp(() {
    // Allow the fixture host and route fetches through a fake that never
    // resolves — identity is read off the built providers, not decoded frames.
    MediaConfig.debugAllowedHosts = <String>{_kHost};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  });

  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  group('the row-1 mark\'s ImageProvider is the ImageCache key — it must be '
      'value-equal, or every card refetches', () {
    testWidgets('two DIFFERENT bookings sharing one client resolve to the '
        'SAME provider — one fetch, one decode, shared', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Column(
          children: <Widget>[
            _card(_booking(id: 'morning', avatarUrl: _kAvatarA)),
            _card(_booking(id: 'afternoon', avatarUrl: _kAvatarA)),
          ],
        ),
      );
      await tester.pump();

      final List<Image> images = tester
          .widgetList<Image>(find.byType(Image))
          .toList();
      expect(
        images,
        hasLength(2),
        reason: 'precondition: both cards render the FULL body\'s row-1 mark',
      );

      expect(
        images.first.image,
        equals(images.last.image),
        reason:
            'ImageCache is keyed by the provider, so two cards for the same '
            'client MUST hand it an `==` provider — otherwise the same avatar '
            'is fetched and decoded once per booking. cached_network_image '
            'keys its provider `==` on (cacheKey ?? url); wrapping a '
            'non-value-equal provider, a per-instance key or a per-card '
            'cacheWidth all break this silently: the photo still renders.',
      );
      expect(
        images.first.image.hashCode,
        images.last.image.hashCode,
        reason:
            'the cache is a HashMap — equal providers with unequal hashCodes '
            'still miss',
      );
      // The dedup key is the URL: the two providers share it, and it is what
      // `CachedNetworkImageProvider.==` decides identity on.
      expect(
        _cacheKeyOf(images.first.image),
        _kAvatarA,
        reason: 'the cache key must be the avatar URL, not a per-card value',
      );
      expect(
        _cacheKeyOf(images.first.image),
        _cacheKeyOf(images.last.image),
        reason: 'same client ⇒ same URL ⇒ same cache key ⇒ one fetch',
      );
    });

    testWidgets('two bookings with DIFFERENT clients do NOT collide — the '
        'equality above is real, not a degenerate always-equal', (
      WidgetTester tester,
    ) async {
      await tester.pumpApp(
        Column(
          children: <Widget>[
            _card(_booking(id: 'morning', avatarUrl: _kAvatarA)),
            _card(_booking(id: 'afternoon', avatarUrl: _kAvatarB)),
          ],
        ),
      );
      await tester.pump();

      final List<Image> images = tester
          .widgetList<Image>(find.byType(Image))
          .toList();
      expect(images, hasLength(2));
      expect(
        images.first.image,
        isNot(equals(images.last.image)),
        reason:
            'distinct avatar URLs must key distinct cache entries, or one '
            'client would render another client\'s photo',
      );
      expect(
        _cacheKeyOf(images.first.image),
        isNot(_cacheKeyOf(images.last.image)),
        reason: 'distinct clients ⇒ distinct URLs ⇒ distinct cache keys',
      );
    });

    testWidgets('a PRESS rebuild hands back an `==` provider, so `Image` skips '
        'resolve entirely and never refetches', (WidgetTester tester) async {
      await tester.pumpApp(
        Center(
          child: _card(_booking(id: 'pressed', avatarUrl: _kAvatarA)),
        ),
      );
      await tester.pump();

      final ImageProvider<Object> before = tester
          .widget<Image>(find.byType(Image))
          .image;

      // `onTapDown` flips `_pressed` and `setState`s, rebuilding the whole
      // card subtree — the mark included — on every touch of every card.
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(MasterBookingCard)),
      );
      await tester.pump();

      final ImageProvider<Object> pressed = tester
          .widget<Image>(find.byType(Image))
          .image;
      expect(
        pressed,
        equals(before),
        reason:
            '`_ImageState.didUpdateWidget` skips `_resolveImage()` only when '
            '`widget.image == oldWidget.image`. An unequal provider here '
            'means every touch re-resolves — and on a cache miss, refetches.',
      );

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.widget<Image>(find.byType(Image)).image,
        equals(before),
        reason: 'releasing the press must not churn the provider either',
      );
    });
  });
}
