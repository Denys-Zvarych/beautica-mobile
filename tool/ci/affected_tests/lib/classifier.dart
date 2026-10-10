import 'package:path/path.dart' as p;

import 'graph.dart';
import 'rules.dart';

enum PathKind {
  none,
  full,
  seed,

  /// `path_includes`: selects a fixed test set, never a seed.
  mapped,

  /// A committed golden PNG: resolved to its golden test file(s) once the
  /// tree is readable; unresolved -> FULL.
  goldenAsset,

  /// An `.arb` file: resolved per changed key; unresolvable -> FULL.
  arb,
}

/// How one changed path is treated, plus the rule that decided it (audit trail).
final class Classification {
  const Classification(this.path, this.kind, this.rule, {this.seedPath});
  final String path;
  final PathKind kind;
  final String rule;

  /// For [PathKind.seed]: the graph node to seed from (a generated file maps to
  /// its owner).
  final String? seedPath;
}

/// One line of `git diff --name-status -M`: `STATUS\tpath[\tnewpath]`.
final class Change {
  const Change(this.status, this.path, [this.newPath]);

  factory Change.parse(String line) {
    final f = line.split('\t');
    if (f.length < 2) throw FormatException('bad change line: "$line"');
    return Change(f[0], f[1], f.length > 2 ? f[2] : null);
  }

  final String status;
  final String path;
  final String? newPath;

  /// Paths that exist AFTER the change.
  List<String> get livePaths => switch (status[0]) {
    'D' => const [],
    'R' || 'C' => [newPath ?? path],
    _ => [path],
  };

  /// Paths that existed BEFORE and are gone/moved: seeds against the BASE tree.
  List<String> get gonePaths => switch (status[0]) {
    'D' || 'R' => [path],
    _ => const [],
  };

  bool get isStructural => 'ADRC'.contains(status[0]);
}

List<Change> parseChanges(String text) => [
  for (final l in text.split('\n'))
    if (l.trim().isNotEmpty) Change.parse(l.trimRight()),
];

/// Classifies one path. Order: none -> full -> graph seed -> FULL (fail-safe).
Classification classify(String path, Rules rules) {
  for (final g in rules.none) {
    if (g.matches(path)) {
      return Classification(path, PathKind.none, 'none: ${g.source}');
    }
  }
  for (final g in rules.arbGlobs) {
    if (g.matches(path)) {
      return Classification(path, PathKind.arb, 'arb: ${g.source}');
    }
  }
  for (final g in rules.goldenAssetGlobs) {
    if (g.matches(path)) {
      return Classification(
        path,
        PathKind.goldenAsset,
        'golden asset: ${g.source}',
      );
    }
  }
  for (final pi in rules.pathIncludes) {
    for (final g in pi.when) {
      if (g.matches(path)) {
        return Classification(
          path,
          PathKind.mapped,
          'path_includes: ${g.source}',
        );
      }
    }
  }
  for (final g in rules.full) {
    if (g.matches(path)) {
      return Classification(path, PathKind.full, 'full: ${g.source}');
    }
  }
  final inRoot = rules.graphRoots.any((r) => path.startsWith('$r/'));
  if (inRoot && path.endsWith('.dart')) {
    var seed = path;
    var rule = 'seed';
    if (isGeneratedDart(path)) {
      seed = path.replaceFirst(RegExp(r'\.(g|freezed)\.dart$'), '.dart');
      rule = 'seed (generated -> owner)';
    }
    return Classification(path, PathKind.seed, rule, seedPath: seed);
  }
  for (final r in rules.fullNonDartRoots) {
    if (path.startsWith('$r/') && p.posix.extension(path) != '.dart') {
      return Classification(
        path,
        PathKind.full,
        'full: non-.dart file under $r/',
      );
    }
  }
  return Classification(path, PathKind.full, 'full: unknown path (fail-safe)');
}
