// Phase 393 (24.7a) — `HttpBookingRepository.getPendingActionsCount`.
//
// Drives the REAL generated `BookingControllerApi` over a real Dio wired to an
// http_mock_adapter, so the asserted path / `asMaster` query param are what
// actually goes on the wire.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/pending_actions_scope.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _mePath = '/api/v1/bookings/me/pending-actions/count';
const _salonPath = '/api/v1/bookings/salon/salon-1/pending-actions/count';

Map<String, dynamic> _envelope(int count) => <String, dynamic>{
  'success': true,
  'message': 'ok',
  'data': <String, dynamic>{'count': count, 'toClose': 1, 'toRateClient': 1},
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late HttpBookingRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: ''));
    adapter = DioAdapter(dio: dio);
    repo = HttpBookingRepository(
      dio,
      BookingControllerApi(dio, beauticaSerializers),
      ReviewControllerApi(dio, beauticaSerializers),
      StaffBookingsApi(dio, beauticaSerializers),
    );
  });

  test(
    '.me(asMaster: false) hits /me with asMaster=false, unwraps count',
    () async {
      adapter.onGet(
        _mePath,
        (s) => s.reply(200, _envelope(4)),
        queryParameters: <String, dynamic>{'asMaster': false},
      );

      expect(
        await repo.getPendingActionsCount(
          const PendingActionsScope.me(asMaster: false),
        ),
        4,
      );
    },
  );

  test('.me(asMaster: true) hits /me with asMaster=true', () async {
    adapter.onGet(
      _mePath,
      (s) => s.reply(200, _envelope(7)),
      queryParameters: <String, dynamic>{'asMaster': true},
    );

    expect(
      await repo.getPendingActionsCount(
        const PendingActionsScope.me(asMaster: true),
      ),
      7,
    );
  });

  test('.salon hits the salon path, no asMaster, unwraps count', () async {
    adapter.onGet(_salonPath, (s) => s.reply(200, _envelope(2)));

    expect(
      await repo.getPendingActionsCount(
        const PendingActionsScope.salon('salon-1'),
      ),
      2,
    );
  });

  test('HTTP 403 maps to a Failure, never a DioException', () async {
    adapter.onGet(
      _salonPath,
      (s) => s.reply(403, <String, dynamic>{'success': false}),
    );

    await expectLater(
      repo.getPendingActionsCount(const PendingActionsScope.salon('salon-1')),
      throwsA(
        isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 403),
      ),
    );
  });

  test('connection timeout maps to NetworkFailure, never 0', () async {
    adapter.onGet(
      _mePath,
      (s) => s.throws(
        0,
        DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: RequestOptions(path: _mePath),
        ),
      ),
      queryParameters: <String, dynamic>{'asMaster': false},
    );

    await expectLater(
      repo.getPendingActionsCount(
        const PendingActionsScope.me(asMaster: false),
      ),
      throwsA(isA<NetworkFailure>()),
    );
  });

  test('missing data.count is a ServerFailure, not 0', () async {
    adapter.onGet(
      _salonPath,
      (s) => s.reply(200, <String, dynamic>{'success': true, 'message': 'ok'}),
    );

    await expectLater(
      repo.getPendingActionsCount(const PendingActionsScope.salon('salon-1')),
      throwsA(isA<ServerFailure>()),
    );
  });

  // Regex cases live in test/core/network/path_segment_test.dart; this proves
  // the repository wires the gate BEFORE any request.
  test('malformed salon id -> ValidationFailure, no request made', () async {
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          requests++;
          h.next(o);
        },
      ),
    );

    await expectLater(
      repo.getPendingActionsCount(const PendingActionsScope.salon('../x')),
      throwsA(isA<ValidationFailure>()),
    );
    expect(requests, 0);
  });

  test('a passed CancelToken is forwarded to the request', () async {
    adapter.onGet(_salonPath, (s) => s.reply(200, _envelope(1)));
    final CancelToken token = CancelToken()..cancel();

    await expectLater(
      repo.getPendingActionsCount(
        const PendingActionsScope.salon('salon-1'),
        cancelToken: token,
      ),
      throwsA(isA<Failure>()),
    );
  });
}
