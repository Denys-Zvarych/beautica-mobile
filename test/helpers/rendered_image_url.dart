// Test helper — the URLs of the network images a subtree ACTUALLY renders.
//
// Asserts on the rendered `ImageProvider` (unwrapping `ResizeImage` down to the
// `CachedNetworkImageProvider`), not on a widget field: a widget-field assert
// is vacuous because it passes even when the image never reaches the screen.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// URLs of every [Image] under [within] (whole tree when null), in tree order.
List<String> renderedImageUrls(WidgetTester tester, {Finder? within}) {
  final Finder images = within == null
      ? find.byType(Image)
      : find.descendant(of: within, matching: find.byType(Image));
  return <String>[
    for (final Image image in tester.widgetList<Image>(images))
      ?_urlOf(image.image),
  ];
}

/// Asserts [card] is BUILT and renders the avatar fallback: no network image
/// and the person glyph. The existence check is load-bearing — a bare
/// `renderedImageUrls(within: card)` is `isEmpty` for an ABSENT card too, so
/// without it the fallback assertion passes vacuously (M14).
void expectAvatarFallback(WidgetTester tester, Finder card) {
  expect(card, findsOneWidget, reason: 'the fallback card must be built');
  expect(renderedImageUrls(tester, within: card), isEmpty);
  expect(
    find.descendant(of: card, matching: find.byIcon(Icons.person_rounded)),
    findsOneWidget,
    reason: 'the fallback is the gradient + person glyph',
  );
}

String? _urlOf(ImageProvider provider) {
  ImageProvider current = provider;
  while (current is ResizeImage) {
    current = current.imageProvider;
  }
  return current is CachedNetworkImageProvider ? current.url : null;
}
