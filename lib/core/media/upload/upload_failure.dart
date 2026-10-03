// Phase 070 — typed failure for the shared media-upload seam.
//
// Every failure the upload path can produce is mapped to one of these so the
// photo screens (phases 071-074) render a single localised message without
// probing Dio internals.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Why a media upload (or delete) failed.
sealed class UploadFailure implements Exception {
  const UploadFailure();

  /// Localised, user-facing message. Never carries server text.
  String message(AppLocalizations l10n);
}

/// The file is over the 5 MB limit — HTTP 413 or the client-side pre-check.
final class UploadTooLargeFailure extends UploadFailure {
  const UploadTooLargeFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorTooLarge;
}

/// The server rejected the file as not JPEG/PNG/WebP — HTTP 400.
final class UploadUnsupportedFormatFailure extends UploadFailure {
  const UploadUnsupportedFormatFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorFormat;
}

/// Media storage is switched off server-side — HTTP 503.
final class UploadStorageUnavailableFailure extends UploadFailure {
  const UploadStorageUnavailableFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorStorage;
}

/// Connect / send / receive timeout or no connection.
final class UploadNetworkFailure extends UploadFailure {
  const UploadNetworkFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorNetwork;
}

/// The TLS handshake was rejected by the pinned trust anchors. Deliberately
/// NOT [UploadNetworkFailure]: retrying or switching network is the wrong
/// advice under an intercepting proxy.
final class UploadCertificateFailure extends UploadFailure {
  const UploadCertificateFailure();

  @override
  String message(AppLocalizations l10n) => l10n.errCertificate;
}

/// HTTP 401 after the refresh interceptor gave up.
final class UploadUnauthorizedFailure extends UploadFailure {
  const UploadUnauthorizedFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorUnauthorized;
}

/// HTTP 403.
final class UploadForbiddenFailure extends UploadFailure {
  const UploadForbiddenFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorForbidden;
}

/// HTTP 404 — e.g. the service definition is inactive or gone.
final class UploadNotFoundFailure extends UploadFailure {
  const UploadNotFoundFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorNotFound;
}

/// The caller cancelled the upload via `UploadTask.cancel()`.
final class UploadCancelledFailure extends UploadFailure {
  const UploadCancelledFailure();

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorCancelled;
}

/// Anything not covered above; [status] is the HTTP status when there was one.
final class UploadUnknownFailure extends UploadFailure {
  const UploadUnknownFailure([this.status]);

  final int? status;

  @override
  String message(AppLocalizations l10n) => l10n.uploadErrorGeneric;
}
