// Phase 071 — what kind of photo is being picked, and the crop/size rules
// that go with it.

/// Where the picture comes from. Own enum (not image_picker's `ImageSource`)
/// so callers and fakes never import a plugin.
enum MediaPickSource { gallery, camera }

/// Picker pre-downscale ceiling (both dimensions), px.
const int kPickerMaxDimension = 2048;

/// uCrop / TOCropViewController output JPEG quality. Near-lossless on purpose:
/// the picker no longer re-encodes (it only bounds dimensions) and the final
/// `compress` pass is the single lossy step that matters.
const int kCropQuality = 100;

/// First final re-encode quality.
const int kFinalQuality = 85;

/// Retry quality when the first re-encode is still over [kRetryAboveBytes].
const int kRetryQuality = 70;

/// A first re-encode above this triggers the q70 retry (headroom under the
/// 5 MB server cap).
const int kRetryAboveBytes = 4500 * 1024;

/// Crop + output spec for one [MediaKind].
final class MediaSpec {
  const MediaSpec({
    required this.aspectX,
    required this.aspectY,
    required this.circle,
    required this.maxWidth,
    required this.maxHeight,
  });

  final int aspectX;
  final int aspectY;

  /// Circular crop overlay (avatars). The output is still a rectangle.
  final bool circle;
  final int maxWidth;
  final int maxHeight;
}

enum MediaKind {
  /// 1:1 circle crop, final ≤ 1024×1024.
  avatar(
    MediaSpec(
      aspectX: 1,
      aspectY: 1,
      circle: true,
      maxWidth: 1024,
      maxHeight: 1024,
    ),
  ),

  /// 4:3 locked rectangle, final ≤ 1600×1200.
  servicePhoto(
    MediaSpec(
      aspectX: 4,
      aspectY: 3,
      circle: false,
      maxWidth: 1600,
      maxHeight: 1200,
    ),
  );

  const MediaKind(this.spec);

  final MediaSpec spec;
}
