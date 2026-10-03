// Phase 072 — the ONE definition of "a file the 071 pipeline produced", shared by
// `MediaPickService` (which writes it) and `LocalPreviewImage` (which renders it).

import 'dart:io' show File;

import 'package:path/path.dart' as p;

/// Sub-directory of the temp dir that holds finished picks.
const String kMediaUploadDirName = 'media_upload';

/// Whether [file] sits directly inside a `media_upload` scratch dir.
///
/// A synchronous SHAPE check (the temp root itself is only known
/// asynchronously via path_provider): the path must be absolute and, once
/// normalised (so `..` cannot escape), its parent directory must be named
/// [kMediaUploadDirName]. `MediaPickService` writes every pick to exactly
/// `<temp>/media_upload/<random>.jpg`.
bool isMediaScratchFile(File file) {
  final String path = p.normalize(file.path);
  if (!p.isAbsolute(path)) return false;
  return p.basename(p.dirname(path)) == kMediaUploadDirName;
}
