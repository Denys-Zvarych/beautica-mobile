// Phase 072 — the ONE definition of "a file the 071 pipeline produced", shared by
// `MediaPickService` (which writes it) and `LocalPreviewImage` (which renders it).

import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Sub-directory of the temp dir that holds finished picks.
const String kMediaUploadDirName = 'media_upload';

/// The temp root `MediaPickService` resolved (`getTemporaryDirectory()` in the
/// app), recorded by [registerMediaScratchRoot]. `null` until a pick service
/// has resolved it in this process.
String? _scratchRoot;

/// Records [tempRoot] as THE temp root the scratch dir lives under. Called by
/// `MediaPickService` every time it resolves its temp dir — always BEFORE it
/// writes a file there, so by the time any scratch file exists to be
/// previewed, the root is known.
void registerMediaScratchRoot(String tempRoot) {
  _scratchRoot = p.normalize(tempRoot);
}

/// Forgets the registered root (tests only).
@visibleForTesting
void debugResetMediaScratchRoot() => _scratchRoot = null;

/// Whether [file] sits directly inside THE `<temp>/media_upload` scratch dir.
///
/// Synchronous (the temp root itself is only known asynchronously via
/// path_provider, so `MediaPickService` registers it — see
/// [registerMediaScratchRoot]): the path must be absolute and, once
/// normalised (so `..` cannot escape), its parent must be EXACTLY
/// `<tempRoot>/media_upload` — not merely any folder named `media_upload`
/// (Phase 367 audit, security INFO). `MediaPickService` writes every pick to
/// exactly `<temp>/media_upload/<random>.jpg`.
///
/// [tempRoot] overrides the registered root. With no root at all (no pick has
/// run in this process — so no legitimate scratch file can exist) a release
/// build fails closed; debug / test builds fall back to the parent-name shape
/// check so widget tests can preview fixture paths without a pick service.
bool isMediaScratchFile(File file, {String? tempRoot}) {
  final String path = p.normalize(file.path);
  if (!p.isAbsolute(path)) return false;
  final String parent = p.dirname(path);
  if (p.basename(parent) != kMediaUploadDirName) return false;
  final String? root = tempRoot ?? _scratchRoot;
  if (root == null) return !kReleaseMode;
  return p.equals(parent, p.join(p.normalize(root), kMediaUploadDirName));
}
