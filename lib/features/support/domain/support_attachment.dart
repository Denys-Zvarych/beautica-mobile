// Pure-Dart domain model for a support-message attachment.
//
// One picked file the user wants to send with their support message. The
// presentation layer holds a growing list of these; the repository turns each
// into a multipart file part. No Flutter imports — this stays testable without
// a widget tree.

/// The two attachment categories the UI distinguishes by glyph + label. Maps
/// from the file's MIME type / extension at pick time.
enum SupportAttachmentKind {
  /// JPEG / PNG / WEBP image.
  image,

  /// PDF document.
  pdf,
}

/// One attachment selected for a support message.
///
/// [bytes] is the in-memory file content (used to build the multipart part and
/// to compute the size meter). [name] is the original filename (shown on the
/// chip). [contentType] is the resolved MIME type sent on the file part
/// (`image/jpeg`, `image/png`, `image/webp`, or `application/pdf`).
final class SupportAttachment {
  const SupportAttachment({
    required this.name,
    required this.bytes,
    required this.contentType,
    required this.kind,
  });

  /// Original filename, e.g. `screenshot.png`.
  final String name;

  /// In-memory file content.
  final List<int> bytes;

  /// Resolved MIME type for the multipart part.
  final String contentType;

  /// Image vs PDF — drives the chip glyph + label.
  final SupportAttachmentKind kind;

  /// Size of this attachment in bytes.
  int get size => bytes.length;
}
