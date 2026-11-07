// Shared source-scan used by the `*_no_settle_*` guard tests. For every match
// of each trigger regex in [path] it takes the window up to the next trigger
// (of any kind) or the next `testWidgets(`, and requires a `pumpUntil*` to
// appear before the first read (first match of [firstRead]) in that window.
// Comments are blanked (same length, newlines kept) so offsets and line
// numbers still map onto the real file. Every trigger must match at least
// once, so a renamed key cannot silently turn the guard vacuous.
//
// [waitPattern] is the accepted wait (default any `pumpUntil*(`).
// [skipInsideFunctions] names helper functions whose bodies are excluded: a
// trigger match inside such a body is not checked (it is still a window
// boundary), because a helper ends without a read — its CALLERS are the
// triggers. With helpers excluded, `read == null` means "no read follows
// before the next trigger/test"; the check then still demands a wait, which
// is intended for the remaining (test-body) triggers, where a trigger with no
// wait before the next test is a missing wait, not a false positive.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void expectPumpUntilBeforeFirstRead({
  required String path,
  required List<RegExp> triggers,
  required RegExp firstRead,
  RegExp? waitPattern,
  List<String> skipInsideFunctions = const <String>[],
}) {
  final RegExp wait = waitPattern ?? RegExp(r'pumpUntil\w*\(');
  final String raw = File(path).readAsStringSync();
  final String src = raw.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/|//[^\n]*'),
    (Match c) => c[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
  final RegExp stopAtTest = RegExp(r'testWidgets\(');
  // [start, end) offsets of each named helper's `{ ... }` body.
  final List<(int, int)> skipped = <(int, int)>[];
  for (final String name in skipInsideFunctions) {
    final RegExpMatch? decl = RegExp(
      r'\b' + RegExp.escape(name) + r'\([^)]*\)\s*(?:async\s*)?\{',
    ).firstMatch(src);
    expect(decl, isNotNull, reason: 'no declaration of $name in $path');
    int depth = 1;
    int i = decl!.end;
    for (; i < src.length && depth > 0; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') depth--;
    }
    skipped.add((decl.start, i));
  }
  for (final RegExp call in triggers) {
    final List<RegExpMatch> calls = call.allMatches(src).toList();
    expect(calls, isNotEmpty, reason: 'no match for ${call.pattern}');
    for (final RegExpMatch m in calls) {
      if (skipped.any(((int, int) r) => m.start >= r.$1 && m.start < r.$2)) {
        continue;
      }
      final String tail = src.substring(m.end);
      int end = tail.length;
      for (final RegExp stop in <RegExp>[...triggers, stopAtTest]) {
        final RegExpMatch? s = stop.firstMatch(tail);
        if (s != null && s.start < end) end = s.start;
      }
      final String rest = tail.substring(0, end);
      final int pump = rest.indexOf(wait);
      final RegExpMatch? read = firstRead.firstMatch(rest);
      final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      expect(
        pump != -1 && (read == null || pump < read.start),
        isTrue,
        reason:
            '$path:$line — ${call.pattern} must be followed by a ${wait.pattern} '
            'before its first read (${firstRead.pattern})',
      );
    }
  }
}
