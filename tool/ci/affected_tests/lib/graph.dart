import 'dart:io';

import 'assets.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'rules.dart';

bool isGeneratedDart(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

/// Reverse import graph over the Dart files under `Rules.graphRoots`.
///
/// Edges come from `import` / `export` / `part` directives (every URI of a
/// conditional import counts). Generated `*.g.dart` / `*.freezed.dart` parts
/// are folded into their owner: they are never nodes, and edges to them are
/// dropped (the selector runs before codegen, so they may not exist).
/// Edges to paths that do not exist are KEPT, which is what lets a deleted
/// file still reach the importers that have not dropped the import.
final class ImportGraph {
  ImportGraph._(this.root, this.nodes, this._rdeps);

  final String root;

  /// Repo-relative posix paths of every scanned Dart file.
  final Set<String> nodes;
  final Map<String, Set<String>> _rdeps;

  /// Direct importers (reverse edges) of [path].
  Set<String> importersOf(String path) => _rdeps[path] ?? const {};

  static ImportGraph build(String root, Rules rules) {
    final packages = Map<String, String>.of(rules.packages);
    final apiPubspec = File(p.join(root, 'api', 'pubspec.yaml'));
    if (apiPubspec.existsSync()) {
      final name = (loadYaml(readTextSync(apiPubspec)) as YamlMap)['name'];
      if (name is String) packages[name] = 'api/lib';
    }

    final nodes = <String>{};
    final rdeps = <String, Set<String>>{};
    for (final r in rules.graphRoots) {
      final dir = Directory(p.join(root, r));
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final rel = p.posix.joinAll(p.split(p.relative(e.path, from: root)));
        if (isGeneratedDart(rel)) continue;
        nodes.add(rel);
        for (final dep in _directiveTargets(readTextSync(e), rel, packages)) {
          (rdeps[dep] ??= <String>{}).add(rel);
        }
      }
    }
    return ImportGraph._(root, nodes, rdeps);
  }

  /// Reverse-reachable set of [seeds] (seeds included). When [isHub] is given,
  /// reached hub nodes are kept but NOT expanded (edges into hubs are not
  /// followed). Seeds themselves are always expanded.
  Set<String> reachableFrom(
    Iterable<String> seeds, {
    bool Function(String)? isHub,
  }) {
    final seen = <String>{...seeds};
    final queue = [...seeds];
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      for (final m in _rdeps[n] ?? const <String>{}) {
        if (!seen.add(m)) continue;
        if (isHub != null && isHub(m)) continue;
        queue.add(m);
      }
    }
    return seen;
  }
}

Iterable<String> _directiveTargets(
  String source,
  String from,
  Map<String, String> packages,
) sync* {
  final unit = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  for (final d in unit.directives) {
    final uris = <String?>[];
    if (d is NamespaceDirective) {
      uris.add(d.uri.stringValue);
      for (final c in d.configurations) {
        uris.add(c.uri.stringValue);
      }
    } else if (d is PartDirective) {
      uris.add(d.uri.stringValue);
    }
    for (final u in uris) {
      final r = resolveUri(from, u, packages);
      if (r != null && !isGeneratedDart(r)) yield r;
    }
  }
}

/// Resolves a directive URI to a repo-relative posix path, or null if it is
/// outside the graph (dart:, third-party packages, other schemes, escapes).
String? resolveUri(String from, String? uri, Map<String, String> packages) {
  if (uri == null || uri.isEmpty) return null;
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    final base = packages[rest.substring(0, slash)];
    if (base == null) return null;
    return p.posix.normalize('$base/${rest.substring(slash + 1)}');
  }
  if (uri.contains(':')) return null; // dart:, file:, http:, ...
  final joined = p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
  return joined.startsWith('..') ? null : joined;
}
