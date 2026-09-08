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
//     That "never auto-retry a 429" rule now lives in its OWN predicate,
//     [isThrottleFailure], consulted by [beauticaProviderRetry] BEFORE
//     transience. It used to be expressed only by returning `false` from
//     [isTransientFailure], which conflated two different questions: "can a
//     later identical attempt succeed?" (a limiter: yes, once it clears) and
//     "may the container re-issue this behind the user's back?" (a limiter:
//     never). [ServiceRateLimitedFailure] answers them differently — `true` and
//     `false` respectively — so the two are now separate. The four older
//     throttles keep answering `false` to BOTH: nothing observable turns on
//     their transience, their UIs render an explicit countdown, and flipping
//     them is a behaviour change with its own pinned tests. Belt and braces
//     either way; neither predicate alone can let a limiter loop.
//
// …AND HOW MANY TIMES
// -------------------
// Classifying WHICH failures retry removed most of the damage, but not all of
// it: a TRANSIENT failure still fell through to `defaultRetry`'s full curve —
// **10 attempts, ~38 s of backoff**, and every one of those attempts may
// additionally burn `dioProvider`'s `connectTimeout` (15 s) or
// `receiveTimeout` (30 s) first. For a provider BUILD that gates a whole
// screen (`bookingsDayProvider` gates «Мої записи»), minutes of
// `AsyncLoading` is indistinguishable from a hang: `AsyncValue.when` routes
// `AsyncLoading(retrying: true)` to `loading:`, so every re-attempt renders
// the same skeleton as the first, with no error surface, nothing in the
// backend log and nothing to tap. A master hit exactly this after creating a
// manual walk-in booking (2026-08-20).
//
// So the transient path is now BOUNDED by [_kMaxTransientRetries] as well as
// classified. The split this file exists for is untouched:
//
//   - deterministic → `null` on retryCount 0, exactly as before. The bound
//     is checked AFTER the classification, so it can only ever make a
//     retryable failure stop SOONER; it can never make a stopped one retry.
//   - transient → still retried, still on `defaultRetry`'s own curve and
//     still delegated to it (so Riverpod's `Error` / `ProviderException`
//     refusals stay authoritative), just not ten times.
//
// The bound covers non-[Failure] errors too. That is deliberate: anything
// that escaped the repository layer unmapped is, by definition, unclassified,
// and an unclassified error is the last thing that should get 38 s of hidden
// backoff.
//
// A bounded automatic retry is not the user's only recourse — it is the one
// that runs BEFORE the UI can offer anything. Both loading and error states
// on «Мої записи» now carry a manual retry affordance
// (`MyBookingsSlowLoadNotice`, `MyBookingsErrorState`), and a user-driven
// retry is strictly better than a hidden one: it is visible, instant, and
// bounded by the user's patience.
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
/// `ProviderException` handling and its backoff curve stay untouched, up to
/// [_kMaxTransientRetries] re-attempts.
Duration? beauticaProviderRetry(int retryCount, Object error) {
  if (error is Failure &&
      (isThrottleFailure(error) || !isTransientFailure(error))) {
    return null;
  }
  // AFTER the classification, never before — see "…AND HOW MANY TIMES" in
  // this file's header. This arm can only shorten a retry sequence the
  // classification above already allowed; it can never start one.
  if (retryCount >= _kMaxTransientRetries) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}

/// How many automatic re-attempts a transient failure gets, on top of the
/// first attempt.
///
/// One — so **two attempts in total**, with `defaultRetry`'s own 200 ms
/// between them, down from ten attempts and ~38 s of backoff.
///
/// Why one and not "a few": the backoff is not what costs the time here. Each
/// attempt independently burns up to `dioProvider`'s `connectTimeout` (15 s)
/// or `receiveTimeout` (30 s) before it even fails, so the attempt COUNT — not
/// the delay curve — is what turns a bad network into a screen that looks
/// hung. A second attempt still catches the case the classification exists to
/// serve (a dropped packet, a Wi-Fi→LTE handover, a backend mid-restart);
/// attempts three through ten only ever added wall-clock behind a spinner.
/// Anything past that is the user's call, through the visible retry
/// affordances the screens now carry.
const int _kMaxTransientRetries = 1;

/// Whether [failure] is an HTTP **429** — a server-side rate limit.
///
/// Checked by [beauticaProviderRetry] ahead of [isTransientFailure], so a
/// limiter is never re-issued automatically no matter how it is classified
/// there. See trap 2 in this file's header for why the two questions are
/// separate: a 429 CAN succeed later (transient) and must STILL never be
/// retried behind the user's back (throttled).
///
/// Deliberately a plain `is`-chain rather than another exhaustive switch: this
/// list is a small, explicitly-enumerated family, and an exhaustive switch here
/// would force every unrelated new `Failure` to declare "I am not a 429".
bool isThrottleFailure(Failure failure) =>
    failure is ResendThrottledFailure ||
    failure is CategoryRequestThrottledFailure ||
    failure is BookingRateLimitedFailure ||
    failure is ScheduleOverrideRateLimitedFailure ||
    failure is ServiceRateLimitedFailure ||
    failure is AccountDeleteRateLimitedFailure;

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
  // 503 from the bulk service-setup lock ceiling. Genuinely transient (another
  // bulk save for the same master was mid-flight) and safe: the batch is
  // all-or-nothing, so the timed-out attempt wrote nothing and a retry cannot
  // duplicate. Note this classification is advisory here — the bulk save runs
  // through a notifier mutation, not a provider build, so the screen's manual
  // retry affordance is what actually re-issues it.
  BulkSetupBusyFailure() => true,
  // 429 from a service-catalogue write. A rate limit clears on its own, so the
  // honest answer to "could an identical later attempt succeed?" is yes — the
  // same answer the 5xx and 503 arms give. What must NOT happen is the
  // CONTAINER deciding when that later attempt is; [isThrottleFailure] stops
  // that above, and the setup screen withholds its manual retry action for this
  // failure, so the only re-issue is a deliberate one by the master. (Like
  // [BulkSetupBusyFailure], the classification is advisory in practice: every
  // service-catalogue write runs through a notifier mutation, never a provider
  // build, so `beauticaProviderRetry` is not on this failure's path at all.)
  ServiceRateLimitedFailure() => true,

  // ---- deterministic: invite-accept post-success hand-off (2026-09-01) ---
  // The 2xx already happened server-side; a retry would resend a mutation
  // request that the server may have already applied (or, for the single-use
  // invite-accept token specifically, cannot possibly succeed again). Neither
  // reaches [beauticaProviderRetry] in practice — both are thrown from a
  // notifier mutation (acceptInvite/verifyEmail), never a provider build —
  // but the classification must still be a real answer, not a default.
  ResponseUnusableFailure() => false,
  InviteHandoffFailure() => false,

  // ---- deterministic: HTTP 4xx and typed 4xx envelopes -------------------
  // A pin miss. Fail-closed and NOT transient in the useful sense: the chain
  // that was rejected is the chain the next identical attempt will meet, so a
  // retry burns the same ~38 s spinner and rejects again. Split out of the
  // NetworkFailure arm on purpose — see CertificateFailure's own doc.
  CertificateFailure() => false,
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
  ConflictFailure() => false,
  // 422 — the client has more than 50 upcoming bookings. Deterministic: an
  // identical retry meets the identical booking count, so a retry burns a
  // spinner and 422s again. The only recovery is a deliberate user action
  // (cancel some bookings first), never an automatic re-issue.
  AccountDeleteBookingLimitFailure() => false,
  // 403 — the caller's authorization/scoping over the target master, or the
  // master's existence/active state. Neither can change by re-issuing the
  // identical request (Phase 246).
  MasterBookingNotPermittedFailure() => false,
  // 409 on the walk-in create path (Phase 256) — deterministic in the exact
  // same sense [ConflictFailure] is: an automatic retry of the IDENTICAL
  // request would just 409 again (the overlap check that produced this
  // failure does not change on its own). Recovery here is a deliberate user
  // action (the confirm step's «Оновити» snack, which changes what gets
  // sent), never an automatic retry.
  MasterBookingDuplicateFailure() => false,
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
  // A mixed-result summary of PUTs already attempted (some succeeded, some
  // failed) — not a single request outcome, so a generic re-issue of "the
  // same request" is not meaningful here. Like [BulkSetupBusyFailure] /
  // [ServiceRateLimitedFailure], this classification is advisory: `putSpan`
  // runs through a notifier mutation, never a provider build, so
  // [beauticaProviderRetry] is not actually on this failure's path.
  OverrideSpanPartialFailure() => false,

  // ---- deterministic: locally-raised, no request to re-issue -------------
  // Never crosses the wire: raised by a SCREEN that found a settled session
  // missing a field it needs. `beauticaProviderRetry` re-runs a provider
  // BUILD, and no provider build produces this failure — the only recovery is
  // the screen's own `onRetry` calling [AuthNotifier.refreshUser]. Classifying
  // it `false` keeps the container from ever inventing an automatic re-attempt
  // of something that was not a request.
  SessionIncompleteFailure() => false,

  // ---- deterministic: throttles (trap 2 in the file header) --------------
  ResendThrottledFailure() => false,
  CategoryRequestThrottledFailure() => false,
  BookingRateLimitedFailure() => false,
  ScheduleOverrideRateLimitedFailure() => false,
  AccountDeleteRateLimitedFailure() => false,

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
