import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart'
    show kPortfolioMaxPhotos;
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Phase 407 (9.12, D2) — opens [PortfolioPhotoViewer] over everything (root
/// navigator, so it also covers a shell's bottom nav) on [initialIndex] of
/// [photos].
///
/// A plain `Navigator.push` of a fullscreen-dialog route, NOT a go_router
/// route: the viewer has no deep link, and a pageless route keeps the route
/// ledgers untouched. The system back gesture / button pops it like any
/// route.
///
/// D5 — [photos] is the list the tapped rail is SHOWING (the viewer never
/// fetches). It is capped to the newest [kPortfolioMaxPhotos], exactly as
/// the rail caps its tiles, so a tile index always maps to the same photo.
Future<void> showPortfolioPhotoViewer(
  BuildContext context,
  List<PortfolioPhoto> photos,
  int initialIndex,
) {
  final List<PortfolioPhoto> shown = List<PortfolioPhoto>.unmodifiable(
    photos.take(kPortfolioMaxPhotos),
  );
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext _) =>
          PortfolioPhotoViewer(photos: shown, initialIndex: initialIndex),
    ),
  );
}

/// Phase 407 (9.12, D1) — the full-screen, READ-ONLY portfolio photo viewer:
/// a horizontal [PageView] of pinch-zoomable photos ([InteractiveViewer],
/// scale 1–4) on a black backdrop, a «n / N» indicator and a close button.
///
/// Rendering goes only through the allow-listed [RemoteImage]; each page is
/// decoded to fit the viewer's box (the screen) — never at the camera
/// original's resolution. A broken / off-allowlist URL shows a broken-image
/// glyph; no page ever exposes its URL to semantics.
///
/// Zoom vs paging: at scale 1 a ONE-finger drag always pages — the page's
/// [InteractiveViewer] gets an unreachable pan slop there (see
/// [_ZoomablePhoto]), so its scale recognizer can claim the gesture arena
/// only with a real pinch (a span change), never by one pointer's travel,
/// however large the first move sample is. Once a page is zoomed in, its pan
/// slop is back to the device default and the pager's physics become
/// [NeverScrollableScrollPhysics] — the pager then has no drag recognizer at
/// all — so a horizontal drag pans the image instead of paging. Pinching back
/// to 1 snaps the page to identity and re-enables paging.
///
/// M1 — while TWO or more pointers are down on the pager it is
/// [NeverScrollableScrollPhysics] too: a pinch is never a page turn. Without
/// this an ANCHORED pinch (one finger still, the other spreading) was lost to
/// the pager — its drag recognizer accepts at 18 px of one finger's travel,
/// while the scale recognizer needs 18 px of SPAN change, which an anchored
/// pinch reaches only after twice that travel. Dropping the drag physics
/// rebuilds the pager's gesture recognizers without a drag recognizer, which
/// disposes the pending one and so rejects it from the arena (and cancels a
/// drag already in progress), leaving the arena to the scale recognizer.
///
/// Memory: the shown page's neighbours are precached at the SAME decode key
/// the pages use (no blank page after a swipe), and every decode the viewer
/// caused is evicted from the [ImageCache] when it closes — paging 30
/// full-screen photos must not push the rails' and avatars' small decodes
/// out of the cache.
class PortfolioPhotoViewer extends StatefulWidget {
  const PortfolioPhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
  });

  /// The photos to page through, in rail order.
  final List<PortfolioPhoto> photos;

  /// The page shown first (clamped into range).
  final int initialIndex;

  static const Key pagerKey = Key('portfolio-viewer-pager');
  static const Key closeKey = Key('portfolio-viewer-close');
  static const Key indicatorKey = Key('portfolio-viewer-indicator');

  /// The page of [photo] (keyed by photo id).
  static Key pageKey(String photoId) => Key('portfolio-viewer-page-$photoId');

  /// Pinch-zoom bounds (D1).
  static const double minScale = 1;
  static const double maxScale = 4;

  @override
  State<PortfolioPhotoViewer> createState() => _PortfolioPhotoViewerState();
}

class _PortfolioPhotoViewerState extends State<PortfolioPhotoViewer> {
  /// The shown page. A notifier (not `setState`) so a page turn rebuilds
  /// only the counter — never the pager or the rest of the chrome.
  late final ValueNotifier<int> _index = ValueNotifier<int>(_clampedInitial());
  late final PageController _controller = PageController(
    initialPage: _index.value,
  );
  bool _zoomed = false;

  /// Pointers currently down on the pager (M1).
  final Set<int> _pointers = <int>{};

  /// 2+ pointers are down — a pinch in progress; the pager must not drag.
  bool _multiTouch = false;

  /// The logical page box (the pager's viewport) — what every page and every
  /// neighbour precache decodes at. Null until the first layout.
  Size? _box;

  /// The device pixel ratio [_box] was last laid out at (M2: a DPR change
  /// alone changes every decode key).
  double? _dpr;

  /// Every decode key `(url, physical w, physical h)` this viewer requested —
  /// a built page or a precached neighbour — that is still in the cache.
  /// Trimmed to the shown page ±1 on every page turn / box change, emptied on
  /// dispose.
  final Set<(String, int, int)> _decodes = <(String, int, int)>{};

  /// A post-frame neighbour refresh is already queued (R2: never queue two).
  bool _refreshQueued = false;

  int _clampedInitial() {
    final int last = math.max(0, widget.photos.length - 1);
    return widget.initialIndex.clamp(0, last);
  }

  @override
  void dispose() {
    _decodes.forEach(_evict);
    _index.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onZoomChanged(bool zoomed) {
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    _syncMultiTouch();
  }

  void _onPointerGone(PointerEvent e) {
    _pointers.remove(e.pointer);
    _syncMultiTouch();
  }

  void _syncMultiTouch() {
    final bool multi = _pointers.length >= 2;
    if (multi != _multiTouch) setState(() => _multiTouch = multi);
  }

  void _onPageChanged(int i) {
    _index.value = i;
    if (_zoomed) setState(() => _zoomed = false);
    _trimTo(i);
    _precacheNeighbours(i);
  }

  /// The same provider (hence the same ImageCache key) RemoteImage and
  /// precacheRemoteImage resolve; evicting an absent key is a no-op.
  static void _evict((String, int, int) key) {
    final (String url, int w, int h) = key;
    beauticaResizedProvider(url, w, h).evict();
  }

  /// R1 — keeps only the decodes page [i] ±1 can show at the CURRENT box and
  /// evicts the rest, so an open viewer holds ~3 full-screen bitmaps, not one
  /// per photo visited. Safe for visible pages: mid-swipe the outgoing page is
  /// ±1 of the new index, and after a box change every page has already
  /// re-laid-out at the new box (this runs post-frame there).
  void _trimTo(int i) {
    final Size? box = _box;
    if (box == null || !mounted) return;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int w = (box.width * dpr).round();
    final int h = (box.height * dpr).round();
    final Set<String> window = <String>{
      for (int n = i - 1; n <= i + 1; n++)
        if (n >= 0 && n < widget.photos.length) widget.photos[n].url,
    };
    final List<(String, int, int)> stale = <(String, int, int)>[
      for (final (String, int, int) key in _decodes)
        if (!window.contains(key.$1) || key.$2 != w || key.$3 != h) key,
    ];
    for (final (String, int, int) key in stale) {
      _evict(key);
      _decodes.remove(key);
    }
  }

  /// Records the decode key RemoteImage will request for [url] in [box]
  /// (mirrors its `(logical × DPR).round()`), for the dispose-time eviction.
  void _track(String url, Size box, double dpr) {
    if (!isAllowedMediaUrl(url)) return;
    _decodes.add((url, (box.width * dpr).round(), (box.height * dpr).round()));
  }

  /// Warms the two neighbours of page [i] at the pages' own decode key.
  void _precacheNeighbours(int i) {
    final Size? box = _box;
    if (box == null || !mounted) return;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    for (final int n in <int>[i - 1, i + 1]) {
      if (n < 0 || n >= widget.photos.length) continue;
      final String url = widget.photos[n].url;
      _track(url, box, dpr);
      precacheRemoteImage(context, url, box.width, box.height);
    }
  }

  /// Layout-time: remember the page box and DPR. When first known — and again
  /// whenever either changes (R2: rotation, split screen; M2: DPR) — refresh the shown
  /// page's neighbours at the new decode key after the frame (never
  /// mid-layout), dropping the old box's decodes. One refresh queued at most.
  void _onBox(Size box, double dpr) {
    if (box == _box && dpr == _dpr) return;
    _box = box;
    _dpr = dpr;
    if (_refreshQueued) return;
    _refreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _refreshQueued = false;
      if (!mounted) return;
      final int i = _index.value;
      _trimTo(i);
      _precacheNeighbours(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<PortfolioPhoto> photos = widget.photos;
    final int total = photos.length;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The pager fills the (expanded) stack, so every page's box is
            // exactly this one.
            LayoutBuilder(
              builder: (BuildContext _, BoxConstraints constraints) {
                final Size box = constraints.biggest;
                _onBox(box, dpr);
                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _onPointerDown,
                  onPointerUp: _onPointerGone,
                  onPointerCancel: _onPointerGone,
                  child: PageView.builder(
                    key: PortfolioPhotoViewer.pagerKey,
                    controller: _controller,
                    physics: _zoomed || _multiTouch
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    itemCount: total,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (BuildContext _, int i) {
                      _track(photos[i].url, box, dpr);
                      return _ZoomablePhoto(
                        key: PortfolioPhotoViewer.pageKey(photos[i].id),
                        url: photos[i].url,
                        box: box,
                        semanticLabel: l10n.portfolioPhotoSemantics(i + 1),
                        onZoomChanged: _onZoomChanged,
                      );
                    },
                  ),
                );
              },
            ),
            // The chrome rides along the TOP edge (below the status bar) —
            // never stretched by the expanding Stack.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      if (total > 0)
                        ValueListenableBuilder<int>(
                          valueListenable: _index,
                          builder: (BuildContext _, int index, Widget? _) =>
                              _PageIndicator(
                                key: PortfolioPhotoViewer.indicatorKey,
                                index: index + 1,
                                total: total,
                              ),
                        ),
                      const Spacer(),
                      IconButton(
                        key: PortfolioPhotoViewer.closeKey,
                        tooltip: l10n.portfolioViewerClose,
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                          backgroundColor: _kChromeFill,
                          foregroundColor: BrandColors.white,
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The chrome's scrim fill — black at 45 % so cream glyphs stay legible over
/// a light photo without boxing the photo in.
final Color _kChromeFill = Colors.black.withValues(alpha: 0.45);

/// «n / N» — Comfortaa CTA type in cream on a black pill; tabular figures
/// so the pill does not jitter between «9 / 12» and «10 / 12». Screen readers
/// hear «Фото n з N» (live region: announced on every page change).
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({super.key, required this.index, required this.total});

  final int index;
  final int total;

  static final TextStyle _style = VelvetText.cta().copyWith(
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: l10n.portfolioViewerPosition(index, total),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _kChromeFill,
          borderRadius: const BorderRadius.all(
            Radius.circular(VelvetRadii.pill),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm,
          ),
          child: Text(l10n.portfolioViewerCounter(index, total), style: _style),
        ),
      ),
    );
  }
}

/// One page: the photo in an [InteractiveViewer], decoded to fit [box] (the
/// page). Reports "zoomed in" changes so the pager can stop competing for
/// horizontal drags.
///
/// F1 (phase 407 audit) — the [InteractiveViewer]'s scale recognizer sits
/// deeper than the pager's drag recognizer, so it sees every pointer move
/// FIRST: with the default pan slop (2 × touch slop), a first move sample
/// that overshoots it would hand it the arena before the pager even checked
/// its own (smaller) slop, and the page would not turn. At scale 1 the page
/// therefore runs its gestures under an infinite pan slop: one pointer can
/// never claim the arena (the pager always wins a one-finger drag), while a
/// pinch still claims it through the span-change / scale-factor tests, so
/// pinch-to-zoom starts from scale 1 as before. Zoomed in, the device
/// settings are back and a drag pans the photo.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.url,
    required this.box,
    required this.semanticLabel,
    required this.onZoomChanged,
  });

  final String url;
  final Size box;
  final String semanticLabel;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _transform = TransformationController();
  bool _zoomed = false;

  /// Above this scale a page counts as zoomed in (absorbs float noise left
  /// after pinching back out).
  static const double _zoomEpsilon = 0.01;

  /// Scale-1 gesture settings: a pan slop no single pointer can reach (F1).
  static const DeviceGestureSettings _pagerFirst = DeviceGestureSettings(
    touchSlop: double.infinity,
  );

  static final Widget _fallback = Center(
    child: Icon(
      Icons.broken_image_outlined,
      color: BrandColors.white.withValues(alpha: 0.6),
      size: 40,
    ),
  );

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  bool get _isZoomedIn =>
      _transform.value.getMaxScaleOnAxis() >
      PortfolioPhotoViewer.minScale + _zoomEpsilon;

  void _onTransform() {
    final bool zoomed = _isZoomedIn;
    if (zoomed == _zoomed) return;
    // Rebuild so the gesture settings follow the zoom state.
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  /// Pinched back to (about) 1 → snap to identity so the page sits exactly
  /// where paging expects it.
  void _onInteractionEnd(ScaleEndDetails _) {
    if (!_isZoomedIn) _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final Size box = widget.box;
    final MediaQueryData media = MediaQuery.of(context);
    final Widget viewer = InteractiveViewer(
      transformationController: _transform,
      minScale: PortfolioPhotoViewer.minScale,
      maxScale: PortfolioPhotoViewer.maxScale,
      onInteractionEnd: _onInteractionEnd,
      child: RemoteImage(
        url: widget.url,
        // Decode cap = the page box (the screen) × device pixel ratio,
        // aspect preserved (RemoteImage's fit decode) — a 12 MP camera
        // original never decodes at full resolution.
        width: box.width,
        height: box.height,
        fit: BoxFit.contain,
        borderRadius: BorderRadius.zero,
        excludeFromSemantics: true,
        fallback: _fallback,
      ),
    );
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      // Always the same MediaQuery node (only its data flips), so crossing the
      // zoom threshold mid-pinch never remounts the InteractiveViewer.
      child: MediaQuery(
        data: _zoomed ? media : media.copyWith(gestureSettings: _pagerFirst),
        child: viewer,
      ),
    );
  }
}
