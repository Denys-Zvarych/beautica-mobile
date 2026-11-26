// M542 — the remote category-icon store (SVC-04 / SVC-58).
//
// Holds the bytes of every category icon the backend published as `iconUrl`
// and that is already on disk, keyed by the category's uppercase wire slug.
// [CategoryIconGlyph] reads ONLY this store, so rendering a glyph never starts
// a network call or a categories fetch (D1: remote first only when already
// cached; the bundled icon shows instantly otherwise).
//
// The store is filled by `categoryIconUrlsProvider`
// (`lib/features/services/presentation/category_icon_urls_provider.dart`),
// which derives the slug → URL map from `approvedCategoriesProvider` and
// calls [CategoryIconStore.prefetchAll] (one shared, capped batch).
//
// Cache: ONE dedicated disk cache, `categoryIcons`, 365-day stale period —
// B539 keys are content-addressed (`…/{sha256[0..16]}.svg`), so a URL's bytes
// never change; a replaced icon arrives as a NEW URL (D3). Downloads go
// through the shared media HTTP client (system trust store, timeouts, per-host
// cap — see `beautica_image.dart`'s ADR) and only for allow-listed hosts.
// Icons are catalogue data, not PII, so this cache is NOT purged on sign-out.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../media/beautica_image.dart'
    show MediaResponseTooLargeException, buildMediaClient, isAllowedMediaUrl;

part 'category_icon_store.g.dart';

/// Hard ceiling on one icon's bytes. B539 rejects uploads above 16 KiB
/// (SVC-59); anything larger on the wire is not a sanitised icon.
const int kMaxCategoryIconBytes = 16 * 1024;

/// Ceiling on simultaneous icon downloads in [CategoryIconStore.prefetchAll]
/// — the ~22-icon first prefetch after login trickles in instead of bursting
/// against the screen that just opened.
const int kMaxConcurrentCategoryIconFetches = 2;

/// Markup a sanitised B539 icon never contains (SVC-59 strips it); bytes
/// carrying any of these are refused before they reach the store.
const List<String> _kForbiddenIconMarkup = <String>[
  '<image',
  '<!doctype',
  '<script',
];

/// The first forbidden marker found in [bytes] (case-insensitive), or `null`.
String? _forbiddenMarkupIn(Uint8List bytes) {
  final String text = latin1.decode(bytes).toLowerCase();
  for (final String marker in _kForbiddenIconMarkup) {
    if (text.contains(marker)) return marker;
  }
  return null;
}

/// The category-icon cache [Config] (D3): `categoryIcons`, 365-day stale
/// period, and the capped (16 KiB), no-redirect media client — a body over the
/// cap is aborted mid-download.
///
/// [storage] exists only so a unit test can build the PRODUCTION composition
/// without path_provider / sqflite (absent under `flutter test`); production
/// passes none. The network side has no override on purpose.
@visibleForTesting
Config categoryIconCacheConfig({
  ({CacheInfoRepository repo, FileSystem fileSystem})? storage,
}) {
  const String cacheKey = 'categoryIcons';
  const Duration stalePeriod = Duration(days: 365);
  const int maxObjects = 200;
  final FileService fileService = HttpFileService(
    httpClient: buildMediaClient(maxResponseBytes: kMaxCategoryIconBytes),
  );
  return switch (storage) {
    null => Config(
      cacheKey,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxObjects,
      fileService: fileService,
    ),
    (:final CacheInfoRepository repo, :final FileSystem fileSystem) => Config(
      cacheKey,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxObjects,
      repo: repo,
      fileSystem: fileSystem,
      fileService: fileService,
    ),
  };
}

/// The dedicated disk cache for category icons (D3). Built lazily on first
/// real use — tests override [categoryIconCacheManagerProvider] instead,
/// because path_provider / sqflite are absent under `flutter test`.
final CacheManager categoryIconDiskCache = CacheManager(
  categoryIconCacheConfig(),
);

/// The cache manager [CategoryIconStore] downloads through.
@Riverpod(keepAlive: true)
BaseCacheManager categoryIconCacheManager(Ref ref) => categoryIconDiskCache;

/// One cached remote icon: the [url] it came from and its SVG [bytes].
typedef CategoryIconBytes = ({String url, Uint8List bytes});

/// Uppercase-trimmed slug, or `null` when blank — the store's key shape.
String? normaliseCategoryIconKey(String? categoryKey) {
  final String? key = categoryKey?.trim().toUpperCase();
  return (key == null || key.isEmpty) ? null : key;
}

/// Slug → cached remote icon. Empty until a prefetch lands.
@Riverpod(keepAlive: true)
class CategoryIconStore extends _$CategoryIconStore {
  /// URLs with a download in flight — de-duplicates concurrent prefetches.
  final Set<String> _inFlight = <String>{};

  /// Keys already logged as failed, so a broken icon logs once, not per
  /// rebuild.
  final Set<String> _loggedFailures = <String>{};

  /// URLs whose bytes were refused (oversize, forbidden markup) or failed to
  /// parse — never re-fetched this session.
  final Set<String> _rejectedUrls = <String>{};

  /// Slug → the most recently requested URL. A download that finishes after
  /// its slug moved on to a newer URL must not overwrite the newer icon.
  final Map<String, String> _latestUrl = <String, String>{};

  @override
  Map<String, CategoryIconBytes> build() => const <String, CategoryIconBytes>{};

  /// Downloads (or reads from disk) [url] for [categoryKey] and stores its
  /// bytes. No-op when the key already holds this URL or the URL is in
  /// flight. A non-allow-listed URL is never fetched; any failure leaves the
  /// key on the bundled fallback and is logged once (slug only — no PII).
  Future<void> prefetch(String categoryKey, String url) async {
    final String? key = normaliseCategoryIconKey(categoryKey);
    if (key == null || !ref.mounted) return;
    _latestUrl[key] = url;
    if (state[key]?.url == url ||
        _inFlight.contains(url) ||
        _rejectedUrls.contains(url)) {
      return;
    }
    if (!isAllowedMediaUrl(url)) {
      _logOnce(key, 'icon host not allow-listed');
      return;
    }
    final BaseCacheManager cache = ref.read(categoryIconCacheManagerProvider);
    _inFlight.add(url);
    try {
      // package:file's `File` — not a lib/ dependency, so left inferred.
      final file = await cache.getSingleFile(url);
      final int length = await file.length();
      if (!ref.mounted) return;
      if (length == 0 || length > kMaxCategoryIconBytes) {
        await _reject(cache, key, url, 'icon size out of bounds ($length B)');
        return;
      }
      final Uint8List bytes = await file.readAsBytes();
      if (!ref.mounted) return;
      if (bytes.isEmpty || bytes.length > kMaxCategoryIconBytes) {
        await _reject(
          cache,
          key,
          url,
          'icon size out of bounds (${bytes.length} B)',
        );
        return;
      }
      final String? forbidden = _forbiddenMarkupIn(bytes);
      if (forbidden != null) {
        await _reject(cache, key, url, 'icon contains forbidden $forbidden');
        return;
      }
      // A newer URL was requested for this slug while this one downloaded:
      // the newer download owns the slot, whatever order they finish in.
      if (_latestUrl[key] != url) return;
      state = <String, CategoryIconBytes>{
        ...state,
        key: (url: url, bytes: bytes),
      };
    } on MediaResponseTooLargeException {
      // Aborted mid-download by the capped client.
      await _reject(
        cache,
        key,
        url,
        'icon download over $kMaxCategoryIconBytes B',
      );
    } on Object catch (e) {
      _logOnce(key, 'icon fetch failed: ${e.runtimeType}');
    } finally {
      _inFlight.remove(url);
    }
  }

  /// Slug → URL waiting for the running batch's workers.
  final Map<String, String> _pending = <String, String>{};

  /// The single running batch, or `null` when idle.
  Completer<void>? _batch;

  /// Workers alive in [_batch] — never above
  /// [kMaxConcurrentCategoryIconFetches].
  int _workers = 0;

  /// Prefetches every slug → URL in [urls] with at most
  /// [kMaxConcurrentCategoryIconFetches] downloads in flight at once — across
  /// ALL callers: while a batch runs, a new call queues its URLs into that
  /// batch (topping its workers back up to the cap) and returns its future,
  /// so overlapping rebuilds never start a parallel set of workers.
  ///
  /// The batch is published before any worker runs (a call made during the
  /// workers' synchronous start joins it) and ends in the same synchronous
  /// step in which its last worker sees an empty queue — so a queued URL is
  /// always taken by a live worker, never stranded in a finished batch.
  Future<void> prefetchAll(Map<String, String> urls) {
    urls.forEach((String slug, String url) {
      final String? key = normaliseCategoryIconKey(slug);
      if (key != null) _latestUrl[key] = url;
    });
    _pending.addAll(urls);
    final Completer<void>? running = _batch;
    if (!ref.mounted || _pending.isEmpty) {
      return running?.future ?? Future<void>.value();
    }
    final Completer<void> batch = running ?? (_batch = Completer<void>());
    while (_workers < kMaxConcurrentCategoryIconFetches &&
        _pending.isNotEmpty) {
      _workers++;
      unawaited(_worker(batch));
    }
    return batch.future;
  }

  /// Drains [_pending] one URL at a time; the last worker out completes
  /// [batch].
  Future<void> _worker(Completer<void> batch) async {
    try {
      while (ref.mounted && _pending.isNotEmpty) {
        final MapEntry<String, String> e = _pending.entries.first;
        _pending.remove(e.key);
        try {
          await prefetch(e.key, e.value);
        } on Object catch (err) {
          // prefetch() handles its own failures; this only keeps one
          // unexpected throw from stopping the queue.
          log(
            'icon prefetch failed: ${err.runtimeType}',
            name: 'core.icons.category',
            level: 900,
          );
        }
      }
    } finally {
      if (--_workers == 0) {
        _batch = null;
        batch.complete();
      }
    }
  }

  /// Refuses [url] for the session and evicts it from the disk cache so the
  /// refused bytes do not linger (best-effort).
  Future<void> _reject(
    BaseCacheManager cache,
    String key,
    String url,
    String reason,
  ) async {
    _rejectedUrls.add(url);
    _logOnce(key, reason);
    try {
      await cache.removeFile(url);
    } on Object catch (e) {
      log(
        'icon cache evict failed for $key: ${e.runtimeType}',
        name: 'core.icons.category',
        level: 900,
      );
    }
  }

  /// Drops [categoryKey]'s remote icon so its glyph falls back to the bundled
  /// set — called by [CategoryIconGlyph] when the cached bytes fail to parse.
  void discard(String categoryKey) {
    final String? key = normaliseCategoryIconKey(categoryKey);
    final CategoryIconBytes? held = key == null ? null : state[key];
    if (key == null || held == null) return;
    _rejectedUrls.add(held.url);
    _logOnce(key, 'icon failed to parse');
    state = <String, CategoryIconBytes>{...state}..remove(key);
  }

  void _logOnce(String key, String reason) {
    if (!_loggedFailures.add(key)) return;
    log('$reason for $key', name: 'core.icons.category', level: 900);
  }
}
