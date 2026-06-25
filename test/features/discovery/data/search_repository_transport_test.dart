// Wire-format regression safety net — REAL-Dio transport tests for
// [HttpSearchRepository].
//
// WHY THIS FILE EXISTS
// --------------------
// search_repository_test.dart mocks [Dio] with mocktail: it captures the
// `queryParameters` MAP the repository hands `Dio.get`, but it never lets Dio
// actually ASSEMBLE the request — so the real URI bytes Dio puts on the socket
// are never exercised there. That is exactly the blind spot the original
// all-regions bug lived in: the generated client built a bracket-nested
// `request[location][cityId]=…` URI that the @ModelAttribute binder dropped.
//
// HERE we fake ONLY the HTTP socket via http_mock_adapter's [DioAdapter].
// Everything above the socket is the production path: the REAL
// [HttpSearchRepository], a REAL [Dio] (the dioProvider BaseOptions shape), and
// the REAL [standardSerializers]. An interceptor captures the OUTGOING
// RequestOptions, so we assert the EXACT path + the EXACT assembled query URI:
//   • city scopes the search via the FLAT dotted key `location.cityId=<uuid>`
//   • the rendered URI contains NO `request` wrapper and NO `[` / `]` / `%5B`
//     bracket-encoding.
// This FAILS the instant anyone reverts to the object-query encoding — the
// socket-level twin of the mocktail regression group.
//
// NOTE: AppConfig.baseUrl does NOT carry the /api/v1 prefix; the repository
// prepends the full /api/v1/ segment. The Dio here mirrors that (baseUrl WITHOUT
// /api/v1) so the assembled path matches production.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://localhost:8080';
const _mastersPath = '/api/v1/search/masters';
const _salonsPath = '/api/v1/search/salons';

// City + district ids the regression pins on the wire.
const _cityId = 'b3f1c2d4-0000-4aaa-bbbb-ccccdddd1111';
const _districtId = 'a1a2a3a4-0000-4bbb-cccc-ddddeeee2222';

/// An empty `ApiResponse<PageResponse<…>>` envelope (no rows) — enough for the
/// repository to deserialize a valid empty page; the request side is what we
/// assert, not the body.
Map<String, dynamic> _emptyEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{
    'success': true,
    'data': <Map<String, dynamic>>[],
    'page': 0,
    'size': 20,
    'totalElements': 0,
    'totalPages': 0,
  },
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpSearchRepository repository;

  setUp(() {
    dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        headers: const <String, dynamic>{
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    adapter = DioAdapter(dio: dio);
    repository = HttpSearchRepository(dio, standardSerializers);
  });

  /// Arms the faked socket for [path] (GET) and installs an interceptor that
  /// captures the OUTGOING [RequestOptions] Dio assembled. Returns a getter for
  /// the captured options once the request has run.
  RequestOptions Function() armAndCapture(String path) {
    RequestOptions? captured;
    adapter.onRoute(
      path,
      (server) => server.reply(200, _emptyEnvelope()),
      request: const Request(method: RequestMethods.get),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ),
    );
    return () => captured!;
  }

  /// Asserts the assembled request for [getOptions] scopes the search to the
  /// picked city/district via FLAT keys and carries NO bracket / object-query
  /// encoding — at BOTH the queryParameters map AND the rendered URI level.
  void expectFlatCityWire(RequestOptions options, String expectedPath) {
    expect(options.method, 'GET');
    expect(options.path, expectedPath);

    // queryParameters map carries the exact backend field names.
    expect(options.queryParameters['location.cityId'], _cityId);
    expect(options.queryParameters['location.districtId'], _districtId);
    expect(options.queryParameters.containsKey('request'), isFalse);
    for (final String key in options.queryParameters.keys) {
      expect(key.contains('['), isFalse, reason: 'bracketed key "$key"');
      expect(key.contains(']'), isFalse, reason: 'bracketed key "$key"');
      expect(key.startsWith('request'), isFalse, reason: 'wrapper key "$key"');
    }

    // The rendered URI Dio would put on the socket — ground-truth bytes.
    final String uri = options.uri.toString();
    expect(
      uri,
      contains('location.cityId=$_cityId'),
      reason: 'city must appear FLAT in the assembled URI',
    );
    expect(uri.contains('request'), isFalse, reason: 'no object-query wrapper');
    expect(
      uri.contains('%5B') || uri.contains('['),
      isFalse,
      reason: 'no `[` / `%5B` bracket-encoding in the assembled URI',
    );
  }

  group('searchMasters — real Dio transport (city wire-format regression)', () {
    test('a picked city+district assembles a FLAT location.* URI, no brackets',
        () async {
      final getOptions = armAndCapture(_mastersPath);

      await repository.searchMasters(
        filters: const SearchFilters(cityId: _cityId, districtId: _districtId),
        page: 0,
      );

      expectFlatCityWire(getOptions(), _mastersPath);
    });
  });

  group('searchSalons — real Dio transport (city wire-format regression)', () {
    test('a picked city+district assembles a FLAT location.* URI, no brackets',
        () async {
      final getOptions = armAndCapture(_salonsPath);

      await repository.searchSalons(
        filters: const SearchFilters(cityId: _cityId, districtId: _districtId),
        page: 0,
      );

      expectFlatCityWire(getOptions(), _salonsPath);
    });
  });
}
