// The row-1 client mark's DECODE + ANIMATION contract — the pin behind
// `_ClientAvatarMark`'s "MEMORY" and "ANIMATED SOURCES" doc sections
// (2026-07-24, mobile-perf LOW).
//
// ## WHY THIS FILE EXISTS SEPARATELY FROM ITS TWO SIBLINGS
//
// `master_booking_card_client_avatar_test.dart` pins the 16dp FOOTPRINT and
// says so — "the ring, the clip and the fit are design choices"; it asserts
// nothing about how the bytes get decoded.
// `master_booking_card_client_avatar_identity_test.dart` pins provider
// EQUALITY — whether two cards share one `ImageCache` entry. Neither can see
// the two invariants below, because both survive every assertion in both
// files while being wrong.
//
// ## THE ONE EDIT THAT REINTRODUCES BOTH DEFECTS
//
// `_ClientAvatarMark` deliberately spells its provider out:
//
//     Image(image: ResizeImage(NetworkImage(url),
//                              width: side, height: side,
//                              policy: ResizeImagePolicy.fit), …)
//
// wrapped in `TickerMode(enabled: false)`. That reads as ceremony, and the
// obvious "simplification" is one line:
//
//     Image.network(url, cacheWidth: side, cacheHeight: side, …)
//
// which silently reintroduces BOTH of the findings the long shape was written
// to answer:
//
//   1. **Animated WebP resumes its loop.** Dropping the `TickerMode` wrapper
//      lets a multi-frame codec's `MultiFrameImageStreamCompleter` re-arm its
//      frame `Timer` forever, driving a `setState` + repaint in EVERY card
//      showing that client, all day, for a decorative 16dp disc. Reachable
//      today: the backend accepts `image/webp`, sniffs MIME from magic bytes
//      and neither transcodes nor re-encodes, and animated WebP shares the
//      RIFF/WEBP signature with still WebP.
//   2. **Non-square avatars get squashed.** `Image.network`'s
//      `cacheWidth`/`cacheHeight` sugar hard-codes `ResizeImagePolicy.exact`,
//      and `exact` with BOTH axes bound is `BoxFit.fill` at DECODE time — the
//      aspect ratio is destroyed before the widget's `BoxFit.cover` ever sees
//      the bitmap. Non-square is the NORM here: avatars are uploaded through
//      `file_picker` with no crop step and stored byte-for-byte.
//
// MUTATION-VERIFIED (QA, 2026-07-24): with `_ClientAvatarMark` reverted to
// exactly that `Image.network(url, cacheWidth: side, cacheHeight: side, …)`
// one-liner, BOTH tests below go red and EVERY OTHER TEST in
// `test/features/booking/` stays green — including all four footprint states
// (the box is still 16dp) and both identity tests (two `NetworkImage`s are
// still `==` to each other, so dedupe still holds; it is the decode SHAPE and
// the animation that are lost, and only this file sees either).
//
// NOT ASSERTED HERE: the decoded pixels. Proving a 3:4 source is not squashed
// end-to-end would need a real multi-frame/non-square codec through
// `runAsync`. The provider's policy and bounds ARE the contract — they are
// what `ResizeImage.resolve` keys the decode off — and the ticker mode is
// what `_ImageState` reads in `didChangeDependencies` to decide whether to
// keep listening past frame 0.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';

import '../../../helpers/pump_app.dart';

const String _kAvatar = 'https://cdn.example.com/avatars/client-1.png';

Booking _booking() {
  // future-date-ok: pinned wall-clock fixture; nothing here reads "now".
  final DateTime startAt = DateTime.utc(2026, 7, 20, 6); // 09:00 Kyiv
  return Booking(
    id: 'decode-fixture',
    masterId: 'master-1',
    masterFirstName: 'Olha',
    masterLastName: 'Koval',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Mariia',
    clientLastName: 'Ivaniuk',
    clientAvatarUrl: _kAvatar,
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

/// Pumps the FULL body (the only layout with a row-1 mark) and returns the
/// mark's `Image`. No `runAsync`: neither assertion needs a decoded frame —
/// the provider and the ticker mode are both readable from the built tree.
Future<Image> _pumpMark(WidgetTester tester) async {
  await tester.pumpApp(
    Center(
      child: SizedBox(
        width: 226,
        child: MasterBookingCard(
          booking: _booking(),
          onTap: () {},
          minHeight: MasterBookingCard.fullLayoutMinHeight,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(
    find.byType(Image),
    findsOneWidget,
    reason: 'precondition: an https URL must reach the row-1 mark\'s Image',
  );
  return tester.widget<Image>(find.byType(Image));
}

void main() {
  group('the row-1 mark decodes through ResizeImage — bounded on BOTH axes, '
      'and by `fit` so non-square avatars are not squashed', () {
    testWidgets('the provider is a ResizeImage with policy `fit` and both '
        'width and height bound', (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final Image image = await _pumpMark(tester);

        final ImageProvider<Object> provider = image.image;
        expect(
          provider,
          isA<ResizeImage>(),
          reason:
              'a bare NetworkImage decodes the R2 object at its NATIVE '
              'resolution into a 16dp disc — the whole point of the explicit '
              'provider is that the decode is bounded',
        );

        final ResizeImage resize = provider as ResizeImage;
        expect(
          resize.policy,
          ResizeImagePolicy.fit,
          reason:
              '`Image.network`\'s cacheWidth/cacheHeight sugar hard-codes '
              '`ResizeImagePolicy.exact`, which with both axes bound is '
              'BoxFit.fill at DECODE time: a 3:4 phone photo is squashed into '
              'a square before the widget\'s BoxFit.cover ever sees it. '
              'Avatars are uploaded via file_picker with no crop step and '
              'stored byte-for-byte, so non-square sources are the norm. '
              'Reaching `fit` is the ONLY reason the provider is spelled out '
              'instead of using the one-line sugar — see _ClientAvatarMark\'s '
              'MEMORY doc section.',
        );

        expect(
          resize.width,
          isNotNull,
          reason: 'an unbounded width decodes at the source\'s native size',
        );
        expect(
          resize.height,
          isNotNull,
          reason:
              'height must be bound TOO. ResizeImagePolicy constrains only '
              'the axes it is given, so with width alone a 1:10 source decodes '
              'to side x 10*side — an order of magnitude over budget — and '
              'BoxFit.cover then throws almost all of it away. Both axes make '
              'the ceiling (16 * dpr)^2 * 4 bytes REGARDLESS of source shape.',
        );
        expect(
          resize.width,
          greaterThan(0),
          reason: 'a zero/negative bound is not a bound',
        );
        expect(
          resize.height,
          resize.width,
          reason:
              'the disc is square, so the decode budget is square — an '
              'asymmetric pair means one axis stopped tracking _kSize',
        );
      });
    });
  });

  group('the row-1 mark is pinned to frame 0 — an animated WebP must not '
      'drive a repaint loop in every card showing that client', () {
    testWidgets('the Image sits under a disabled TickerMode, and the '
        'EFFECTIVE ticker mode at its own context is false', (
      WidgetTester tester,
    ) async {
      await mockNetworkImagesFor(() async {
        await _pumpMark(tester);

        // The structural half: the widget itself installs the disable. A
        // route- or app-level disable would satisfy the behavioural half
        // below by accident, so this pins WHERE it comes from.
        expect(
          find.descendant(
            of: find.byType(MasterBookingCard),
            matching: find.byWidgetPredicate(
              (Widget w) => w is TickerMode && !w.enabled,
            ),
          ),
          findsOneWidget,
          reason:
              'the mark must wrap its Image in TickerMode(enabled: false). '
              'Without it a multi-frame codec re-arms its frame Timer forever '
              '(repetitionCount == -1), and every card listening to that '
              'completer takes a setState + repaint per frame, all day, for a '
              'decorative 16dp disc. The backend accepts image/webp, sniffs '
              'MIME from magic bytes and never transcodes, so animated '
              'avatars are already reachable — see ANIMATED SOURCES.',
        );

        // The behavioural half, read the way the framework reads it:
        // `_ImageState.didChangeDependencies` resolves the ambient ticker mode
        // at the Image's own context (`widgets/image.dart:1151`) and, on the
        // first delivered frame, calls
        // `_stopListeningToStream(keepStreamAlive: true)` when it is false.
        // `valuesOf(...).enabled` rather than the framework's own
        // `TickerMode.of` only because the latter is deprecated post-3.35 —
        // same resolved value, same inherited widget.
        expect(
          TickerMode.valuesOf(tester.element(find.byType(Image))).enabled,
          isFalse,
          reason:
              'whatever the tree shape, the ticker mode RESOLVED at the '
              'Image\'s own context is what _ImageState acts on — a disabled '
              'TickerMode placed somewhere that does not enclose the Image '
              'would satisfy the structural check above and still animate',
        );
      });
    });
  });
}
