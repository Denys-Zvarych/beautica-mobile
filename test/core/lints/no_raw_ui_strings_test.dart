// Phase 1.3 — Tests for the `no_raw_ui_strings` custom lint rule.
//
// We test the rule's AST-inspection logic via the pure-analyzer checker
// (`no_raw_ui_strings_checker.dart`) rather than via `custom_lint_builder`'s
// `testAnalyzeAndRun` harness. Reason: `custom_lint_builder` 0.7.3 pulls
// in `analyzer_plugin` 0.12.0, which still uses the analyzer 6.x `Element`
// API; Flutter 3.41+ ships analyzer 7.x with the new `Element2` API. The
// resulting compile mismatch makes `testAnalyzeAndRun` unusable from
// inside `flutter test`. The checker is dependency-free of the plugin SDK,
// so it parses + asserts cleanly. End-to-end coverage of the
// `custom_lint` runtime (including `// ignore:` filtering and severity
// reporting) is delegated to `mobile-build-verifier`'s
// `dart run custom_lint` smoke check.
//
// Coverage targets the seven cases enumerated in phase doc § Step 8:
//   1. FLAG  Text('Hello')
//   2. FLAG  AppBar(title: Text('Home'))
//   3. FLAG  TextField(decoration: InputDecoration(hintText: 'Search'))
//   4. FLAG  Tooltip(message: 'Open menu')
//   5. PASS  Text(l10n.loginTitle)
//   6. PASS  Text(user.name)
//   7. PASS  Text('debug-only')  // ignore: no_raw_ui_strings  ← runtime filter
//      The runtime ignore is a custom_lint pipeline concern; here we
//      simulate it by checking that the checker reports the literal AND
//      that the same line carries the directive, leaving the actual skip
//      to the plugin host.

// ignore_for_file: depend_on_referenced_packages

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:beautica_mobile/core/lints/no_raw_ui_strings_checker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget expression in the minimum scaffolding required for the
/// analyzer to build a syntactically valid compilation unit. The path is
/// passed separately to the checker so allow-list semantics can be tested
/// in isolation from the source text.
String _wrap(String widgetExpr) =>
    '''
import 'package:flutter/material.dart';

class _User { final String name = ''; }
abstract class _L10n { String get loginTitle; }

Widget build(BuildContext context, _L10n l10n, _User user) {
  return $widgetExpr;
}
''';

/// Parse + run the checker against [widgetExpr]. [path] defaults to a
/// `lib/`-flavoured path so allow-list rules don't accidentally clear all
/// findings; tests that target allow-listed paths override it.
List<String> _findings(String widgetExpr, {String path = '/proj/lib/x.dart'}) {
  final result = parseString(
    content: _wrap(widgetExpr),
    throwIfDiagnostics: false,
  );
  final hits = findRawUiStringLiterals(result.unit, path: path);
  return hits.map((lit) => lit.value).toList();
}

void main() {
  group('no_raw_ui_strings — FLAG cases', () {
    test('1. Text(\'Hello\') — positional literal on Text', () {
      expect(_findings("Text('Hello')"), <String>['Hello']);
    });

    test(
      '2. AppBar(title: Text(\'Home\')) — descends through Text wrapper',
      () {
        // The visitor reaches the inner `'Home'` literal twice — once via
        // AppBar.title descent, once via the nested Text directly. The
        // checker de-duplicates by source offset (mirroring the custom_lint
        // runtime behaviour), so we expect exactly one finding.
        expect(_findings("AppBar(title: Text('Home'))"), <String>['Home']);
      },
    );

    test('3. TextField hintText literal', () {
      expect(
        _findings("TextField(decoration: InputDecoration(hintText: 'Search'))"),
        <String>['Search'],
      );
    });

    test('4. Tooltip(message: \'Open menu\')', () {
      expect(
        _findings("Tooltip(message: 'Open menu', child: SizedBox())"),
        <String>['Open menu'],
      );
    });
  });

  group('no_raw_ui_strings — PASS cases', () {
    test('5. Text(l10n.loginTitle) — AppLocalizations reference', () {
      expect(_findings('Text(l10n.loginTitle)'), isEmpty);
    });

    test('6. Text(user.name) — property access, not a literal', () {
      expect(_findings('Text(user.name)'), isEmpty);
    });

    test(
      '7. Text(\'debug-only\') skipped by `// ignore: no_raw_ui_strings` '
      '(runtime filter; checker reports the literal, runtime suppresses)',
      () {
        // The checker itself does NOT consume `// ignore:` directives —
        // that is a `custom_lint` runtime concern. So we verify TWO
        // things in this test:
        //   a) The checker DOES surface the literal (the rule is correct).
        //   b) The literal sits on the line *immediately after* an
        //      `// ignore: no_raw_ui_strings` directive — i.e. the
        //      runtime filter has a valid input to suppress it.
        const source = '''
import 'package:flutter/material.dart';

Widget build(BuildContext context) {
  // ignore: no_raw_ui_strings
  return Text('debug-only');
}
''';
        final result = parseString(content: source, throwIfDiagnostics: false);
        final hits = findRawUiStringLiterals(
          result.unit,
          path: '/proj/lib/x.dart',
        );
        expect(hits, hasLength(1));
        // Compute the line number of the literal in the ORIGINAL source
        // (lineInfo from the parser is relative to the input string, so
        // we split the same input by '\n' to look at the actual lines).
        final int literalLine = result.lineInfo
            .getLocation(hits.first.offset)
            .lineNumber;
        final List<String> sourceLines = source.split('\n');
        // Lines are 1-indexed; the line immediately above the literal
        // sits at `literalLine - 2` in the zero-indexed split.
        expect(literalLine, greaterThan(1));
        final String previousLine = sourceLines[literalLine - 2];
        expect(
          previousLine.contains('// ignore: no_raw_ui_strings'),
          isTrue,
          reason:
              'Line above the literal must carry the ignore directive '
              'so the custom_lint runtime suppresses it (found instead: '
              '"$previousLine").',
        );
      },
    );
  });

  group('no_raw_ui_strings — allow-list', () {
    test('empty Text(\'\') does not fire', () {
      expect(_findings("Text('')"), isEmpty);
    });

    test('files under lib/api/ are exempt (generated OpenAPI client)', () {
      expect(
        _findings("Text('Hello')", path: '/proj/lib/api/foo.dart'),
        isEmpty,
      );
    });

    test('*.g.dart files are exempt (codegen output)', () {
      expect(
        _findings("Text('Hello')", path: '/proj/lib/features/x.g.dart'),
        isEmpty,
      );
    });

    test('files under test/ are exempt', () {
      expect(
        _findings("Text('Hello')", path: '/proj/test/widget/x_test.dart'),
        isEmpty,
      );
    });
  });
}
