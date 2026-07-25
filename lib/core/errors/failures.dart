// Phase 1.5 — Sealed Failure hierarchy.
//
// Every repository catches `DioException` (or raw exceptions) and re-throws
// as one of these typed subclasses. Presenters and notifiers handle only
// `Failure` — they are never exposed to raw HTTP or Dio internals.
//
// Intentionally NOT freezed — sealed Dart classes keep the domain layer a
// pure-Dart library with no generated code dependency. Freezed is introduced
// for data-carrying entities in Phase 4+.
//
// `userMessage(BuildContext ctx)` returns a localized string via
// `AppLocalizations` for direct display in the UI. Notifiers must pass
// `context` through only when constructing the SnackBar/dialog — not stored
// inside the notifier itself (see flutter skill § Forbidden Patterns).

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:flutter/material.dart';

/// Base class for all domain-level failures.
///
/// Every public repository method either returns a value or throws a `Failure`
/// subclass. Callers should pattern-match (switch on) the sealed type to
/// handle each case explicitly.
sealed class Failure implements Exception {
  const Failure({this.cause});

  /// The underlying raw exception or error object, if available.
  ///
  /// Exposed for logging (`log(error: failure.cause)`). Never displayed
  /// directly to the user — use [userMessage] instead.
  final Object? cause;

  /// Returns a localized, user-facing description of this failure.
  ///
  /// Requires a valid [BuildContext] with [AppLocalizations] configured.
  String userMessage(BuildContext ctx);
}

/// Emitted when a request fails due to absent or broken network connectivity
/// (e.g. `DioExceptionType.connectionError`, `DioExceptionType.receiveTimeout`).
final class NetworkFailure extends Failure {
  const NetworkFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) => AppLocalizations.of(ctx).errNetwork;
}

/// Emitted when the server responds with HTTP 404 Not Found.
final class NotFoundFailure extends Failure {
  const NotFoundFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) => AppLocalizations.of(ctx).errNotFound;
}

/// Emitted when the server responds with HTTP 401 Unauthorized.
///
/// The auth interceptor handles 401 by attempting a token refresh first;
/// this failure is only thrown when the refresh itself also fails.
///
/// [emailNotVerified] is `true` when the backend 401 body contains the
/// `EMAIL_NOT_VERIFIED` sub-code (account exists but OTP has not been completed).
/// Check this typed field instead of probing [cause].toString() — that pattern
/// couples UI logic to the internal DioException representation (MEDIUM-2,
/// mobile-security 2026-05-24).
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({super.cause, this.emailNotVerified = false});

  /// `true` when the backend 401 body carries the `EMAIL_NOT_VERIFIED` sub-code.
  ///
  /// Set by [ErrorMapperInterceptor] when the 401 response contains that code.
  /// Used by [LoginScreen] to decide whether to navigate to the verification
  /// screen instead of showing a generic "wrong credentials" error.
  final bool emailNotVerified;

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).errUnauthorized;
}

/// Emitted when the user supplies wrong email/password at the login endpoint.
///
/// Semantically distinct from [UnauthorizedFailure] (session expiry / token
/// revocation) — the user intentionally submitted a credential, and it was
/// rejected by the server.
///
/// Mapped by [HttpAuthRepository.login] when [ErrorMapperInterceptor] returns
/// an [UnauthorizedFailure] without [UnauthorizedFailure.emailNotVerified]:
/// a plain 401 on `/auth/login` always means wrong credentials, never a
/// session expiry (the user has no session yet at that point).
final class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).errInvalidCredentials;
}

/// Emitted when the server responds with HTTP 422 Unprocessable Entity.
///
/// [fieldErrors] maps field path (e.g. `"email"`) to a localized or
/// server-supplied message. Screens that show per-field inline errors
/// should switch on this subtype and read [fieldErrors].
final class ValidationFailure extends Failure {
  const ValidationFailure({
    required this.fieldErrors,
    this.serverMessage,
    super.cause,
  });

  /// Server-supplied field error messages keyed by field name / JSON path.
  ///
  /// Never display raw values from this map directly in UI labels without
  /// sanitizing or truncating them — server strings are untrusted input.
  /// Use [userMessage] for a safe localized summary.
  final Map<String, String> fieldErrors;

  /// Top-level server `message` from the 400/422 envelope, if any.
  ///
  /// Captured so the UI can show a generic SnackBar even when [fieldErrors]
  /// is empty (no field could be highlighted inline). This is the durable
  /// guard against a backend contract that returns a 400 with no usable
  /// field map — without it the Save button could die silently with no
  /// feedback. Truncated/sanitized by [ErrorMapperInterceptor]; may be `null`
  /// or blank, in which case callers fall back to a localized string.
  final String? serverMessage;

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).errValidation;
}

/// Emitted when the server responds with a 5xx status code.
///
/// [statusCode] is preserved for logging. May be `null` when the
/// exception is produced before an HTTP response is received.
final class ServerFailure extends Failure {
  const ServerFailure({this.statusCode, super.cause});

  /// The HTTP status code that triggered this failure, if available.
  final int? statusCode;

  @override
  String userMessage(BuildContext ctx) => AppLocalizations.of(ctx).errServer;
}

/// Catch-all for any failure not covered by the more specific subtypes.
///
/// Typically wraps a raw `Exception` or `Error` that escaped the repository
/// layer without being mapped. The repository should log `cause` before
/// re-throwing so there is always a full stack trace in the log output.
final class UnknownFailure extends Failure {
  const UnknownFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) => AppLocalizations.of(ctx).errUnknown;
}

/// Typed error codes returned by `POST /auth/verify-email` (backend Phase 1.5).
///
/// The backend envelope `{success:false, data:{code:"..."}}` carries one of
/// these wire values. [ErrorMapperInterceptor] decodes the wire string into
/// this enum so the screen can render the right localized copy without
/// re-parsing the response body.
enum VerificationErrorCode {
  /// Wrong OTP digits — also returned when the email does not exist (the
  /// backend deliberately reuses the same code to prevent enumeration).
  invalidCode,

  /// OTP older than the 15-minute TTL.
  codeExpired,

  /// The account was verified by a previous successful call.
  alreadyVerified;

  /// Decodes the backend wire string into [VerificationErrorCode].
  ///
  /// Unknown values fall back to [invalidCode] so the user still sees a
  /// reasonable error message — the screen will surface "wrong code" rather
  /// than crash on an unrecognised future server enum.
  static VerificationErrorCode fromWire(String? wire) {
    switch (wire) {
      case 'INVALID_CODE':
        return VerificationErrorCode.invalidCode;
      case 'CODE_EXPIRED':
        return VerificationErrorCode.codeExpired;
      case 'ALREADY_VERIFIED':
        return VerificationErrorCode.alreadyVerified;
      default:
        return VerificationErrorCode.invalidCode;
    }
  }
}

/// Emitted when `POST /auth/verify-email` returns 400 with a typed
/// `data.code` error envelope (backend Phase 1.5).
///
/// [code] is one of the [VerificationErrorCode] variants and lets the
/// verification screen surface the exact UA copy for each case (wrong code,
/// expired code, already verified).
final class VerificationFailure extends Failure {
  const VerificationFailure({required this.code, super.cause});

  /// The typed error code returned by the backend.
  final VerificationErrorCode code;

  @override
  String userMessage(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    switch (code) {
      case VerificationErrorCode.invalidCode:
        return l10n.verificationErrInvalidCode;
      case VerificationErrorCode.codeExpired:
        return l10n.verificationErrCodeExpired;
      case VerificationErrorCode.alreadyVerified:
        return l10n.verificationErrAlreadyVerified;
    }
  }
}

/// Emitted when `POST /auth/resend-verification` returns 429 because the
/// per-account resend cooldown is still active (backend Phase 1.6).
///
/// [retryAfterSeconds] is the server-supplied number of seconds the client
/// must wait before retrying. May be 0 if the body is malformed.
///
/// `null` means the server value exceeded [kMaxUxCooldownSeconds] (10 min).
/// The UI must show a static "try later" message instead of a countdown when
/// this field is null.
final class ResendThrottledFailure extends Failure {
  const ResendThrottledFailure({required this.retryAfterSeconds, super.cause});

  /// Seconds until the next resend is allowed, or `null` when the server
  /// value exceeded the UX ceiling (10 min / 600 s).
  ///
  /// When `null`, show a static message instead of a countdown timer.
  /// When 0, no cooldown should be started — allow immediate retry.
  final int? retryAfterSeconds;

  @override
  String userMessage(BuildContext ctx) {
    final seconds = retryAfterSeconds;
    if (seconds == null) {
      return AppLocalizations.of(ctx).cooldownTryLater;
    }
    return AppLocalizations.of(ctx).verificationErrResendThrottled(seconds);
  }
}

/// Emitted when `POST /auth/register` (or its role-specific variant) returns
/// HTTP 409 with the typed `data.code == "EMAIL_ALREADY_REGISTERED"` envelope.
///
/// Backend default behaviour is to silently return 200 on a duplicate-email
/// registration (anti-enumeration). When the `app.security
/// .disclose-duplicate-registration` flag is true (currently `application-
/// local.yml` in dev), the backend instead returns 409 with this envelope:
/// ```json
/// {
///   "success": false,
///   "data": { "code": "EMAIL_ALREADY_REGISTERED" },
///   "message": "Email already registered"
/// }
/// ```
/// The mobile must surface a useful localized message + a "Sign In" CTA. The
/// server-supplied `message` field is intentionally NOT used — the mobile owns
/// the displayed copy (l10n) so it can stay in voice with the rest of the
/// auth surface.
///
/// Mapped by [ErrorMapperInterceptor]; re-thrown unchanged by the auth
/// repository so the register notifier / step screen can branch on it.
final class EmailAlreadyRegisteredFailure extends Failure {
  const EmailAlreadyRegisteredFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).errEmailAlreadyRegistered;
}

/// Emitted when a provider role ([UserRole.independentMaster] or
/// [UserRole.salonOwner]) reaches the post-OTP profile save step without a
/// `cityId` in the registration draft.
///
/// This means the Step 3 address wizard data was lost (e.g. the draft was
/// cleared by a navigation edge case) after the user already filled it. The
/// account has been verified, but the PATCH /independent-masters/me (or
/// POST /salons) cannot run without a city. Surface this failure to the user
/// so they can go back and re-enter their address rather than silently
/// producing a verified account with no location in the DB.
///
/// Not thrown for [UserRole.client] — clients are allowed to skip Step 3.
final class ProviderMissingCityFailure extends Failure {
  const ProviderMissingCityFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).verificationErrProviderMissingCity;
}

/// Typed error codes returned by `POST /auth/verify-password-reset-otp`
/// (backend Phase A3) when the submitted OTP is rejected.
///
/// The backend deliberately reuses the SAME generic shapes as
/// `POST /auth/verify-email` (`{success:false, data:{code:"..."}}`) for
/// invalid, expired, exhausted, and locked-account states — no oracle. There
/// is no `ALREADY_VERIFIED` equivalent here (a password-reset OTP has no
/// "already verified" state), so this is a smaller enum than
/// [VerificationErrorCode] rather than a reuse of it — reusing it would let
/// [VerificationFailure.userMessage] surface email-verification-specific copy
/// ("Цей акаунт вже підтверджено...") in a password-reset context.
enum PasswordResetOtpErrorCode {
  /// Wrong OTP digits — also returned when the code was already consumed or
  /// the account cannot be resolved (the backend reuses this code to prevent
  /// enumeration).
  invalidCode,

  /// OTP older than the TTL.
  codeExpired;

  /// Decodes the backend wire string into [PasswordResetOtpErrorCode].
  ///
  /// Unknown values fall back to [invalidCode] so the user still sees a
  /// reasonable error message instead of crashing on an unrecognised future
  /// server enum.
  static PasswordResetOtpErrorCode fromWire(String? wire) {
    switch (wire) {
      case 'CODE_EXPIRED':
        return PasswordResetOtpErrorCode.codeExpired;
      case 'INVALID_CODE':
      default:
        return PasswordResetOtpErrorCode.invalidCode;
    }
  }
}

/// Emitted when `POST /auth/verify-password-reset-otp` returns 400 with a
/// typed `data.code` error envelope (backend Phase A3).
///
/// [code] is one of the [PasswordResetOtpErrorCode] variants and lets the
/// password-reset OTP screen surface the exact UA copy for each case (wrong
/// code vs. expired code) without re-parsing the response body.
final class PasswordResetOtpFailure extends Failure {
  const PasswordResetOtpFailure({required this.code, super.cause});

  /// The typed error code returned by the backend.
  final PasswordResetOtpErrorCode code;

  @override
  String userMessage(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    switch (code) {
      case PasswordResetOtpErrorCode.invalidCode:
        return l10n.resetOtpErrInvalidCode;
      case PasswordResetOtpErrorCode.codeExpired:
        return l10n.resetOtpErrCodeExpired;
    }
  }
}

/// Emitted when `POST /auth/reset-password` returns the backend's generic
/// 400 for an invalid, used, or expired reset token (backend Phase 11.3).
///
/// The backend deliberately returns a single, byte-identical generic 400
/// envelope (`{success:false, data:null, message:"Invalid or expired reset
/// token"}`) for all three cases so the endpoint cannot be used as a
/// token-probing oracle. There are therefore NO field errors and NO sub-code
/// to distinguish them — the [ErrorMapperInterceptor] maps the 400 to a
/// [ValidationFailure] with empty `fieldErrors`, and
/// [HttpAuthRepository.confirmPasswordReset] re-throws it as this dedicated
/// failure so the reset screen can render its "link invalid or expired"
/// state with a recovery CTA.
final class ResetTokenInvalidFailure extends Failure {
  const ResetTokenInvalidFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).resetErrTokenInvalid;
}

/// Emitted when `POST /api/v1/service-categories/requests` returns **409**
/// because the requested category already exists or is already pending review.
///
/// Surfaced to the suggestion dialog so it can show a friendly "this category
/// already exists" message instead of a generic server error.
final class CategoryAlreadyExistsFailure extends Failure {
  const CategoryAlreadyExistsFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).categoryRequestErrExists;
}

/// Emitted when `POST /api/v1/service-categories/requests` returns **429**
/// because the per-IP category-request rate limit (5/hr) is exhausted.
///
/// Surfaced to the suggestion dialog so it can show a "too many requests, try
/// later" message instead of a generic server error.
final class CategoryRequestThrottledFailure extends Failure {
  const CategoryRequestThrottledFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).categoryRequestErrThrottled;
}

/// Emitted when `POST /api/v1/support/contact` returns **503 Service
/// Unavailable** because the support channel is not configured on the backend
/// (e.g. the support inbox / forwarding address is unset).
///
/// Distinct from [ServerFailure] so the contact screen can show a specific
/// "support is temporarily unavailable, try later" message rather than the
/// generic server-error copy.
final class SupportChannelUnavailableFailure extends Failure {
  const SupportChannelUnavailableFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).contactSupportErrUnavailable;
}

/// Emitted when `POST /api/v1/support/contact` returns **413 Payload Too
/// Large** because the combined attachment size exceeded the 5 MB envelope the
/// backend enforces at the transport layer.
///
/// The client mirrors this limit (see [SupportLimits]) so a well-behaved client
/// never reaches the server with an over-budget payload — but a 413 is mapped
/// here as a backstop so the user still gets the right "attachments too large"
/// message instead of a generic server error.
final class SupportAttachmentTooLargeFailure extends Failure {
  const SupportAttachmentTooLargeFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).contactSupportErrTotalTooBig;
}

/// Emitted when `POST /api/v1/independent-masters/me/services/bulk` returns
/// **409 Conflict** because the master already has at least one active service.
///
/// The bulk endpoint is the first-time-setup guard: it only succeeds while the
/// master's catalogue is empty. A 409 means another path (e.g. the single-create
/// form, or a concurrent device) already populated the catalogue, so the
/// one-pass setup screen is no longer the right surface. The screen surfaces
/// this with a friendly "you already have services" message and routes the user
/// to the regular services list (which now has content) instead of retrying.
final class MasterAlreadyHasServicesFailure extends Failure {
  const MasterAlreadyHasServicesFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).serviceSetupErrAlreadyHasServices;
}

/// Emitted when a booking write returns HTTP **409 Conflict** because the
/// requested slot is no longer available.
///
/// Two call sites (Phase 14.0):
///   - `POST /bookings` — another client booked the same slot first (or the
///     master's schedule changed) between the client fetching available slots
///     and submitting the request.
///   - `PATCH /bookings/{id}/reschedule` — the requested new slot is taken, or
///     the booking is no longer in a reschedulable state (server-side race).
///
/// Generic on purpose — unlike [MasterAlreadyHasServicesFailure] or
/// [EmailAlreadyRegisteredFailure], this is not tied to one specific write; the
/// booking repository re-maps the interceptor's default
/// `ServerFailure(statusCode: 409)` to this type by checking
/// `e.response?.statusCode == 409` BEFORE deferring to `e.error is Failure`
/// (see `HttpBookingRepository._mapBookingWriteException`, mirroring the
/// `MasterAlreadyHasServicesFailure` precedent in `service_repository.dart`).
final class ConflictFailure extends Failure {
  const ConflictFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) => AppLocalizations.of(ctx).errConflict;
}

/// Emitted when `POST /appointments` returns HTTP **409** with the typed
/// `data.code == "DUPLICATE_SERVICE"` envelope (backend
/// `feat/multi-service-appointments`): the multi-service visit payload carried
/// the SAME `masterServiceId` more than once (or a conflicting service pairing
/// the backend rejects).
///
/// The MO-3 selection UI dedupes the chosen services up-front (a service can be
/// selected only once — the catalogue selection is a `Set` keyed by id), so a
/// well-behaved client never reaches the server with a duplicate. This failure
/// is the backstop for a stale/edge payload, mapped BEFORE the generic 409 →
/// [ConflictFailure] fallback in
/// `HttpAppointmentRepository._mapAppointmentWriteException` — mirroring the
/// `CLIENT_BOOKING_CONFLICT` / `BOOKING_ALREADY_ELAPSED` hand-decode precedent.
final class DuplicateServiceFailure extends Failure {
  const DuplicateServiceFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).bookingErrDuplicateService;
}

/// Emitted when a service-catalog WRITE (create / update / bulk-create) returns
/// HTTP **409** with the typed `data.code == "DUPLICATE_SERVICE"` envelope: the
/// master tried to add a service that is already in their menu (same service
/// type / definition), or a DB unique-index race caught a concurrent add.
///
/// Distinct from the appointment-path [DuplicateServiceFailure] — that one is a
/// booking payload naming the same `masterServiceId` twice ("a service can't be
/// added twice" to ONE visit), which reads wrong for the catalogue's "already in
/// your menu" case. This failure carries the two nullable diagnostic fields the
/// backend returns:
///   - [serviceName]: the clashing service's display name. **Null on the bulk
///     path** (the bulk envelope omits it) — render the plain message then.
///   - [existingServiceDefId]: the id of the already-present service definition.
///     **Null when the DB unique-index race caught it** (no row id to report).
///
/// Expected backend envelope:
/// ```json
/// {
///   "success": false,
///   "data": {
///     "code": "DUPLICATE_SERVICE",
///     "serviceName": "Манікюр класичний" | null,
///     "existingServiceDefId": "3f2a1c1e-…" | null
///   },
///   "message": "This service already exists"
/// }
/// ```
/// The server-supplied top-level `message` is intentionally NEVER shown (it is
/// untranslated internal English copy) — [userMessage] returns the Ukrainian
/// catalogue-specific copy regardless of which fields are present.
///
/// Decoded by `HttpServiceRepository._mapServiceWriteException` (create / update)
/// and `_mapBulkCreateException` (bulk) — checked BEFORE deferring to any
/// [Failure] the [ErrorMapperInterceptor] may already have attached (it maps a
/// non-auth 409 to a generic [ServerFailure]), mirroring the
/// `CategoryAlreadyExistsFailure` precedent.
final class ServiceDuplicateFailure extends Failure {
  const ServiceDuplicateFailure({
    this.serviceName,
    this.existingServiceDefId,
    super.cause,
  });

  /// The clashing service's display name, exactly as returned by the backend
  /// (an untranslated catalogue value). Null on the bulk path.
  final String? serviceName;

  /// The id of the already-present service definition. Null when a DB
  /// unique-index race caught the duplicate (no persisted row id to report).
  final String? existingServiceDefId;

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).serviceErrDuplicate;
}

/// Emitted when a booking WRITE (create/reschedule) returns HTTP **409** with
/// the typed `data.code == "CLIENT_BOOKING_CONFLICT"` envelope (backend
/// commit f95d8fd): the authenticated CLIENT already has a PENDING/CONFIRMED
/// booking — with ANY master or salon, not just the one being booked — whose
/// `[startsAt, endsAt)` window overlaps the requested slot.
///
/// Distinct from the generic [ConflictFailure] (the MASTER's slot is taken by
/// someone else) — here the CLIENT would be double-booking themselves. Carries
/// enough of the clashing booking to name it in the UI: [conflictingBookingId],
/// [serviceName], [masterName], [startsAt], [endsAt].
///
/// Expected backend envelope:
/// ```json
/// {
///   "success": false,
///   "data": {
///     "code": "CLIENT_BOOKING_CONFLICT",
///     "conflictingBookingId": "3f2a1c1e-…",
///     "serviceName": "Манікюр класичний",
///     "masterName": "Олена Коваль",
///     "startsAt": "2026-07-15T14:00:00+03:00",
///     "endsAt": "2026-07-15T15:30:00+03:00"
///   },
///   "message": "Client already has an overlapping booking"
/// }
/// ```
/// The server-supplied top-level `message` is intentionally NEVER shown (it is
/// untranslated, internal English copy) — [userMessage] composes its own
/// Ukrainian sentence from the typed fields via [formatBookingWindow], the SAME
/// shared formatter the booking confirm/success screens already use for the
/// "Час" row, so the window reads identically everywhere in the app (never a
/// raw ISO string).
///
/// Decoded by `HttpBookingRepository._mapBookingWriteException` — checked
/// BEFORE the generic 409 → [ConflictFailure] fallback (mirrors the
/// `EMAIL_ALREADY_REGISTERED` / `CategoryAlreadyExistsFailure` precedent: the
/// status-code branch runs before deferring to any [Failure] the interceptor
/// may already have attached).
final class ClientBookingConflictFailure extends Failure {
  const ClientBookingConflictFailure({
    required this.conflictingBookingId,
    required this.serviceName,
    required this.masterName,
    required this.startsAt,
    required this.endsAt,
    super.cause,
  });

  /// Id of the client's own PENDING/CONFIRMED booking that clashes with the
  /// requested slot. Not navigated to anywhere yet — kept typed (rather than
  /// discarded) as the natural extension point for a future "View booking"
  /// deep link from the conflict dialog.
  final String conflictingBookingId;

  /// The clashing booking's service name, exactly as returned by the backend
  /// (an untranslated catalogue/user value, not an l10n key).
  final String serviceName;

  /// The clashing booking's master (or salon-master) display name.
  final String masterName;

  /// The clashing booking's window start.
  final DateTime startsAt;

  /// The clashing booking's window end.
  final DateTime endsAt;

  @override
  String userMessage(BuildContext ctx) {
    final l10n = AppLocalizations.of(ctx);
    return l10n.bookingErrClientConflict(
      serviceName,
      masterName,
      formatBookingWindow(startsAt, endsAt),
    );
  }
}

/// Emitted when `PATCH /bookings/{id}/reschedule` or `PATCH /bookings/{id}/cancel`
/// returns HTTP **409** with the typed `data.code == "BOOKING_ALREADY_ELAPSED"`
/// envelope (backend commit 952e441): the booking's `endsAt` is already before
/// the SERVER clock, so it can no longer be rescheduled or cancelled — the visit
/// window has passed.
///
/// The guard is SERVER-authoritative: a client device-clock rollback cannot
/// bypass it. The mobile UI already flips an elapsed CONFIRMED booking to
/// read-only (see `BookingDisplayX.isPast`), so this failure is the defensive
/// backstop for a stale screen or a rolled-back clock that let the tap through
/// anyway — the screen catches it, shows [userMessage], and refetches the
/// booking so it re-renders read-only.
///
/// Decoded by `HttpBookingRepository` (both the write mapper
/// `_mapBookingWriteException` for reschedule and the cancel mapper) — the
/// `data.code` check runs BEFORE the generic 409 → [ConflictFailure] /
/// [ClientBookingConflictFailure] fallbacks, mirroring the
/// `CLIENT_BOOKING_CONFLICT` precedent.
final class BookingAlreadyElapsedFailure extends Failure {
  const BookingAlreadyElapsedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).bookingErrorAlreadyElapsed;
}

/// Emitted when `PATCH /bookings/{id}/decline` returns HTTP **409**.
///
/// Historically the backend's Phase 27.1 `BookingTemporalGuard
/// .assertFutureForProviderCancel` guard rejected a decline once a booking's
/// `startsAt` was no longer strictly in the future — a since-reversed
/// decision (the backend now allows a provider to decline a CONFIRMED
/// booking at ANY time, elapsed or not, so a client no-show is recorded as a
/// decline with a free-text reason rather than a separate status). This
/// failure is kept as a defensive backstop only: some OTHER 409 shape on this
/// endpoint is still plausible (e.g. a concurrent status change), and this is
/// the generic "decline was rejected" fallback for it.
///
/// **Decode note — unlike [BookingAlreadyElapsedFailure]:** the backend's
/// `BookingTemporalGuard`-family guards throw a plain
/// `BusinessException(CONFLICT, "...")` with no typed `data.code` envelope
/// (see `GlobalExceptionHandler.handleBusiness`, which genericises every
/// CONFLICT body to `{"data": null}`), unlike the `BookingElapsedException` /
/// `BOOKING_ALREADY_ELAPSED` shape [BookingAlreadyElapsedFailure] decodes.
/// `HttpBookingRepository.declineBooking` therefore maps EVERY 409 from this
/// endpoint to this failure directly, by CALL SITE rather than by body
/// content — there is nothing else a decline 409 could mean.
///
/// The mobile UI now offers «Скасувати» (decline) on a CONFIRMED provider
/// booking regardless of [BookingDisplayX.hasStarted], so this failure is
/// not expected to fire in normal operation — the screen still catches it,
/// shows [userMessage], and refetches the booking so the footer re-renders
/// correctly, as defense-in-depth against an unforeseen server-side
/// rejection.
final class ProviderDeclineWindowClosedFailure extends Failure {
  const ProviderDeclineWindowClosedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).bookingErrorProviderDeclineWindowClosed;
}

/// Emitted when `PATCH /bookings/{id}/complete` returns HTTP **409** — the
/// backend's Phase 27.1 `BookingTemporalGuard.assertElapsedForComplete`
/// guard: the booking's `startsAt` is still in the future (`now < startsAt`),
/// so a PROVIDER may not mark it COMPLETED yet.
///
/// Same decode note as [ProviderDeclineWindowClosedFailure] — the guard's
/// `BusinessException` carries no typed `data.code`, so
/// `HttpBookingRepository.completeBooking` maps every 409 from this endpoint
/// to this failure by call site. Defensive backstop for a stale screen /
/// rolled-back clock, mirroring that failure's doc.
final class ProviderCompleteNotStartedFailure extends Failure {
  const ProviderCompleteNotStartedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).bookingErrorProviderCompleteNotStarted;
}

/// Emitted when `POST /bookings` or `PATCH /bookings/{id}/reschedule` returns
/// HTTP **429** — the per-user booking-write rate limit (5 requests / 10 s,
/// backend commit f95d8fd) is exhausted.
///
/// Decoded by `HttpBookingRepository._mapBookingWriteException` — checked
/// BEFORE deferring to any [Failure] the interceptor already attached (the
/// interceptor has no booking-specific 429 case and would otherwise surface an
/// [UnknownFailure]), mirroring the `CategoryRequestThrottledFailure`
/// precedent in `service_repository.dart`.
final class BookingRateLimitedFailure extends Failure {
  const BookingRateLimitedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).bookingErrRateLimited;
}

/// Emitted when `POST /reviews` returns HTTP **409 Conflict** because the
/// authenticated client has ALREADY left a review for this booking (Phase
/// 14.6). The booking's server-computed `canReview` flag normally hides the
/// entry point, so this is the backstop for a stale screen or a stale
/// `/bookings/{id}/review` deep link opened after a review was already left.
///
/// Decoded by `HttpBookingRepository._mapReviewException` — the 409 status
/// check runs before deferring to any [Failure] the interceptor may have
/// attached (mirrors the `MasterAlreadyHasServicesFailure` precedent).
final class ReviewAlreadyExistsFailure extends Failure {
  const ReviewAlreadyExistsFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).reviewErrAlreadyReviewed;
}

/// Emitted when `POST /reviews` is rejected because the booking is not
/// reviewable by this client (Phase 14.6): HTTP **403** (the booking is not
/// owned by the authenticated client) or a **4xx** (e.g. the booking is not in
/// the `COMPLETED` state the backend requires). Both collapse to one friendly
/// "this booking can't be reviewed" message — the client never needs to
/// distinguish the two, and the `canReview` gate already prevents the happy
/// path from reaching either.
///
/// Decoded by `HttpBookingRepository._mapReviewException` before deferring to
/// the shared `_mapDioException`.
final class ReviewNotAllowedFailure extends Failure {
  const ReviewNotAllowedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).reviewErrNotAllowed;
}

/// Emitted when `POST /client-reviews` returns HTTP **409 Conflict** because
/// the authenticated PROVIDER has ALREADY left feedback about this booking's
/// client (track 7.x Wave B — «ВІДГУК ПРО КЛІЄНТА», backend `POST
/// /client-reviews`).
///
/// Unlike [ReviewAlreadyExistsFailure] (the CLIENT→MASTER direction), there is
/// currently NO server-computed canReview-equivalent flag on
/// `BookingDetailResponse` for the PROVIDER side — `BookingDetailScreen`
/// offers the «Залишити відгук про клієнта» entry CTA on every COMPLETED
/// provider booking, with no client-side way to know in advance whether
/// feedback was already left. This failure is therefore the ONLY signal of a
/// duplicate submit; `LeaveClientFeedbackScreen` surfaces it by swapping the
/// form for the same not-reviewable info state the CLIENT flow shows on a
/// stale deep link, rather than a silent no-op or a raw error.
///
/// Decoded by `HttpClientReviewRepository._mapClientReviewException` — the 409
/// status check runs before deferring to any [Failure] the interceptor may
/// have attached, mirroring the [ReviewAlreadyExistsFailure] precedent.
final class ClientReviewAlreadyExistsFailure extends Failure {
  const ClientReviewAlreadyExistsFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).clientReviewErrAlreadyReviewed;
}

/// Emitted when `POST /client-reviews` is rejected because the booking is not
/// eligible for provider feedback (track 7.x Wave B): HTTP **403** (not the
/// booking's provider), or any other **4xx** — e.g. the booking is not
/// COMPLETED, or it is a guest/LINK booking with no registered client account
/// to rate ([BookingDisplayX.isGuestBooking]). Both collapse into one friendly
/// message; the provider never needs to distinguish the two.
///
/// Decoded by `HttpClientReviewRepository._mapClientReviewException` before
/// deferring to the shared `_mapDioException`, mirroring
/// [ReviewNotAllowedFailure].
final class ClientReviewNotAllowedFailure extends Failure {
  const ClientReviewNotAllowedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).clientReviewErrNotAllowed;
}
