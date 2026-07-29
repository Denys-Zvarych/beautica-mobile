// Media origin allowlist — the closable trust boundary for remote media.
//
// Beautica's public media (avatars, salon portfolio photos) is served from a
// Cloudflare R2 bucket's PUBLIC URL. The backend builds every object URL as
// `<app.cloudflare-r2.public-url>/<key>` (see R2StorageService.buildPublicUrl),
// where `public-url` is an infra-only env var (`CLOUDFLARE_R2_PUBLIC_URL`,
// documented "infra, not repo" in docs/backend-phases/backlog.md) whose value
// never lands in this repo. Its shape is Cloudflare's managed public bucket
// domain `pub-<hash>.r2.dev` OR a custom domain mapped to the bucket. Object
// keys look like `avatars/<userId>/<epochMillis>-<UUIDv4>.<ext>`.
//
// WHY A HOST ALLOWLIST IS THE REAL CONTROL (mobile-security MEDIUM):
//   An avatar/photo URL arrives as a plain string on an API response. A
//   malformed or attacker-influenced response could point that string at ANY
//   host. The pinned-certificate control on the API path (dio_provider.dart)
//   does NOT cover the media path — media deliberately uses the system trust
//   store (see beautica_image.dart's ADR). So the enforceable, pure-Dart,
//   both-platforms-identical boundary for media is: the URL host must be https
//   AND must `==` a host we configured. Everything else falls back to a
//   local placeholder WITHOUT touching the network.
//
// CONFIGURATION:
//   The allowed hosts are injected at build time via
//   `--dart-define=BEAUTICA_MEDIA_ORIGIN=<host>[,<host>…]` — the same
//   compile-time-constant pattern as BEAUTICA_BASE_URL (see AppConfig). Each
//   entry is a bare HOST (no scheme, no path), e.g.
//   `pub-1a2b3c.r2.dev` or `media.beautica.app`. Multiple hosts are
//   comma-separated so a custom-domain migration can allow the old and new
//   host simultaneously.
//
//   DEFAULT IS EMPTY = CLOSED. A build that does not pass the define allows no
//   remote media host at all, so every avatar renders its local fallback and
//   NOTHING is fetched. This is fail-safe by design: a forgotten define
//   degrades to placeholders, never to an unguarded fetch. Release/deploy
//   builds MUST pass `--dart-define=BEAUTICA_MEDIA_ORIGIN=<prod R2 host>`
//   once R2 media is live (R2 is gated behind the backend's `R2_ENABLED`,
//   default false, so media is not broadly live yet — hence an empty default
//   cannot regress today's behaviour: with R2 disabled the backend emits
//   empty avatar URLs, which fall back regardless).

import 'package:flutter/foundation.dart';

/// Compile-time media-origin configuration for the shared image loader.
///
/// Read by [isAllowedMediaUrl] (in `beautica_image.dart`). Kept in its own file
/// so the allowlist has a single home rather than the four duplicated
/// per-site scheme checks it replaces.
abstract final class MediaConfig {
  /// Raw comma-separated host allowlist from the build environment.
  ///
  /// Read directly via [String.fromEnvironment] so it stays a compile-time
  /// constant. Parsed once into [allowedHosts].
  static const String _rawOrigins = String.fromEnvironment(
    'BEAUTICA_MEDIA_ORIGIN',
    defaultValue: '',
  );

  /// The set of exact hosts (lower-cased, trimmed) allowed to serve media.
  ///
  /// Empty when the build did not pass `BEAUTICA_MEDIA_ORIGIN` — in which case
  /// no remote media is fetched (fail-safe; see the file header).
  ///
  /// A `static final` rather than `const` because parsing runs at first
  /// access; the source [_rawOrigins] is still a compile-time constant.
  static final Set<String> allowedHosts = _parse(_rawOrigins);

  /// Test-only override for [effectiveAllowedHosts].
  ///
  /// [String.fromEnvironment] cannot be varied under `flutter test`, so the
  /// "allowed host" code path (and the widgets that depend on it) is
  /// unreachable in tests without this seam. Set it in `setUp`, clear it
  /// (`= null`) in `tearDown`. Never read in production — [isAllowedMediaUrl]
  /// goes through [effectiveAllowedHosts], which returns [allowedHosts]
  /// whenever this is null.
  static Set<String>? _debugAllowedHostsOverride;

  /// The host set actually consulted by [isAllowedMediaUrl] — the test
  /// override when set, otherwise the build-time [allowedHosts].
  static Set<String> get effectiveAllowedHosts =>
      _debugAllowedHostsOverride ?? allowedHosts;

  /// Test-only: replace (or clear, with `null`) the allowed-host set.
  @visibleForTesting
  static set debugAllowedHosts(Set<String>? hosts) =>
      _debugAllowedHostsOverride = hosts
          ?.map((String h) => h.toLowerCase())
          .toSet();

  /// Splits a comma-separated origin list into a normalised host set.
  ///
  /// Each entry is trimmed and lower-cased; empty entries are dropped. An
  /// entry that was mistakenly given as a full URL (`https://host/…`) is
  /// reduced to its host so a careless `--dart-define` still yields a usable
  /// host rather than silently allowing nothing.
  ///
  /// Exposed for testing — [String.fromEnvironment] cannot be varied under
  /// `flutter test`, so the parsing logic is verified directly.
  static Set<String> _parse(String raw) {
    final Set<String> hosts = <String>{};
    for (final String part in raw.split(',')) {
      final String entry = part.trim().toLowerCase();
      if (entry.isEmpty) continue;
      // Tolerate a full URL slipped into the define: keep only the host.
      final Uri? uri = Uri.tryParse(
        entry.contains('://') ? entry : 'https://$entry',
      );
      final String host = uri?.host ?? '';
      if (host.isNotEmpty) hosts.add(host);
    }
    return hosts;
  }

  /// Exposed for tests: run [_parse] on an arbitrary raw string.
  static Set<String> parseForTest(String raw) => _parse(raw);
}
