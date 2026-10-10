import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'assets.dart';
import 'classifier.dart';
import 'graph.dart';
import 'rules.dart';

enum Mode { full, none, selective }

final class Reason {
  const Reason(this.path, this.rule);
  final String path;
  final String rule;
  Map<String, String> toJson() => {'path': path, 'rule': rule};
}

/// The selector's verdict: full, none, or explicit file lists.
final class Selection {
  const Selection({
    required this.mode,
    this.unit = const [],
    this.golden = const [],
    this.tzSweep = const [],
    this.integration = const [],
    this.reasons = const [],
  });

  final Mode mode;
  final List<String> unit;
  final List<String> golden;
  final List<String> tzSweep;
  final List<String> integration;
  final List<Reason> reasons;

  Selection copyWith({
    List<String>? unit,
    List<String>? golden,
    List<String>? tzSweep,
    List<String>? integration,
  }) => Selection(
    mode: mode,
    unit: unit ?? this.unit,
    golden: golden ?? this.golden,
    tzSweep: tzSweep ?? this.tzSweep,
    integration: integration ?? this.integration,
    reasons: reasons,
  );

  Map<String, Object> toJson() => {
    'mode': mode.name,
    'unit': unit,
    'golden': golden,
    'tz_sweep': tzSweep,
    'integration': integration,
    'reasons': [for (final r in reasons) r.toJson()],
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

List<RuleGlob> _mappedIncludes(String path, Rules rules) => [
  for (final pi in rules.pathIncludes)
    if (pi.when.any((w) => w.matches(path))) ...pi.include,
];

bool _isTest(String path) => path.endsWith('_test.dart');

/// Every test the selector knows about, from a built [graph].
({List<String> unit, List<String> golden, List<String> flows}) universe(
  ImportGraph graph,
  Rules rules,
) {
  final unit = <String>[], golden = <String>[], flows = <String>[];
  for (final n in graph.nodes) {
    if (n.startsWith('test/') && _isTest(n)) {
      (n.startsWith('test/golden/') ? golden : unit).add(n);
    } else if (rules.flowGlob.matches(n)) {
      flows.add(n);
    }
  }
  return (unit: unit..sort(), golden: golden..sort(), flows: flows..sort());
}

/// Selects the tests affected by [changes] in the tree at [root].
///
/// [baseRoot] (optional) is the BASE tree: deleted/renamed Dart files are
/// resolved against it so their BASE importers are selected.
Selection select({
  required String root,
  required List<Change> changes,
  required Rules rules,
  String? baseRoot,
  ImportGraph? graph,
}) {
  final reasons = <Reason>[];
  // 1. classify
  var forceFull = false;
  final seeds = <String>{}; // live seeds (HEAD tree)
  final goneSeeds = <String>{}; // BASE-tree seeds (deleted / renamed-away)
  final livePaths = <String>[]; // non-ignored live changed paths
  final mappedPicks = <RuleGlob>[]; // path_includes -> fixed test sets
  final goldenPngs = <String>[]; // committed golden images (live + removed)
  final arbPaths = <String>[];
  for (final c in changes) {
    for (final path in c.livePaths) {
      final k = classify(path, rules);
      reasons.add(Reason(path, k.rule));
      switch (k.kind) {
        case PathKind.none:
          break;
        case PathKind.full:
          forceFull = true;
          livePaths.add(path);
        case PathKind.seed:
          seeds.add(k.seedPath!);
          livePaths.add(path);
        case PathKind.mapped:
          livePaths.add(path);
          mappedPicks.addAll(_mappedIncludes(path, rules));
        case PathKind.goldenAsset:
          livePaths.add(path);
          goldenPngs.add(path);
        case PathKind.arb:
          livePaths.add(path);
          arbPaths.add(path);
      }
    }
    for (final path in c.gonePaths) {
      final k = classify(path, rules);
      reasons.add(Reason(path, '${k.rule} [removed]'));
      if (k.kind == PathKind.full) forceFull = true;
      if (k.kind == PathKind.seed) {
        goneSeeds.add(k.seedPath!);
        seeds.add(k.seedPath!);
      }
      if (k.kind == PathKind.mapped) {
        mappedPicks.addAll(_mappedIncludes(path, rules));
      }
      if (k.kind == PathKind.goldenAsset) goldenPngs.add(path);
      if (k.kind == PathKind.arb) arbPaths.add(path);
    }
  }
  if (forceFull) return Selection(mode: Mode.full, reasons: reasons);

  // The graph is only needed once nothing forced FULL (building it is the
  // expensive part).
  final g = graph ?? ImportGraph.build(root, rules);
  final uni = universe(g, rules);
  final allTests = [...uni.unit, ...uni.golden];

  // 1b. non-Dart changes that map to tests instead of forcing FULL. Anything
  // unresolvable falls back to FULL (fail-safe).
  String? readLive(String path) {
    final f = File(p.join(root, path));
    return f.existsSync() ? readTextSync(f) : null;
  }

  final directPicks = <String>{};
  final extraFlows = <String>{};
  for (final png in goldenPngs) {
    final owners = goldenOwners(png, allTests);
    if (owners.isEmpty) {
      reasons.add(Reason(png, 'full: golden image no test names'));
      return Selection(mode: Mode.full, reasons: reasons);
    }
    reasons.add(Reason(png, 'golden image -> ${owners.join(', ')}'));
    directPicks.addAll(owners);
  }
  if (arbPaths.isNotEmpty) {
    final keys = <String>{}, chunks = <String>{};
    for (final path in arbPaths) {
      final baseFile = baseRoot == null ? null : File(p.join(baseRoot, path));
      final delta = baseRoot == null
          ? null
          : arbDelta(
              baseFile!.existsSync() ? readTextSync(baseFile) : null,
              readLive(path),
            );
      if (delta == null) {
        reasons.add(Reason(path, 'full: arb delta unresolvable'));
        return Selection(mode: Mode.full, reasons: reasons);
      }
      keys.addAll(delta.keys);
      chunks.addAll(delta.chunks);
    }
    reasons.add(Reason('*', 'arb: ${keys.length} changed key(s)'));
    for (final n in g.nodes) {
      final text = readLive(n);
      if (text == null) continue;
      final isLib = n.startsWith('lib/');
      final isTest = allTests.contains(n);
      final isFlow = rules.flowGlob.matches(n);
      if (!isLib && !isTest && !isFlow) continue;
      final ids = identifiers(text);
      final byKey = keys.any(ids.contains);
      if (isLib && byKey) {
        seeds.add(n);
        if (!livePaths.contains(n)) livePaths.add(n); // ledger expansion too
      }
      if (isTest || isFlow) {
        final hit =
            byKey ||
            chunks.any(text.contains) ||
            (isTest && rules.arbReaderLiteral.hasMatch(text)) ||
            rules.arbIncludeAlways.any((x) => x.matches(n));
        if (hit) (isTest ? directPicks : extraFlows).add(n);
      }
    }
  }
  for (final path in mappedPicks.map((x) => x.source).toSet()) {
    reasons.add(Reason('*', 'path_includes -> $path'));
  }
  for (final t in allTests) {
    if (mappedPicks.any((x) => x.matches(t))) directPicks.add(t);
  }

  // 2./3. reverse reachability (HEAD graph, plus the BASE graph for removals)
  var affected = g.reachableFrom(seeds);
  ImportGraph? base;
  if (goneSeeds.isNotEmpty && baseRoot != null) {
    base = ImportGraph.build(baseRoot, rules);
    affected = {...affected, ...base.reachableFrom(goneSeeds)};
  }

  final picked = <String>{
    for (final t in allTests)
      if (affected.contains(t)) t,
    ...directPicks,
  };

  // 5. ledgers (cardinality tests that must run whole)

  void include(List<RuleGlob> globs, String why) {
    final hit = [
      for (final t in allTests)
        if (globs.any((x) => x.matches(t))) t,
    ];
    if (hit.isNotEmpty) {
      reasons.add(Reason('*', '$why -> ${hit.length} test(s)'));
    }
    picked.addAll(hit);
  }

  for (final path in livePaths) {
    for (final l in rules.ledgers) {
      final w = l.when.where((x) => x.matches(path));
      if (w.isEmpty) continue;
      if (l.whenText != null &&
          !(readLive(path)?.contains(l.whenText!) ?? false)) {
        continue;
      }
      include(
        l.include,
        'ledger ${w.first.source}${l.whenText == null ? '' : ' (text ${l.whenText})'}',
      );
    }
  }
  for (final c in changes) {
    final touched = [...c.livePaths, ...c.gonePaths];
    if (c.isStructural &&
        touched.any((t) => rules.structuralRoots.any((r) => r.matches(t)))) {
      include(rules.structuralInclude, 'structural ${c.status} ${c.path}');
    }
  }
  final allPaths = [
    for (final c in changes) ...[...c.livePaths, ...c.gonePaths],
  ];
  if (allPaths.any(rules.alwaysIncludeWhenChanged.matches)) {
    final readers = [
      for (final t in allTests)
        if ((readLive(t) ?? '').contains(rules.alwaysIncludeLiteral)) t,
    ];
    if (readers.isNotEmpty) {
      reasons.add(
        Reason(
          '*',
          "always_include: ${readers.length} test(s) read 'lib/ literals",
        ),
      );
    }
    picked.addAll(readers);
  }

  // 4. split
  final unit = [
    for (final t in picked)
      if (!t.startsWith('test/golden/')) t,
  ]..sort();
  final golden = [
    for (final t in picked)
      if (t.startsWith('test/golden/')) t,
  ]..sort();

  // 6. tz sweep
  final tz = [
    for (final t in [...unit, ...golden])
      if (rules.inTzSweep(t)) t,
  ]..sort();

  // 7. integration flows (hub cut)
  var flows = <String>[];
  if (seeds.any(rules.isHub)) {
    flows = [...uni.flows];
    reasons.add(Reason('*', 'hub changed -> all ${flows.length} flow(s)'));
  } else {
    var reach = g.reachableFrom(seeds, isHub: rules.isHub);
    if (base != null) {
      reach = {...reach, ...base.reachableFrom(goneSeeds, isHub: rules.isHub)};
    }
    flows = [
      for (final f in uni.flows)
        if (reach.contains(f)) f,
    ];
  }
  flows = {...flows, ...extraFlows}.toList()..sort();

  // 8. fallback + none
  if (uni.unit.isNotEmpty &&
      unit.length > rules.fullThreshold * uni.unit.length) {
    reasons.add(
      Reason(
        '*',
        'unit selection ${unit.length}/${uni.unit.length} > ${(rules.fullThreshold * 100).round()}% -> full',
      ),
    );
    return Selection(mode: Mode.full, reasons: reasons);
  }
  if (unit.isEmpty && golden.isEmpty && flows.isEmpty) {
    return Selection(mode: Mode.none, reasons: reasons);
  }
  return Selection(
    mode: Mode.selective,
    unit: unit,
    golden: golden,
    tzSweep: tz,
    integration: flows,
    reasons: reasons,
  );
}
