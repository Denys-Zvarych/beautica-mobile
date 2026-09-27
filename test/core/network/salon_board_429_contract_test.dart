// CHAIN-LEVEL contract tests for HTTP 429 on the three SALON BOARD routes.
//
// WHY THIS FILE EXISTS
// --------------------
// Backend PR #130 put a shared per-user 60/min budget in front of the three
// endpoints the salon «Записи» board lives on, answering HTTP 429 with a
// `Retry-After` header:
//
//   GET /api/v1/salons/{salonId}/masters/effective-schedule
//   GET /api/v1/bookings/salon/{salonId}/booked-days
//   GET /api/v1/bookings/salon/{salonId}            (incl. ?partition=HISTORY)
//
// Two prior audits disagreed on which [Failure] a 429 on these routes
// produces: `UnknownFailure` (from `ErrorMapperInterceptor`'s fall-through)
// or `ServerFailure(statusCode: 429)` (from each repository's own
// `_mapDioException`). The disagreement is not academic — it decides whether
// `isTransientFailure` sees a 5xx-shaped `ServerFailure` and hands the board
// an automatic retry straight back into a live rate limit.
//
// A STATIC reading cannot settle it, because the two mappers are chained: the
// interceptor rejects with a NEW DioException carrying the Failure as
// `error`, and every repository mapper opens with
// `if (e.error is Failure) return e.error as Failure;`. Which one wins
// depends on whether the interceptor is actually REACHED — precisely the
// class of defect `interceptor_chain_test.dart` was written for after
// `RefreshInterceptor` sat unreachable for every endpoint in the app.
//
// So these tests do what a static read cannot: they wire the REAL
// `dioProvider` (production interceptor list, production order) to a scripted
// transport that answers 429 with a `Retry-After`, then drive the REAL
// repositories through their REAL providers and assert the [Failure] that
// comes out the far end.
//
// THREE INVARIANTS ARE PINNED PER ROUTE (these are the load-bearing ones):
//   1. NO LOGOUT.        A 429 must never destroy the session. `RefreshInterceptor`
//                        only acts on 401 (`refresh_interceptor.dart`), but that
//                        is a property of the interceptor ORDER, which a future
//                        reorder can silently break — exactly the shipped defect
//                        `interceptor_chain_test.dart` documents.
//   2. NO TOKEN REFRESH. A 429 is not an auth failure; burning a refresh token
//                        on one is both wasted and a second hit on the limiter.
//   3. NO AUTO-RETRY.    Exactly ONE transport round-trip. The scripted adapter
//                        throws on an unscripted call, so a hidden replay or a
//                        repository-level retry loop fails loudly instead of
//                        silently reusing the last reply.
//
// GROUND TRUTH IS PINNED SEPARATELY from the invariants, in its own group, so
// that the fix for the 429 mapping defect (see `_kRetryAfterSeconds` below)
// touches one group and leaves the three invariants untouched.
//
// TRANSPORT-LEVEL COUNTING IS DELIBERATE, for the same reason
// `interceptor_chain_test.dart` gives: asserting only on the final `Failure`
// cannot distinguish "failed once" from "retried three times and failed".
//
// RETRY IS PINNED TO "NEVER" AT THE CONTAINER, and that is NOT what makes the
// no-auto-retry assertion pass. These tests call the repository METHOD
// directly — no provider build is in flight — so `beauticaProviderRetry` is
// not in the path at all. The container-level pin only stops an unrelated
// provider in the harness (`authProvider`) from re-issuing work behind the
// test's back. The `beauticaProviderRetry` classification of the mapped
// failure is asserted EXPLICITLY and separately, in the ground-truth group.

import 'dart:convert';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/refresh_dio_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String kRefreshPath = '/api/v1/auth/refresh';
const String kStaleAccess = 'stale-access';

/// A salon id that survives `encodePathSegment` unchanged (no `.`, no `..`,
/// nothing percent-encodable) so a rejected segment can never be mistaken for
/// the 429 mapping under test.
const String kSalonId = '11111111-2222-3333-4444-555555555555';

/// The `Retry-After` the backend's limiter sends (PR #130).
///
/// Deliberately a value no other fixture in this file uses, so an assertion
/// that finds it has genuinely read the header rather than coincidentally
/// matched a default.
const int _kRetryAfterSeconds = 37;

/// A window inside `kMaxSalonRosterScheduleRangeDays` (62) so the
/// repository's own bounded-range guard cannot pre-empt the transport and
/// throw a `ValidationFailure` that never reaches the interceptor.
final DateTime kFrom = DateTime(2026, 3, 1);
final DateTime kTo = DateTime(2026, 3, 31);

// ---------------------------------------------------------------------------
// Mocks / scripted transport
// ---------------------------------------------------------------------------

class _MockDio extends Mock implements Dio {}

/// [HttpClientAdapter] that answers every request with one 429 carrying a
/// `Retry-After` header, and records what reached the wire.
///
/// Throws after the first call so an automatic retry — at the Dio layer, the
/// repository layer, or a provider — surfaces as a loud failure rather than a
/// silently-reused reply.
final class _RateLimitedAdapter implements HttpClientAdapter {
  final List<String> paths = <String>[];
  final List<Map<String, dynamic>> queries = <Map<String, dynamic>>[];

  int get calls => paths.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (calls >= 1) {
      throw StateError(
        'Transport called ${calls + 1} times — the salon board must NOT '
        'auto-retry a 429. paths=$paths',
      );
    }
    paths.add(options.path);
    queries.add(Map<String, dynamic>.from(options.queryParameters));
    return ResponseBody.fromString(
      jsonEncode(const <String, dynamic>{
        'success': false,
        'message': 'Too many requests',
      }),
      429,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
        // Lower-case: Dio normalises response header keys, and the mapper's
        // own extractor reads them case-insensitively. Spelling it the way
        // the wire actually delivers it keeps this fixture honest.
        'retry-after': <String>['$_kRetryAfterSeconds'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Retry pinned to "never" for the harness's own providers. See the file
/// header — this is NOT what proves the no-auto-retry assertion.
Duration? _noRetry(int retryCount, Object error) => null;

final class _Board {
  _Board({
    required this.container,
    required this.adapter,
    required this.authRepo,
    required this.refreshDio,
  });

  final ProviderContainer container;
  final _RateLimitedAdapter adapter;
  final FakeAuthRepository authRepo;
  final _MockDio refreshDio;

  int get transportCalls => adapter.calls;

  int get logoutCalls => authRepo.logoutCallCount;

  BookingRepository get bookings => container.read(bookingRepositoryProvider);

  SalonRosterScheduleRepository get rosterSchedule =>
      container.read(salonRosterScheduleRepositoryProvider);

  /// mocktail's `verify(...).callCount` FAILS rather than returning 0 when
  /// nothing matched, so the zero case gets `verifyNever` per the repo
  /// convention.
  void expectNoRefresh() => verifyNever(
    () => refreshDio.post<Map<String, dynamic>>(
      kRefreshPath,
      data: any(named: 'data'),
    ),
  );
}

/// Boots the REAL production Dio (via `dioProvider`, production interceptor
/// list and order) over a transport that answers 429, with an already-settled
/// `Authenticated` session.
Future<_Board> _boot() async {
  final FakeSecureStorage storage = FakeSecureStorage();
  await storage.writeRefreshToken('stored-refresh');

  final FakeAuthRepository authRepo = FakeAuthRepository()
    ..refreshResult = const AuthTokens(
      accessToken: kStaleAccess,
      refreshToken: 'stored-refresh',
    );

  final _MockDio refreshDio = _MockDio();

  final ProviderContainer container = ProviderContainer(
    retry: _noRetry,
    overrides: [
      secureStorageProvider.overrideWith((_) => storage),
      authRepositoryProvider.overrideWith((_) => authRepo),
      // Keeps the refresh round-trip off the scripted transport so
      // `transportCalls` counts ONLY the board's own request.
      refreshDioProvider.overrideWith((_) => refreshDio),
    ],
  );
  addTearDown(container.dispose);

  final Dio dio = container.read(dioProvider);
  final _RateLimitedAdapter adapter = _RateLimitedAdapter();
  dio.httpClientAdapter = adapter;

  final AuthSession session = await container.read(authProvider.future);
  expect(
    session,
    isA<Authenticated>(),
    reason: 'harness precondition: the board runs under a live session',
  );

  return _Board(
    container: container,
    adapter: adapter,
    authRepo: authRepo,
    refreshDio: refreshDio,
  );
}

/// Runs [call] and returns the [Failure] it threw.
///
/// Fails the test if it completes, or throws a non-[Failure] — a raw
/// `DioException` escaping the repository layer is itself a contract breach
/// and must not be silently reported as "wrong failure type".
Future<Failure> _failureFrom(Future<void> Function() call) async {
  try {
    await call();
  } on Failure catch (f) {
    return f;
  } catch (e) {
    fail('Expected a Failure, got ${e.runtimeType}: $e');
  }
  fail('Expected the call to throw on 429, but it completed');
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // GROUP 1 — the three invariants, per route.
  //
  // These must hold whatever the 429 mapping ends up being, so they are
  // deliberately type-agnostic: they assert on the session, the refresh
  // round-trip and the transport count, never on the Failure subtype.
  // ══════════════════════════════════════════════════════════════════════
  group('429 on a salon-board route never logs out, refreshes or retries', () {
    test('GET /bookings/salon/{id} (board)', () async {
      final _Board board = await _boot();

      final Failure f = await _failureFrom(
        () => board.bookings.getSalonBookings(salonId: kSalonId, page: 0),
      );

      expect(f, isNotNull);
      expect(
        board.transportCalls,
        1,
        reason: 'a 429 must cost exactly one round-trip, never a replay',
      );
      expect(
        board.logoutCalls,
        0,
        reason: 'a 429 must not destroy the session',
      );
      board.expectNoRefresh();
      expect(
        board.container.read(authProvider).value,
        isA<Authenticated>(),
        reason: 'the session must survive a rate limit intact',
      );
    });

    test('GET /bookings/salon/{id}?partition=HISTORY (archive)', () async {
      final _Board board = await _boot();

      await _failureFrom(
        () => board.bookings.getSalonBookings(
          salonId: kSalonId,
          page: 0,
          partition: BookingPartition.history,
        ),
      );

      // Pins that the ARCHIVE variant really did travel as its own request
      // shape — otherwise this test would be a duplicate of the board one
      // and the `partition` arm would be untested.
      expect(
        board.adapter.queries.single['partition'],
        BookingPartition.history.wireValue,
        reason: 'the archive route must be exercised, not the plain board one',
      );
      expect(board.transportCalls, 1);
      expect(board.logoutCalls, 0);
      board.expectNoRefresh();
      expect(board.container.read(authProvider).value, isA<Authenticated>());
    });

    test('GET /bookings/salon/{id}/booked-days (day dots)', () async {
      final _Board board = await _boot();

      await _failureFrom(
        () => board.bookings.getSalonBookedDays(
          salonId: kSalonId,
          from: kFrom,
          to: kTo,
        ),
      );

      expect(
        board.adapter.paths.single,
        '/api/v1/bookings/salon/$kSalonId/booked-days',
        reason: 'the booked-days route must be the one that got limited',
      );
      expect(board.transportCalls, 1);
      expect(board.logoutCalls, 0);
      board.expectNoRefresh();
      expect(board.container.read(authProvider).value, isA<Authenticated>());
    });

    test('GET /salons/{id}/masters/effective-schedule (roster)', () async {
      final _Board board = await _boot();

      await _failureFrom(
        () => board.rosterSchedule.salonRosterEffectiveSchedule(
          kSalonId,
          kFrom,
          kTo,
        ),
      );

      expect(
        board.adapter.paths.single,
        contains('/masters/effective-schedule'),
        reason: 'the roster-schedule route must be the one that got limited',
      );
      expect(board.transportCalls, 1);
      expect(board.logoutCalls, 0);
      board.expectNoRefresh();
      expect(board.container.read(authProvider).value, isA<Authenticated>());
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // GROUP 2 — the 429 mapping, MEASURED through the real chain.
  //
  // ── UPDATED 2026-09-20, WHEN THE MAPPING WAS FIXED ────────────────────
  //
  // This group used to record the DEFECT as ground truth: all four routes
  // fell through `ErrorMapperInterceptor`'s status chain to the terminal
  // `UnknownFailure`, `isThrottleFailure` answered `false`, and the
  // `Retry-After` the transport really sent reached `Failure.cause` and
  // nowhere else — so no screen could render a cooldown and every retry
  // affordance re-fired straight back into a live limiter.
  //
  // `ErrorMapperInterceptor` now maps a 429 on those routes to
  // [SalonBoardRateLimitedFailure], carrying `retryAfterSeconds` parsed by
  // the interceptor's OWN existing `_extractRetryAfterSecondsNullable` (the
  // same header-then-body resolver, and the same 600 s UX ceiling, every
  // other throttle in the app uses). The three expectations below were
  // flipped deliberately, one per defect the old group recorded:
  //
  //   1. the type          UnknownFailure          → SalonBoardRateLimitedFailure
  //   2. isThrottleFailure false                   → true
  //   3. Retry-After       discarded (cause only)  → 37 on the Failure itself
  //
  // WHAT DID NOT CHANGE, and must not: GROUP 1's three invariants (no
  // logout, no token refresh, no auto-retry) are untouched, and the
  // `beauticaProviderRetry(0, f) == null` assertion below is asserted
  // against the NEW type — which is classified TRANSIENT, so that null is
  // now the throttle guard talking and nothing else. That is the exact
  // regression the old comment warned about ("a fix that makes the failure
  // transient without making it a throttle would silently START
  // auto-retrying"), and it is why the assertion stayed.
  // ══════════════════════════════════════════════════════════════════════
  group('429 mapping — measured through the real chain', () {
    test('every board route maps a 429 to the SAME failure type', () async {
      final _Board a = await _boot();
      final Failure board429 = await _failureFrom(
        () => a.bookings.getSalonBookings(salonId: kSalonId, page: 0),
      );

      final _Board b = await _boot();
      final Failure days429 = await _failureFrom(
        () => b.bookings.getSalonBookedDays(
          salonId: kSalonId,
          from: kFrom,
          to: kTo,
        ),
      );

      final _Board c = await _boot();
      final Failure roster429 = await _failureFrom(
        () =>
            c.rosterSchedule.salonRosterEffectiveSchedule(kSalonId, kFrom, kTo),
      );

      // The `ErrorMapperInterceptor` mapping wins on all three, and that is
      // the SAME chain fact the old `UnknownFailure` expectation recorded —
      // only the branch it lands on changed. The interceptor runs LAST in
      // the production chain, rejects with a new DioException whose `error`
      // is the mapped Failure, and every repository mapper's first line
      // (`if (e.error is Failure) return e.error as Failure;`) hands that
      // straight back. The repositories' own `badResponse →
      // ServerFailure(statusCode: 429)` arm is still UNREACHABLE on the
      // wired chain — it only fires for a DioException fabricated without
      // the interceptor, i.e. in a Dio-mocking unit test. That is precisely
      // why the fix had to land in the interceptor and not in either
      // repository.
      expect(board429, isA<SalonBoardRateLimitedFailure>());
      expect(days429, isA<SalonBoardRateLimitedFailure>());
      expect(roster429, isA<SalonBoardRateLimitedFailure>());

      // Guards against a "fix" that changes one route and leaves the other
      // two — three different cooldown behaviours on one screen.
      expect(board429.runtimeType, days429.runtimeType);
      expect(board429.runtimeType, roster429.runtimeType);
    });

    test('the mapped 429 IS classified as a throttle, and is still NOT '
        'auto-retried by the provider retry policy', () async {
      final _Board board = await _boot();
      final Failure f = await _failureFrom(
        () => board.bookings.getSalonBookings(salonId: kSalonId, page: 0),
      );

      // THE FIX, stated as an assertion. This was `isFalse` — a real HTTP
      // 429 did not reach `isThrottleFailure` at all, so nothing downstream
      // could tell a rate limit apart from an unclassified error or render a
      // cooldown.
      expect(
        isThrottleFailure(f),
        isTrue,
        reason:
            'a board 429 maps to SalonBoardRateLimitedFailure, which is a '
            'member of the throttle family — this is what lets the UI gate '
            'its retry affordance behind the cooldown',
      );

      // ⚠ THIS ASSERTION IS LOAD-BEARING IN A WAY IT WAS NOT BEFORE.
      // The failure is now classified TRANSIENT (a limiter genuinely does
      // clear on its own — the same honest answer `ServiceRateLimitedFailure`
      // gives), so `isThrottleFailure` is the ONLY thing standing between a
      // rate limit and `defaultRetry`'s 10-attempt backoff firing straight
      // back into it. The old group's comment predicted exactly this shape
      // of regression; the non-vacuity check below proves the null is the
      // guard talking rather than transience declining on its own.
      expect(
        isTransientFailure(f),
        isTrue,
        reason:
            'a limiter clears on its own, so an identical later attempt can '
            'succeed — see failure_retry_policy\'s trap 2 on why that is a '
            'different question from "may the container re-issue it?"',
      );
      expect(
        ProviderContainer.defaultRetry(0, f),
        isNotNull,
        reason:
            'non-vacuity: the DEFAULT policy would retry this, so the null '
            'below is isThrottleFailure and nothing else',
      );
      expect(
        beauticaProviderRetry(0, f),
        isNull,
        reason:
            'a 429 must never be re-issued behind the user\'s back, whatever '
            'type it maps to',
      );
    });

    test(
      'the Retry-After header reaches the Failure as a readable cooldown',
      () async {
        final _Board board = await _boot();
        final Failure f = await _failureFrom(
          () => board.bookings.getSalonBookings(salonId: kSalonId, page: 0),
        );

        expect(f, isA<SalonBoardRateLimitedFailure>());
        final SalonBoardRateLimitedFailure limited =
            f as SalonBoardRateLimitedFailure;

        // The transport DID send it — asserting the header was on the wire
        // first is what stops this test from passing vacuously if the adapter
        // ever stops sending it. Kept from the ground-truth version verbatim.
        expect(
          (limited.cause as DioException?)?.response?.headers.value(
            'retry-after',
          ),
          '$_kRetryAfterSeconds',
          reason:
              'fixture precondition: the 429 really carried Retry-After, so a '
              'failure to surface it is the mapper\'s, not the fixture\'s',
        );

        // THE FIX. The value no longer has to be dug out of `cause` — which
        // would mean probing a DioException from presentation code, something
        // this codebase forbids (see login_screen.dart's note). It is a typed
        // field, which is what `MyBookingsErrorState` reads to gate its retry
        // button behind a live countdown.
        expect(
          limited.retryAfterSeconds,
          _kRetryAfterSeconds,
          reason:
              'the typed field is the ONLY thing a screen may read; a value '
              'reachable solely through `cause` is not surfaced at all',
        );
      },
    );

    test('all four routes surface the SAME cooldown — one budget, one '
        'countdown', () async {
      // The board route is covered above; this pins the other three, so a
      // fix that wired the cooldown on one route and left the rest reading
      // `null` (three different waits on one screen) cannot pass.
      final _Board a = await _boot();
      final Failure history = await _failureFrom(
        () => a.bookings.getSalonBookings(
          salonId: kSalonId,
          page: 0,
          partition: BookingPartition.history,
        ),
      );

      final _Board b = await _boot();
      final Failure days = await _failureFrom(
        () => b.bookings.getSalonBookedDays(
          salonId: kSalonId,
          from: kFrom,
          to: kTo,
        ),
      );

      final _Board c = await _boot();
      final Failure roster = await _failureFrom(
        () =>
            c.rosterSchedule.salonRosterEffectiveSchedule(kSalonId, kFrom, kTo),
      );

      for (final Failure f in <Failure>[history, days, roster]) {
        expect(f, isA<SalonBoardRateLimitedFailure>());
        expect(
          (f as SalonBoardRateLimitedFailure).retryAfterSeconds,
          _kRetryAfterSeconds,
        );
      }
    });
  });
}
