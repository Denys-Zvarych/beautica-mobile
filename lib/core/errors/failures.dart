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
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({super.cause});

  @override
  String userMessage(BuildContext ctx) =>
      AppLocalizations.of(ctx).errUnauthorized;
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
