// Mobile-qa (2026-07-31 debug chain) — the `serviceId` REPEATABLE-QUERY-PARAM
// wire contract between the GENERATED OpenAPI client and `FakeBackend`.
//
// WHAT BROKE, AND WHY IT WAS EXPENSIVE
// ------------------------------------
// `integration_test/support/fake_backend.dart` read the `serviceId` param with
// a direct cast, `req.queryParameters['serviceId'] as String?`. That was true
// until the `d42c7cf1` OpenAPI regen re-declared `serviceId` list-valued on
// `/masters/{id}/working-days` and `/masters/{id}/slots`. From that commit the
// generated `master_controller_api.dart` routes the param through
// `encodeCollectionQueryParameter<String>`, which emits a Dio
// `ListParam<Object?>{value: [...], format: ListFormat.multi}` — never a
// `String`.
//
// The cast then threw INSIDE the DioAdapter route callback. Nothing said
// "the fake is broken". The request simply failed → `workingDaysProvider` went
// `AsyncError` → the calendar painted `_WorkingDaysErrorBody` → FOUR tests
// across TWO unrelated flow files failed on downstream assertions about
// missing day cells. Diagnosing that took far longer than the one-line fix.
//
// WHAT THIS FILE PINS
// -------------------
// The contract has TWO halves and this file asserts BOTH, because either half
// moving alone re-opens the bug:
//
//   1. WIRE SHAPE — the generated client really does emit `serviceId` as a
//      Dio `ListParam` with `ListFormat.multi`. Asserted directly off the
//      outgoing `RequestOptions` via an interceptor, so the NEXT regen that
//      flips a param's collection shape fails HERE, on a named one-line
//      assertion naming the type, instead of as an opaque calendar-error
//      cascade four files away.
//   2. FAKE PARSE — `FakeBackend` decodes that shape back into the ORDERED,
//      COMPLETE id list, for one id AND for two. Two ids matter specifically:
//      the pre-fix scalar view silently kept only the first, so a
//      multi-service visit would have queried availability for one service.
//
// This runs in the FAST unit tier (`flutter test test/`) with no widget tree
// and no device — the same offline-proof pattern as
// `fake_backend_bookings_dataset_test.dart` beside it. It does NOT replace
// `integration_test/independent_multi_service_booking_flow_test.dart`, which
// drives the real screen→notifier→repository stack; it makes the wire-shape
// failure legible when it happens.
//
// Structural sibling: `scripts/forbid_raw_query_param_cast.sh` bans the cast
// that caused this. That grep stops the pattern being re-typed; this test
// catches the spec-side flip the grep cannot see.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/fake_backend.dart';

/// Captures the OUTGOING `serviceId` query param, exactly as the generated
/// client handed it to Dio — before any adapter/fake sees it.
class _ServiceIdWireCapture extends Interceptor {
  Object? lastRaw;
  bool sawRequest = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.queryParameters.containsKey('serviceId')) {
      sawRequest = true;
      lastRaw = options.queryParameters['serviceId'];
    }
    handler.next(options);
  }
}

void main() {
  group('serviceId repeatable-query-param wire contract '
      '(generated client → FakeBackend)', () {
    late FakeBackend fb;
    late _ServiceIdWireCapture capture;
    late SlotRepository repo;

    setUp(() {
      fb = FakeBackend();
      capture = _ServiceIdWireCapture();
      // Interceptor first so it observes the request the GENERATED client
      // built, not a version the adapter has already normalised.
      fb.dio.interceptors.insert(0, capture);
      repo = HttpSlotRepository(
        MasterControllerApi(fb.dio, standardSerializers),
      );
    });

    // The window must stay inside the backend's 62-day availability-aware cap
    // (see SlotRepository.getWorkingDays' doc comment).
    final DateTime from = DateTime(2026, 8, 1);
    final DateTime to = DateTime(2026, 8, 20);

    test('ONE serviceId — the generated client emits a Dio ListParam '
        '(NOT a String), and FakeBackend parses it back to that one id', () async {
      await repo.getWorkingDays(
        masterId: 'master-aaa',
        from: from,
        to: to,
        serviceIds: <String>['svc-a'],
      );

      expect(
        capture.sawRequest,
        isTrue,
        reason:
            'the request must actually carry a serviceId param — without '
            'this the assertions below would pass vacuously',
      );

      // ── Half 1: the wire shape, named explicitly. ──────────────────────────
      // If a regen makes this param scalar again, THIS is the assertion that
      // fails, and its message names the type.
      expect(
        capture.lastRaw,
        isA<ListParam<Object?>>(),
        reason:
            'the generated client must send serviceId via '
            'encodeCollectionQueryParameter (a Dio ListParam). If this now '
            'fails, an OpenAPI regen changed the param collection shape — '
            'update FakeBackend._multiQueryParam to match BEFORE chasing the '
            'downstream calendar/slot test failures it will cause.',
      );
      expect(
        (capture.lastRaw! as ListParam<Object?>).format,
        ListFormat.multi,
        reason:
            'repeated `serviceId=a&serviceId=b`, not a comma-joined value '
            '— the backend binds a List<String>',
      );

      // ── Half 2: the fake decodes it. ──────────────────────────────────────
      expect(fb.lastMasterAaaWorkingDaysServiceIds, <String>['svc-a']);
      expect(fb.lastMasterAaaWorkingDaysServiceId, 'svc-a');
    });

    test('TWO serviceIds — FakeBackend records BOTH, in order (the pre-fix '
        'scalar read silently kept only the first)', () async {
      await repo.getWorkingDays(
        masterId: 'master-aaa',
        from: from,
        to: to,
        serviceIds: <String>['svc-a', 'svc-b'],
      );

      expect(capture.lastRaw, isA<ListParam<Object?>>());
      expect(
        (capture.lastRaw! as ListParam<Object?>).value,
        <Object?>['svc-a', 'svc-b'],
        reason: 'both ids must survive on the wire, in the caller order',
      );

      // The load-bearing assertion: the FULL ordered list, not just the head.
      expect(
        fb.lastMasterAaaWorkingDaysServiceIds,
        <String>['svc-a', 'svc-b'],
        reason:
            'a multi-service visit queries availability for the SUMMED '
            'duration of every selected service; dropping the tail silently '
            'books against the wrong duration',
      );
      // The scalar convenience view is explicitly the HEAD — pinned so nobody
      // "fixes" it into something else and breaks the legacy assertions that
      // still read it.
      expect(fb.lastMasterAaaWorkingDaysServiceId, 'svc-a');
    });

    test('NO serviceIds (schedule-shape mode) — the param is omitted entirely '
        'and the fake reports null, not an empty list', () async {
      await repo.getWorkingDays(masterId: 'master-aaa', from: from, to: to);

      expect(
        capture.sawRequest,
        isFalse,
        reason:
            'schedule-shape mode must omit serviceId altogether — sending '
            'an empty list would flip the backend into availability-aware '
            'mode with an empty selection',
      );
      expect(
        fb.lastMasterAaaWorkingDaysServiceIds,
        isNull,
        reason:
            'null means "no constraint"; an empty list would mean "no '
            'service matches" and is a different query',
      );
      expect(fb.lastMasterAaaWorkingDaysServiceId, isNull);
    });

    test('FakeBackend._multiQueryParam tolerates a RAW BuiltList-backed list '
        'too — so the next regen shape does not re-break the fake', () async {
      // Bypasses the generated client and hands the adapter a bare List (the
      // shape the param had BEFORE encodeCollectionQueryParameter, and a
      // plausible shape for it to return to). The fake must cope with both.
      await fb.dio.get<Map<String, dynamic>>(
        '/api/v1/masters/master-aaa/working-days',
        queryParameters: <String, dynamic>{
          'from': '2026-08-01',
          'to': '2026-08-20',
          'serviceId': <String>['svc-a', 'svc-b'],
        },
      );

      expect(fb.lastMasterAaaWorkingDaysServiceIds, <String>['svc-a', 'svc-b']);
    });

    test('a BARE SCALAR serviceId is still accepted — the pre-regen shape must '
        'not throw inside the route callback either', () async {
      await fb.dio.get<Map<String, dynamic>>(
        '/api/v1/masters/master-aaa/working-days',
        queryParameters: <String, dynamic>{
          'from': '2026-08-01',
          'to': '2026-08-20',
          'serviceId': 'svc-solo',
        },
      );

      expect(fb.lastMasterAaaWorkingDaysServiceIds, <String>['svc-solo']);
      expect(fb.lastMasterAaaWorkingDaysServiceId, 'svc-solo');
    });

    test('the generated BuiltList round-trips >2 ids (maxServicesPerVisit '
        'boundary is not silently truncated)', () async {
      final BuiltList<String> ids = BuiltList<String>(<String>[
        'svc-a',
        'svc-b',
        'svc-c',
      ]);
      await repo.getWorkingDays(
        masterId: 'master-aaa',
        from: from,
        to: to,
        serviceIds: ids.toList(),
      );

      expect(fb.lastMasterAaaWorkingDaysServiceIds, <String>[
        'svc-a',
        'svc-b',
        'svc-c',
      ]);
    });
  });
}
