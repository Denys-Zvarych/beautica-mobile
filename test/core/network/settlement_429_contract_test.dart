// Phase 346 — L6 (security #4): a 429 from `GET /api/v1/settlements` is a
// typed throttle failure, is never re-issued by the container, and the
// settlement sheet issues no request until the cooldown elapses.
//
// Drives a REAL Dio carrying the production `ErrorMapperInterceptor` and the
// REAL `HttpLocationRepository`, over a counting fake transport — so the
// assertion is on requests that actually left the client, not on a
// fabricated DioException.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/presentation/widgets/settlement_select_field.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Answers every request with [statusCode] and records its query parameter.
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter({this.retryAfter});

  /// Flipped to 200 by a test once the limiter should have cleared.
  int statusCode = 429;
  final String? retryAfter;
  final List<String?> queries = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    queries.add(options.queryParameters['query'] as String?);
    final Map<String, List<String>> headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      if (retryAfter != null) 'retry-after': <String>[retryAfter!],
    };
    final String body = statusCode == 200
        ? jsonEncode(<String, Object?>{
            'success': true,
            'data': <Object?>[
              <String, Object?>{
                'settlementId': 's-1',
                'nameUk': 'Полтава',
                'settlementType': 'CITY',
                'oblastNameUk': 'Полтавська',
                'hromadaNameUk': null,
              },
            ],
          })
        : jsonEncode(<String, Object?>{'error': 'Too many requests'});
    return ResponseBody.fromString(body, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_CountingAdapter adapter) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(ErrorMapperInterceptor());
  return dio;
}

void main() {
  group('settlement search 429 — mapping', () {
    test('maps to SettlementSearchRateLimitedFailure carrying Retry-After, '
        'and is a member of the throttle family', () async {
      final adapter = _CountingAdapter(retryAfter: '7');
      final repo = HttpLocationRepository(_dio(adapter));

      final Object error = await repo
          .searchSettlements('Полтава')
          .then<Object>((_) => 'no error', onError: (Object e) => e);

      expect(error, isA<SettlementSearchRateLimitedFailure>());
      final limited = error as SettlementSearchRateLimitedFailure;
      expect(limited.retryAfterSeconds, 7);
      expect(isThrottleFailure(limited), isTrue);
      expect(beauticaProviderRetry(0, limited), isNull);
      expect(adapter.queries, <String?>['Полтава']);
    });

    test('is NOT re-issued by the container under the production retry '
        'policy', () async {
      final adapter = _CountingAdapter(retryAfter: '7');
      final container = ProviderContainer(
        overrides: [
          locationRepositoryProvider.overrideWithValue(
            HttpLocationRepository(_dio(adapter)),
          ),
        ],
        retry: beauticaProviderRetry,
      );
      addTearDown(container.dispose);
      final sub = container.listen(settlementSearchProvider('Полт'), (_, _) {});
      addTearDown(sub.close);

      await expectLater(
        container.read(settlementSearchProvider('Полт').future),
        throwsA(isA<SettlementSearchRateLimitedFailure>()),
      );
      // Well past Riverpod's default first-retry delay.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(adapter.queries, hasLength(1));
      expect(
        container.read(settlementSearchProvider('Полт')).error,
        isA<SettlementSearchRateLimitedFailure>(),
      );
    });

    test('settlementThrottleCooldown honours Retry-After and falls back when '
        'it is absent; non-throttle errors get none', () {
      expect(
        settlementThrottleCooldown(
          const SettlementSearchRateLimitedFailure(retryAfterSeconds: 3),
        ),
        const Duration(seconds: 3),
      );
      expect(
        settlementThrottleCooldown(const SettlementSearchRateLimitedFailure()),
        kSettlementThrottleFallback,
      );
      expect(settlementThrottleCooldown(const NetworkFailure()), isNull);
      expect(settlementThrottleCooldown(StateError('x')), isNull);
    });
  });

  group('settlement search 429 — the sheet suppresses requests', () {
    testWidgets('no request leaves the client until the cooldown elapses, '
        'and no Retry is offered meanwhile', (tester) async {
      // The advertised Retry-After. The test advances the FAKE clock by
      // fractions of it: the timing is the behaviour under test here, not a
      // guess at when some async state settles.
      const Duration cooldown = Duration(seconds: 5);
      final adapter = _CountingAdapter(retryAfter: '${cooldown.inSeconds}');
      final router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) =>
                Scaffold(body: SettlementSelectField(onSelected: (_, _) {})),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationRepositoryProvider.overrideWithValue(
              HttpLocationRepository(_dio(adapter)),
            ),
          ],
          retry: beauticaProviderRetry,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('settlement_select_field')));
      await tester.pumpAndSettle();
      // The blank-query major list was the first request and it was throttled.
      expect(adapter.queries, <String?>[null]);
      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('select-menu-search'))),
      );
      expect(find.text(l10n.settlementSearchErrRateLimited), findsOneWidget);
      expect(find.byKey(const Key('select-menu-retry')), findsNothing);

      // Typing through the cooldown issues nothing, debounce or not.
      await tester.enterText(
        find.byKey(const Key('select-menu-search')),
        'Полтава',
      );
      await tester.pump(kSettlementSearchDebounce);
      await tester.pump(cooldown ~/ 2);
      expect(adapter.queries, <String?>[null]);

      // Cooldown over: exactly ONE request, for what the box now holds.
      adapter.statusCode = 200;
      await tester.pump(cooldown ~/ 2);
      await tester.pumpAndSettle();
      expect(adapter.queries, <String?>[null, 'Полтава']);
      expect(find.byKey(const Key('settlement_option_s-1')), findsOneWidget);
    });
  });
}
