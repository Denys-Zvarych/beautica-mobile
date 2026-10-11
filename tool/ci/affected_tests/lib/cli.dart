import 'dart:io';

import 'assets.dart';
import 'package:path/path.dart' as p;

import 'classifier.dart';
import 'graph.dart';
import 'rules.dart';
import 'selection.dart';
import 'shard.dart';

const usage = '''
affected_tests --changes <file> | --diff <A..B>  [--repo <root>] [--out <json>]
               [--base-root <dir> | --base-ref <git-ref>] [--rules <yaml>]
               [--shard i/N] [--all]

  --changes   file of "STATUS<TAB>path[<TAB>newpath]" lines (git diff --name-status -M)
  --diff      A..B  : compute the changes with git (merge-base NOT applied; pass it)
  --base-ref  extract this ref to a temp dir to resolve deleted/renamed Dart files
  --all       emit every test (full-run sharding input); ignores --changes
  --shard     keep only shard i of N of each list (1-based)
Writes <out> (default build/ci/selection.json) plus unit.txt, golden.txt,
tz_sweep.txt, integration.txt beside it. Exit 0 always on a verdict.''';

/// Runs the selector CLI; returns the process exit code.
int run(List<String> args) {
  String? changes, diff, repo, out, baseRoot, baseRef, rulesPath, shardSpec;
  var all = false;
  for (var i = 0; i < args.length; i++) {
    String next() => i + 1 < args.length
        ? args[++i]
        : throw FormatException('${args[i]} needs a value');
    switch (args[i]) {
      case '--changes':
        changes = next();
      case '--diff':
        diff = next();
      case '--repo':
        repo = next();
      case '--out':
        out = next();
      case '--base-root':
        baseRoot = next();
      case '--base-ref':
        baseRef = next();
      case '--rules':
        rulesPath = next();
      case '--shard':
        shardSpec = next();
      case '--all':
        all = true;
      case '-h' || '--help':
        stdout.writeln(usage);
        return 0;
      default:
        stderr.writeln('unknown argument ${args[i]}\n$usage');
        return 64;
    }
  }
  final root = p.normalize(p.absolute(repo ?? Directory.current.path));
  final rules = Rules.fromFile(
    rulesPath ??
        p.join(
          p.dirname(p.dirname(Platform.script.toFilePath())),
          'rules.yaml',
        ),
  );
  out ??= p.join(root, 'build', 'ci', 'selection.json');

  Selection sel;
  if (all) {
    final u = universe(ImportGraph.build(root, rules), rules);
    sel = Selection(
      mode: Mode.full,
      unit: u.unit,
      golden: u.golden,
      tzSweep: [
        for (final t in [...u.unit, ...u.golden])
          if (rules.inTzSweep(t)) t,
      ],
      integration: u.flows,
      reasons: const [Reason('*', '--all')],
    );
  } else {
    final String text;
    if (changes != null) {
      text = readTextSync(File(changes));
    } else if (diff != null) {
      final r = Process.runSync('git', [
        '-C',
        root,
        'diff',
        '--name-status',
        '-M',
        diff,
      ]);
      if (r.exitCode != 0) {
        stderr.writeln('git diff failed: ${r.stderr}');
        return 2;
      }
      text = r.stdout as String;
    } else {
      stderr.writeln('need --changes, --diff or --all\n$usage');
      return 64;
    }
    Directory? tmp;
    if (baseRoot == null && baseRef != null) {
      tmp = Directory.systemTemp.createTempSync('affected_base_');
      baseRoot = extractTree(root, baseRef, tmp.path, rules);
    }
    try {
      sel = select(
        root: root,
        changes: parseChanges(text),
        rules: rules,
        baseRoot: baseRoot,
      );
    } finally {
      tmp?.deleteSync(recursive: true);
    }
  }

  if (shardSpec != null) {
    final s = parseShard(shardSpec);
    sel = sel.copyWith(
      unit: shard(sel.unit, s.index, s.count),
      golden: shard(sel.golden, s.index, s.count),
      tzSweep: shard(sel.tzSweep, s.index, s.count),
      integration: shard(sel.integration, s.index, s.count),
    );
  }

  final dir = Directory(p.dirname(out))..createSync(recursive: true);
  File(out).writeAsStringSync('${sel.toJsonString()}\n');
  for (final e in {
    'unit': sel.unit,
    'golden': sel.golden,
    'tz_sweep': sel.tzSweep,
    'integration': sel.integration,
  }.entries) {
    File(
      p.join(dir.path, '${e.key}.txt'),
    ).writeAsStringSync(e.value.map((f) => '$f\n').join());
  }
  stdout.writeln(
    'mode=${sel.mode.name} unit=${sel.unit.length} golden=${sel.golden.length} '
    'tz_sweep=${sel.tzSweep.length} integration=${sel.integration.length} -> $out',
  );
  return 0;
}

/// `git archive <ref>` of the graph roots into [dest]; returns [dest].
String extractTree(String repoRoot, String ref, String dest, Rules rules) {
  final paths = [...rules.graphRoots, 'api/pubspec.yaml'];
  final archive = Process.runSync('git', [
    '-C',
    repoRoot,
    'archive',
    '--format=tar',
    ref,
    ...paths,
  ], stdoutEncoding: null);
  if (archive.exitCode != 0) {
    throw StateError('git archive $ref failed: ${archive.stderr}');
  }
  final tmpTar = File(p.join(dest, '.tree.tar'))
    ..writeAsBytesSync(archive.stdout as List<int>);
  final x = Process.runSync('tar', ['-x', '-f', tmpTar.path, '-C', dest]);
  tmpTar.deleteSync();
  if (x.exitCode != 0) throw StateError('tar failed: ${x.stderr}');
  return dest;
}
