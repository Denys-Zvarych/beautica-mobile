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
  const ValidationFailure({required this.fieldErrors, super.cause});

  /// Server-supplied field error messages keyed by field name / JSON path.
  ///
  /// Never display raw values from this map directly in UI labels without
  /// sanitizing or truncating them — server strings are untrusted input.
  /// Use [userMessage] for a safe localized summary.
  final Map<String, String> fieldErrors;

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
