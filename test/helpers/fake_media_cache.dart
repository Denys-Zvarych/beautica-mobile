// Test double for the shared media loader (lib/core/media/beautica_image.dart).
//
// The real `beauticaImageCacheManager` is a `CacheManager` whose store is
// backed by path_provider + sqflite — both unavailable under `flutter test`,
// so it cannot run in a widget test at all. Every media-loader test therefore
// injects one of these via `debugMediaCacheManager`, driving the three
// observable states deterministically:
//
//   • [mediaLoadingForever] — never emits, never closes → the provider stays
//     loading (no frame, no error) for the life of the test.
//   • [mediaLoaded]         — emits one FileInfo backed by a real (in-memory)
//     PNG → the provider decodes a frame (needs `tester.runAsync`).
//   • [mediaFetchError]     — errors immediately → the provider's errorBuilder
//     fires.
//
// [FakeMediaCacheManager.getFileStreamCalls] counts invocations so a test can
// assert a guarded (disallowed) URL made NO network attempt.

import 'dart:async';
import 'dart:typed_data';

import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// A minimal in-memory [BaseCacheManager]. Only [getFileStream] is wired — the
/// one method `CachedNetworkImageProvider` calls when no on-disk resize is
/// requested (the shared providers never pass maxWidth/maxHeight). Everything
/// else throws via [noSuchMethod], which is never reached in these tests.
class FakeMediaCacheManager implements BaseCacheManager {
  FakeMediaCacheManager(this.responder);

  /// Builds the response stream for a requested URL. Swap per test.
  Stream<FileResponse> Function(String url) responder;

  /// Number of [getFileStream] calls — 0 proves a disallowed URL never reached
  /// the network layer.
  int getFileStreamCalls = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    getFileStreamCalls++;
    return responder(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FakeMediaCacheManager.${invocation.memberName} is not wired for tests',
  );
}

/// A response that never resolves — the loading state.
Stream<FileResponse> mediaLoadingForever(String url) =>
    Stream<FileResponse>.fromFuture(Completer<FileResponse>().future);

/// A response that fails immediately — the error state.
Stream<FileResponse> mediaFetchError(String url) =>
    Stream<FileResponse>.fromFuture(
      Future<FileResponse>.error(
        Exception('media fetch failed (test fixture)'),
      ),
    );

/// A response that delivers a decodable 1×1 PNG — the loaded state.
///
/// The bytes live in a [MemoryFileSystem], so the decode path
/// (`FileInfo.file.readAsBytes()` in cached_network_image's ImageLoader)
/// reads real bytes with no disk I/O.
Stream<FileResponse> mediaLoaded(String url) {
  final file = MemoryFileSystem().file('/${url.hashCode}.png')
    ..writeAsBytesSync(kTransparentPng);
  return Stream<FileResponse>.value(
    FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 1)),
      url,
    ),
  );
}

/// A canonical 1×1 fully-transparent PNG (67 bytes) — the smallest input that
/// decodes to a valid frame.
final Uint8List kTransparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
]);
