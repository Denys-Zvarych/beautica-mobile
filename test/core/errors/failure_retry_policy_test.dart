// Direct tests for [beauticaProviderRetry] / [isTransientFailure] — the
// app-wide Riverpod retry predicate installed on the root `ProviderScope`.
//
// WHY THE PREDICATE IS TESTED DIRECTLY AND NOT ONLY END-TO-END
// -----------------------------------------------------------
// The defect this guards against is a TIMING behaviour: Riverpod's
// `defaultRetry` retries any non-`Error`, non-`ProviderException` ten times
// over ~38 s, holding the element in `AsyncLoading` the whole time. The
// predicate answers that on TWO axes — WHICH failures retry (the
// transient/deterministic split below) and HOW MANY TIMES (`retryCount >=
// _kMaxTransientRetries`, added 2026-08-20 after a master watched «Мої
// записи» shimmer indefinitely on a freshly-booked day). Observing
// that end-to-end means either waiting 38 s of wall-clock or asserting on
// pumped frames, both of which are slow and flaky, and neither of which pins
// down WHICH failures were classified which way. Calling the predicate is the
// exact, fast, total statement of the contract; the container-level test at
// the bottom then proves the predicate is actually wired to an element.
//
// The transient/deterministic split is asserted over an EXHAUSTIVE list of
// every `Failure` subtype, and exhaustiveness is enforced at TWO levels that
// catch different mistakes:
//
//   * The COMPILER. `isTransientFailure` switches over the sealed hierarchy
//     with no `default`, so adding a subtype without ANY case fails the build.
//     What it does NOT catch is a subtype that HAS a case nobody ever asserted
//     — the compiler is happy with a wrong answer.
//   * The `anchored to the REAL Failure hierarchy` test below, which parses the
//     concrete subclasses out of `failures.dart` and demands the expectation
//     table name every one. That is what closes the "case exists but is
//     misclassified and untested" hole.
//
// The neighbouring `classifies every Failure subtype` test compares the two
// tables in THIS file against each other. That check is useful for keeping the
// instance/expectation pair in step, but on its own it is self-referential:
// both tables staying silent about a new subtype keeps it green. Do not treat
// it as the exhaustiveness guarantee — the anchored test is (verified by
// mutation 2026-07-31: adding a subtype with a wrong-but-present switch case
// leaves this test green and fails only the anchored one).

import 'dart:io';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `Failure` this app can throw, paired with whether a later identical
/// attempt could plausibly succeed.
const Map<String, bool> _expectedTransience = <String, bool>{
  // Transient — worth retrying.
  'NetworkFailure': true,
  'ServerFailure(500)': true,
  'ServerFailure(503)': true,
  'ServerFailure(599)': true,
  // The bulk-setup advisory lock was still held when the backend's 3 s ceiling
  // expired. The batch is all-or-nothing, so NOTHING was written — an identical
  // resubmit once the lock frees is both safe and the expected outcome.
  'BulkSetupBusyFailure': true,
  // A rate limit clears on its own, so an identical later attempt genuinely can
  // succeed — the same answer the 5xx and 503 rows give, and the honest one for
  // the question this table asks. It is NOT the question "may the container
  // re-issue this behind the user's back?"; `isThrottleFailure` answers that one
  // with a flat no for the whole 429 family, and `beauticaProviderRetry` checks
  // it FIRST. The two are asserted separately below — a `true` here does not
  // mean an automatic retry, and the throttle test is what proves it.
  'ServiceRateLimitedFailure': true,
  // Deterministic.
  'ServerFailure(409)': false,
  'ServerFailure(null)': false,
  // A TLS pin miss (Phase 111). Fail-closed, and the rejected chain does not
  // change on its own — an identical retry meets it again. Classified apart
  // from NetworkFailure precisely so it cannot inherit that arm's `true`.
  'CertificateFailure': false,
  'NotFoundFailure': false,
  'UnauthorizedFailure': false,
  'InvalidCredentialsFailure': false,
  'ValidationFailure': false,
  'VerificationFailure': false,
  'PasswordResetOtpFailure': false,
  'ResetTokenInvalidFailure': false,
  'EmailAlreadyRegisteredFailure': false,
  'ProviderMissingCityFailure': false,
  'CategoryAlreadyExistsFailure': false,
  'SupportAttachmentTooLargeFailure': false,
  'SupportChannelUnavailableFailure': false,
  'ConflictFailure': false,
  'DuplicateServiceFailure': false,
  'ServiceDuplicateFailure': false,
  'ClientBookingConflictFailure': false,
  'BookingAlreadyElapsedFailure': false,
  'ProviderDeclineWindowClosedFailure': false,
  'ProviderCompleteNotStartedFailure': false,
  'ReviewAlreadyExistsFailure': false,
  'ReviewNotAllowedFailure': false,
  'ClientReviewAlreadyExistsFailure': false,
  'ClientReviewNotAllowedFailure': false,
  'ResendThrottledFailure': false,
  'CategoryRequestThrottledFailure': false,
  'BookingRateLimitedFailure': false,
  // A 403 "you may not book for this master" is an authorization verdict, not
  // a transient network condition — retrying re-sends a request that fails
  // identically.
  'MasterBookingNotPermittedFailure': false,
  // A 409 on the walk-in create path (Phase 256) is deterministic in the
  // same sense ConflictFailure is — the overlap check that produced it does
  // not change on its own, so an automatic retry just 409s again.
  'MasterBookingDuplicateFailure': false,
  'ScheduleOverrideRateLimitedFailure': false,
  'OverrideSpanPartialFailure': false,
  'UnknownFailure': false,
};

/// One instance per key in [_expectedTransience].
Map<String, Failure> _instances() {
  final DateTime at = DateTime(2026, 8, 14, 10);
  return <String, Failure>{
    'NetworkFailure': const NetworkFailure(),
    'ServerFailure(500)': const ServerFailure(statusCode: 500),
    'ServerFailure(503)': const ServerFailure(statusCode: 503),
    'ServerFailure(599)': const ServerFailure(statusCode: 599),
    'ServerFailure(409)': const ServerFailure(statusCode: 409),
    'ServerFailure(null)': const ServerFailure(),
    'CertificateFailure': const CertificateFailure(),
    'NotFoundFailure': const NotFoundFailure(),
    'UnauthorizedFailure': const UnauthorizedFailure(),
    'InvalidCredentialsFailure': const InvalidCredentialsFailure(),
    'ValidationFailure': const ValidationFailure(
      fieldErrors: <String, String>{},
    ),
    'VerificationFailure': const VerificationFailure(
      code: VerificationErrorCode.invalidCode,
    ),
    'PasswordResetOtpFailure': const PasswordResetOtpFailure(
      code: PasswordResetOtpErrorCode.codeExpired,
    ),
    'ResetTokenInvalidFailure': const ResetTokenInvalidFailure(),
    'EmailAlreadyRegisteredFailure': const EmailAlreadyRegisteredFailure(),
    'ProviderMissingCityFailure': const ProviderMissingCityFailure(),
    'CategoryAlreadyExistsFailure': const CategoryAlreadyExistsFailure(),
    'SupportAttachmentTooLargeFailure':
        const SupportAttachmentTooLargeFailure(),
    'SupportChannelUnavailableFailure':
        const SupportChannelUnavailableFailure(),
    'BulkSetupBusyFailure': const BulkSetupBusyFailure(),
    'ServiceRateLimitedFailure': const ServiceRateLimitedFailure(
      retryAfterSeconds: 20,
    ),
    'ConflictFailure': const ConflictFailure(),
    'DuplicateServiceFailure': const DuplicateServiceFailure(),
    'ServiceDuplicateFailure': const ServiceDuplicateFailure(),
    'ClientBookingConflictFailure': ClientBookingConflictFailure(
      conflictingBookingId: 'booking-1',
      serviceName: 'Манікюр',
      masterName: 'Олена Коваль',
      startsAt: at,
      endsAt: at.add(const Duration(hours: 1)),
    ),
    'BookingAlreadyElapsedFailure': const BookingAlreadyElapsedFailure(),
    'ProviderDeclineWindowClosedFailure':
        const ProviderDeclineWindowClosedFailure(),
    'ProviderCompleteNotStartedFailure':
        const ProviderCompleteNotStartedFailure(),
    'ReviewAlreadyExistsFailure': const ReviewAlreadyExistsFailure(),
    'ReviewNotAllowedFailure': const ReviewNotAllowedFailure(),
    'ClientReviewAlreadyExistsFailure':
        const ClientReviewAlreadyExistsFailure(),
    'ClientReviewNotAllowedFailure': const ClientReviewNotAllowedFailure(),
    'ResendThrottledFailure': const ResendThrottledFailure(
      retryAfterSeconds: 42,
    ),
    'CategoryRequestThrottledFailure': const CategoryRequestThrottledFailure(),
    'BookingRateLimitedFailure': const BookingRateLimitedFailure(),
    'MasterBookingNotPermittedFailure':
        const MasterBookingNotPermittedFailure(),
    'MasterBookingDuplicateFailure': const MasterBookingDuplicateFailure(),
    'ScheduleOverrideRateLimitedFailure':
        const ScheduleOverrideRateLimitedFailure(retryAfterSeconds: 30),
    'OverrideSpanPartialFailure': OverrideSpanPartialFailure(
      failedDates: <DateTime>[at],
    ),
    'UnknownFailure': const UnknownFailure(),
  };
}

void main() {
  group('isTransientFailure', () {
    test('classifies every Failure subtype, and the table covers them all', () {
      final Map<String, Failure> instances = _instances();
      expect(
        instances.keys.toSet(),
        _expectedTransience.keys.toSet(),
        reason:
            'the instance table and the expectation table must stay in step — '
            'a new Failure subtype needs a row in both',
      );

      for (final MapEntry<String, Failure> e in instances.entries) {
        expect(
          isTransientFailure(e.value),
          _expectedTransience[e.key],
          reason:
              '${e.key} is classified as '
              '${isTransientFailure(e.value) ? 'transient' : 'deterministic'} '
              'but should be the opposite',
        );
      }
    });

    // The test above compares two tables that both live in THIS FILE, so on its
    // own it only proves they agree with each other — add a new
    // `final class FooFailure extends Failure`, give it a case in the
    // production switch, and leave this file untouched: the compiler is
    // satisfied (the switch is exhaustive), both tables are still mutually
    // consistent (neither mentions it), and a possibly-MISCLASSIFIED failure
    // ships with zero coverage. The sealed hierarchy stops "no case at all",
    // not "a case nobody asserted".
    //
    // This test closes that loop by reading the REAL hierarchy out of
    // `failures.dart` and demanding the table match it, so the exhaustiveness
    // claim is anchored to the source of truth rather than to itself.
    test('the expectation table is anchored to the REAL Failure hierarchy in '
        'failures.dart — not merely self-consistent', () {
      final File source = File('lib/core/errors/failures.dart');
      expect(
        source.existsSync(),
        isTrue,
        reason:
            'non-vacuity: this test is meaningless if the source file is '
            'not found (flutter test runs with the package root as cwd). If '
            'failures.dart moved, update this path rather than deleting the '
            'test.',
      );

      final Set<String> declared = RegExp(
        r'^final class (\w+) extends Failure\b',
        multiLine: true,
      ).allMatches(source.readAsStringSync()).map((m) => m.group(1)!).toSet();

      expect(
        declared.length,
        greaterThan(20),
        reason:
            'non-vacuity: the regex must actually be finding the subclass '
            'declarations. If this trips, the declaration style in '
            'failures.dart changed and the regex needs updating — do NOT '
            'weaken it, or this guard silently passes on an empty set.',
      );

      // The table keys carry ServerFailure status-code variants
      // ('ServerFailure(500)'); reduce each to its bare class name.
      final Set<String> covered = _expectedTransience.keys
          .map((String k) => k.split('(').first)
          .toSet();

      expect(
        covered,
        declared,
        reason:
            'every concrete Failure subclass declared in failures.dart '
            'must have an explicit transient/deterministic expectation here. '
            'Missing key => a new Failure subtype was added and classified in '
            'the production switch with NOBODY asserting the classification is '
            'correct (retrying a deterministic failure holds the UI in an '
            'indefinite spinner for ~38s over 10 attempts — the exact defect '
            'this policy exists to prevent). Extra key => a Failure subclass '
            'was deleted or renamed and this table went stale.',
      );
    });

    test('ServerFailure is classified by STATUS CODE, not by type — the '
        'interceptor also emits it for 409 and the mappers for a broken '
        'contract (statusCode null)', () {
      expect(isTransientFailure(const ServerFailure(statusCode: 500)), isTrue);
      expect(isTransientFailure(const ServerFailure(statusCode: 502)), isTrue);
      // Below the 5xx band.
      expect(isTransientFailure(const ServerFailure(statusCode: 409)), isFalse);
      expect(isTransientFailure(const ServerFailure(statusCode: 499)), isFalse);
      // Above it.
      expect(isTransientFailure(const ServerFailure(statusCode: 600)), isFalse);
      // The mappers' broken-contract shape.
      expect(isTransientFailure(const ServerFailure()), isFalse);
    });
  });

  group('beauticaProviderRetry', () {
    test('a transient Failure retries ONCE, on the default backoff, then '
        'stops', () {
      // The first re-attempt still comes off `ProviderContainer.defaultRetry`'s
      // own curve — the predicate delegates rather than inventing a delay, so
      // Riverpod's `Error` / `ProviderException` refusals stay authoritative.
      expect(
        beauticaProviderRetry(0, const NetworkFailure()),
        const Duration(milliseconds: 200),
      );
      expect(
        beauticaProviderRetry(0, const ServerFailure(statusCode: 503)),
        const Duration(milliseconds: 200),
      );

      // …and that is the ONLY one. `defaultRetry` would still be handing out
      // 400 / 1600 / 6400 ms here, for ten attempts and ~38 s in total; the
      // bound in `beauticaProviderRetry` is what stops it. Each attempt can
      // additionally burn `dioProvider`'s 15 s connect / 30 s receive timeout
      // before it even fails, so the attempt COUNT — not the delay curve — is
      // what turned a bad network into a screen that looked hung.
      expect(
        beauticaProviderRetry(1, const NetworkFailure()),
        isNull,
        reason: 'two attempts in total is the bound',
      );
      expect(beauticaProviderRetry(3, const NetworkFailure()), isNull);
      expect(
        beauticaProviderRetry(5, const ServerFailure(statusCode: 503)),
        isNull,
      );
      expect(beauticaProviderRetry(10, const NetworkFailure()), isNull);

      // Negative control: without the bound these WOULD be retried — proving
      // the assertions above are the predicate talking and not `defaultRetry`
      // declining on its own account.
      expect(
        ProviderContainer.defaultRetry(1, const NetworkFailure()),
        const Duration(milliseconds: 400),
      );
      expect(
        ProviderContainer.defaultRetry(5, const ServerFailure(statusCode: 503)),
        const Duration(milliseconds: 6400),
      );
    });

    test('the bound is checked AFTER classification — it can only shorten a '
        'retry sequence, never start one', () {
      // A deterministic failure is refused at retryCount 0, where the bound is
      // not yet in play, and stays refused past it. If the two checks were
      // ever swapped, the first assertion here would be the one that broke.
      expect(beauticaProviderRetry(0, const NotFoundFailure()), isNull);
      expect(beauticaProviderRetry(1, const NotFoundFailure()), isNull);
      // A throttle likewise — the 429 guard runs ahead of both.
      expect(
        beauticaProviderRetry(0, const BookingRateLimitedFailure()),
        isNull,
      );
    });

    test('a deterministic Failure stops on the FIRST attempt — this is the '
        'whole fix: no 38 s of AsyncLoading before the error surfaces', () {
      for (final MapEntry<String, Failure> e in _instances().entries) {
        if (_expectedTransience[e.key] ?? false) continue;
        expect(
          beauticaProviderRetry(0, e.value),
          isNull,
          reason: '${e.key} must not be retried at all',
        );
      }
    });

    // ── A 429 is transient AND must never auto-retry ─────────────────────────
    //
    // These two statements are not in tension, they are different questions,
    // and conflating them is what this pair of tests exists to prevent.
    // `ServiceRateLimitedFailure` is classified TRANSIENT (the limiter really
    // does clear on its own), so the test above — which only walks the
    // DETERMINISTIC rows — skips it entirely. Without the assertion below,
    // flipping that classification to `true` would have silently handed the
    // whole 429 family to `defaultRetry`'s 10-attempt backoff: an automatic
    // answer of "send more" to a server that just said "you are sending too
    // much", spending the exact budget the master's next deliberate attempt
    // needs.
    test('every 429 is refused by the container even when classified '
        'transient — isThrottleFailure is checked BEFORE transience', () {
      const Map<String, Failure> throttles = <String, Failure>{
        'ResendThrottledFailure': ResendThrottledFailure(retryAfterSeconds: 30),
        'CategoryRequestThrottledFailure': CategoryRequestThrottledFailure(),
        'BookingRateLimitedFailure': BookingRateLimitedFailure(),
        'ScheduleOverrideRateLimitedFailure':
            ScheduleOverrideRateLimitedFailure(retryAfterSeconds: 30),
        'ServiceRateLimitedFailure': ServiceRateLimitedFailure(
          retryAfterSeconds: 20,
        ),
      };
      for (final MapEntry<String, Failure> e in throttles.entries) {
        expect(
          isThrottleFailure(e.value),
          isTrue,
          reason: '${e.key} is an HTTP 429 and belongs to the throttle family',
        );
        expect(
          beauticaProviderRetry(0, e.value),
          isNull,
          reason:
              '${e.key} must never be re-issued automatically, whatever '
              'isTransientFailure says about it',
        );
      }
    });

    test('the throttle guard is doing real work — the one transient 429 would '
        'otherwise be handed to the default backoff', () {
      const Failure throttled = ServiceRateLimitedFailure(
        retryAfterSeconds: 20,
      );
      // Non-vacuity: this failure IS on the transient side, so the ONLY thing
      // stopping `beauticaProviderRetry` from delegating to
      // `ProviderContainer.defaultRetry` is `isThrottleFailure`. Delete that
      // clause and the assertion above goes red rather than staying green for
      // an unrelated reason.
      expect(isTransientFailure(throttled), isTrue);
      expect(
        ProviderContainer.defaultRetry(0, throttled),
        isNotNull,
        reason:
            'non-vacuity: the default policy WOULD retry this, so the null '
            'above is the guard talking and not defaultRetry declining on its '
            'own',
      );
      expect(beauticaProviderRetry(0, throttled), isNull);
    });

    test('an UnknownFailure wrapping a deserialization breakdown is not '
        'retried — re-parsing the same bytes can never yield a new answer', () {
      final Failure decodeFailure = UnknownFailure(
        cause: ArgumentError('RESCHEDULED'),
      );
      expect(beauticaProviderRetry(0, decodeFailure), isNull);
    });

    test('non-Failure errors keep Riverpod default behaviour — the predicate '
        'narrows the Failure path only, it does not take over retry policy '
        'wholesale', () {
      // An `Error` is refused by `defaultRetry` itself.
      expect(beauticaProviderRetry(0, StateError('boom')), isNull);
      // A plain Exception that never reached the repository mapper still gets
      // the default backoff.
      expect(
        beauticaProviderRetry(
          0,
          DioException(requestOptions: RequestOptions(path: '/x')),
        ),
        const Duration(milliseconds: 200),
      );
    });
  });

  group('wired to a container', () {
    // The predicate is only worth anything if a real element consults it.
    // Generated providers all emit `retry: null`, and `ProviderElement`
    // resolves `origin.retry ?? container.retry ?? defaultRetry` — so a
    // container-level `retry` reaches every one of them. These two tests pin
    // that resolution order down.

    test('a deterministic Failure surfaces AsyncError immediately instead of '
        'parking the element in AsyncLoading', () async {
      var builds = 0;
      final provider = FutureProvider<int>((ref) async {
        builds++;
        throw const NotFoundFailure();
      });
      final container = ProviderContainer(retry: beauticaProviderRetry);
      addTearDown(container.dispose);

      await expectLater(
        container.read(provider.future),
        throwsA(isA<NotFoundFailure>()),
      );
      expect(container.read(provider), isA<AsyncError<int>>());
      expect(builds, 1, reason: 'no retry attempt may have been scheduled');
    });

    test('WITHOUT the predicate the SAME failure is retried — proving the '
        'container default really was the amplifier, and that these tests '
        'would not pass vacuously', () async {
      var builds = 0;
      final provider = FutureProvider<int>((ref) async {
        builds++;
        throw const NotFoundFailure();
      });
      // DELIBERATELY BARE — do NOT add `retry:` here.
      //
      // This is the negative control for the test above it: omitting `retry:`
      // falls through to `ProviderContainer.defaultRetry`, which refuses only
      // `Error` and `ProviderException` — and a `Failure` is neither. The whole
      // point is to demonstrate the blanket-retry behaviour the predicate
      // removes, so passing `beauticaProviderRetry` here would make this test
      // assert the same thing as its sibling and the pair would prove nothing.
      // (The 2026-07-31 sweep that put `retry: beauticaProviderRetry` on every
      // other test container skipped this one for exactly that reason.)
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final AsyncValue<int> first = container.read(provider);
      expect(first, isA<AsyncLoading<int>>());
      // First attempt runs and fails; the element schedules a retry rather
      // than settling on AsyncError.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(provider),
        isA<AsyncLoading<int>>(),
        reason:
            'the default policy leaves the element LOADING after a failed '
            'attempt — the indefinite spinner this fix removes',
      );
      expect(builds, 1);
    });
  });
}
