import 'dart:io';

import 'assets.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A glob that remembers its source pattern (for the audit trail).
final class RuleGlob {
  RuleGlob(this.source) : _glob = Glob(source, context: p.posix);
  final String source;
  final Glob _glob;
  bool matches(String path) => _glob.matches(path);
}

List<RuleGlob> _globs(Object? v) => [
  for (final s in (v as YamlList? ?? YamlList())) RuleGlob(s as String),
];

/// One cardinality-ledger rule: when [when] matches a changed path (and, if
/// [whenText] is set, that file's text contains it), every test matching
/// [include] is selected.
final class LedgerRule {
  LedgerRule(this.when, this.whenText, this.include);
  final List<RuleGlob> when;
  final String? whenText;
  final List<RuleGlob> include;
}

/// `path_includes` entry: a changed path matching [when] is NOT forced to
/// FULL; it selects exactly the tests matching [include] instead.
final class PathInclude {
  PathInclude(this.when, this.include);
  final List<RuleGlob> when;
  final List<RuleGlob> include;
}

/// Parsed `rules.yaml`. The code holds no paths: everything lives there.
final class Rules {
  Rules._({
    required this.packages,
    required this.graphRoots,
    required this.none,
    required this.full,
    required this.fullNonDartRoots,
    required this.ledgers,
    required this.structuralRoots,
    required this.structuralInclude,
    required this.alwaysIncludeWhenChanged,
    required this.alwaysIncludeLiteral,
    required this.tzDirs,
    required this.tzFiles,
    required this.flowGlob,
    required this.hubs,
    required this.fullThreshold,
    required this.pathIncludes,
    required this.goldenAssetGlobs,
    required this.arbGlobs,
    required this.arbReaderLiteral,
    required this.arbIncludeAlways,
  });

  factory Rules.fromYaml(String source) {
    final y = loadYaml(source) as YamlMap;
    final tz = y['tz_sweep'] as YamlMap;
    final integ = y['integration'] as YamlMap;
    final golden = y['golden_assets'] as YamlMap? ?? YamlMap();
    final arb = y['arb'] as YamlMap? ?? YamlMap();
    return Rules._(
      pathIncludes: [
        for (final e in (y['path_includes'] as YamlList? ?? YamlList()))
          PathInclude(_globs((e as YamlMap)['when']), _globs(e['include'])),
      ],
      goldenAssetGlobs: _globs(golden['globs']),
      arbGlobs: _globs(arb['globs']),
      arbReaderLiteral: RegExp((arb['reader_literal'] as String?) ?? r'(?!)'),
      arbIncludeAlways: _globs(arb['include_always']),
      packages: {
        for (final e in (y['packages'] as YamlMap).entries)
          e.key as String: e.value as String,
      },
      graphRoots: [for (final r in y['graph_roots'] as YamlList) r as String],
      none: _globs(y['none_globs']),
      full: _globs(y['full_globs']),
      fullNonDartRoots: [
        for (final r in y['full_nondart_roots'] as YamlList) r as String,
      ],
      ledgers: [
        for (final l in y['ledgers'] as YamlList)
          LedgerRule(
            _globs((l as YamlMap)['when']),
            l['when_text'] as String?,
            _globs(l['include']),
          ),
      ],
      structuralRoots: _globs(y['structural_roots']),
      structuralInclude: _globs(y['structural_include']),
      alwaysIncludeWhenChanged: RuleGlob(
        y['always_include_when_changed'] as String,
      ),
      alwaysIncludeLiteral: RegExp(y['always_include_literal'] as String),
      tzDirs: [for (final d in tz['dirs'] as YamlList) d as String],
      tzFiles: [for (final f in tz['files'] as YamlList) f as String],
      flowGlob: RuleGlob(integ['flow_glob'] as String),
      hubs: _globs(integ['hubs']),
      fullThreshold: (y['full_threshold'] as num).toDouble(),
    );
  }

  factory Rules.fromFile(String path) =>
      Rules.fromYaml(readTextSync(File(path)));

  final Map<String, String> packages;
  final List<String> graphRoots;
  final List<RuleGlob> none;
  final List<RuleGlob> full;
  final List<String> fullNonDartRoots;
  final List<LedgerRule> ledgers;
  final List<RuleGlob> structuralRoots;
  final List<RuleGlob> structuralInclude;
  final RuleGlob alwaysIncludeWhenChanged;
  final RegExp alwaysIncludeLiteral;
  final List<String> tzDirs;
  final List<String> tzFiles;
  final RuleGlob flowGlob;
  final List<RuleGlob> hubs;
  final double fullThreshold;
  final List<PathInclude> pathIncludes;
  final List<RuleGlob> goldenAssetGlobs;
  final List<RuleGlob> arbGlobs;
  final RegExp arbReaderLiteral;
  final List<RuleGlob> arbIncludeAlways;

  bool isHub(String path) => hubs.any((h) => h.matches(path));

  bool inTzSweep(String path) =>
      tzFiles.contains(path) || tzDirs.any((d) => path.startsWith(d));
}
