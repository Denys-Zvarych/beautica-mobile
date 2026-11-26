// M542 audit-fix cycle 3 (QA LOW) — the PRODUCTION category-icon cache
// wiring: `categoryIconCacheConfig()` (what `categoryIconDiskCache` is built
// from) downloads through the capped, no-redirect `MediaHttpClient` over the
// real dart:io media client. Only the socket is faked (HttpOverrides); the
// whole package:http / MediaHttpClient / HttpFileService chain is production.
import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/icons/category_icon_store.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart'
    show MediaResponseTooLargeException;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// One canned dart:io answer.
typedef _Answer = ({int status, List<int> body, bool declareLength});

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = <String>['$value'];

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this._answer);

  final _Answer _answer;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  int get statusCode => _answer.status;

  @override
  int get contentLength => _answer.declareLength ? _answer.body.length : -1;

  @override
  bool get isRedirect => _answer.status >= 300 && _answer.status < 400;

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => '';

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable(<List<int>>[
        for (int i = 0; i < _answer.body.length; i += 1024)
          _answer.body.sublist(i, (i + 1024).clamp(0, _answer.body.length)),
      ]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._answer);

  final _Answer _answer;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(_answer);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._answer);

  final _Answer _answer;
  final List<_FakeRequest> requests = <_FakeRequest>[];

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final _FakeRequest req = _FakeRequest(_answer);
    requests.add(req);
    return req;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const String _url =
    'https://media.test/catalog/category-icons/NAILS/0123456789abcdef.svg';

/// Builds the production config and runs one `fileService.get` + body drain
/// against [answer], with every dart:io `HttpClient` replaced by [socket].
Future<({FileServiceResponse response, Object? bodyError})> _fetch(
  _FakeHttpClient socket,
) => HttpOverrides.runZoned(() async {
  final Config config = categoryIconCacheConfig(
    storage: (
      repo: NonStoringObjectProvider(),
      fileSystem: MemoryCacheSystem(),
    ),
  );
  final FileServiceResponse response = await config.fileService.get(_url);
  Object? bodyError;
  try {
    await response.content.drain<void>();
  } on Object catch (e) {
    bodyError = e;
  }
  return (response: response, bodyError: bodyError);
}, createHttpClient: (_) => socket);

void main() {
  test('cache identity: categoryIcons, 365-day stale period', () {
    final _FakeHttpClient socket = _FakeHttpClient((
      status: 200,
      body: const <int>[],
      declareLength: true,
    ));
    final Config config = HttpOverrides.runZoned(
      () => categoryIconCacheConfig(
        storage: (
          repo: NonStoringObjectProvider(),
          fileSystem: MemoryCacheSystem(),
        ),
      ),
      createHttpClient: (_) => socket,
    );
    expect(config.cacheKey, 'categoryIcons');
    expect(config.stalePeriod, const Duration(days: 365));
    expect(config.fileService, isA<HttpFileService>());
  });

  test(
    'downloads go over the media dart:io client with redirects OFF',
    () async {
      final _FakeHttpClient socket = _FakeHttpClient((
        status: 302,
        body: const <int>[],
        declareLength: true,
      ));
      final r = await _fetch(socket);

      expect(socket.requests, hasLength(1), reason: 'the media socket is used');
      expect(socket.requests.single.followRedirects, isFalse);
      expect(
        r.response.statusCode,
        302,
        reason: 'a 3xx surfaces, not followed',
      );
      // buildMediaHttpClient's socket controls reached the dart:io client.
      expect(socket.connectionTimeout, isNotNull);
      expect(socket.maxConnectionsPerHost, isNotNull);
    },
  );

  test('a declared body over 16 KiB is refused before it is read', () async {
    final _FakeHttpClient socket = _FakeHttpClient((
      status: 200,
      body: List<int>.filled(16 * 1024 + 1, 0x20),
      declareLength: true,
    ));
    await expectLater(
      HttpOverrides.runZoned(() async {
        final Config config = categoryIconCacheConfig(
          storage: (
            repo: NonStoringObjectProvider(),
            fileSystem: MemoryCacheSystem(),
          ),
        );
        await config.fileService.get(_url);
      }, createHttpClient: (_) => socket),
      throwsA(isA<MediaResponseTooLargeException>()),
    );
  });

  test('an undeclared body over 16 KiB is aborted mid-stream', () async {
    final _FakeHttpClient socket = _FakeHttpClient((
      status: 200,
      body: List<int>.filled(16 * 1024 + 512, 0x20),
      declareLength: false,
    ));
    final r = await _fetch(socket);

    expect(r.bodyError, isA<MediaResponseTooLargeException>());
  });

  test('a body at exactly 16 KiB passes the cap', () async {
    final _FakeHttpClient socket = _FakeHttpClient((
      status: 200,
      body: List<int>.filled(kMaxCategoryIconBytes, 0x20),
      declareLength: false,
    ));
    final r = await _fetch(socket);

    expect(r.bodyError, isNull);
    expect(kMaxCategoryIconBytes, 16 * 1024);
  });
}
