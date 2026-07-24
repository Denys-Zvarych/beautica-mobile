// Shared, disk-cached, TLS-controlled loader for Beautica's PUBLIC remote
// media (client/master avatars, salon portfolio photos served from Cloudflare
// R2). One home for what used to be four hand-rolled `Image.network` sites,
// each duplicating the same https guard and decode-bounding.
//
// ===========================================================================
// ADR — WHY THE MEDIA PATH USES THE SYSTEM TRUST STORE, NOT THE PINNED CONTEXT
// (mobile-security MEDIUM "trust-anchor asymmetry", decided 2026-07-24)
// ===========================================================================
// The authenticated API path (see `core/network/dio_provider.dart`,
// `initCertPinning`) validates TLS against a PINNED [SecurityContext] that
// trusts only two hard-coded ISRG roots. A reviewer looking at this file will
// notice the media path does the OPPOSITE — it trusts the OS store — and may
// be tempted to "fix the asymmetry" by pinning here too. Do NOT. That would
// brick every avatar on a silent CA rotation:
//
//   • Media is served from a Cloudflare R2 PUBLIC bucket URL. Cloudflare picks
//     the issuing CA PER-ISSUANCE and rotates it without notice or contract
//     (Let's Encrypt / ISRG, Google Trust Services, SSL.com have all been
//     observed). A pin at ANY level — leaf, intermediate, or root — fails
//     closed the moment Cloudflare hands out a cert from a different chain,
//     and there is no remote-config / forced-update channel to push a new pin
//     before the shipped build goes dark. (This is the SAME rotation-process
//     gap documented in dio_provider.dart, made WORSE here because we do not
//     even control which of several CAs Cloudflare uses.)
//   • The API host is a single Railway platform wildcard we can reason about;
//     the R2 media origin is not. Pinning a party whose CA choice is opaque to
//     us converts a theoretical MITM risk into a certain outage.
//
// The correct, operable controls for the media path — each implemented here:
//   1. SYSTEM trust store, EXPLICITLY. [buildMediaHttpClient] passes
//      `SecurityContext.defaultContext` (the OS anchors) rather than the
//      pinned context — a DELIBERATE divergence, recorded so it is never
//      mistaken for an oversight.
//   2. OUR OWN [HttpClient], not `NetworkImage._sharedHttpClient`. We inject a
//      `dart:io` client with a connection timeout, an idle timeout, and a
//      bounded `maxConnectionsPerHost`. This closes the
//      unbounded-concurrency / no-timeout finding at the SOCKET level, beneath
//      cached_network_image's own request queue — a stalled or slow R2 origin
//      can no longer pin an unbounded number of sockets open forever.
//   3. https-only + EXACT host allowlist. [isAllowedMediaUrl] (backed by
//      `media_config.dart`) rejects anything that is not https on a configured
//      R2 host. This is the real closable trust boundary — pure Dart, enforced
//      identically on Android and iOS — against a malformed or
//      attacker-influenced API response pointing an avatar at an unintended
//      host. It runs BEFORE any socket is opened.
//
// See dio_provider.dart's pinning header for the reciprocal pointer back here.
// ===========================================================================

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';

import 'media_config.dart';

// ---------------------------------------------------------------------------
// The injected socket-level HTTP client — control #2 of the ADR.
// ---------------------------------------------------------------------------

/// Socket connect timeout for media fetches — a dead R2 origin fails fast
/// instead of holding the connection attempt open indefinitely.
@visibleForTesting
const Duration kMediaConnectionTimeout = Duration(seconds: 10);

/// How long an idle keep-alive socket lingers before the client closes it —
/// bounds the number of half-open sockets a burst of thumbnails can leave
/// behind after a fast scroll.
@visibleForTesting
const Duration kMediaIdleTimeout = Duration(seconds: 15);

/// Ceiling on concurrent sockets to a single host. cached_network_image queues
/// its own requests above this; this is the hard floor the queue cannot exceed,
/// so an avatar-heavy timeline cannot open an unbounded connection fan-out to
/// the R2 origin.
@visibleForTesting
const int kMediaMaxConnectionsPerHost = 6;

/// The trust context for the media path: the SYSTEM trust store, explicitly.
///
/// A getter (not a stored field) so it always resolves the live
/// `SecurityContext.defaultContext` singleton — which lets a regression test
/// assert `identical(mediaTrustContext, SecurityContext.defaultContext)` and,
/// by extension, that this is NOT the pinned dio context. See the ADR.
@visibleForTesting
SecurityContext get mediaTrustContext => SecurityContext.defaultContext;

/// Builds the `dart:io` [HttpClient] that backs [beauticaImageCacheManager]'s
/// file service. Every knob here is part of the ADR's control #2.
///
/// Exposed so a security test can assert the timeouts and the per-host cap
/// without reaching through three layers of cache-manager internals.
HttpClient buildMediaHttpClient() => HttpClient(context: mediaTrustContext)
  ..connectionTimeout = kMediaConnectionTimeout
  ..idleTimeout = kMediaIdleTimeout
  ..maxConnectionsPerHost = kMediaMaxConnectionsPerHost;

// ---------------------------------------------------------------------------
// The shared cache manager — disk cache + the injected client.
// ---------------------------------------------------------------------------

/// The one cache manager for all Beautica media.
///
/// Disk-caches up to 200 objects for 7 days (control against re-fetching the
/// same avatar every scroll), and routes every download through
/// [buildMediaHttpClient] so the socket-level controls apply. Constructed
/// lazily on first real use (device only — tests inject a fake via
/// [debugMediaCacheManager], so this is never built under `flutter test`,
/// where its path_provider / sqflite backing store is unavailable anyway).
final CacheManager beauticaImageCacheManager = CacheManager(
  Config(
    'beauticaImages',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 200,
    fileService: HttpFileService(httpClient: IOClient(buildMediaHttpClient())),
  ),
);

/// Test-only cache-manager override.
///
/// The real [beauticaImageCacheManager] needs path_provider + sqflite, which
/// are absent under `flutter test`; a widget test injects a fake
/// [BaseCacheManager] here to drive loading / loaded / error deterministically.
/// Set in `setUp`, clear (`= null`) in `tearDown`.
BaseCacheManager? _debugMediaCacheManager;

/// The cache manager the media providers actually use — the test fake when
/// set, otherwise the real [beauticaImageCacheManager]. Reading this in
/// production never touches [_debugMediaCacheManager] beyond a null check.
BaseCacheManager get _activeMediaCacheManager =>
    _debugMediaCacheManager ?? beauticaImageCacheManager;

/// Test-only: install (or clear, with `null`) a fake cache manager.
@visibleForTesting
set debugMediaCacheManager(BaseCacheManager? manager) =>
    _debugMediaCacheManager = manager;

/// Empties the shared media disk cache — the metadata store AND the cached
/// image bytes it points at.
///
/// Routed through [_activeMediaCacheManager] (not the raw
/// [beauticaImageCacheManager]) ON PURPOSE: it respects the
/// [debugMediaCacheManager] override, so a `flutter test` observes the purge
/// through the injected fake and never touches path_provider / sqflite (which
/// are unavailable under the test binding and would throw
/// `MissingPluginException`).
///
/// Called on sign-out (see `AuthNotifier.logout`): the avatars/photos an
/// account viewed are cached on disk for 7 days and are PII (client faces), so
/// they must not survive the auth boundary onto a shared/reassigned device.
/// The caller is expected to treat this as best-effort and tolerate any error.
Future<void> purgeBeauticaMediaCache() => _activeMediaCacheManager.emptyCache();

// ---------------------------------------------------------------------------
// The guard — control #3 of the ADR. One home for the check that was
// duplicated (and, at the salon portfolio site, incompletely) across four
// widgets.
// ---------------------------------------------------------------------------

/// Whether [url] is safe to fetch as Beautica media.
///
/// Returns `false` — so the caller renders its local fallback WITHOUT opening a
/// socket — for anything that is null, empty, unparseable, not `https`, or
/// whose host is not in the configured allowlist ([MediaConfig]). This is the
/// single choke point every media site funnels through.
bool isAllowedMediaUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'https') return false;
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;
  return MediaConfig.effectiveAllowedHosts.contains(host);
}

// ---------------------------------------------------------------------------
// The providers — the ImageProvider layer the sites plug into. Sites keep
// their own plain `Image(image: …)` (with their own frameBuilder/errorBuilder
// and layout), so intrinsic sizing is unchanged; only the byte SOURCE moves
// onto the shared, cached, TLS-controlled path.
// ---------------------------------------------------------------------------

/// The disk-cached provider for [url]. Callers MUST gate on
/// [isAllowedMediaUrl] first — this does not re-check.
///
/// `CachedNetworkImageProvider` keys its `ImageCache` entry and its `==` on
/// the URL (verified against cached_network_image 3.4.1:
/// `(cacheKey ?? url, scale, maxHeight, maxWidth)`), so two cards for the same
/// avatar resolve to ONE cache entry and ONE fetch — the same dedup the old
/// `NetworkImage` gave, now with a disk tier underneath.
ImageProvider beauticaMediaProvider(String url) =>
    CachedNetworkImageProvider(url, cacheManager: _activeMediaCacheManager);

/// [beauticaMediaProvider] with the decode bounded to a [width]×[height] box.
///
/// `ResizeImagePolicy.fit` (not `exact`) so a non-square source keeps its
/// aspect ratio at decode time and the widget's `BoxFit.cover` upsizes from a
/// correctly-shaped bitmap — a full-res R2 object is never decoded into a
/// tiny disc. Both axes are bound so the decode ceiling is `w*h*4` bytes
/// regardless of source shape.
ImageProvider beauticaResizedProvider(String url, int width, int height) =>
    ResizeImage(
      beauticaMediaProvider(url),
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
    );

// ---------------------------------------------------------------------------
// RemoteImage — the widget the three non-critical sites adopt. Folds in the
// guard, the decode bound, animated-WebP suppression, semantics exclusion, a
// per-site shape, and the fallback. The critical timeline avatar
// (_ClientAvatarMark) deliberately does NOT use this — it keeps its exact
// hand-built tree and swaps only the provider.
// ---------------------------------------------------------------------------

/// The clip shape [RemoteImage] applies to the loaded photo.
enum RemoteImageShape {
  /// A circle (avatar). Uses `ClipOval`.
  circle,

  /// A rounded rectangle. Uses `ClipRRect` with [RemoteImage.borderRadius].
  roundedRect,
}

/// A guarded, disk-cached, decode-bounded remote image with a per-site
/// [fallback].
///
/// Behaviour, in order:
///   • [isAllowedMediaUrl] fails → renders [fallback] sized to the box, WITHOUT
///     resolving any provider or opening a socket.
///   • otherwise renders a plain [Image] fed by [beauticaResizedProvider],
///     clipped to [shape], with:
///       – `TickerMode(enabled: false)` around it, so an animated WebP (the
///         backend serves webp un-transcoded) is pinned to frame 0 and cannot
///         drive a repaint loop;
///       – [fallback] on decode error (`errorBuilder`);
///       – [excludeFromSemantics] passed through — set it for decorative
///         avatar/thumbnail variants whose identity is announced by adjacent
///         text or an enclosing `Semantics`.
///
/// Deliberately NO loading placeholder / cross-fade: the sites this replaces
/// showed a blank box (inside their own decorated container) until the first
/// frame, and adding cached_network_image's placeholder/fade layout would
/// change intrinsic sizing. The box is always [width]×[height].
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fallback,
    this.shape = RemoteImageShape.roundedRect,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.excludeFromSemantics = false,
  }) : assert(
         shape != RemoteImageShape.roundedRect || borderRadius != null,
         'roundedRect requires a borderRadius',
       );

  /// The media URL, or null / non-allowed → [fallback] with no fetch.
  final String? url;

  /// Logical box the image (or the fallback) occupies.
  final double width;
  final double height;

  /// Shown when the URL is not allowed or the fetch/decode fails. Sized to the
  /// box by the caller-agnostic wrapper, so the site can pass a bare disc.
  final Widget fallback;

  /// Clip shape for the loaded photo.
  final RemoteImageShape shape;

  /// Corner radius for [RemoteImageShape.roundedRect]. Ignored for circles.
  final BorderRadius? borderRadius;

  /// How the decoded bitmap fills the box. Defaults to cover.
  final BoxFit fit;

  /// Whether to keep the [Image] out of the semantics tree. Set for decorative
  /// variants (the surrounding widget already provides the a11y label).
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    if (!isAllowedMediaUrl(url)) {
      return SizedBox(width: width, height: height, child: fallback);
    }
    // url is non-null and allowed here.
    final String allowed = url!;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int w = (width * dpr).round();
    final int h = (height * dpr).round();

    Widget image = Image(
      image: beauticaResizedProvider(allowed, w, h),
      fit: fit,
      excludeFromSemantics: excludeFromSemantics,
      errorBuilder: (_, _, _) => fallback,
    );
    // Pin animated WebP to frame 0 — see the class doc and _ClientAvatarMark's
    // ANIMATED SOURCES header.
    image = TickerMode(enabled: false, child: image);

    final Widget clipped = switch (shape) {
      RemoteImageShape.circle => ClipOval(child: image),
      RemoteImageShape.roundedRect => ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      ),
    };
    return SizedBox(width: width, height: height, child: clipped);
  }
}
