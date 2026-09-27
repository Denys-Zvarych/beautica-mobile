// Phase 7.1 — the RAW QUERY STRING that leaves Dio for `GET /bookings/me`.
//
// WHY THIS FILE EXISTS (and why it is not a duplicate of
// `booking_repository_master_query_test.dart`)
// ---------------------------------------------------------------------------
// The sibling file asserts the `queryParameters` MAP the repository hands to
// Dio — that `status` is a `List<String>` and not a comma-joined string. That
// is necessary and it caught real bugs. But it stops one layer short of the
// bug this phase nearly shipped, because it asserts against a **mocktail
// `Dio`**: a mock never runs Dio's own serialisation, so it cannot observe
// what `?status=` actually looks like on the wire.
//
// The near-miss: the phase doc originally prescribed
// `ListFormat.multiCompatible`. Under that format the SAME `List<String>` this
// suite already asserts is rendered as
//
//     ?status%5B%5D=CONFIRMED&status%5B%5D=COMPLETED     (status[]=…)
//
// which Spring binds to a request parameter literally named `status[]`. The
// declared `status` param stays null, the filter silently does NOTHING, and
// `GET /bookings/me` returns a perfectly valid unfiltered 200. No exception,
// no 400, no failing test — the master's «Мої записи» just quietly ignores
// every filter they set.
//
// `ListFormat` is configured on `BaseOptions`, in `dio_provider.dart` — a file
// this feature does not own and that nothing in the booking suite pins. Someone
// setting `listFormat: ListFormat.multiCompatible` there (a plausible fix for
// an unrelated endpoint) reverts this feature's filtering with a green suite.
//
// So these tests drive a **REAL `Dio`** and capture `RequestOptions.uri`, which
// is where Dio applies `listFormat`. An interceptor rejects the request before
// any socket is opened, so the test stays hermetic while still exercising the
// genuine serialisation path.

import 'dart:io';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_tab.dart';

class _MockBookingApi extends Mock implements BookingControllerApi {}

class _MockReviewApi extends Mock implements ReviewControllerApi {}

class _MockStaffBookingsApi extends Mock implements StaffBookingsApi {}

void main() {
  late Dio dio;
  late HttpBookingRepository repository;
  Uri? capturedUri;

  setUp(() {
    capturedUri = null;
    // A REAL Dio — its BaseOptions are what decide the list rendering. No
    // `listFormat` is set here for the same reason `dio_provider.dart` sets
    // none: the DEFAULT (`ListFormat.multi`) is the correct one, and these
    // tests exist to keep it that way.
    dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          // `options.uri` is the fully-composed URL, with `listFormat` already
          // applied — the exact string that would hit the socket.
          capturedUri = options.uri;
          // Reject before any network work. The repository maps this to a
          // typed Failure, which each test swallows; the assertion is on the
          // captured URI, not on the outcome.
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'intercepted by test',
            ),
          );
        },
      ),
    );
    repository = HttpBookingRepository(
      dio,
      _MockBookingApi(),
      _MockReviewApi(),
      _MockStaffBookingsApi(),
    );
  });

  /// Runs [call], swallows the injected transport failure, and returns the raw
  /// (percent-DECODED) query string Dio composed.
  Future<String> rawQuery(Future<void> Function() call) async {
    try {
      await call();
    } catch (_) {
      // Expected — the interceptor rejects every request.
    }
    expect(
      capturedUri,
      isNotNull,
      reason: 'the repository did not issue a request at all',
    );
    return Uri.decodeQueryComponent(capturedUri!.query);
  }

  group('repeated status params render as ?status=A&status=B', () {
    test(
      'a multi-status filter emits BARE repeated params, never status[]',
      () async {
        final String q = await rawQuery(
          () => repository.getMyBookings(
            statuses: <BookingStatus>{
              BookingStatus.confirmed,
              BookingStatus.completed,
            },
            page: 0,
          ),
        );

        expect(
          q,
          contains('status=CONFIRMED'),
          reason: 'Spring binds a bare repeated `status`, and nothing else',
        );
        expect(q, contains('status=COMPLETED'));

        // The regression itself, stated directly. `status[]=` binds to a param
        // named `status[]`, leaving the real `status` null → unfiltered 200.
        expect(
          q,
          isNot(contains('status[]')),
          reason:
              'ListFormat.multiCompatible would render status[]=…, which Spring '
              'ignores — the filter would silently do nothing',
        );
        // The other wrong renderings, ruled out explicitly.
        expect(
          q,
          isNot(contains('status=CONFIRMED,COMPLETED')),
          reason: 'ListFormat.csv would collapse the list into one param',
        );
      },
    );

    test('exactly one `status=` segment per selected status — no dropped or '
        'duplicated value', () async {
      final String q = await rawQuery(
        () => repository.getMyBookings(
          statuses: BookingStatus.filterable.toSet(),
          page: 0,
        ),
      );

      expect(
        'status='.allMatches(q).length,
        5,
        reason: 'five filterable statuses → five bare status= segments',
      );
      expect(q, isNot(contains('UNKNOWN')));
    });

    test(
      'a single-status filter is still a bare param (not a special case)',
      () async {
        final String q = await rawQuery(
          () => repository.getMyBookings(
            statuses: <BookingStatus>{BookingStatus.confirmed},
            page: 0,
          ),
        );

        expect(q, contains('status=CONFIRMED'));
        expect(q, isNot(contains('status[]')));
      },
    );
  });

  group('repeated serviceId params render the same way (backend 26.4)', () {
    test(
      'a multi-service filter emits bare repeated serviceId params',
      () async {
        final String q = await rawQuery(
          () => repository.getMyBookings(
            statuses: const <BookingStatus>{},
            serviceIds: <String>{'svc-alpha', 'svc-zebra'},
            page: 0,
          ),
        );

        expect(q, contains('serviceId=svc-alpha'));
        expect(q, contains('serviceId=svc-zebra'));
        expect(q, isNot(contains('serviceId[]')));
        expect(q, isNot(contains('serviceId=svc-alpha,svc-zebra')));
      },
    );
  });

  group('the scalar params survive real serialisation too', () {
    test(
      'date bounds reach the URL as bare yyyy-MM-dd, not a timestamp',
      () async {
        final String q = await rawQuery(
          () => repository.getMyBookings(
            statuses: const <BookingStatus>{},
            from: DateTime(2026, 7, 1),
            to: DateTime(2026, 7, 31),
            page: 0,
          ),
        );

        expect(q, contains('from=2026-07-01'));
        expect(q, contains('to=2026-07-31'));
        // A leaked `toIso8601String()` would put a `T` and a colon in there,
        // which the backend's ISO.DATE binder rejects outright.
        expect(q, isNot(contains('T00:00')));
      },
    );

    test('the sort param survives as `<property>,<direction>` — the comma is '
        'NOT escaped into a separate value', () async {
      final String q = await rawQuery(
        () => repository.getMyBookings(
          statuses: const <BookingStatus>{},
          sort: BookingSort.oldest,
          page: 0,
        ),
      );

      expect(q, contains('sort=startsAt,asc'));
      // Guards the mirror-image mistake: sending the sort as a two-element
      // List would render `sort=startsAt&sort=asc`, which the 26.6
      // whitelist rejects with a 400.
      expect(q, isNot(contains('sort=asc')));
    });
  });

  // ==========================================================================
  // The tests above drive a Dio this FILE constructs. That proves the
  // repository + Dio's default rendering agree — but it would keep passing if
  // `dio_provider.dart` (the Dio the APP actually ships) started overriding
  // `listFormat`, because this file never reads that file's options.
  //
  // Closing that loop by instantiating the real `dioProvider` is not viable in
  // a unit test: it asserts a secure base URL and installs a pinned
  // `SecurityContext` from `initCertPinning`. So the app-side half is pinned
  // STRUCTURALLY — the same approach as `add_2_calendar_version_pin_test.dart`,
  // which likewise guards a config value no runtime assertion can reach.
  // ==========================================================================
  group('the APP\'s Dio keeps Dio\'s default ListFormat (structural pin)', () {
    test('dio_provider.dart declares no listFormat override', () {
      final File provider = File('lib/core/network/dio_provider.dart');
      expect(
        provider.existsSync(),
        isTrue,
        reason: 'dio_provider.dart moved — update this guard',
      );

      expect(
        provider.readAsStringSync(),
        isNot(contains('listFormat')),
        reason:
            'Setting listFormat on the app Dio silently changes how every '
            'repeated query param renders. `ListFormat.multiCompatible` in '
            'particular turns ?status=A&status=B into ?status[]=A&status[]=B, '
            'which Spring binds to a param named "status[]" — every booking '
            'filter would stop working and the endpoint would still return '
            '200. If a listFormat override is genuinely needed, set it '
            'PER-REQUEST in the repository and re-point this guard.',
      );
    });

    test('Dio\'s own default is still ListFormat.multi — the assumption the '
        'repository is written against', () {
      // If a future Dio major flips the default, the tests above would keep
      // passing against this file's own Dio while the app broke. This states
      // the assumption so the upgrade surfaces it.
      expect(BaseOptions().listFormat, ListFormat.multi);
    });
  });

  group('the CLIENT tabs go out on the same wire format (regression gate)', () {
    // `MyBookingsNotifier` reaches this serialisation boundary WITHOUT passing
    // through `MasterBookingsQuery`, so the shipped client tabs need their own
    // wire assertion — a ListFormat change breaks them identically.
    for (final BookingTab tab in BookingTab.values) {
      test('$tab emits bare repeated status params', () async {
        final String q = await rawQuery(
          () => repository.getMyBookings(statuses: tab.statuses, page: 0),
        );

        expect(q, isNot(contains('status[]')));
        expect('status='.allMatches(q).length, tab.statuses.length);
        for (final BookingStatus s in tab.statuses) {
          expect(q, contains('status=${s.wireValue}'));
        }
      });
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 342 D2 — `GET /bookings/salon/{salonId}` after backend phases 319
  // (repeatable `status`) and 322 (`partition`). The wrapper used to take ONE
  // `BookingStatus?` and two REQUIRED bounds; all three were widened.
  // ───────────────────────────────────────────────────────────────────────────
  group('getSalonBookings — the widened wire (phase 342 D2)', () {
    const String salonId = '11111111-2222-3333-4444-555555555555';

    test('the ARCHIVE shape: partition=HISTORY is sent, and NEITHER `from` nor '
        '`to` appears in the query string at all', () async {
      final String q = await rawQuery(
        () => repository.getSalonBookings(
          salonId: salonId,
          statuses: const <BookingStatus>{
            BookingStatus.completed,
            BookingStatus.notCompleted,
            BookingStatus.cancelled,
            BookingStatus.declined,
          },
          partition: BookingPartition.history,
          sort: BookingSort.newest,
          page: 0,
        ),
      );

      expect(q, contains('partition=HISTORY'));
      expect(
        q,
        isNot(contains('from=')),
        reason:
            'an omitted bound must be DROPPED, never sent as `from=` or '
            '`from=null` — the archive wants the salon whole history',
      );
      expect(q, isNot(contains('to=')));
      expect(q, contains('sort=${BookingSort.newest.wireValue}'));
      expect(q, contains('page=0'));
    });

    test('statuses render as BARE repeated `status=` params — one per '
        'selected status, never status[] and never a csv join', () async {
      final String q = await rawQuery(
        () => repository.getSalonBookings(
          salonId: salonId,
          statuses: const <BookingStatus>{
            BookingStatus.confirmed,
            BookingStatus.completed,
          },
          page: 0,
        ),
      );

      expect(q, contains('status=CONFIRMED'));
      expect(q, contains('status=COMPLETED'));
      expect('status='.allMatches(q).length, 2);
      expect(
        q,
        isNot(contains('status[]')),
        reason:
            'ListFormat.multiCompatible would render status[]=…, which Spring '
            'binds to a param literally named `status[]` — the filter would '
            'silently do nothing and the endpoint would return unfiltered 200s',
      );
      expect(q, isNot(contains('status=CONFIRMED,COMPLETED')));
    });

    test(
      'BookingStatus.unknown is STRIPPED, not sent — it is a decode-only '
      'member with no wire representation and `status=UNKNOWN` is a 400',
      () async {
        final String q = await rawQuery(
          () => repository.getSalonBookings(
            salonId: salonId,
            statuses: const <BookingStatus>{
              BookingStatus.unknown,
              BookingStatus.completed,
            },
            page: 0,
          ),
        );

        expect(q, contains('status=COMPLETED'));
        expect('status='.allMatches(q).length, 1);
        expect(q, isNot(contains('UNKNOWN')));
      },
    );

    test('an omitted / empty statuses set emits NO `status` param at all — no '
        'predicate, not an empty one', () async {
      final String q = await rawQuery(
        () => repository.getSalonBookings(salonId: salonId, page: 0),
      );

      expect(q, isNot(contains('status')));
      expect(
        q,
        isNot(contains('partition')),
        reason:
            'an omitted partition is byte-identical pre-322 behaviour, not '
            '`partition=`',
      );
    });

    test(
      'the BOARD shape is unchanged by the widening — both bounds still go '
      'out as `yyyy-MM-dd`, and no partition or status rides along',
      () async {
        final String q = await rawQuery(
          () => repository.getSalonBookings(
            salonId: salonId,
            masterId: 'master-9',
            from: DateTime(2026, 3, 7),
            to: DateTime(2026, 3, 7),
            sort: BookingSort.oldest,
            page: 0,
            size: 100,
          ),
        );

        expect(q, contains('from=2026-03-07'));
        expect(q, contains('to=2026-03-07'));
        expect(q, contains('masterId=master-9'));
        expect(q, contains('size=100'));
        expect(q, isNot(contains('partition')));
        expect(q, isNot(contains('status')));
      },
    );

    // mobile-qa (phase 342 QA pass) — the two claims this group's original
    // cases could not fail on.

    test('the repeated statuses are CANONICALLY ORDERED by enum index, not by '
        'the order the caller built the set in — the emitted URL is a pure '
        'function of the filter VALUE', () async {
      // Deliberately built in REVERSE declaration order. The `contains`
      // assertions above are order-insensitive and stay green with the sort
      // deleted or reversed; this one pins the sequence.
      final String q = await rawQuery(
        () => repository.getSalonBookings(
          salonId: salonId,
          statuses: <BookingStatus>{
            BookingStatus.declined,
            BookingStatus.completed,
            BookingStatus.confirmed,
          },
          page: 0,
        ),
      );

      final List<String> emitted = RegExp('status=([A-Z_]+)')
          .allMatches(q)
          .map((RegExpMatch m) => m.group(1)!)
          .toList(growable: false);
      final List<String> canonical =
          (<BookingStatus>[
                BookingStatus.declined,
                BookingStatus.completed,
                BookingStatus.confirmed,
              ]..sort(
                (BookingStatus a, BookingStatus b) =>
                    a.index.compareTo(b.index),
              ))
              .map((BookingStatus st) => st.wireValue)
              .toList(growable: false);

      expect(
        emitted,
        canonical,
        reason:
            'this method\'s doc claims the set is canonicalised at the '
            'serialisation boundary "sorted by enum index, not by wire '
            'string". Without that, two callers holding the SAME filter emit '
            'different URLs',
      );
      // Non-vacuity: the fixture must actually MOVE under the sort, otherwise
      // this test would pass with the sort deleted.
      expect(
        canonical,
        isNot(<String>[
          BookingStatus.declined.wireValue,
          BookingStatus.completed.wireValue,
          BookingStatus.confirmed.wireValue,
        ]),
        reason:
            'the insertion order and the canonical order must DIFFER, or the '
            'assertion above is satisfied by an unsorted list too',
      );
    });

    test('`from` and `to` are INDEPENDENTLY optional — a one-sided window '
        'sends exactly that one bound, never both and never neither', () async {
      final String fromOnly = await rawQuery(
        () => repository.getSalonBookings(
          salonId: salonId,
          from: DateTime(2026, 3, 7),
          page: 0,
        ),
      );
      expect(fromOnly, contains('from=2026-03-07'));
      expect(
        fromOnly,
        isNot(contains('to=')),
        reason:
            'an open-ended FUTURE window: coupling the two bounds (`if (from '
            '!= null && to != null)`) would silently drop the one the caller '
            'did pass and return an unfiltered page',
      );

      final String toOnly = await rawQuery(
        () => repository.getSalonBookings(
          salonId: salonId,
          to: DateTime(2026, 3, 7),
          page: 0,
        ),
      );
      expect(toOnly, contains('to=2026-03-07'));
      expect(
        toOnly,
        isNot(contains('from=')),
        reason: 'an open-ended PAST window',
      );
    });
  });
}
