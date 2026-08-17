// Standalone CLI host for the `no_raw_ui_strings` AST checker.
//
// WHY THIS EXISTS (2026-08-18)
// ----------------------------
// The rule was authored in Phase 1.3 as a `custom_lint` plugin: a pure
// checker (`lib/core/lints/no_raw_ui_strings_checker.dart`) plus a thin
// `DartLintRule` adapter, discovered through `lib/beautica_mobile.dart`'s
// `createPlugin()`. It never ran once. `custom_lint` discovers plugins by
// scanning the ANALYZED package's dependencies for packages that depend on
// `custom_lint_builder`, then loading `package:<dep>/<dep>.dart` — and a
// package is never a plugin of itself. `lib/beautica_mobile.dart` is not a
// dependency of `beautica_mobile`, so `createPlugin()` was never called.
// `dart run custom_lint` returned exit 0 in under a second across ~1200
// files, and a planted `Text('Raw untranslated probe string')` under `lib/`
// went undetected even with the rule promoted to `error` severity.
//
// The checker itself was always correct and is covered by 19 unit tests. So
// the fix is a WIRING fix: keep the checker byte-for-byte, delete the plugin
// host, and drive the checker from this CLI behind the house-pattern shell
// guard `scripts/forbid_raw_ui_strings.sh`.
//
// WHAT THE `custom_lint` RUNTIME USED TO PROVIDE, AND IS REIMPLEMENTED HERE
// ------------------------------------------------------------------------
// Suppression. The checker has no notion of it — it reports every literal it
// finds. Under `custom_lint` the runtime filtered findings against `// ignore:`
// / `// ignore_for_file:` directives before reporting. Off that runtime, the
// host owns it, so this file implements:
//
//   * `// ignore_for_file: no_raw_ui_strings`  anywhere in the file -> the
//     whole file is skipped.
//   * `// ignore: no_raw_ui_strings`           on the offending line, or
//     anywhere in the unbroken run of `//` comment lines directly above it.
//   * `// raw-ui-string-ok: <reason>`          same placement rules; the
//     house escape-comment spelling, matching `i18n-finder-ok:` /
//     `future-date-ok:` / `cycle-safe:` elsewhere in `scripts/`.
//
// BOTH `ignore:` and `raw-ui-string-ok:` are accepted, permanently.
// `ignore:` because suppressions were written across the corpus on the
// (mistaken) assumption the plugin was live, and silently re-flagging all of
// them would bury the real signal; `raw-ui-string-ok:` because it is the
// convention every other guard in this repo uses and it is the spelling for
// new code. A bare `raw-ui-string-ok:` carrying NO reason parses fine on
// purpose — the gate should never be the thing that blocks a merge over
// comment prose — but it is a review smell: the reason is the only part a
// human can check.
//
// COMMENT-RUN SCOPING is deliberately identical to
// `scripts/forbid_cyrillic_finder.sh`: the walk upward from an offender stops
// at the first line that is not a bare `//` comment line. An annotation
// separated from its literal by real code does NOT count — otherwise any
// escape comment near the top of a file would quietly become a blanket
// file-level opt-out.
//
// ALLOW-LIST RATCHET
// ------------------
// `scripts/.raw_ui_strings_allow`, one repo-relative path per line, `#`
// comments and blanks ignored — loaded exactly as
// `scripts/.stale_future_date_allow` is. The corpus predates any working
// enforcement of this rule, so the baseline grandfathers the files that
// already violate it. It only ever SHRINKS. Every normal run prints
// `allow-listed files: N` so the number is visible in CI output and a
// baseline that stops shrinking is noticeable.
//
// USAGE
//   dart tool/lints/no_raw_ui_strings.dart [--root=<abs>]
//       Scan `lib/`, print offenders, exit 1 if any survive the allow-list.
//   dart tool/lints/no_raw_ui_strings.dart --self-test
//       Run the synthetic probe matrix; exit 0/1.
//   dart tool/lints/no_raw_ui_strings.dart --write-allow
//       Rescan ignoring the current allow-list and REWRITE it from the
//       result. Baseline-only; exit 0.
//
// Normally invoked through `scripts/forbid_raw_ui_strings.sh`.

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:beautica_mobile/core/lints/no_raw_ui_strings_checker.dart';

/// Repo-relative path of the ratchet baseline.
const String kAllowListPath = 'scripts/.raw_ui_strings_allow';

/// Repo-relative root the gate scans. Deliberately `lib/` only: `test/`,
/// `integration_test/` and `tool/` all legitimately carry raw literals, and
/// the checker's own [isRawUiStringFileAllowListed] already exempts `test/`.
const String kScanRoot = 'lib';

/// `// ignore_for_file: … no_raw_ui_strings …` anywhere in the file.
final RegExp _ignoreForFile = RegExp(
  r'//\s*ignore_for_file:[^\n]*\bno_raw_ui_strings\b',
);

/// `// ignore: … no_raw_ui_strings …` on a single line.
final RegExp _ignoreLine = RegExp(r'//\s*ignore:[^\n]*\bno_raw_ui_strings\b');

/// `// raw-ui-string-ok: <reason>` — the house escape comment.
final RegExp _escapeComment = RegExp(r'//\s*raw-ui-string-ok:');

/// One reportable offender.
class Offender {
  const Offender({
    required this.relativePath,
    required this.line,
    required this.text,
  });

  final String relativePath;
  final int line;
  final String text;

  /// House output format, byte-compatible with the `printf "%s:%d:%s\n"`
  /// every `scripts/forbid_*.sh` guard emits.
  String format() => '$relativePath:$line:$text';
}

Future<void> main(List<String> args) async {
  final String root = _resolveRoot(args);

  // A root path that itself trips the checker's own path exemptions would
  // silently allow-list EVERY file — the exact silent-pass failure mode this
  // gate was written to end. Fail loudly instead of passing vacuously.
  if (isRawUiStringFileAllowListed('$root/_probe.dart')) {
    stderr.writeln(
      'FATAL: the repo root "$root" matches isRawUiStringFileAllowListed '
      '(it contains "/test/" or "/dev/"), so every scanned file would be '
      'exempt and this gate would pass vacuously. Move the checkout, or '
      'pass an explicit --root=<path>.',
    );
    exit(2);
  }

  if (args.contains('--self-test')) {
    exit(await _runSelfTest());
  }

  if (args.contains('--write-allow')) {
    exit(await _writeAllowList(root));
  }

  final Set<String> allowed = _loadAllowList(root);
  final List<Offender> offenders = await _scan(root, skip: allowed);

  stdout.writeln('allow-listed files: ${allowed.length}');

  if (offenders.isEmpty) {
    exit(0);
  }
  for (final Offender o in offenders) {
    stdout.writeln(o.format());
  }
  exit(1);
}

String _resolveRoot(List<String> args) {
  for (final String a in args) {
    if (a.startsWith('--root=')) {
      return Directory(a.substring('--root='.length)).absolute.path;
    }
  }
  return Directory.current.absolute.path;
}

// ---------------------------------------------------------------------------
// Scanning
// ---------------------------------------------------------------------------

/// Walks `<root>/lib/**.dart` and returns every surviving offender.
///
/// [skip] holds repo-relative paths grandfathered by the ratchet.
Future<List<Offender>> _scan(
  String root, {
  required Set<String> skip,
  String scanRoot = kScanRoot,
}) async {
  final Directory dir = Directory('$root/$scanRoot');
  if (!dir.existsSync()) return const <Offender>[];

  final List<File> files =
      dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  final List<Offender> out = <Offender>[];
  for (final File f in files) {
    final String absolute = f.absolute.path;
    final String relative = _relativize(absolute, root);
    if (skip.contains(relative)) continue;
    out.addAll(_scanFile(absolute, relative));
  }
  return out;
}

/// Parses one file and applies the suppression rules the `custom_lint`
/// runtime used to apply.
List<Offender> _scanFile(String absolutePath, String relativePath) {
  // Cheap path exemptions first — no point parsing `*.g.dart`.
  if (isRawUiStringFileAllowListed(absolutePath)) return const <Offender>[];

  final String content = File(absolutePath).readAsStringSync();
  if (_ignoreForFile.hasMatch(content)) return const <Offender>[];

  final result = parseString(
    content: content,
    path: absolutePath,
    throwIfDiagnostics: false,
  );

  // Pass the ABSOLUTE path: isRawUiStringFileAllowListed matches on
  // `/test/`, `/dev/`, `/lib/api/` substrings and needs the leading slashes.
  final List<SimpleStringLiteral> found = findRawUiStringLiterals(
    result.unit,
    path: absolutePath,
  );
  if (found.isEmpty) return const <Offender>[];

  final List<String> lines = content.split('\n');
  final List<Offender> out = <Offender>[];
  for (final SimpleStringLiteral literal in found) {
    final int lineNumber = result.lineInfo
        .getLocation(literal.offset)
        .lineNumber;
    if (_isSuppressed(lines, lineNumber)) continue;
    final String text = lineNumber - 1 < lines.length
        ? lines[lineNumber - 1]
        : '';
    out.add(Offender(relativePath: relativePath, line: lineNumber, text: text));
  }
  return out;
}

/// True when line [lineNumber] (1-based) carries an escape comment on itself,
/// or anywhere in the unbroken run of `//` comment lines directly above it.
///
/// The upward walk stops at the first line that is not a bare `//` comment —
/// identical to `forbid_cyrillic_finder.sh`'s `comment_run_annotated`
/// semantics, so an annotation separated from the literal by real code does
/// NOT unblock it.
bool _isSuppressed(List<String> lines, int lineNumber) {
  final int index = lineNumber - 1;
  if (index < 0 || index >= lines.length) return false;

  if (_carriesEscape(lines[index])) return true;

  for (int i = index - 1; i >= 0; i--) {
    final String trimmed = lines[i].trimLeft();
    if (!trimmed.startsWith('//')) break; // real code breaks the run
    if (_carriesEscape(lines[i])) return true;
  }
  return false;
}

bool _carriesEscape(String line) =>
    _ignoreLine.hasMatch(line) || _escapeComment.hasMatch(line);

String _relativize(String absolute, String root) {
  final String prefix = root.endsWith('/') ? root : '$root/';
  return absolute.startsWith(prefix)
      ? absolute.substring(prefix.length)
      : absolute;
}

// ---------------------------------------------------------------------------
// Allow-list ratchet
// ---------------------------------------------------------------------------

/// Loads `scripts/.raw_ui_strings_allow`. One repo-relative path per line;
/// `#` comments and blank lines ignored. Missing file -> empty allow-list.
Set<String> _loadAllowList(String root) {
  final File f = File('$root/$kAllowListPath');
  if (!f.existsSync()) return <String>{};
  final Set<String> out = <String>{};
  for (final String raw in f.readAsLinesSync()) {
    final int hash = raw.indexOf('#');
    final String line = (hash >= 0 ? raw.substring(0, hash) : raw).trim();
    if (line.isEmpty) continue;
    out.add(line);
  }
  return out;
}

/// Rescans with an EMPTY allow-list and rewrites the baseline from the
/// result. Used once, to establish the ratchet.
Future<int> _writeAllowList(String root) async {
  final List<Offender> offenders = await _scan(root, skip: <String>{});
  final List<String> paths =
      offenders.map((Offender o) => o.relativePath).toSet().toList()..sort();

  final String today = DateTime.now().toIso8601String().substring(0, 10);
  final StringBuffer b = StringBuffer()
    ..writeln('# Baseline for scripts/forbid_raw_ui_strings.sh — SHRINK-ONLY')
    ..writeln('# RATCHET. Established $today, the day the gate first actually')
    ..writeln('# ran. Every path below carries at least one raw user-visible')
    ..writeln('# string literal in a widget argument that should be flowing')
    ..writeln('# through AppLocalizations.of(context).<key>.')
    ..writeln('#')
    ..writeln('# These are NOT approved. They are the honest measurement of a')
    ..writeln('# debt that accumulated while `dart run custom_lint` passed')
    ..writeln('# unconditionally: the rule was authored in Phase 1.3, promoted')
    ..writeln(
      '# to `error` in Phase 1.5, and never executed once. Ukrainian is',
    )
    ..writeln('# the product language, so every literal here renders UA no')
    ..writeln('# matter the active locale and silently breaks the EN build.')
    ..writeln('#')
    ..writeln('# THE LIST ONLY SHRINKS. Adding a path is never the fix for a')
    ..writeln('# new violation — localize it, or annotate the one line with')
    ..writeln('#     // raw-ui-string-ok: <why this literal is not UI copy>')
    ..writeln('# When a listed file is next meaningfully touched, move its')
    ..writeln('# strings into lib/l10n/app_uk.arb (+ app_en.arb), run')
    ..writeln('# `flutter gen-l10n`, and delete its line here.')
    ..writeln('#')
    ..writeln('# Regenerate (baseline reset only, never to make CI green):')
    ..writeln('#   dart tool/lints/no_raw_ui_strings.dart --write-allow')
    ..writeln('');
  for (final String p in paths) {
    b.writeln(p);
  }

  File('$root/$kAllowListPath').writeAsStringSync(b.toString());
  stdout.writeln('Wrote $kAllowListPath with ${paths.length} path(s).');
  return 0;
}

// ---------------------------------------------------------------------------
// Self-test
// ---------------------------------------------------------------------------

/// Synthetic probe matrix.
///
/// The EXACT-COUNT assertion is the point. A checker that quietly stopped
/// working returns zero offenders — which is precisely how `dart run
/// custom_lint` passed a planted violation for two phases. Asserting "at
/// least one offender" would have passed then too. Every probe below is
/// additionally asserted BY LINE, so a rule that starts flagging the wrong
/// construct is caught as well as one that flags nothing.
Future<int> _runSelfTest() async {
  final Directory tmp = Directory.systemTemp.createTempSync('nrus_probe');
  try {
    // Probe A — the offender / suppression matrix.
    const String probeA = 'lib/features/probe/widgets_probe.dart';
    const List<String> linesA = <String>[
      "// Probe A — offenders and suppressions.",
      "import 'package:flutter/material.dart';",
      "",
      "Widget plainText() => Text('Привіт');",
      "Widget appBarText() => AppBar(title: Text('Головна'));",
      "Widget hint() => InputDecoration(hintText: 'Пошук');",
      "",
      "// ignore: no_raw_ui_strings",
      "Widget ignoredAbove() => Text('x');",
      "Widget okSameLine() => Text('y'); // raw-ui-string-ok: brand mark",
      "",
      "// raw-ui-string-ok: orphaned from its literal by the code line below",
      "final int spacer = 0;",
      "Widget orphaned() => Text('z');",
      "",
      "Widget keyArg() => const Key('slot-card');",
      "Widget interpolated(String n) => Text('\$n');",
      "Widget localized(dynamic l10n) => Text(l10n.bookCta);",
      "void logging() => debugPrint('trace');",
      "void nav(dynamic context) => context.go('/bookings');",
    ];
    // 4  raw Text literal
    // 5  AppBar(title: Text(...)) — must fire exactly ONCE (offset de-dup)
    // 6  InputDecoration.hintText
    // 14 escape comment separated from the literal by real code
    const List<int> expectedA = <int>[4, 5, 6, 14];

    // Probe B — allow-listed BY PATH inside the checker (`/lib/api/`).
    const String probeB = 'lib/api/generated_probe.dart';
    const List<String> linesB = <String>[
      "// Probe B — generated client, exempt by path.",
      "import 'package:flutter/material.dart';",
      "",
      "Widget generated() => Text('Привіт');",
    ];

    // Probe C — whole-file suppression.
    const String probeC = 'lib/features/probe/file_ignored_probe.dart';
    const List<String> linesC = <String>[
      "// Probe C — whole-file opt-out.",
      "// ignore_for_file: no_raw_ui_strings",
      "import 'package:flutter/material.dart';",
      "",
      "Widget suppressed() => Text('Привіт');",
    ];

    // Probe D — the ratchet target: flagged with an empty allow-list,
    // silent once its repo-relative path is grandfathered.
    const String probeD = 'lib/features/probe/ratchet_probe.dart';
    const List<String> linesD = <String>[
      "// Probe D — allow-list ratchet target.",
      "import 'package:flutter/material.dart';",
      "",
      "Widget ratcheted() => Text('Привіт');",
    ];

    const Map<String, List<String>> probes = <String, List<String>>{
      probeA: linesA,
      probeB: linesB,
      probeC: linesC,
      probeD: linesD,
    };
    for (final MapEntry<String, List<String>> e in probes.entries) {
      final File f = File('${tmp.path}/${e.key}');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('${e.value.join('\n')}\n');
    }

    const int expectedTotal = 5; // 4 from probe A + 1 from probe D

    // (1) Empty allow-list: exact count, then exact identity per line.
    final List<Offender> out = await _scan(tmp.path, skip: <String>{});
    if (out.length != expectedTotal) {
      _fail(
        'expected exactly $expectedTotal offenders across ${probes.length} '
        'probe files, got ${out.length}',
        out,
      );
      return 1;
    }
    for (final int ln in expectedA) {
      if (!out.any((Offender o) => o.relativePath == probeA && o.line == ln)) {
        _fail('probe A line $ln was not flagged', out);
        return 1;
      }
    }
    if (!out.any((Offender o) => o.relativePath == probeD && o.line == 4)) {
      _fail('probe D line 4 was not flagged', out);
      return 1;
    }
    for (final String clean in <String>[probeB, probeC]) {
      if (out.any((Offender o) => o.relativePath == clean)) {
        _fail('$clean must be clean but was flagged', out);
        return 1;
      }
    }

    // (2) The ratchet is per-path, not global: grandfathering probe D must
    //     remove exactly its one offender and leave probe A's four intact.
    final List<Offender> ratcheted = await _scan(
      tmp.path,
      skip: <String>{probeD},
    );
    if (ratcheted.length != expectedA.length) {
      _fail(
        'allow-listing $probeD should leave exactly ${expectedA.length} '
        'offenders, got ${ratcheted.length}',
        ratcheted,
      );
      return 1;
    }
    if (ratcheted.any((Offender o) => o.relativePath == probeD)) {
      _fail('an allow-listed path was still flagged', ratcheted);
      return 1;
    }

    stdout.writeln(
      'SELF-TEST OK: no_raw_ui_strings '
      '(${probes.length} probes, $expectedTotal expected offenders)',
    );
    stdout.writeln(
      '  flagged: raw Text literal; AppBar(title: Text(...)) exactly once; '
      'InputDecoration.hintText;',
    );
    stdout.writeln(
      '           an escape comment separated from its literal by real code.',
    );
    stdout.writeln(
      '  clean:   // ignore: above; // raw-ui-string-ok: same-line; '
      'Key(); interpolation;',
    );
    stdout.writeln(
      '           l10n getter; debugPrint; context.go; /lib/api/ path; '
      '// ignore_for_file:.',
    );
    stdout.writeln(
      '  ratchet: allow-listing one path silences only that path.',
    );
    return 0;
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void _fail(String message, List<Offender> out) {
  stdout.writeln('SELF-TEST FAIL: $message');
  for (final Offender o in out) {
    stdout.writeln('  ${o.format()}');
  }
}
