// Phase 413 (D6) — the app's ONLY door to the native share sheet.
//
// Wraps `share_plus` behind a provider-injected interface so widget tests
// override [shareServiceProvider] with a mocktail fake and never touch the
// platform channel. Never call `SharePlus` directly from a widget.
//
// [ShareService.shareText] never throws: a platform failure is logged and
// reported as [ShareOutcome.failed] so the caller can show a snackbar.

import 'dart:developer';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'share_service.g.dart';

/// What happened to a share request.
enum ShareOutcome {
  /// The user picked a target (Android / iOS report this).
  shared,

  /// The user closed the sheet without picking a target.
  dismissed,

  /// The platform does not report the outcome.
  unavailable,

  /// The sheet could not be opened.
  failed,
}

abstract interface class ShareService {
  /// Opens the native share sheet with [text]; [subject] is used by targets
  /// that have one (e-mail).
  Future<ShareOutcome> shareText(String text, {String? subject});
}

final class PlatformShareService implements ShareService {
  PlatformShareService([SharePlus? sharePlus])
    : _sharePlus = sharePlus ?? SharePlus.instance;

  final SharePlus _sharePlus;

  @override
  Future<ShareOutcome> shareText(String text, {String? subject}) async {
    try {
      final ShareResult result = await _sharePlus.share(
        ShareParams(text: text, subject: subject),
      );
      return switch (result.status) {
        ShareResultStatus.success => ShareOutcome.shared,
        ShareResultStatus.dismissed => ShareOutcome.dismissed,
        ShareResultStatus.unavailable => ShareOutcome.unavailable,
      };
    } on Object catch (e, st) {
      // The shared text is never logged — it may carry a personal link.
      log(
        'share sheet failed: ${e.runtimeType}',
        name: 'core.share',
        level: 900,
        stackTrace: st,
      );
      return ShareOutcome.failed;
    }
  }
}

@Riverpod(keepAlive: true)
ShareService shareService(Ref ref) => PlatformShareService();
