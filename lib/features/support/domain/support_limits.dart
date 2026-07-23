// Client-side mirror of the backend's `POST /api/v1/support/contact` limits.
//
// The server is the source of truth; these constants exist so the UI can give
// instant feedback BEFORE the request fires (a too-short message disables Send,
// an over-budget attachment set turns the size meter red, etc.). Keep these in
// lockstep with the backend contract.
//
// Pure Dart — no Flutter imports.

/// Validation limits + allowed content types for the support-contact form,
/// mirroring the backend's server-side enforcement.
abstract final class SupportLimits {
  /// Minimum message length (characters). Below this, Send is disabled.
  static const int minMessage = 10;

  /// Maximum message length (characters).
  static const int maxMessage = 5000;

  /// Maximum subject length (characters); the subject is optional.
  static const int maxSubject = 150;

  /// Maximum number of attachments.
  static const int maxFiles = 5;

  /// Maximum size of any single attachment, in bytes (5 MB).
  static const int maxFileBytes = 5 * 1024 * 1024;

  /// Maximum combined size of all attachments, in bytes (5 MB).
  static const int maxTotalBytes = 5 * 1024 * 1024;

  /// Content types the backend accepts (sniffed by magic bytes server-side).
  static const Set<String> allowedContentTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
  };

  /// File extensions accepted by the picker, mapped to their MIME type. Used to
  /// resolve a content type when the picker does not report one directly.
  static const Map<String, String> extensionContentTypes = <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
  };
}
