import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../bin/gen_integration_entry.dart' as gen;

/// Phase 401 QA additions: D3 boundary arithmetic, alias hygiene, output
/// determinism, part-file fail-safe, CLI edge arguments, and the
/// entry-output -> step-`if:` contract of the integration job.
void main() {
  final pkg = Directory.current.path;
  String ip(String n) => 'integration_test/${n}_test.dart';
  String sel(Iterable<String> names) =>
      '{"mode":"selective","integration":[${names.map((n) => '"${ip(n)}"').join(',')}]}';
  String partSrc(List<String> names) => [
    "import 'package:flutter_test/flutter_test.dart';",
    for (final n in names) "import '${n}_test.dart' as $n;",
  ].join('\n');
  List<String> names(String prefix, int n) => [
    for (var i = 0; i < n; i++) '$prefix$i',
  ];
  String entryFor(
    Iterable<String> picked,
    int sizeA,
    int sizeB, {
    double t = gen.defaultThreshold,
  }) => gen
      .decide(
        selectionJson: sel(picked),
        partSources: [partSrc(names('a', sizeA)), partSrc(names('b', sizeB))],
        threshold: t,
      )
      .entry;

  group('D3 boundary arithmetic', () {
    test('exactly 70% of a 10-flow part (7/10) -> parts', () {
      expect(entryFor(names('a', 7), 10, 10), 'parts');
    });

    test('69% territory (6/10) -> selected', () {
      expect(entryFor(names('a', 6), 10, 10), 'selected');
    });

    test('a 27-flow part (under the flow cap): 19 (70.4%) -> parts, 18 (66.7%) '
        '-> selected', () {
      expect(entryFor(names('a', 19), 27, 73), 'parts');
      expect(entryFor(names('a', 18), 27, 73), 'selected');
    });

    test('P4 flow cap (one shard, ${gen.maxSelectedFlows}) is independent of '
        'D3: cap + 1 of a 200-flow part -> parts, cap -> selected', () {
      expect(gen.maxSelectedFlows, 19);
      expect(entryFor(names('a', gen.maxSelectedFlows + 1), 200, 200), 'parts');
      expect(entryFor(names('a', gen.maxSelectedFlows), 200, 200), 'selected');
    });

    test(
      'threshold is per part, never summed: 6/10 of each part -> selected',
      () {
        expect(
          entryFor([...names('a', 6), ...names('b', 6)], 10, 10),
          'selected',
        );
      },
    );

    test('one part at threshold while the other is untouched -> parts', () {
      expect(entryFor(names('b', 7), 10, 10), 'parts');
    });

    test('both parts at threshold -> parts', () {
      expect(entryFor([...names('a', 7), ...names('b', 7)], 10, 10), 'parts');
    });

    test('flows that live in NEITHER part never count toward D3', () {
      final extra = names('zz', gen.maxSelectedFlows);
      expect(entryFor(extra, 10, 10), 'selected');
    });

    test('a custom threshold moves the boundary (0.5: 2/4 -> parts)', () {
      expect(entryFor(names('a', 2), 4, 4, t: 0.5), 'parts');
      expect(entryFor(names('a', 1), 4, 4, t: 0.5), 'selected');
    });
  });

  // mobile-perf cycle 2 P1: the testWidgets of the selection are summed
  // (`tests`, the workflow's bound input) and capped at one shard.
  group('P4 test cap + tests=', () {
    ({String entry, int count, int tests}) withTests(Map<String, int> w) {
      final d = gen.decide(
        selectionJson: sel(w.keys),
        partSources: [partSrc(names('a', 200)), partSrc(names('b', 200))],
        testsOf: (f) =>
            w[RegExp(
              r'integration_test/(\w+)_test\.dart',
            ).firstMatch(f)!.group(1)!]!,
      );
      return (entry: d.entry, count: d.count, tests: d.tests);
    }

    test('tests = the sum of testWidgets of the selected flows', () {
      expect(withTests({'x1': 3, 'x2': 5, 'x3': 0}), (
        entry: 'selected',
        count: 3,
        tests: 8,
      ));
    });

    test('exactly ${gen.maxSelectedTests} tests -> selected; one more -> '
        'parts (count/tests reset to 0)', () {
      expect(gen.maxSelectedTests, 74);
      expect(withTests({'x1': 70, 'x2': 4}).entry, 'selected');
      expect(withTests({'x1': 70, 'x2': 5}), (
        entry: 'parts',
        count: 0,
        tests: 0,
      ));
    });

    test('the test cap bites with few flows; the flow cap with few tests', () {
      expect(withTests({'x1': 75}).entry, 'parts');
      expect(
        withTests({
          for (var i = 0; i <= gen.maxSelectedFlows; i++) 'y$i': 1,
        }).entry,
        'parts',
      );
    });

    test('--force-selected skips the test cap too', () {
      final d = gen.decide(
        selectionJson: sel(['x1']),
        partSources: ['', ''],
        forceSelected: true,
        testsOf: (_) => 500,
      );
      expect((d.entry, d.tests), ('selected', 500));
    });

    test('no testsOf -> tests 0 (the workflow then refuses `selected`)', () {
      final d = gen.decide(
        selectionJson: sel(['x1']),
        partSources: [partSrc(names('a', 10)), partSrc(names('b', 10))],
      );
      expect((d.entry, d.tests), ('selected', 0));
    });
  });

  group('renderEntry hygiene + determinism', () {
    test('input order and duplicates never change a byte of the output', () {
      final base = ['c_flow', 'a_flow', 'b'].map(ip).toList();
      final want = gen.renderEntry(base);
      expect(gen.renderEntry(base.reversed), want);
      expect(gen.renderEntry([...base, ...base]), want);
      expect(gen.renderEntry(base), want);
    });

    test('imports and groups are in the same sorted order', () {
      final out = gen.renderEntry(['z', 'm', 'a'].map(ip));
      final imports = RegExp(
        r"^import '(\w+)_test\.dart'",
        multiLine: true,
      ).allMatches(out).map((m) => m.group(1)).toList();
      final groups = RegExp(
        r"^  group\('(\w+)'",
        multiLine: true,
      ).allMatches(out).map((m) => m.group(1)).toList();
      expect(imports, ['a', 'm', 'z']);
      expect(groups, imports);
    });

    test(
      '4-way alias clash: unique aliases and each group uses ITS import alias',
      () {
        final flows = ['x_flow', 'x', 'x_2', 'x_2_flow'].map(ip).toList();
        final out = gen.renderEntry(flows);
        final aliasOfFile = {
          for (final m in RegExp(
            r"^import '(\w+)_test\.dart' as (\w+);",
            multiLine: true,
          ).allMatches(out))
            m.group(1)!: m.group(2)!,
        };
        final aliasOfGroup = {
          for (final m in RegExp(
            r"^  group\('(\w+)', (\w+)\.main\);",
            multiLine: true,
          ).allMatches(out))
            m.group(1)!: m.group(2)!,
        };
        expect(aliasOfFile.keys.toSet(), {'x_flow', 'x', 'x_2', 'x_2_flow'});
        expect(
          aliasOfFile.values.toSet(),
          hasLength(4),
          reason: '$aliasOfFile',
        );
        expect(aliasOfGroup, aliasOfFile);
      },
    );

    test('a flow whose name starts with a digit gets a valid identifier', () {
      final out = gen.renderEntry([ip('2fa_flow')]);
      expect(out, contains("as f_2fa;"));
      expect(out, contains("group('2fa_flow', f_2fa.main);"));
    });
  });

  group('CLI edges', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gen_qa_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ProcessResult runGen(
      String selJson, {
      List<String> extra = const [],
      bool part1 = true,
      bool part2 = true,
      Map<String, String> flowSrc = const {},
    }) {
      final sf = File(p.join(tmp.path, 'selection.json'))
        ..writeAsStringSync(selJson);
      for (final e in {
        if (part1) 'all_tests_part1.dart': partSrc(names('a', 10)),
        if (part2) 'all_tests_part2.dart': partSrc(names('b', 10)),
      }.entries) {
        File(p.join(tmp.path, 'integration_test', e.key))
          ..createSync(recursive: true)
          ..writeAsStringSync(e.value);
      }
      Directory(
        p.join(tmp.path, 'integration_test'),
      ).createSync(recursive: true);
      // The selected flow files exist, as they do in a real PR tree.
      for (final n in RegExp(
        r'integration_test/(\w+_test\.dart)',
      ).allMatches(selJson).map((m) => m.group(1)!)) {
        File(p.join(tmp.path, 'integration_test', n))
          ..createSync()
          ..writeAsStringSync(flowSrc[n] ?? '');
      }
      return Process.runSync(Platform.resolvedExecutable, [
        p.join(pkg, 'bin', 'gen_integration_entry.dart'),
        '--selection',
        sf.path,
        '--repo',
        tmp.path,
        ...extra,
      ]);
    }

    File entry() =>
        File(p.join(tmp.path, 'integration_test', 'ci_selected_tests.dart'));
    String out(ProcessResult r) =>
        (r.stdout as String).trim().split('\n').first;

    test('ONE missing part file -> parts, no file (never a smaller run)', () {
      for (final missing in [(false, true), (true, false)]) {
        final it = Directory(p.join(tmp.path, 'integration_test'));
        if (it.existsSync()) it.deleteSync(recursive: true);
        final r = runGen(sel(['a0']), part1: missing.$1, part2: missing.$2);
        expect(out(r), 'entry=parts', reason: '${r.stderr}');
        expect(entry().existsSync(), isFalse);
      }
    });

    String widgets(int n, {int commented = 0}) =>
        "void main() {\n${"  testWidgets('t', (t) async {});\n" * n}"
        "${"  // testWidgets('off', (t) async {});\n" * commented}"
        "  test('plain', () {});\n}\n";

    test('selected prints entry / count / tests (testWidgets of the selected '
        'files; comments and plain test() not counted)', () {
      final r = runGen(
        sel(['a0', 'a1']),
        flowSrc: {
          'a0_test.dart': widgets(3, commented: 2),
          'a1_test.dart': widgets(4),
        },
      );
      expect((r.stdout as String).trim().split('\n'), [
        'entry=selected',
        'count=2',
        'tests=7',
      ]);
    });

    test('more than maxSelectedTests testWidgets -> parts, no file', () {
      final r = runGen(
        sel(['a0', 'a1']),
        flowSrc: {
          'a0_test.dart': widgets(gen.maxSelectedTests),
          'a1_test.dart': widgets(1),
        },
      );
      expect((r.stdout as String).trim(), 'entry=parts');
      expect(entry().existsSync(), isFalse);
    });

    test('--force-selected ignores unreadable parts and D3', () {
      final r = runGen(
        sel(names('a', 9)),
        extra: ['--force-selected'],
        part1: false,
        part2: false,
      );
      expect(out(r), 'entry=selected');
      expect(entry().existsSync(), isTrue);
    });

    test('non-numeric --threshold is fail-safe parts, exit 0', () {
      final r = runGen(sel(['a0']), extra: ['--threshold', 'abc']);
      expect(r.exitCode, 0);
      expect(out(r), 'entry=parts');
      expect(entry().existsSync(), isFalse);
    });

    test('--threshold is honoured by the CLI (0.1: 1/10 -> parts)', () {
      final r = runGen(sel(['a0']), extra: ['--threshold', '0.1']);
      expect(out(r), 'entry=parts');
    });

    test('a stale entry is also removed when the selection is `none`', () {
      entry()
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
      final r = runGen(sel([]));
      expect(out(r), 'entry=none');
      expect(entry().existsSync(), isFalse);
    });

    test('a stale entry is removed when the selection file is missing', () {
      entry()
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
      final r = runGen(
        sel(['a0']),
        extra: ['--selection', '/nonexistent.json'],
      );
      expect(out(r), 'entry=parts');
      expect(entry().existsSync(), isFalse);
    });

    test(
      'unwritable --out never prints entry=selected (workflow -> parts)',
      () {
        final r = runGen(
          sel(['a0']),
          extra: ['--out', p.join(tmp.path, 'no', 'such', 'dir', 'x.dart')],
        );
        expect(out(r), isNot('entry=selected'));
      },
    );
  });

  group('integration job: entry output -> step `if:` contract', () {
    final wfFile = File(
      p.normalize(
        p.join(
          pkg,
          '..',
          '..',
          '..',
          '.github',
          'workflows',
          'pr-validate.yml',
        ),
      ),
    );

    // Evaluates the `a == 'x' && b != 'y'` subset the integration job uses.
    bool eval(String cond, Map<String, String> ctx) {
      for (final clause in cond.split('&&')) {
        final m = RegExp(
          r"^\s*([\w.\-]+)\s*(==|!=)\s*'([^']*)'\s*$",
        ).firstMatch(clause);
        if (m == null) fail('unsupported clause in if: "$clause"');
        final v = ctx[m.group(1)] ?? '';
        if ((m.group(2) == '==') != (v == m.group(3))) return false;
      }
      return true;
    }

    late List<YamlMap> steps;
    late List<YamlMap> shardSteps;
    late String shardIf;
    setUpAll(() {
      if (!wfFile.existsSync()) return;
      final jobs =
          (loadYaml(wfFile.readAsStringSync()) as YamlMap)['jobs'] as YamlMap;
      List<YamlMap> of(String j) =>
          ((jobs[j] as YamlMap)['steps'] as YamlList).cast<YamlMap>().toList();
      steps = of('integration');
      shardSteps = of('integration-shard');
      shardIf = (jobs['integration-shard'] as YamlMap)['if'].toString();
    });

    /// Which run families execute for [entry] (null = entry step skipped,
    /// i.e. a non-selective plan), attempt 1 all failing afterwards. The
    /// shard family (2026-11-06) is the `integration-shard` matrix, gated on
    /// the `integration` job's published entry (FULL / not selected = parts).
    Set<String> families(
      String? entry, {
      required bool allAttemptsFail,
      bool buildOk = true,
    }) {
      final ctx = <String, String>{
        'steps.entry.outputs.entry': ?entry,
        // The selected pre-build runs iff entry=selected (its own `if:`).
        if (entry == 'selected')
          'steps.it-sel-build.outcome': buildOk ? 'success' : 'failure',
        'needs.integration.outputs.entry': entry == 'selected'
            ? 'selected'
            : 'parts',
      };
      final ran = <String>{};
      void walk(String fam, List<YamlMap> from) {
        for (var k = 1; k <= 3; k++) {
          final s = from.singleWhere((s) => s['id'] == '$fam-attempt-$k');
          final cond = (s['if'] ?? 'success()').toString();
          if (cond == 'success()' || eval(cond, ctx)) {
            ran.add('$fam-$k');
            ctx['steps.$fam-attempt-$k.outcome'] = allAttemptsFail
                ? 'failure'
                : 'success';
          } else {
            ctx['steps.$fam-attempt-$k.outcome'] = 'skipped';
          }
        }
      }

      walk('it-sel', steps);
      if (eval(shardIf, ctx)) walk('it-shard', shardSteps);
      return ran;
    }

    test('entry=selected -> only the selected family runs', () {
      expect(families('selected', allAttemptsFail: false), {'it-sel-1'});
    });

    test('entry=selected but the pre-build failed -> no attempt runs (the '
        'verify step then fails: no attempt passed)', () {
      expect(
        families('selected', allAttemptsFail: true, buildOk: false),
        isEmpty,
      );
      final b = steps.singleWhere((s) => s['id'] == 'it-sel-build');
      expect(b['if'], "steps.entry.outputs.entry == 'selected'");
    });

    test(
      'entry=selected + attempts fail -> retries 2 and 3 are selected-only',
      () {
        expect(families('selected', allAttemptsFail: true), {
          'it-sel-1',
          'it-sel-2',
          'it-sel-3',
        });
      },
    );

    for (final e in <String?>['parts', null]) {
      test(
        'entry=${e ?? "<step skipped: full mode>"} -> only the shards run',
        () {
          final ran = families(e, allAttemptsFail: false);
          expect(ran, {'it-shard-1'});
        },
      );
    }

    test('entry=parts + attempts fail -> shard retries run, none selected', () {
      final ran = families('parts', allAttemptsFail: true);
      expect(ran.where((r) => r.startsWith('it-sel')), isEmpty);
      expect(ran, containsAll(['it-shard-2', 'it-shard-3']));
    });
  });
}
