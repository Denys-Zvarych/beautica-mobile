// The app-wide Riverpod retry predicate — which [Failure]s are worth retrying.
//
// THE DEFECT THIS EXISTS FOR
// --------------------------
// Riverpod 3's `ProviderContainer.defaultRetry` gives up on two error shapes
// only:
//
//     if (error is ProviderException || error is Error) return null;
//
// A [Failure] is neither. It is a `sealed class Failure implements Exception`
// (`failures.dart`), so EVERY repository error in this app — a 404, a
// validation error, a deserialization breakdown — fell through to the default
// backoff: **10 attempts, 200 ms doubling to 6400 ms, ~38 s in total**, with
// the element parked in `AsyncLoading` the whole time. The screen shows a
// spinner, not an error, and offers no way out.
//
// For a deterministic error that is pure damage. Re-issuing a request that
// returns the same 404, or re-parsing a payload whose enum this build does not
// recognise, cannot produce a different answer on attempt 10 than it did on
// attempt 1 — it just hides the error state for 38 s first. The
// unknown-booking-status bug was found through exactly this symptom (an
// indefinite spinner on «Мої записи», not an error screen); fixing the decode
// removed one TRIGGER, while every other deterministic decode failure on the
// same path still reproduced it. This predicate removes the AMPLIFIER.
//
// WHAT STILL RETRIES
// ------------------
// Retrying is kept for the failures where a later attempt genuinely can
// succeed without anything else changing:
//
//   - [NetworkFailure] — connection error / connect, send or receive timeout.
//     A tunnel, a Wi-Fi→LTE handover, a dropped packet. The canonical
//     retryable case.
//   - [ServerFailure] with a **5xx** [ServerFailure.statusCode] — an
//     overloaded or restarting backend. Idempotent GETs dominate the provider
//     graph, so a retry is safe and usually works.
//
// Everything else stops on the first error and surfaces `AsyncError`
// immediately, so the screen's `error:` branch (with its retry button) renders
// at once. A user-driven retry is strictly better than a hidden automatic one:
// it is visible, it is instant, and it is bounded by the user's patience
// rather than by a 38-second timer.
//
// TWO TRAPS WORTH SPELLING OUT
// ----------------------------
//  1. [ServerFailure] is NOT uniformly transient, so it is classified by
//     [ServerFailure.statusCode], not by type. `ErrorMapperInterceptor` also
//     emits `ServerFailure(statusCode: 409)` for a plain conflict, and the
//     mappers throw `ServerFailure(statusCode: null)` for a broken backend
//     contract (a missing `id`/`startsAt`). Both are perfectly deterministic;
//     a blanket "ServerFailure is transient" rule would retry a contract
//     breach ten times.
//  2. A 429 is deliberately NOT retried, even though it is nominally
//     temporary. The server has just said "you are sending too much"; an
//     automatic backoff answers that by sending more, burning the very budget
//     the user needs for their next deliberate attempt. Those failures
//     ([ResendThrottledFailure], [BookingRateLimitedFailure],
//     [ScheduleOverrideRateLimitedFailure], …) carry a `retryAfterSeconds` the
//     UI shows as a countdown — retrying behind the user's back would race it.
//
// EXHAUSTIVENESS IS THE POINT
// ---------------------------
// [isTransientFailure] switches over the SEALED [Failure] hierarchy with no
// `default` clause. Adding a new `Failure` subtype therefore breaks the build
// here until someone classifies it. That is deliberate: the safe default for
// an unclassified failure is "do not retry", and a silent fallthrough to that
// default would be indistinguishable from a considered decision.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'failures.dart';

/// The app-wide Riverpod [Retry] predicate.
///
/// Installed on the root `ProviderScope` in `main.dart`, so it governs every
/// provider in the container. Generated providers emit `retry: null`, and
/// `ProviderElement` resolves `origin.retry ?? container.retry ??
/// ProviderContainer.defaultRetry` — so this reaches all of them.
///
/// Returns `null` (stop, surface `AsyncError`) for any deterministic
/// [Failure]. Anything else — a transient [Failure], or a non-[Failure] error
/// that escaped the repository layer — is delegated to
/// [ProviderContainer.defaultRetry] so Riverpod's own `Error` /
/// `ProviderException` handling and its backoff curve stay untouched.
Duration? beauticaProviderRetry(int retryCount, Object error) {
  if (error is Failure && !isTransientFailure(error)) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}

/// Whether [failure] can plausibly succeed on a later identical attempt.
///
/// `true` only for connectivity trouble and 5xx. See this file's header for
/// why 429 and `ServerFailure(statusCode: null)` are excluded.
bool isTransientFailure(Failure failure) => switch (failure) {
  // ---- transient ---------------------------------------------------------
  NetworkFailure() => true,
  // 5xx only. 409 and the mappers' `statusCode: null` contract breach are
  // deterministic — see trap 1 in the file header.
  ServerFailure(:final int? statusCode) =>
    statusCode != null && statusCode >= 500 && statusCode <= 599,

  // ---- deterministic: HTTP 4xx and typed 4xx envelopes -------------------
  NotFoundFailure() => false,
  UnauthorizedFailure() => false,
  InvalidCredentialsFailure() => false,
  ValidationFailure() => false,
  VerificationFailure() => false,
  PasswordResetOtpFailure() => false,
  ResetTokenInvalidFailure() => false,
  EmailAlreadyRegisteredFailure() => false,
  ProviderMissingCityFailure() => false,
  CategoryAlreadyExistsFailure() => false,
  SupportAttachmentTooLargeFailure() => false,
  MasterAlreadyHasServicesFailure() => false,
  ConflictFailure() => false,
  DuplicateServiceFailure() => false,
  ServiceDuplicateFailure() => false,
  ClientBookingConflictFailure() => false,
  BookingAlreadyElapsedFailure() => false,
  ProviderDeclineWindowClosedFailure() => false,
  ProviderCompleteNotStartedFailure() => false,
  ReviewAlreadyExistsFailure() => false,
  ReviewNotAllowedFailure() => false,
  ClientReviewAlreadyExistsFailure() => false,
  ClientReviewNotAllowedFailure() => false,

  // ---- deterministic: throttles (trap 2 in the file header) --------------
  ResendThrottledFailure() => false,
  CategoryRequestThrottledFailure() => false,
  BookingRateLimitedFailure() => false,
  ScheduleOverrideRateLimitedFailure() => false,

  // ---- deterministic: server-side configuration --------------------------
  // Nominally a 503, but it means "the support channel is not configured on
  // the backend" — a deployment state, not load. Retrying cannot change it.
  SupportChannelUnavailableFailure() => false,

  // ---- deterministic: everything unmapped --------------------------------
  // The catch-all the repositories wrap a deserialization breakdown in
  // (`HttpBookingRepository._deserialize`), plus every DioException the error
  // mapper did not match — notably `DioExceptionType.cancel`, where a retry
  // would resurrect a request the caller explicitly abandoned.
  UnknownFailure() => false,
};
