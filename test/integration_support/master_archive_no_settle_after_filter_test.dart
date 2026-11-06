// Source-scan guard (the lull race is not reproducible headless: it needs the
// emulator's animations-off timing). `applyConfirmedFilter(tester);` in
// `master_archive_flow_test.dart` ends on a single pump; an
// `AppHarness.settle` right after it can return before the filtered page
// lands (nothing keeps frames scheduled across the fetch lull). A `settle` may
// only drain the sheet pop; the first `expect(` after the apply must be
// preceded by a `pumpUntil*` that waits for the filtered page.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'applyConfirmedFilter is followed by pumpUntil* before the first expect',
    () {
      final String raw = File(
        'integration_test/master_archive_flow_test.dart',
      ).readAsStringSync();
      // Comments blanked (same length, newlines kept) so offsets and line
      // numbers still map onto the real file.
      final String src = raw.replaceAllMapped(
        RegExp(r'/\*[\s\S]*?\*/|//[^\n]*'),
        (Match c) => c[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
      );
      final RegExp call = RegExp(r'await applyConfirmedFilter\(tester\);');
      final List<RegExpMatch> calls = call.allMatches(src).toList();
      expect(calls, isNotEmpty);
      for (final RegExpMatch m in calls) {
        // Window ends at the next apply call or the end of the enclosing test.
        final String tail = src.substring(m.end);
        int end = tail.length;
        for (final RegExp stop in <RegExp>[call, RegExp(r'testWidgets\(')]) {
          final RegExpMatch? s = stop.firstMatch(tail);
          if (s != null && s.start < end) end = s.start;
        }
        final String rest = tail.substring(0, end);
        final int pump = rest.indexOf('pumpUntil');
        final int expectAt = rest.indexOf('expect(');
        final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        expect(
          pump != -1 && (expectAt == -1 || pump < expectAt),
          isTrue,
          reason:
              'master_archive_flow_test.dart:$line — applyConfirmedFilter must '
              'be followed by a pumpUntil* before its first expect(',
        );
      }
    },
  );
}
