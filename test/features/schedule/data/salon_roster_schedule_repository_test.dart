// Phase 335 — Unit tests for [HttpSalonRosterScheduleRepository]
// (`GET /salons/{salonId}/masters/effective-schedule`).
//
// Same strategy as `schedule_repository_test.dart`: mock the generated
// [SalonControllerApi] with mocktail and construct the repository directly. No
// ProviderScope.
//
// Covers: the masterId-keyed grouping, ROSTER-COMPLETENESS survival (a master
// with zero schedule rows must come back as an EMPTY list, never be dropped —
// that entry is the only thing that lets a caller tell "off today" from "not
// loaded"), the 62-day range guard firing BEFORE any wire call, the empty-salon
// fail-fast, and the typed-failure mapping.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSalonControllerApi extends Mock implements SalonControllerApi {}

const String _salonId = 'salon-1';
const String _path = '/api/v1/salons/$_salonId/masters/effective-schedule';

// future-date-ok: fixed PAST dates, used only as request bounds / row dates
final DateTime _from = DateTime(2026, 6);
final DateTime _to = DateTime(2026, 6, 30);

Response<ApiResponseListSalonMasterEffectiveScheduleResponse> _envelope(
  Iterable<SalonMasterEffectiveScheduleResponse> rows,
) => Response<ApiResponseListSalonMasterEffectiveScheduleResponse>(
  data: ApiResponseListSalonMasterEffectiveScheduleResponse(
    (b) => b
      ..success = true
      ..data.replace(rows),
  ),
  requestOptions: RequestOptions(path: _path),
  statusCode: 200,
);

/// One working day, 09:00–18:00, on 2026-06-15.
EffectiveDayResponse _workingDay() => EffectiveDayResponse(
  (b) => b
    ..date = Date(2026, 6, 15)
    ..source_ = EffectiveDayResponseSource_Enum.TEMPLATE
    ..intervals.replace(<WorkIntervalDto>[
      WorkIntervalDto(
        (i) => i
          ..startTime = '09:00:00'
          ..endTime = '18:00:00',
      ),
    ]),
);

SalonMasterEffectiveScheduleResponse _entry({
  required String? masterId,
  List<EffectiveDayResponse>? days,
}) => SalonMasterEffectiveScheduleResponse((b) {
  b.masterId = masterId;
  if (days != null) b.days.replace(days);
});

void main() {
  // `any()` on the generated `Date` parameters needs a registered fallback.
  setUpAll(() => registerFallbackValue(Date(2026, 1, 1)));

  /// The guard asserts in debug (test) mode and throws [ValidationFailure] in
  /// release; tests run with asserts ON, so an [AssertionError] fires first.
  /// The contract under audit is "rejects BEFORE any wire call" — accept
  /// either mechanism and prove no call, exactly as
  /// `schedule_repository_test.dart`'s own bounded-range group does.
  final Matcher rejectsBeforeCall = throwsA(
    anyOf(isA<AssertionError>(), isA<ValidationFailure>()),
  );

  late _MockSalonControllerApi api;
  late SalonRosterScheduleRepository repo;

  setUp(() {
    api = _MockSalonControllerApi();
    repo = HttpSalonRosterScheduleRepository(salonApi: api);
  });

  void stub(
    Response<ApiResponseListSalonMasterEffectiveScheduleResponse> response,
  ) {
    when(
      () => api.getSalonMastersEffectiveSchedule(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) async => response);
  }

  test('keys the result by masterId and maps each day', () async {
    stub(
      _envelope(<SalonMasterEffectiveScheduleResponse>[
        _entry(masterId: 'm1', days: <EffectiveDayResponse>[_workingDay()]),
        _entry(masterId: 'm2', days: <EffectiveDayResponse>[_workingDay()]),
      ]),
    );

    final Map<String, List<EffectiveDay>> out = await repo
        .salonRosterEffectiveSchedule(_salonId, _from, _to);

    expect(out.keys, <String>['m1', 'm2']);
    expect(out['m1']?.single.source, EffectiveSource.template);
    expect(out['m1']?.single.intervals.single.startMinutes, 9 * 60);
    expect(out['m1']?.single.intervals.single.endMinutes, 18 * 60);
  });

  // ── QA 2026-09-17 — THE WIRE ARGUMENTS WERE NOT PINNED ANYWHERE ────────
  // Every test in this file stubbed with `any()` on all three params and
  // never verified them; the notifier tier above verifies the REPOSITORY's
  // arguments, not the API's; and the integration tier's fake backend ignores
  // `from`/`to` entirely. Mutation-proved: swapping the two bounds at the call
  // site (`from: dateToWire(to), to: dateToWire(from)`) left all 9 tests in
  // this file GREEN. An inverted window is a 400 on a real backend and a
  // silently blank board here — M4, strict argument matching.
  test('puts the salonId and BOTH range bounds on the wire VERBATIM — a '
      'swapped, dropped or re-derived bound would fetch a window the board is '
      'not showing', () async {
    stub(_envelope(const <SalonMasterEffectiveScheduleResponse>[]));

    await repo.salonRosterEffectiveSchedule(_salonId, _from, _to);

    // Exact values, never `any()`: `_from` is June 1st and `_to` June 30th, so
    // the two are distinguishable and a swap cannot pass.
    verify(
      () => api.getSalonMastersEffectiveSchedule(
        salonId: _salonId,
        from: Date(2026, 6, 1),
        to: Date(2026, 6, 30),
      ),
    ).called(1);
  });

  test('ROSTER-COMPLETENESS survives the mapping: a master with NO days comes '
      'back as an EMPTY list, never a missing key — that entry is what lets a '
      'caller tell "off today" from "not loaded"', () async {
    stub(
      _envelope(<SalonMasterEffectiveScheduleResponse>[
        _entry(masterId: 'm1', days: <EffectiveDayResponse>[_workingDay()]),
        // `days` omitted entirely — the shape a master with zero schedule
        // rows produces on the wire.
        _entry(masterId: 'm-no-schedule'),
      ]),
    );

    final Map<String, List<EffectiveDay>> out = await repo
        .salonRosterEffectiveSchedule(_salonId, _from, _to);

    expect(out.containsKey('m-no-schedule'), isTrue);
    expect(out['m-no-schedule'], isEmpty);
  });

  test('drops an entry with no masterId rather than keying it on the empty '
      'string, which would silently merge two such entries', () async {
    stub(
      _envelope(<SalonMasterEffectiveScheduleResponse>[
        _entry(masterId: null, days: <EffectiveDayResponse>[_workingDay()]),
        _entry(masterId: 'm1', days: <EffectiveDayResponse>[_workingDay()]),
      ]),
    );

    final Map<String, List<EffectiveDay>> out = await repo
        .salonRosterEffectiveSchedule(_salonId, _from, _to);

    expect(out.keys, <String>['m1']);
  });

  test('a null data envelope maps to an empty map, never a throw', () async {
    stub(
      Response<ApiResponseListSalonMasterEffectiveScheduleResponse>(
        data: null,
        requestOptions: RequestOptions(path: _path),
        statusCode: 200,
      ),
    );

    expect(
      await repo.salonRosterEffectiveSchedule(_salonId, _from, _to),
      isEmpty,
    );
  });

  test('an over-wide range throws ValidationFailure BEFORE any wire call — the '
      '62-day batch cap, not the 366-day per-master one', () async {
    await expectLater(
      repo.salonRosterEffectiveSchedule(
        _salonId,
        _from,
        _from.add(const Duration(days: kMaxSalonRosterScheduleRangeDays + 1)),
      ),
      rejectsBeforeCall,
    );
    verifyNever(
      () => api.getSalonMastersEffectiveSchedule(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    );
  });

  test(
    'a 63-day range across the Kyiv spring forward (2026-03-01..05-03) is '
    'still rejected — `difference().inDays` read it as 62 and let it through',
    () async {
      await expectLater(
        repo.salonRosterEffectiveSchedule(
          _salonId,
          DateTime(2026, 3, 1),
          DateTime(2026, 5, 3),
        ),
        rejectsBeforeCall,
      );
      verifyNever(
        () => api.getSalonMastersEffectiveSchedule(
          salonId: any(named: 'salonId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
    },
  );

  test(
    'an inverted range throws ValidationFailure before any wire call',
    () async {
      await expectLater(
        repo.salonRosterEffectiveSchedule(_salonId, _to, _from),
        rejectsBeforeCall,
      );
      verifyNever(
        () => api.getSalonMastersEffectiveSchedule(
          salonId: any(named: 'salonId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
    },
  );

  test(
    'an empty salonId fails fast with UnauthorizedFailure, no wire call',
    () async {
      await expectLater(
        repo.salonRosterEffectiveSchedule('', _from, _to),
        throwsA(isA<UnauthorizedFailure>()),
      );
      verifyNever(
        () => api.getSalonMastersEffectiveSchedule(
          salonId: any(named: 'salonId'),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
    },
  );

  test('a connection error maps to NetworkFailure — no raw DioException '
      'escapes', () async {
    when(
      () => api.getSalonMastersEffectiveSchedule(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: _path),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      repo.salonRosterEffectiveSchedule(_salonId, _from, _to),
      throwsA(isA<NetworkFailure>()),
    );
  });

  // ── QA 2026-09-17 — THE badCertificate ARM HAD NO TEST IN THE FEATURE ──
  // Phase 335 hoisted the per-arm `DioException` mapping out of
  // `HttpScheduleRepository._mapDioException` into the library-private
  // `_mapScheduleDioException`, which BOTH schedule repositories now share.
  // The `badCertificate` arm moved verbatim — and moved without coverage:
  // mutation-proved, rewriting it to `return NetworkFailure(cause: e)` left
  // all 112 tests under `test/features/schedule/data/` green, for the master
  // repository as well as this one.
  //
  // What the arm must keep doing is FAIL CLOSED: a TLS failure is a possible
  // MITM on schedule traffic and must surface as a [ServerFailure], never as
  // a [NetworkFailure] — the latter is the app's "you are offline, retry"
  // shape, which invites a caller to retry straight back into the attacker.
  // The Dart switch is exhaustive over `DioExceptionType`, so DELETING the
  // arm is a compile error; silently RE-MAPPING it is not, and this is what
  // catches that.
  test('a badCertificate FAILS CLOSED as ServerFailure — a possible MITM on '
      'schedule traffic must never be reported as mere connectivity, which is '
      'the app\'s retry-me shape', () async {
    when(
      () => api.getSalonMastersEffectiveSchedule(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: _path),
        type: DioExceptionType.badCertificate,
      ),
    );

    await expectLater(
      repo.salonRosterEffectiveSchedule(_salonId, _from, _to),
      throwsA(
        isA<ServerFailure>().having(
          (ServerFailure f) => f.cause,
          'cause',
          isA<DioException>(),
        ),
      ),
    );
    // NOT the connectivity failure — asserted separately because
    // `isA<ServerFailure>` alone would also admit a subtype relationship that
    // does not exist today but could be introduced.
    await expectLater(
      repo.salonRosterEffectiveSchedule(_salonId, _from, _to),
      throwsA(isNot(isA<NetworkFailure>())),
    );
  });

  test('a Failure the interceptor already attached is re-thrown verbatim (an '
      'expired session on a board the caller left open)', () async {
    when(
      () => api.getSalonMastersEffectiveSchedule(
        salonId: any(named: 'salonId'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: _path),
        type: DioExceptionType.badResponse,
        error: const UnauthorizedFailure(),
      ),
    );

    await expectLater(
      repo.salonRosterEffectiveSchedule(_salonId, _from, _to),
      throwsA(isA<UnauthorizedFailure>()),
    );
  });
}
