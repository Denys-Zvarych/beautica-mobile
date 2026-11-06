// Phase 401: selection.json -> integration_test/ci_selected_tests.dart.
//
//   dart tool/ci/affected_tests/bin/gen_integration_entry.dart
//        --selection <selection.json> [--repo <root>] [--out <file>]
//        [--threshold 0.7] [--force-selected]
//
// Prints `entry=<parts|selected|none>` on the first stdout line (the workflow
// parses it) and, for `selected` only, `count=<N flows>` on the second and
// `tests=<testWidgets of those flows>` on the third (the workflow's per-attempt
// bound is derived from it, mobile-perf cycle 2 P1):
//   selected  <out> was written; run it instead of the two part files.
//   parts     run all_tests_part1.dart + all_tests_part2.dart unchanged.
//   none      the selection holds no flow; nothing was written.
//
// Audit cycle 1 (401): a selection of more than [maxSelectedFlows] flows or
// [maxSelectedTests] testWidgets (one shard's size: above it the 8 parallel
// shards finish sooner than one serial run), or one naming a flow file that
// does not exist, also lands on `parts` (P4/S6).
// The entry file is written through a same-directory temp file + rename after
// removing whatever (file, directory, dangling symlink) sits at the target
// without following links (S1); any write failure prints `entry=parts` (Q2).
//
// D3: the parts win when the selection covers >= threshold (default 0.7) of
// the flows of EITHER part file. A hub change selects every flow, so it lands
// here too (100 %).
// Fail-safe (phase 400 D7): anything unexpected (unreadable or invalid JSON,
// a non-selective mode, a path that is not a flat integration_test/<x>_test.dart,
// unreadable part files) => `parts`, exit 0. It never falls through to a
// smaller run than the selector asked for.
//
// Shard mode (2026-11-06): `--shard K/N` writes shard K of N of the FULL
// suite to integration_test/ci_shard_tests.dart (or --out). The flows are the
// imports of all_tests.dart (the single source of flows), partitioned by
// [partitionShards]: deterministic, balanced by `testWidgets(` count. Prints
// `entry=shard`, `count=<flows>`, `tests=<testWidgets>`; anything wrong
// (bad K/N, unreadable all_tests.dart, a missing flow, an empty shard) prints
// `entry=error` and exits 1 -- a shard never silently runs less.
//
// Dependency-free on purpose (dart:io + dart:convert only): CI runs it with
// the SDK Dart of the emulator job, straight from the BASE commit, without a
// `pub get`.
import 'dart:convert';
import 'dart:io';

const defaultThreshold = 0.7;

/// P4: more selected flows than this in one process => the shards instead.
/// One shard's size (2026-11-06: 149 flows / 588 testWidgets in 8 shards of
/// 18-19 flows / 73-74 testWidgets), mobile-perf cycle 2 P1.
const maxSelectedFlows = 19;

/// P4: more selected testWidgets than this => the shards instead (one shard).
const maxSelectedTests = 74;

const partFiles = [
  'integration_test/all_tests_part1.dart',
  'integration_test/all_tests_part2.dart',
];

/// The full suite runs as this many parallel `integration-shard` matrix legs.
const integrationShards = 8;

/// The single source of flows the shards are cut from.
const allTestsFile = 'integration_test/all_tests.dart';

final _testWidgets = RegExp(r'\btestWidgets\s*\(');

final _flowPath = RegExp(r'^integration_test/([A-Za-z0-9_]+_test)\.dart$');
// Q3: single- OR double-quoted imports (the back-reference pairs the quotes).
final _partImport = RegExp(
  "^import ([\'\"])([A-Za-z0-9_]+_test\\.dart)\\1",
  multiLine: true,
);

/// Identifiers an import alias must never be (S6): Dart reserved words and
/// built-in identifiers (illegal as a prefix), plus names the generated
/// `main` and the test framework use, which an alias would shadow.
const _badAliases = {
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
  'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
  'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
  'factory', 'false', 'final', 'finally', 'for', 'function', 'get', 'hide',
  'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
  'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
  'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
  'throw', 'true', 'try', 'typedef', 'var', 'void', 'while', 'with', 'yield',
  // Shadowed by / used in the generated file.
  'group', 'main', 'test', 'expect', 'setUp', 'tearDown', 'setUpAll',
  'tearDownAll', 'print', 'IntegrationTestWidgetsFlutterBinding',
};

/// `integration_test/auth_login_flow_test.dart` -> `auth_login_flow`.
String groupName(String flowPath) => _flowPath
    .firstMatch(flowPath)!
    .group(1)!
    .replaceFirst(RegExp(r'_test$'), '');

/// Unique Dart import alias per flow: the group name without `_flow` (the
/// convention of the part files), `_2`, `_3`... on a clash.
Map<String, String> aliasesFor(List<String> flows) {
  final used = <String>{};
  final out = <String, String>{};
  for (final f in flows) {
    var base = groupName(f).replaceFirst(RegExp(r'_flow$'), '');
    if (base.isEmpty || RegExp(r'^[0-9]').hasMatch(base)) base = 'f_$base';
    var a = base;
    for (var n = 2; used.contains(a) || _badAliases.contains(a); n++) {
      a = '${base}_$n';
    }
    used.add(a);
    out[f] = a;
  }
  return out;
}

/// The aggregator text for [flows] (sorted, de-duplicated). Same shape as
/// all_tests_part*.dart: one `import` and one `group(...)` per flow.
String renderEntry(Iterable<String> flows, {List<String>? header}) {
  final sorted = ({...flows}.toList()..sort());
  final alias = aliasesFor(sorted);
  final b = StringBuffer()
    ..writeln(
      '// GENERATED by tool/ci/affected_tests/bin/gen_integration_entry.dart',
    )
    ..writeln('// (phase 401). Gitignored; never edit or commit.');
  for (final l
      in header ??
          const [
            'The selected integration flows of this PR, in one process, like',
            'all_tests_part1.dart / all_tests_part2.dart.',
          ]) {
    b.writeln('// $l');
  }
  b
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln("import 'package:integration_test/integration_test.dart';")
    ..writeln();
  for (final f in sorted) {
    b.writeln(
      "import '${f.substring('integration_test/'.length)}' as ${alias[f]};",
    );
  }
  b
    ..writeln()
    ..writeln('void main() {')
    ..writeln('  IntegrationTestWidgetsFlutterBinding.ensureInitialized();')
    ..writeln();
  for (final f in sorted) {
    b.writeln("  group('${groupName(f)}', ${alias[f]}.main);");
  }
  // Audit cycle 4: no in-band completion marker. run_it_attempt.sh judges the
  // host-side JSON test protocol (group testCount vs testDone), which a test's
  // print() cannot forge, so the entry carries no build-time secret.
  b.writeln('}');
  return b.toString();
}

/// Flow file names (`x_test.dart`) a part file imports.
Set<String> partFlows(String partSource) => {
  for (final m in _partImport.allMatches(partSource)) m.group(2)!,
};

/// `testWidgets(` calls in a flow source, `//` comments stripped: the shard
/// weight (an app boot per testWidgets; plain `test(` is cheap).
int testWidgetsCount(String src) =>
    _testWidgets.allMatches(src.replaceAll(RegExp(r'//[^\n]*'), '')).length;

/// Deterministic greedy (LPT) partition of [weights] (flow -> testWidgets)
/// into [n] shards: heaviest flow first (ties by name), each into the shard
/// with the least load (ties: fewer flows, then lowest index). Every flow lands
/// in exactly one shard.
List<List<String>> partitionShards(Map<String, int> weights, int n) {
  final flows = weights.keys.toList()
    ..sort((a, b) {
      final c = weights[b]!.compareTo(weights[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  final bins = [for (var i = 0; i < n; i++) <String>[]];
  final load = List<int>.filled(n, 0);
  for (final f in flows) {
    var best = 0;
    for (var i = 1; i < n; i++) {
      if (load[i] < load[best] ||
          (load[i] == load[best] && bins[i].length < bins[best].length)) {
        best = i;
      }
    }
    bins[best].add(f);
    load[best] += weights[f]!;
  }
  for (final b in bins) {
    b.sort();
  }
  return bins;
}

/// Shard mode: writes shard [k] of [n] of all_tests.dart's flows to [out].
/// Returns the exit code (0 written, 1 refused -- fail closed).
int runShard(String spec, String repo, String? out) {
  out ??= '$repo/integration_test/ci_shard_tests.dart';
  int refuse(String why) {
    stderr.writeln('gen_integration_entry: shard refused ($why)');
    stdout.writeln('entry=error');
    return 1;
  }

  // A stale entry must never survive a refusal.
  try {
    _clear(out);
  } on FileSystemException catch (e) {
    return refuse('cannot clear the entry (${e.message})');
  }
  final m = RegExp(r'^([0-9]{1,2})/([0-9]{1,2})$').firstMatch(spec);
  final k = m == null ? 0 : int.parse(m.group(1)!);
  final n = m == null ? 0 : int.parse(m.group(2)!);
  if (n < 1 || k < 1 || k > n) return refuse('bad --shard "$spec", want K/N');
  final String src;
  try {
    src = File('$repo/$allTestsFile').readAsStringSync();
  } on FileSystemException {
    return refuse('$allTestsFile unreadable');
  }
  final names = partFlows(src).toList()..sort();
  if (names.isEmpty) return refuse('$allTestsFile imports no flow');
  final weights = <String, int>{};
  for (final name in names) {
    final path = 'integration_test/$name';
    if (!_flowPath.hasMatch(path) ||
        FileSystemEntity.typeSync('$repo/$path', followLinks: false) !=
            FileSystemEntityType.file) {
      return refuse('$path is not a regular flow file');
    }
    weights[path] = testWidgetsCount(File('$repo/$path').readAsStringSync());
  }
  final bins = partitionShards(weights, n);
  final mine = bins[k - 1];
  if (mine.isEmpty) return refuse('shard $k/$n would be empty');
  int tests(List<String> b) => b.fold(0, (s, f) => s + weights[f]!);
  try {
    _writeAtomically(
      out,
      renderEntry(
        mine,
        header: [
          'Shard $k of $n of the FULL integration suite (all_tests.dart),',
          'balanced by testWidgets count; ${mine.length} flows, ${tests(mine)} '
              'testWidgets.',
        ],
      ),
    );
  } on FileSystemException catch (e) {
    return refuse('cannot write the entry (${e.message})');
  }
  stderr.writeln(
    'gen_integration_entry: shard $k/$n; testWidgets per shard: '
    '${bins.map(tests).join(' ')}',
  );
  stdout
    ..writeln('entry=shard')
    ..writeln('count=${mine.length}')
    ..writeln('tests=${tests(mine)}');
  return 0;
}

/// `true` when [flows] covers >= [threshold] of any part's flows.
bool coversPart(Set<String> flows, List<Set<String>> parts, double threshold) {
  final names = {
    for (final f in flows) f.substring('integration_test/'.length),
  };
  for (final part in parts) {
    if (part.isEmpty) continue;
    if (names.where(part.contains).length >= threshold * part.length) {
      return true;
    }
  }
  return false;
}

/// Pure decision; returns (entry, source-to-write-or-null, why, count, tests).
///
/// [exists] answers "is this repo-relative flow path a file on disk"; when
/// given, a selected path that is not => `parts` (S6). [testsOf] answers "how
/// many testWidgets does this flow declare" (null => 0 each); `tests` is their
/// sum and is capped at [maxSelectedTests]. [forceSelected] (test hook, never
/// used by the workflow) skips D3, both caps and [exists].
({String entry, String? source, String why, int count, int tests}) decide({
  required String selectionJson,
  required List<String> partSources,
  double threshold = defaultThreshold,
  bool forceSelected = false,
  bool Function(String flowPath)? exists,
  int Function(String flowPath)? testsOf,
}) {
  ({String entry, String? source, String why, int count, int tests}) parts(
    String why,
  ) => (entry: 'parts', source: null, why: why, count: 0, tests: 0);
  final Object? j;
  try {
    j = jsonDecode(selectionJson);
  } on FormatException {
    return parts('selection.json is not valid JSON');
  }
  if (j is! Map || j['mode'] != 'selective' || j['integration'] is! List) {
    return parts(
      'selection is not a selective verdict with an integration list',
    );
  }
  final list = j['integration'] as List;
  if (list.any((e) => e is! String || !_flowPath.hasMatch(e))) {
    return parts(
      'a selected path is not a flat integration_test/<x>_test.dart',
    );
  }
  final flows = {...list.cast<String>()};
  if (flows.isEmpty) {
    return (
      entry: 'none',
      source: null,
      why: 'no flow selected',
      count: 0,
      tests: 0,
    );
  }
  if (!forceSelected) {
    if (exists != null && !flows.every(exists)) {
      return parts('a selected flow file does not exist in the tree');
    }
    if (flows.length > maxSelectedFlows) {
      return parts(
        '${flows.length} flows exceed the $maxSelectedFlows-flow cap (P4)',
      );
    }
  }
  final tests = testsOf == null ? 0 : flows.fold(0, (s, f) => s + testsOf(f));
  if (!forceSelected) {
    if (tests > maxSelectedTests) {
      return parts(
        '$tests testWidgets exceed the $maxSelectedTests-test cap (P4)',
      );
    }
    final sets = [for (final s in partSources) partFlows(s)];
    if (sets.length != partFiles.length || sets.any((s) => s.isEmpty)) {
      return parts('part files unreadable or empty');
    }
    if (coversPart(flows, sets, threshold)) {
      return parts(
        'selection covers >= ${(threshold * 100).round()}% of a part (D3)',
      );
    }
  }
  return (
    entry: 'selected',
    source: renderEntry(flows),
    why: '${flows.length} flow(s), $tests testWidgets selected',
    count: flows.length,
    tests: tests,
  );
}

int run(List<String> args) {
  String? selection, out, shard;
  var repo = Directory.current.path,
      force = false,
      threshold = defaultThreshold;
  try {
    for (var i = 0; i < args.length; i++) {
      String next() => i + 1 < args.length
          ? args[++i]
          : throw FormatException('${args[i]} needs a value');
      switch (args[i]) {
        case '--selection':
          selection = next();
        case '--repo':
          repo = next();
        case '--out':
          out = next();
        case '--threshold':
          threshold = double.parse(next());
        case '--force-selected':
          force = true;
        case '--shard':
          shard = next();
        default:
          throw FormatException('unknown argument ${args[i]}');
      }
    }
    if (shard != null) return runShard(shard, repo, out);
    if (selection == null) {
      throw const FormatException('--selection is required');
    }
  } on FormatException catch (e) {
    stderr.writeln('gen_integration_entry: ${e.message}');
    stdout.writeln('entry=parts');
    return 0; // fail-safe: bad usage never shrinks the run
  }
  out ??= '$repo/integration_test/ci_selected_tests.dart';
  String read(String p) {
    try {
      return File(p).readAsStringSync();
    } on FileSystemException {
      return '';
    }
  }

  final d = decide(
    selectionJson: read(selection),
    partSources: [for (final p in partFiles) read('$repo/$p')],
    threshold: threshold,
    forceSelected: force,
    exists: (f) =>
        FileSystemEntity.typeSync('$repo/$f', followLinks: false) ==
        FileSystemEntityType.file,
    testsOf: (f) {
      try {
        return testWidgetsCount(File('$repo/$f').readAsStringSync());
      } on FileSystemException {
        return 0;
      }
    },
  );
  try {
    _clear(out);
    final src = d.source;
    if (src != null) _writeAtomically(out, src);
  } on FileSystemException catch (e) {
    // Q2: a failed write must never reach the workflow as `selected`.
    stderr.writeln(
      'gen_integration_entry: cannot write the entry (${e.message})',
    );
    try {
      _clear(out);
    } on FileSystemException {
      // best effort; the workflow rm -f's it again for `parts`
    }
    stdout.writeln('entry=parts');
    return 0;
  }
  stderr.writeln('gen_integration_entry: ${d.entry} (${d.why})');
  stdout.writeln('entry=${d.entry}');
  if (d.entry == 'selected') {
    stdout
      ..writeln('count=${d.count}')
      ..writeln('tests=${d.tests}');
  }
  return 0;
}

/// Removes whatever sits at [path] WITHOUT following links (S1): a regular
/// file, a directory tree, or a (possibly dangling) symlink.
void _clear(String path) {
  switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    case FileSystemEntityType.link:
      Link(path).deleteSync();
    case FileSystemEntityType.file:
      File(path).deleteSync();
    case FileSystemEntityType.directory:
      Directory(path).deleteSync(recursive: true);
    default:
      break;
  }
}

/// Writes [src] to [out] through a temp file in the same directory + rename
/// (rename replaces a link at the destination instead of writing through it).
/// The parent must be a real directory, not a link.
void _writeAtomically(String out, String src) {
  final dir = File(out).parent.path;
  if (FileSystemEntity.typeSync(dir, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FileSystemException('parent is not a real directory', dir);
  }
  final tmp = '$out.tmp$pid';
  _clear(tmp);
  File(tmp).writeAsStringSync(src, flush: true);
  File(tmp).renameSync(out);
  if (FileSystemEntity.typeSync(out, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException('entry is not a regular file after write', out);
  }
}

void main(List<String> args) => exitCode = run(args);
