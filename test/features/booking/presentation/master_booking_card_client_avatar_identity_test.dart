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
// ## CORRECTION — `headers:` IS part of the key (recorded 2026-07-24)
//
// An earlier QA pass on this file recorded that passing `headers:` to
// `NetworkImage` "would NOT defeat dedupe, because `NetworkImage.==` compares
// only `url` and `scale`". That is WRONG on this project's Flutter (3.41.9,
// framework rev `00b0c91f06`). `painting/_network_image_io.dart:163-176`:
//
//     return other is NetworkImage &&
//         other.url == url &&
//         other.scale == scale &&
//         mapEquals(other.headers, headers);
//
//     int get hashCode =>
//         Object.hash(url, scale, const MapEquality<String, String>().hash(headers));
//
// Headers participate in BOTH `==` and `hashCode`, by VALUE. So a header map
// whose contents vary per card or per rebuild — a rotated bearer token, a
// per-request nonce, a signed-URL parameter — keys a DISTINCT `ImageCache`
// entry every time, and every card refetches and re-decodes the same avatar.
// (A map with identical contents everywhere is still `==`; it is variance that
// costs, and an auth header is exactly the kind that varies.)
//
// No live defect: nothing passes `headers:` anywhere today, because
// `clientAvatarUrl` is a PUBLIC R2 object URL. This note exists so the earlier
// claim cannot later be read as licence to attach an `Authorization` header
// here if those objects ever stop being public. If they do, the fix is a
// shared pinned-image loader with a stable key — not a per-card header map.
//
// NOT ASSERTED HERE: fetch COUNTS. Counting real loads would need a stubbed
// `HttpClient` plus `runAsync`, would re-enter the shared-`_sharedHttpClient`
// trap documented in the sibling file, and would still only be measuring the
// framework's own cache. The provider key is the contract; the cache is
// Flutter's.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';

import '../../../helpers/pump_app.dart';

const String _kAvatarA = 'https://cdn.example.com/avatars/client-1.png';
const String _kAvatarB = 'https://cdn.example.com/avatars/client-2.png';

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

void main() {
  group('the row-1 mark\'s ImageProvider is the ImageCache key — it must be '
      'value-equal, or every card refetches', () {
    testWidgets('two DIFFERENT bookings sharing one client resolve to the '
        'SAME provider — one fetch, one decode, shared', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
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
              'client MUST hand it an `==` provider — otherwise the same '
              'avatar is fetched and decoded once per booking. A per-instance '
              'key, a non-value-equal provider or a per-card cacheWidth all '
              'break this silently: the photo still renders correctly.',
        );
        expect(
          images.first.image.hashCode,
          images.last.image.hashCode,
          reason:
              'the cache is a HashMap — equal providers with unequal hashCodes '
              'still miss',
        );
      });
    });

    testWidgets('two bookings with DIFFERENT clients do NOT collide — the '
        'equality above is real, not a degenerate always-equal', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
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
      });
    });

    testWidgets('a PRESS rebuild hands back an `==` provider, so `Image` skips '
        'resolve entirely and never refetches', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
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
  });
}
