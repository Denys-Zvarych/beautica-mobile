// Shared source-scan used by the `*_no_settle_*` guard tests. For every match
// of each trigger regex in [path] it takes the window up to the next trigger
// (of any kind) or the next `testWidgets(`, and requires a `pumpUntil*` to
// appear before the first read (first match of [firstRead]) in that window.
// Comments are blanked (same length, newlines kept) so offsets and line
// numbers still map onto the real file. Every trigger must match at least
// once, so a renamed key cannot silently turn the guard vacuous.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void expectPumpUntilBeforeFirstRead({
  required String path,
  required List<RegExp> triggers,
  required RegExp firstRead,
}) {
  final String raw = File(path).readAsStringSync();
  final String src = raw.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/|//[^\n]*'),
    (Match c) => c[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
  final RegExp stopAtTest = RegExp(r'testWidgets\(');
  for (final RegExp call in triggers) {
    final List<RegExpMatch> calls = call.allMatches(src).toList();
    expect(calls, isNotEmpty, reason: 'no match for ${call.pattern}');
    for (final RegExpMatch m in calls) {
      final String tail = src.substring(m.end);
      int end = tail.length;
      for (final RegExp stop in <RegExp>[...triggers, stopAtTest]) {
        final RegExpMatch? s = stop.firstMatch(tail);
        if (s != null && s.start < end) end = s.start;
      }
      final String rest = tail.substring(0, end);
      final int pump = rest.indexOf(RegExp(r'pumpUntil\w*\('));
      final RegExpMatch? read = firstRead.firstMatch(rest);
      final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      expect(
        pump != -1 && (read == null || pump < read.start),
        isTrue,
        reason:
            '$path:$line — ${call.pattern} must be followed by a pumpUntil* '
            'before its first read (${firstRead.pattern})',
      );
    }
  }
}
