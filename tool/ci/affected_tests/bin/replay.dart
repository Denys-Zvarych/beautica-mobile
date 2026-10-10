// Replays the selector over historic commits: for commit C it diffs C^..C
// (first parent), extracts both trees with `git archive` (read-only, no
// checkout) and prints a mode / selected-count table with the FULL reason per
// commit (398 R2: full_glob <glob> | >60% (share) | fail-safe <rule> <path>).
//
//   dart run tool/ci/affected_tests/bin/replay.dart --commit <sha> [--commit ...]
//   dart run tool/ci/affected_tests/bin/replay.dart --last 30 --ref dev
//        [--repo <root>] [--verbose]
import 'dart:io';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;

String _git(String repo, List<String> args) {
  final r = Process.runSync('git', ['-C', repo, ...args]);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
  return r.stdout as String;
}

void main(List<String> args) {
  final commits = <String>[];
  var repo = Directory.current.path, ref = 'HEAD', last = 0, verbose = false;
  String? rulesPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--commit':
        commits.add(args[++i]);
      case '--last':
        last = int.parse(args[++i]);
      case '--ref':
        ref = args[++i];
      case '--repo':
        repo = args[++i];
      case '--rules':
        rulesPath = args[++i];
      case '--verbose':
        verbose = true;
      default:
        stderr.writeln('unknown ${args[i]}');
        exit(64);
    }
  }
  if (last > 0) {
    commits.addAll(
      _git(repo, [
        'rev-list',
        '--first-parent',
        '--merges',
        '-n',
        '$last',
        ref,
      ]).split('\n').where((l) => l.isNotEmpty),
    );
  }
  final rules = Rules.fromFile(
    rulesPath ??
        p.join(
          p.dirname(p.dirname(Platform.script.toFilePath())),
          'rules.yaml',
        ),
  );

  stdout.writeln(replayHeader);
  final pcts = <double>[];
  for (final c in commits) {
    final tmp = Directory.systemTemp.createTempSync('replay_');
    try {
      final head = Directory(p.join(tmp.path, 'head'))..createSync();
      final base = Directory(p.join(tmp.path, 'base'))..createSync();
      extractTree(repo, c, head.path, rules);
      extractTree(repo, '$c^', base.path, rules);
      final changes = parseChanges(
        _git(repo, ['diff', '--name-status', '-M', '$c^', c]),
      );
      final g = ImportGraph.build(head.path, rules);
      final total = universe(g, rules).unit.length;
      final s = select(
        root: head.path,
        changes: changes,
        rules: rules,
        baseRoot: base.path,
        graph: g,
      );
      final subject = _git(repo, ['log', '-1', '--format=%s', c]).trim();
      if (s.mode != Mode.full && total > 0) pcts.add(s.unit.length / total);
      stdout.writeln(
        replayRow(
          commit: c,
          files: changes.length,
          s: s,
          totalUnit: total,
          rules: rules,
          subject: subject,
        ),
      );
      if (verbose) {
        stdout.writeln(
          '<!-- unit: ${s.unit.join(' ')} golden: ${s.golden.join(' ')} flows: ${s.integration.join(' ')} -->',
        );
        for (final r in s.reasons) {
          stdout.writeln('<!--   ${r.path}: ${r.rule} -->');
        }
      }
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }
  if (pcts.isNotEmpty) {
    pcts.sort();
    stdout.writeln(
      '\nnon-full: ${pcts.length}/${commits.length}; median unit share '
      '${(pcts[pcts.length ~/ 2] * 100).toStringAsFixed(1)}%',
    );
  }
}
