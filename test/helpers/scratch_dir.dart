// Teardown helper for tests that hand a real temp dir to code which deletes
// files inside it ASYNCHRONOUSLY (e.g. `PortfolioEditController`'s
// fire-and-forget dispose delete, `portfolio_edit_controller.dart`).

import 'dart:io';

/// Recursively deletes [dir], tolerating files that vanish mid-walk.
///
/// `deleteSync(recursive: true)` lists the dir and then deletes each entry;
/// an entry removed by a still-running async delete in between makes it throw
/// `PathNotFoundException` reported against [dir] itself (CI-only — slower
/// I/O widens the window). Each retry re-lists, so it converges; a dir that is
/// already gone is done.
void deleteScratchDir(Directory dir) {
  const int attempts = 5;
  for (var i = 1; ; i++) {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (i >= attempts) rethrow;
    }
  }
}
