// Phase 407 (9.12) — the full-screen portfolio photo viewer
// (lib/shared/widgets/portfolio_photo_viewer.dart).
//
//   • opens on the requested index (via the real `showPortfolioPhotoViewer`
//     route helper) and pages by swipe, the «n / N» indicator following;
//   • close button and the system back both pop it;
//   • ZOOM vs PAGING: zoomed in, a horizontal drag pans the photo and does NOT
//     page; pinched back to 1, swipes page again;
//   • D5 / allowlist: only allow-listed URLs reach the network; a broken or
//     off-allowlist URL shows the fallback glyph; no semantics node carries a
//     URL; the decode is capped at the screen box;
//   • a11y: close button label, «Фото n з N» indicator announcement, page
//     label «Фото роботи n».

import 'dart:async';

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart'
    show kPortfolioMaxPhotos;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/rendered_image_url.dart';

/// UA copy resolved from the ARB (no Cyrillic literals in finders).
final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const List<PortfolioPhoto> _photos = <PortfolioPhoto>[
  PortfolioPhoto(id: 'p1', url: 'https://media.test/1.webp'),
  PortfolioPhoto(id: 'p2', url: 'https://media.test/2.webp'),
  PortfolioPhoto(id: 'p3', url: 'https://media.test/3.webp'),
];

/// An allow-listed photo whose fetch a test makes fail.
const PortfolioPhoto _broken = PortfolioPhoto(
  id: 'broken',
  url: 'https://media.test/broken.webp',
);

const Key _open = Key('open-viewer');

final Finder _viewer = find.byType(PortfolioPhotoViewer);
final Finder _pager = find.byKey(PortfolioPhotoViewer.pagerKey);

Finder _page(String id) => find.byKey(PortfolioPhotoViewer.pageKey(id));

String _counter(int n, int total) => _l10n.portfolioViewerCounter(n, total);

/// The «n / N» text INSIDE the indicator pill (Q2 — never an unscoped
/// `find.text`, which any other «2 / 3» on screen would satisfy).
Finder _counterText(int n, int total) => find.descendant(
  of: find.byKey(PortfolioPhotoViewer.indicatorKey),
  matching: find.text(_counter(n, total)),
);

/// A host screen whose button opens the viewer through the production helper
/// (so the route — fullscreen dialog on the root navigator — is under test).
Future<void> _pumpHost(
  WidgetTester tester, {
  List<PortfolioPhoto> photos = _photos,
  int initialIndex = 0,
  PortfolioPhotoReportCallback? onReport,
}) async {
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            key: _open,
            onPressed: () => showPortfolioPhotoViewer(
              context,
              photos,
              initialIndex,
              onReport: onReport,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
}

/// Scale of the [InteractiveViewer] on the page of photo [id].
double _scaleOf(WidgetTester tester, String id) {
  final InteractiveViewer iv = tester.widget<InteractiveViewer>(
    find.descendant(of: _page(id), matching: find.byType(InteractiveViewer)),
  );
  final TransformationController? c = iv.transformationController;
  expect(c, isNotNull);
  return c?.value.getMaxScaleOnAxis() ?? 0;
}

/// The indicator pill's semantics label («Фото n з N»).
String _indicatorLabel(WidgetTester tester) => tester
    .getSemantics(find.byKey(PortfolioPhotoViewer.indicatorKey))
    .getSemanticsData()
    .label;

/// The page controller's current page (fractional mid-drag).
double? _pagerPage(WidgetTester tester) =>
    tester.widget<PageView>(_pager).controller?.page;

/// The [InteractiveViewer] transformation of the page of photo [id].
TransformationController? _transformOf(WidgetTester tester, String id) => tester
    .widget<InteractiveViewer>(
      find.descendant(of: _page(id), matching: find.byType(InteractiveViewer)),
    )
    .transformationController;

/// Runs [steps] pointer-move steps, one frame each; [afterFrame] (the
/// per-step assertion, if any) runs after each step's frame.
Future<void> _paced(
  WidgetTester tester,
  int steps,
  Future<void> Function(int i) move, [
  void Function(int i)? afterFrame,
]) async {
  for (int i = 0; i < steps; i++) {
    await move(i);
    // fixed-wait-ok: one frame per pointer-move step (gesture pacing, not
    // a wait for async work — a gesture has no completion to poll for).
    await tester.pump(const Duration(milliseconds: 16));
    afterFrame?.call(i);
  }
}

/// Puts two fingers down (pointers 7 and 8) at [a] and [b], then a frame.
Future<(TestGesture, TestGesture)> _twoFingers(
  WidgetTester tester,
  Offset a,
  Offset b,
) async {
  final TestGesture first = await tester.startGesture(a, pointer: 7);
  final TestGesture second = await tester.startGesture(b, pointer: 8);
  await tester.pump();
  return (first, second);
}

/// Lifts every finger in [fingers] and settles.
Future<void> _lift(WidgetTester tester, List<TestGesture> fingers) async {
  for (final TestGesture f in fingers) {
    await f.up();
  }
  await tester.pumpAndSettle();
}

/// A two-finger pinch around the screen centre, from [fromGap] to [toGap]
/// apart along [axis] (a unit vector). VERTICAL by default, so the pager's
/// horizontal drag recognizer never sees horizontal travel — only the scale
/// recognizer can claim it; pass a horizontal [axis] to make the pinch
/// compete with the pager.
Future<void> _pinch(
  WidgetTester tester, {
  required double fromGap,
  required double toGap,
  Offset axis = const Offset(0, 1),
}) async {
  final Offset c = tester.getCenter(_pager);
  final (TestGesture a, TestGesture b) = await _twoFingers(
    tester,
    c - axis * (fromGap / 2),
    c + axis * (fromGap / 2),
  );
  const int steps = 10;
  final double stepDelta = (toGap - fromGap) / 2 / steps;
  await _paced(tester, steps, (int _) async {
    await a.moveBy(-axis * stepDelta);
    await b.moveBy(axis * stepDelta);
  });
  await _lift(tester, <TestGesture>[a, b]);
}

void main() {
  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });

  group('open / page / close', () {
    testWidgets('opens on initialIndex: that page is shown, the indicator '
        'reads «2 / 3», and the page renders THAT photo', (tester) async {
      await _pumpHost(tester, initialIndex: 1);

      expect(_viewer, findsOneWidget);
      expect(_counterText(2, 3), findsOneWidget);
      expect(_page('p2').hitTestable(), findsOneWidget);
      expect(renderedImageUrls(tester, within: _page('p2')), <String>[
        _photos[1].url,
      ]);
    });

    testWidgets('swiping pages forward and back; the indicator follows', (
      tester,
    ) async {
      await _pumpHost(tester);
      expect(_counterText(1, 3), findsOneWidget);

      await tester.fling(_pager, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(_counterText(2, 3), findsOneWidget);
      expect(_page('p2').hitTestable(), findsOneWidget);

      await tester.fling(_pager, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(_counterText(3, 3), findsOneWidget);

      await tester.fling(_pager, const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(_counterText(2, 3), findsOneWidget);
    });

    testWidgets('the close button pops back to the opener', (tester) async {
      await _pumpHost(tester);
      await tester.tap(find.byKey(PortfolioPhotoViewer.closeKey));
      await tester.pumpAndSettle();
      expect(_viewer, findsNothing);
      expect(find.byKey(_open), findsOneWidget);
    });

    testWidgets('the system back pops it (a plain route — no go_router '
        'entry to unwind)', (tester) async {
      await _pumpHost(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_viewer, findsNothing);
      expect(find.byKey(_open), findsOneWidget);
    });

    testWidgets('an out-of-range initialIndex is clamped (no throw)', (
      tester,
    ) async {
      await _pumpHost(tester, initialIndex: 9);
      expect(_counterText(3, 3), findsOneWidget);
    });

    testWidgets('a negative initialIndex is clamped to the first photo', (
      tester,
    ) async {
      await _pumpHost(tester, initialIndex: -3);
      expect(_counterText(1, 3), findsOneWidget);
      expect(_page('p1').hitTestable(), findsOneWidget);
    });

    testWidgets('an EMPTY list (a rail tapped while its data is gone) opens '
        'without an indicator or page, and close still pops', (tester) async {
      await _pumpHost(tester, photos: const <PortfolioPhoto>[]);
      expect(_viewer, findsOneWidget);
      expect(find.byKey(PortfolioPhotoViewer.indicatorKey), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
      await tester.tap(find.byKey(PortfolioPhotoViewer.closeKey));
      await tester.pumpAndSettle();
      expect(_viewer, findsNothing);
      expect(find.byKey(_open), findsOneWidget);
    });

    testWidgets('the helper caps the list at kPortfolioMaxPhotos, like the '
        'rail', (tester) async {
      await _pumpHost(
        tester,
        photos: <PortfolioPhoto>[
          for (int i = 0; i < kPortfolioMaxPhotos + 5; i++)
            PortfolioPhoto(id: 'x$i', url: 'https://media.test/$i.webp'),
        ],
      );
      expect(_counterText(1, kPortfolioMaxPhotos), findsOneWidget);
    });
  });

  group('zoom vs paging', () {
    testWidgets('zoomed in, a horizontal drag pans the photo and does NOT '
        'page; pinched back to 1, a swipe pages again', (tester) async {
      await _pumpHost(tester, initialIndex: 1);
      expect(_scaleOf(tester, 'p2'), 1);

      await _pinch(tester, fromGap: 100, toGap: 300);
      final double zoomed = _scaleOf(tester, 'p2');
      expect(zoomed, greaterThan(1.5), reason: 'the pinch zoomed in');
      final Matrix4 before = Matrix4.copy(
        _transformOf(tester, 'p2')?.value ?? Matrix4.zero(),
      );

      await tester.drag(_pager, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(_counterText(2, 3), findsOneWidget, reason: 'no paging');
      expect(_page('p2').hitTestable(), findsOneWidget);
      final Matrix4 after = _transformOf(tester, 'p2')?.value ?? Matrix4.zero();
      expect(
        after.getTranslation().x,
        lessThan(before.getTranslation().x),
        reason: 'the drag panned the zoomed photo left',
      );

      // Pinch back out to (at most) scale 1 — snaps to identity.
      await _pinch(tester, fromGap: 300, toGap: 60);
      expect(_scaleOf(tester, 'p2'), 1);

      await tester.fling(_pager, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(_counterText(3, 3), findsOneWidget, reason: 'pages again');
    });

    testWidgets('at scale 1 the InteractiveViewer does not swallow a swipe '
        '(paging works from the first frame)', (tester) async {
      await _pumpHost(tester);
      await tester.drag(_pager, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(_counterText(2, 3), findsOneWidget);
      expect(_scaleOf(tester, 'p2'), 1);
    });
  });

  // QA finding F1 (phase 407, MEDIUM) — the page's InteractiveViewer scale
  // recognizer joins the gesture arena BEFORE the pager's horizontal drag
  // recognizer, so a swipe whose first sample after touch-down crosses BOTH
  // the drag slop (18) and the pan slop (36) is won by the zoom surface (a
  // no-op pan at scale 1) and the pager never turns. Measured 2026-10-13: a
  // first sample of 20 / 30 px pages; 10 (then 50), 40 or 60 px does not.
  // A real fast flick on a low-rate touch panel produces exactly that.
  // Fixed in the audit-fix pass: at scale 1 the page's pan slop is infinite.
  testWidgets(
    'a fast swipe whose first sample overshoots the pan slop still pages',
    (tester) async {
      await _pumpHost(tester);
      for (final double first in <double>[40, 60]) {
        final int before = tester
            .widget<PageView>(_pager)
            .controller!
            .page!
            .round();
        final TestGesture g = await tester.startGesture(
          tester.getCenter(_pager),
        );
        await g.moveBy(Offset(-first, 0));
        // fixed-wait-ok: one frame per pointer-move step (gesture pacing).
        await tester.pump(const Duration(milliseconds: 16));
        for (int i = 0; i < 8; i++) {
          await g.moveBy(const Offset(-50, 0));
          // fixed-wait-ok: one frame per pointer-move step (gesture pacing).
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pumpAndSettle();
        expect(
          _counterText(before + 2, 3),
          findsOneWidget,
          reason: 'a ${first}px first sample must still page',
        );
      }
    },
  );

  testWidgets('pinch-to-zoom still starts from scale 1 (the scale-1 pan '
      'slop does not block a pinch) and the pinch never pages', (tester) async {
    await _pumpHost(tester);
    expect(_scaleOf(tester, 'p1'), 1);

    await _pinch(tester, fromGap: 80, toGap: 260);

    expect(_scaleOf(tester, 'p1'), greaterThan(1.5));
    expect(_counterText(1, 3), findsOneWidget);
    expect(_page('p1').hitTestable(), findsOneWidget);
  });

  // A real pinch is rarely vertical: two fingers spreading SIDEWAYS move
  // horizontally, which is exactly what the pager's drag recognizer listens
  // for. The vertical pinch above cannot tell whether the pager would steal
  // it; this one competes with the pager head-on.
  testWidgets('a HORIZONTAL pinch from scale 1 zooms and does not page', (
    tester,
  ) async {
    await _pumpHost(tester, initialIndex: 1);
    expect(_scaleOf(tester, 'p2'), 1);

    await _pinch(tester, fromGap: 80, toGap: 260, axis: const Offset(1, 0));

    expect(_scaleOf(tester, 'p2'), greaterThan(1.5));
    expect(_counterText(2, 3), findsOneWidget, reason: 'no paging');
    expect(_page('p2').hitTestable(), findsOneWidget);
  });

  // QA re-check (phase 407, MEDIUM, open) — a pinch with one finger
  // ANCHORED and the other spreading sideways (thumb still, index finger
  // moving) is lost to the pager. The scale recognizer accepts only on a span
  // change > kScaleSlop (18), and an anchored pinch changes the span by HALF
  // the moving finger's travel, while the pager's drag recognizer accepts on
  // 18 px of travel — so the pager always claims it first and the photo never
  // zooms. Pre-existing (identical with the pre-F1 default pan slop); the
  // symmetric pinch above passes only because its two drag deltas cancel.
  // Fixed (M1): the pager is NeverScrollable while 2+ pointers are down.
  testWidgets(
    'a pinch with one finger anchored and the other spreading sideways '
    'zooms and does not drag the pager',
    (tester) async {
      await _pumpHost(tester, initialIndex: 1);
      final Offset c = tester.getCenter(_pager);
      final (TestGesture anchored, TestGesture spreading) = await _twoFingers(
        tester,
        c - const Offset(40, 0),
        c + const Offset(40, 0),
      );
      await _paced(
        tester,
        30,
        (int _) => spreading.moveBy(const Offset(6, 0)),
        (int i) => expect(
          _pagerPage(tester),
          1,
          reason: 'the pager must not move during a pinch (step $i)',
        ),
      );
      await _lift(tester, <TestGesture>[anchored, spreading]);

      expect(_scaleOf(tester, 'p2'), greaterThan(1.5));
      expect(_counterText(2, 3), findsOneWidget);
    },
  );

  // M1 edge — a one-finger swipe has ALREADY won the arena and is moving the
  // pager when a second finger lands. The 2-pointer NeverScrollable switch
  // must cancel that in-flight drag: the pager settles back on its page and
  // the fingers' further travel never pages. The second finger MOVES (the
  // user spreads a pinch): under the default `latestPointer` multitouch
  // strategy an uncancelled drag follows THAT finger, so a stationary
  // second finger would pass with or without the fix (mutation-checked).
  testWidgets('a second finger landing mid-swipe cancels the swipe: the '
      'pager settles back and the spreading fingers do not page', (
    tester,
  ) async {
    await _pumpHost(tester, initialIndex: 1);
    final Offset c = tester.getCenter(_pager);
    final TestGesture first = await tester.startGesture(c, pointer: 7);
    await _paced(tester, 4, (int _) => first.moveBy(const Offset(-30, 0)));
    final double midSwipe = _pagerPage(tester) ?? 0;
    expect(midSwipe, greaterThan(1), reason: 'precondition: drag in flight');

    final TestGesture second = await tester.startGesture(
      c + const Offset(0, 120),
      pointer: 8,
    );
    await tester.pump();
    await _paced(
      tester,
      10,
      (int _) async {
        await first.moveBy(const Offset(-40, 0));
        await second.moveBy(const Offset(40, 0));
      },
      (int i) => expect(
        _pagerPage(tester),
        inInclusiveRange(1, midSwipe),
        reason: 'the cancelled drag follows neither finger (step $i)',
      ),
    );
    await _lift(tester, <TestGesture>[first, second]);

    expect(_pagerPage(tester), 1);
    expect(_counterText(2, 3), findsOneWidget, reason: 'no page turn');
  });

  // M3 — a pinch that ends barely above 1 (inside the 0.01 "not zoomed"
  // epsilon) must snap to IDENTITY, not leave a 1.005 matrix behind.
  testWidgets('a pinch released at ~1.005 snaps to the identity matrix and '
      'the next swipe pages', (tester) async {
    await _pumpHost(tester);
    final Offset c = tester.getCenter(_pager);
    final (TestGesture a, TestGesture b) = await _twoFingers(
      tester,
      c - const Offset(0, 50),
      c + const Offset(0, 50),
    );
    // Spread 100 → 140 (past the scale slop), then back to 100.5 → 1.005.
    const List<double> steps = <double>[5, 5, 5, 5, -5, -5, -5, -4.75];
    await _paced(tester, steps.length, (int i) async {
      await a.moveBy(Offset(0, -steps[i]));
      await b.moveBy(Offset(0, steps[i]));
    });
    final TransformationController? t = _transformOf(tester, 'p1');
    final double held = t?.value.getMaxScaleOnAxis() ?? 0;
    expect(held, greaterThan(1.0001), reason: 'precondition: mid-pinch > 1');
    expect(held, lessThan(1.01), reason: 'precondition: inside the epsilon');

    await _lift(tester, <TestGesture>[a, b]);

    expect(t?.value, Matrix4.identity());
    await tester.fling(_pager, const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(_counterText(2, 3), findsOneWidget);
  });

  group('image cache (perf P1 / P2)', () {
    /// Whether the viewer-sized decode of [url] is in the ImageCache (pending,
    /// completed or live). The key is built from the SAME provider the pages
    /// resolve, at the screen box × DPR.
    Future<bool> cachedAtScreen(
      WidgetTester tester,
      String url, {
      Size? physicalBox,
    }) async {
      final Size physical = physicalBox ?? tester.view.physicalSize;
      final Object key = await beauticaResizedProvider(
        url,
        physical.width.round(),
        physical.height.round(),
      ).obtainKey(ImageConfiguration.empty);
      return PaintingBinding.instance.imageCache.containsKey(key);
    }

    tearDown(() => PaintingBinding.instance.imageCache.clear());

    /// [n] photos whose URLs are UNIQUE to [tag]. The previous test's viewer
    /// is disposed only when the next test pumps its own tree (after this
    /// group's tearDown has run), so a decode it failed to evict lands in the
    /// NEXT test's cache. Per-test URLs keep such a leak from failing — or
    /// satisfying — another test's assertions: each test answers only for
    /// its own viewer.
    List<PortfolioPhoto> photosFor(String tag, int n) => <PortfolioPhoto>[
      for (int i = 0; i < n; i++)
        PortfolioPhoto(id: 'q$i', url: 'https://media.test/$tag-$i.webp'),
    ];

    testWidgets('R1 — paging away evicts decodes further than ±1 from the '
        'shown page; the shown page and its neighbours stay cached', (
      tester,
    ) async {
      final List<PortfolioPhoto> six = photosFor('r1', 6);
      await _pumpHost(tester, photos: six);
      expect(await cachedAtScreen(tester, six[0].url), isTrue);
      expect(await cachedAtScreen(tester, six[1].url), isTrue);

      for (int i = 0; i < 3; i++) {
        await tester.fling(_pager, const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();
      }
      expect(_counterText(4, 6), findsOneWidget);
      expect(_page('q3').hitTestable(), findsOneWidget);

      expect(await cachedAtScreen(tester, six[0].url), isFalse);
      expect(await cachedAtScreen(tester, six[1].url), isFalse);
      for (final int keep in <int>[2, 3, 4]) {
        expect(
          await cachedAtScreen(tester, six[keep].url),
          isTrue,
          reason: 'index $keep is the shown page or a neighbour',
        );
      }
      expect(await cachedAtScreen(tester, six[5].url), isFalse);
    });

    testWidgets('M2 — a DPR change at the SAME logical size re-precaches ±1 '
        'at the new pixel key and drops the old keys', (tester) async {
      final Size before = tester.view.physicalSize;
      final double dpr = tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final List<PortfolioPhoto> six = photosFor('m2', 6);
      await _pumpHost(tester, photos: six, initialIndex: 2);
      for (final int n in <int>[1, 2, 3]) {
        expect(await cachedAtScreen(tester, six[n].url), isTrue);
      }

      const double newDpr = 2;
      final Size after = before / dpr * newDpr;
      tester.view
        ..devicePixelRatio = newDpr
        ..physicalSize = after;
      await tester.pumpAndSettle();
      expect(_counterText(3, 6), findsOneWidget, reason: 'no page turn');

      for (final int n in <int>[1, 2, 3]) {
        expect(
          await cachedAtScreen(tester, six[n].url, physicalBox: after),
          isTrue,
          reason: 'index $n at the new DPR',
        );
        expect(
          await cachedAtScreen(tester, six[n].url, physicalBox: before),
          isFalse,
          reason: 'index $n at the old DPR is evicted',
        );
      }
    });

    testWidgets('R2 — a box change (rotation) re-precaches ±1 at the NEW '
        'decode key without waiting for a page turn, and drops the old '
        'box\'s decodes', (tester) async {
      final Size before = tester.view.physicalSize;
      addTearDown(tester.view.resetPhysicalSize);
      final List<PortfolioPhoto> six = photosFor('r2', 6);
      await _pumpHost(tester, photos: six, initialIndex: 2);
      for (final int n in <int>[1, 2, 3]) {
        expect(await cachedAtScreen(tester, six[n].url), isTrue);
      }

      final Size rotated = Size(before.height, before.width);
      tester.view.physicalSize = rotated;
      await tester.pumpAndSettle();
      expect(_counterText(3, 6), findsOneWidget, reason: 'no page turn');

      for (final int n in <int>[1, 2, 3]) {
        expect(
          await cachedAtScreen(tester, six[n].url, physicalBox: rotated),
          isTrue,
          reason: 'index $n at the rotated box',
        );
        expect(
          await cachedAtScreen(tester, six[n].url, physicalBox: before),
          isFalse,
          reason: 'index $n at the old box is evicted',
        );
      }
    });

    testWidgets('the shown page\'s neighbours are precached at the pages\' '
        'decode key; a page turn warms the next one', (tester) async {
      final List<PortfolioPhoto> four = photosFor('p2', 4);
      await _pumpHost(tester, photos: four, initialIndex: 1);

      expect(await cachedAtScreen(tester, four[0].url), isTrue);
      expect(await cachedAtScreen(tester, four[1].url), isTrue);
      expect(await cachedAtScreen(tester, four[2].url), isTrue);
      expect(
        await cachedAtScreen(tester, four[3].url),
        isFalse,
        reason: 'only ±1 is warmed',
      );

      await tester.fling(_pager, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(_counterText(3, 4), findsOneWidget);
      expect(await cachedAtScreen(tester, four[3].url), isTrue);
    });

    testWidgets('closing the viewer evicts every decode it caused (pages + '
        'precached neighbours) and nothing else', (tester) async {
      // A rail-sized decode of the same photo — not the viewer's; must stay.
      final List<PortfolioPhoto> three = photosFor('p1', 3);
      final ImageCache cache = PaintingBinding.instance.imageCache;
      final Object railKey = await beauticaResizedProvider(
        three[0].url,
        96,
        96,
      ).obtainKey(ImageConfiguration.empty);
      cache.putIfAbsent(
        railKey,
        () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future),
      );

      await _pumpHost(tester, photos: three, initialIndex: 1);
      for (final PortfolioPhoto p in three) {
        expect(await cachedAtScreen(tester, p.url), isTrue, reason: p.id);
      }

      await tester.tap(find.byKey(PortfolioPhotoViewer.closeKey));
      await tester.pumpAndSettle();
      expect(_viewer, findsNothing);

      for (final PortfolioPhoto p in three) {
        expect(await cachedAtScreen(tester, p.url), isFalse, reason: p.id);
      }
      expect(cache.containsKey(railKey), isTrue);
    });
  });

  group('allowlist / fallback / decode', () {
    testWidgets('an off-allowlist URL shows the fallback glyph, renders no '
        'image and fetches nothing', (tester) async {
      final FakeMediaCacheManager cache = FakeMediaCacheManager(
        mediaLoadingForever,
      );
      debugMediaCacheManager = cache;
      await _pumpHost(
        tester,
        photos: const <PortfolioPhoto>[
          PortfolioPhoto(id: 'evil', url: 'https://evil.test/x.webp'),
        ],
      );

      expect(
        find.descendant(
          of: _page('evil'),
          matching: find.byIcon(Icons.broken_image_outlined),
        ),
        findsOneWidget,
      );
      expect(renderedImageUrls(tester, within: _page('evil')), isEmpty);
      expect(cache.getFileStreamCalls, 0);
    });

    testWidgets('a failed fetch (broken photo) shows the fallback glyph', (
      tester,
    ) async {
      debugMediaCacheManager = FakeMediaCacheManager(mediaFetchError);
      await _pumpHost(tester, photos: const <PortfolioPhoto>[_broken]);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _page(_broken.id),
          matching: find.byIcon(Icons.broken_image_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the decode is capped at the screen box × DPR (never the '
        'camera original), aspect preserved (fit)', (tester) async {
      await _pumpHost(tester);
      final Image image = tester.widget<Image>(
        find.descendant(of: _page('p1'), matching: find.byType(Image)),
      );
      final ImageProvider provider = image.image;
      expect(provider, isA<ResizeImage>());
      final ResizeImage resize = provider as ResizeImage;
      final Size physical = tester.view.physicalSize;
      expect(resize.width, physical.width.round());
      expect(resize.height, physical.height.round());
      expect(resize.policy, ResizeImagePolicy.fit);
      expect(image.fit, BoxFit.contain);
    });
  });

  group('accessibility', () {
    testWidgets('close button, indicator and page labels; no semantics node '
        'carries a URL', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpHost(tester, initialIndex: 1);

      // The close button's accessible name is its tooltip (IconButton's
      // a11y contract) and it announces as a button.
      final SemanticsData close = tester
          .getSemantics(find.byKey(PortfolioPhotoViewer.closeKey))
          .getSemanticsData();
      expect(close.tooltip, _l10n.portfolioViewerClose);
      expect(close.flagsCollection.isButton, isTrue);
      expect(_indicatorLabel(tester), _l10n.portfolioViewerPosition(2, 3));
      final SemanticsData page = tester
          .getSemantics(_page('p2'))
          .getSemanticsData();
      expect(page.label, _l10n.portfolioPhotoSemantics(2));
      expect(page.flagsCollection.isImage, isTrue);
      expect(
        find.bySemanticsLabel(RegExp('https?:|media\\.test')),
        findsNothing,
      );

      await tester.fling(_pager, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(_indicatorLabel(tester), _l10n.portfolioViewerPosition(3, 3));
      handle.dispose();
    });
  });

  group('report (phase 424 D3)', () {
    final Finder report = find.byKey(PortfolioPhotoViewer.reportKey);

    testWidgets('onReport null (owner screens) → no report button', (
      tester,
    ) async {
      await _pumpHost(tester);
      expect(report, findsNothing);
      expect(find.byIcon(Icons.outlined_flag_rounded), findsNothing);
      expect(find.byKey(PortfolioPhotoViewer.closeKey), findsOneWidget);
    });

    testWidgets('onReport set → flag button LEFT of close, tooltip from the '
        'ARB; a tap reports the SHOWN photo with the viewer context', (
      tester,
    ) async {
      final List<(BuildContext, PortfolioPhoto)> calls =
          <(BuildContext, PortfolioPhoto)>[];
      await _pumpHost(
        tester,
        initialIndex: 0,
        onReport: (BuildContext ctx, PortfolioPhoto photo) =>
            calls.add((ctx, photo)),
      );
      expect(report, findsOneWidget);
      expect(
        tester.getCenter(report).dx,
        lessThan(
          tester.getCenter(find.byKey(PortfolioPhotoViewer.closeKey)).dx,
        ),
      );
      expect(
        tester.widget<IconButton>(report).tooltip,
        _l10n.portfolioViewerReport,
      );

      await tester.fling(_pager, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      await tester.tap(report);
      await tester.pump();

      expect(calls, hasLength(1));
      expect(calls.single.$2.id, 'p2');
      // The context sits UNDER the viewer, so a sheet shown from it lands
      // above the photo (the viewer is on the root navigator).
      expect(calls.single.$1.widget, isA<PortfolioPhotoViewer>());
    });
  });
}
