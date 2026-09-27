// Phase 352 cycle-1 (mobile-perf LOW) — REAL-Dio transport test for
// [HttpSearchSuggestionRepository]'s CancelToken handling.
//
// A superseded suggestion fetch (`search_suggestions_provider.dart`'s
// `_scheduleFetch`) cancels its own [CancelToken] the instant a newer
// keystroke schedules a replacement fetch. This pins the REPOSITORY side of
// that fix: a genuinely cancelled request must surface as a raw
// [DioException] with `CancelToken.isCancel(e)` true — NOT wrapped into a
// [Failure] the way every other DioException is — so the provider can
// recognise it and drop it silently instead of treating it as a fetch
// failure (see that provider's `on DioException catch (e)` branch).
//
// Uses http_mock_adapter's [DioAdapter] with a DELAYED reply so the request
// is still in flight when `cancelToken.cancel()` is called — a REAL [Dio]
// with only the socket faked, mirroring
// `search_repository_transport_test.dart`'s shape. Dio's cancellation race
// (`listenCancelForAsyncTask` in `dio_mixin.dart`) runs in Dio core
// regardless of which `HttpClientAdapter` is installed, so faking the socket
// does not weaken this assertion.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/discovery/data/search_suggestion_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _baseUrl = 'http://localhost:8080';
const _path = '/api/v1/search/suggestions';

Map<String, dynamic> _emptyEnvelope() => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <Map<String, dynamic>>[],
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpSearchSuggestionRepository repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _baseUrl));
    adapter = DioAdapter(dio: dio);
    repository = HttpSearchSuggestionRepository(dio, standardSerializers);
  });

  test('a CancelToken cancelled mid-flight surfaces as a raw DioException '
      '(CancelToken.isCancel true) — never wrapped into a Failure', () async {
    adapter.onRoute(
      _path,
      (server) => server.reply(
        200,
        _emptyEnvelope(),
        delay: const Duration(milliseconds: 200),
      ),
      request: const Request(method: RequestMethods.get),
    );

    final CancelToken token = CancelToken();
    final future = repository.fetch(term: 'нар', cancelToken: token);
    // Cancel while the (delayed) reply is still in flight.
    token.cancel();

    await expectLater(
      future,
      throwsA(
        isA<DioException>().having(
          (DioException e) => CancelToken.isCancel(e),
          'CancelToken.isCancel',
          isTrue,
        ),
      ),
    );
  });

  test('a genuine server error (500) still maps to a Failure — the '
      'cancellation carve-out does not swallow real failures', () async {
    adapter.onRoute(
      _path,
      (server) => server.reply(500, <String, dynamic>{'message': 'boom'}),
      request: const Request(method: RequestMethods.get),
    );

    await expectLater(repository.fetch(term: 'нар'), throwsA(isA<Failure>()));
  });

  test('no CancelToken passed (the default) behaves exactly as before — a '
      'normal reply resolves normally', () async {
    adapter.onRoute(
      _path,
      (server) => server.reply(200, _emptyEnvelope()),
      request: const Request(method: RequestMethods.get),
    );

    final rows = await repository.fetch(term: 'нар');
    expect(rows, isEmpty);
  });
}
