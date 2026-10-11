@Tags(['e2e', 'e2e-b'])
library;

/// Phase 402 end-to-end (part 3 of 4): plan -> shard_units.sh -> unit shards ->
/// tests-ran. See support_pipeline.dart.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support_pipeline.dart';

void main() {
  final mobile = p.normalize(p.join(Directory.current.path, '..', '..', '..'));
  final wfFile = File(
    p.join(mobile, '.github', 'workflows', 'pr-validate.yml'),
  );
  final haveTools =
      wfFile.existsSync() &&
      which('git') &&
      which('jq') &&
      which('bash') &&
      which('dart');
  final skip = haveTools
      ? false
      : 'needs the beautica-mobile tree + git/jq/dart';

  late YamlMap jobs;
  late Pipeline pl;
  setUpAll(() {
    if (!haveTools) return;
    jobs = (loadYaml(wfFile.readAsStringSync()) as YamlMap)['jobs'] as YamlMap;
    pl = Pipeline(mobile, jobs);
  });
  tearDownAll(() {
    if (haveTools) pl.dispose();
  });

  const e2eTimeout = Timeout(Duration(minutes: 3));

  group('phase 402: unit sharding (plan -> shards -> tests-ran)', () {
    /// `n` filler unit tests edited, so exactly those `n` are selected.
    Map<String, String> edited(int n) => {
      for (var i = 0; i < n; i++)
        'test/filler/f${i}_test.dart': 'void main() {}\n// edit\n',
    };

    // D3a boundaries through the REAL resolver + shard_units.sh + selector.
    for (final row in [(80, '[1]', 1), (81, '[1,2]', 2)]) {
      test('selective ${row.$1} unit files -> unit_shards ${row.$2}: shards '
          'partition the list, no --coverage, tests-ran green', () {
        final out = pl.select(edited(row.$1));
        expect(out, containsPair('mode', 'selective'));
        expect(out, containsPair('unit_count', '${row.$1}'));
        expect(out, containsPair('unit_warn_threshold', '80'));
        expect(out, containsPair('unit_shards', row.$2));
        expect(out, containsPair('unit_shard_count', '${row.$3}'));

        final calls = pl.runTestJob(out).where((c) => c.step == 'Test');
        expect(calls, hasLength(row.$3));
        final listed = File(
          p.join(pl.testRt, 'sel', 'unit.txt'),
        ).readAsLinesSync();
        expect(listed, hasLength(row.$1));
        expect(
          [for (final c in calls) ...c.files]..sort(),
          [...listed]..sort(),
        );
        expect({for (final c in calls) ...c.files}, hasLength(row.$1));
        for (final c in calls) {
          expect(c.args, isNot(contains('--coverage')));
          expect(c.args, containsAllInOrder(['--exclude-tags', 'golden']));
          expect(c.files.length, lessThanOrEqualTo(80));
        }
        final tr = pl.testsRan(out);
        expect(tr.code, 0, reason: tr.output);
        for (var i = 1; i <= row.$3; i++) {
          expect(tr.output, contains('events/unit-$i-events.json'));
        }
      }, timeout: e2eTimeout);
    }

    test(
      'full run: every shard carries --coverage and its own stream name',
      () {
        final out = pl.select({'tool/ci/x.sh': 'echo 3\n'});
        final calls = pl
            .runTestJob(out)
            .where((c) => c.step == 'Test')
            .toList();
        expect(calls, hasLength(4));
        for (final c in calls) {
          expect(c.args, contains('--coverage'));
        }
        expect(
          [
            for (final c in calls)
              c.args.singleWhere((a) => a.startsWith('--file-reporter=')),
          ],
          [
            for (var i = 1; i <= 4; i++)
              '--file-reporter=json:build/ci/unit-$i-events.json',
          ],
        );
      },
      timeout: e2eTimeout,
    );

    test(
      'count invariant: tests-ran is RED when the shards stop adding up',
      () {
        final out = pl.select({'tool/ci/x.sh': 'echo 4\n'});
        pl.runTestJob(out);
        final n = pl.universeUnit().length;
        expect(pl.testsRan(out, floor: n).code, 0);

        // A shard never reported.
        final lost = pl.testsRan(out, floor: 1, drop: {'unit-2'});
        expect(lost.code, isNot(0), reason: lost.output);
        expect(lost.output, contains('events/unit-2-events.json is missing'));

        // A file silently dropped from a shard's run (its suite never loaded).
        final f = File(p.join(pl.pr, 'build', 'ci', 'unit-3-events.json'));
        final saved = f.readAsStringSync();
        addTearDown(() => f.writeAsStringSync(saved));
        final victim = RegExp(
          r'"path":"([^"]+_test\.dart)"',
        ).firstMatch(saved)!.group(1)!;
        f.writeAsStringSync(
          saved
              .split('\n')
              .where((l) => !l.contains('"path":"$victim"'))
              .join('\n'),
        );
        final dropped = pl.testsRan(out, floor: 1);
        expect(dropped.code, isNot(0), reason: dropped.output);
        expect(dropped.output, contains('never loaded as a suite'));
        f.writeAsStringSync(saved);

        // A file run twice (a doubled suite).
        f.writeAsStringSync(
          saved + '{"suite":{"id":99,"path":"$victim"},"type":"suite"}\n',
        );
        final doubled = pl.testsRan(out, floor: 1);
        expect(doubled.code, isNot(0), reason: doubled.output);
        expect(doubled.output, contains('more than once'));
      },
      timeout: e2eTimeout,
    );

    test(
      'falsifiability: a failing test in shard 2 fails ONLY that shard',
      () {
        final out = pl.select({'tool/ci/x.sh': 'echo 5\n'});
        final shards = jsonDecode(out['unit_shards']!) as List;
        final shard2 = File(
          p.join(pl.rt, 'ci', 'shards', 'unit-shard-2.txt'),
        ).readAsLinesSync().first;
        final codes = {
          for (final sh in shards)
            sh: pl.runUnitShard(out, '$sh', fail: shard2).exitCode,
        };
        expect(codes, {1: 0, 2: isNot(0), 3: 0, 4: 0});
      },
      timeout: e2eTimeout,
    );

    test('base without shard_units.sh (bootstrap): ["whole"], the Test step '
        'runs the pre-400 command, tests-ran judges unit-events.json', () {
      final out = pl.select({
        'lib/features/foo/foo.dart': 'int foo = 6;\n',
      }, bootstrap: true);
      expect(out, containsPair('mode', 'full'));
      expect(out, containsPair('unit_shards', '["whole"]'));
      expect(out, containsPair('unit_shard_count', '1'));
      final calls = pl.runTestJob(out).where((c) => c.step == 'Test').toList();
      expect(calls, hasLength(1));
      final pre = pl.runPre400().singleWhere((c) => c.step == 'Test');
      expect(
        '${calls.single.tz}|${calls.single.args.join(' ')}',
        '${pre.tz}|${pre.args.join(' ')}',
      );
      final tr = pl.testsRan(out, floor: Pipeline.fullPasses);
      expect(tr.code, 0, reason: tr.output);
      final red = pl.testsRan(out, floor: Pipeline.fullPasses + 1);
      expect(red.code, isNot(0));
    }, timeout: e2eTimeout);

    test(
      'integration-only selection: unit job skipped, no unit stream owed',
      () {
        final out = pl.select({'integration_test/x_test.dart': '// c2\n'});
        expect(out, containsPair('unit_count', '0'));
        expect(out, containsPair('unit_shard_count', '0'));
        expect(pl.jobRuns('unit', out), isFalse);
        expect(pl.runTestJob(out), isEmpty);
      },
      timeout: e2eTimeout,
    );

    test('plan wiring: matrix outputs and the shard step come from the BASE '
        'commit', () {
      final st = pl.step(
        'plan',
        'Shard unit tests (script from the BASE commit)',
      );
      final run = st['run'].toString();
      expect(run, contains(r'$GITHUB_WORKSPACE/trusted/tool/ci'));
      expect(run, contains(r'bash "$trusted/shard_units.sh"'));
      final env = st['env'] as YamlMap;
      expect(
        env['SHARD_THRESHOLD'],
        r'${{ steps.sel.outputs.unit_warn_threshold }}',
      );
    }, timeout: e2eTimeout);
  }, skip: skip);
}
