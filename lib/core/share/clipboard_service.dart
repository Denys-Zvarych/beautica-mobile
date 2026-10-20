// Phase 413 (D6) — the app's ONLY clipboard writer.
//
// Wraps `Clipboard.setData` behind a provider-injected interface so widget
// tests override [clipboardServiceProvider] with a mocktail fake.
//
// [ClipboardService.copyText] returns `false` instead of throwing when the
// platform rejects the write, so the caller decides what to show.

import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clipboard_service.g.dart';

abstract interface class ClipboardService {
  /// Puts [text] on the system clipboard; `true` on success.
  Future<bool> copyText(String text);
}

final class PlatformClipboardService implements ClipboardService {
  const PlatformClipboardService();

  @override
  Future<bool> copyText(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } on Object catch (e, st) {
      // The copied text is never logged — it may carry a personal link.
      log(
        'clipboard write failed: ${e.runtimeType}',
        name: 'core.share',
        level: 900,
        stackTrace: st,
      );
      return false;
    }
  }
}

@Riverpod(keepAlive: true)
ClipboardService clipboardService(Ref ref) => const PlatformClipboardService();
