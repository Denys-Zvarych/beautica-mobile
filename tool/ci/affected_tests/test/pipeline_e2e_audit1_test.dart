@Tags(['e2e', 'e2e-b'])
library;

/// Phase 402 audit cycle 1 end-to-end (part 4 of 4): D10 fallbacks, the
/// ['whole'] leg through lcov/coverage, weighted shards, events intake.

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

  group('phase 402 audit cycle 1: fallbacks, coverage, events intake', () {
    // Evaluates `continue-on-error` the way Actions would for a step whose
    // exit code is [code]: a failure is tolerated iff the (pinned) expression
    // is true for the given guard / plan modes.
    bool stepGreen(
      YamlMap st,
      int code, {
      String guard = '',
      String planMode = 'full',
    }) {
      if (code == 0) return true;
      const expr =
          r"${{ (steps.guard.outputs.mode || steps.plan.outputs.mode) == 'full' }}";
      expect(st['continue-on-error'], expr);
      return (guard.isNotEmpty ? guard : planMode) == 'full';
    }

    /// A PATH with the host tools but NO real `dart`; [dartStub] (when given)
    /// is a `dart` that fails every call, like an unresolved selector package.
    Map<String, String> brokenDart(Pipeline pl, {required bool stub}) {
      final bin = Directory(p.join(pl.ws, stub ? 'failbin' : 'nodartbin'))
        ..createSync(recursive: true);
      if (stub) {
        File(p.join(bin.path, 'dart'))..writeAsStringSync(
          '#!/usr/bin/env bash\necho "pub get failed" >&2\nexit 1\n',
        );
        Process.runSync('chmod', ['+x', p.join(bin.path, 'dart')]);
      }
      return {'PATH': '${bin.path}:/usr/bin:/bin'};
    }

    for (final stub in [true, false]) {
      test(
        'D10: FULL mode, selector ${stub ? 'pub get fails (dart exits 1)' : 'Dart setup failed (no dart on PATH)'}'
        ' -> plan stays green, unit_shards ["whole"], warning, whole leg + '
        'tests-ran green',
        () {
          final env = brokenDart(pl, stub: stub);
          // The two setup steps, as the runner would judge them.
          final setupDart = pl.step('plan', 'Set up Dart (selector)');
          expect(stepGreen(setupDart, 1, planMode: 'full'), isTrue);
          expect(stepGreen(setupDart, 1, planMode: 'selective'), isFalse);
          expect(
            stepGreen(setupDart, 1, guard: 'full', planMode: 'selective'),
            isTrue,
            reason: 'guard forced full',
          );
          if (stub) {
            final pg = pl.runStep(
              'plan',
              'Selector pub get (base commit)',
              env: {...env, 'GITHUB_WORKSPACE': pl.ws, 'RUNNER_TEMP': pl.rt},
              cwd: pl.pr,
            );
            expect(
              stepGreen(
                pl.step('plan', 'Selector pub get (base commit)'),
                pg.exitCode,
              ),
              isTrue,
              reason: '${pg.stdout}${pg.stderr}',
            );
          }
          final out = pl.select(
            {'tool/ci/x.sh': 'echo 11\n'},
            planMode: 'full',
            shardEnv: env,
          );
          expect(out, containsPair('mode', 'full'));
          expect(out, containsPair('unit_shards', '["whole"]'));
          expect(out, containsPair('unit_shard_count', '1'));
          expect(
            pl.lastShardLog,
            contains('::warning::selector unavailable, unsharded fallback'),
          );
          final calls = pl.runTestJob(out).where((c) => c.step == 'Test');
          expect(calls, hasLength(1));
          final tr = pl.testsRan(out, floor: Pipeline.fullPasses);
          expect(tr.code, 0, reason: tr.output);
        },
        timeout: e2eTimeout,
      );
    }

    test('D10 control: the same break in SELECTIVE mode is not tolerated '
        '(the step has no free pass)', () {
      final st = pl.step('plan', 'Set up Dart (selector)');
      expect(stepGreen(st, 1, planMode: 'selective'), isFalse);
      expect(stepGreen(st, 1, planMode: 'none'), isFalse);
      expect(stepGreen(st, 0, planMode: 'selective'), isTrue);
    });

    test('Q-M1: the ["whole"] fallback leg flows through tests-ran, the lcov '
        'upload and the coverage merge', () {
      final out = pl.select(
        {'tool/ci/x.sh': 'echo 12\n'},
        planMode: 'full',
        shardEnv: brokenDart(pl, stub: false),
      );
      expect(out, containsPair('unit_shards', '["whole"]'));
      pl.resetCoverage();

      // unit job, matrix.shard == 'whole': the pre-sharding command.
      final r = pl.runUnitShard(out, 'whole');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      pl.uploadShardCoverage(out, 'whole');
      expect(
        Directory(
          pl.lcovArtifacts.path,
        ).listSync().map((e) => p.basename(e.path)),
        ['lcov-unit-whole'],
      );

      // tests-ran judges unit-events.json (artifact events-unit-whole).
      final tr = pl.testsRan(out, floor: Pipeline.fullPasses);
      expect(tr.code, 0, reason: tr.output);
      expect(tr.output, contains('collect_events: 1 stream(s) accepted'));
      expect(tr.output, contains('tests-ran green'));

      // coverage job: ONE lcov file from the whole leg, merged and summarised.
      final cov = pl.mergeCoverage();
      expect(cov.code, 0, reason: cov.output);
      expect('SF:'.allMatches(cov.merged), hasLength(1));
      expect(cov.output, contains('Merged coverage (1 shard file(s))'));
      expect(
        cov.apt,
        contains(
          'apt-get install -y -qq --no-install-recommends lcov=2.0-4ubuntu2',
        ),
      );
    }, timeout: e2eTimeout);

    test('Q-M1: the sharded path merges every shard lcov (4 files); a '
        'selective run uploads and merges nothing', () {
      final full = pl.select({'tool/ci/x.sh': 'echo 13\n'});
      expect(full, containsPair('unit_shards', '[1,2,3,4]'));
      pl.resetCoverage();
      for (var i = 1; i <= 4; i++) {
        final r = pl.runUnitShard(full, '$i');
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        pl.uploadShardCoverage(full, '$i');
      }
      final cov = pl.mergeCoverage();
      expect(cov.code, 0, reason: cov.output);
      expect('SF:'.allMatches(cov.merged), hasLength(4));
      expect(cov.output, contains('Merged coverage (4 shard file(s))'));

      final sel = pl.select({
        for (var i = 0; i < 3; i++)
          'test/filler/f${i}_test.dart': 'void main() {}\n// q-m1\n',
      });
      expect(sel, containsPair('mode', 'selective'));
      pl.resetCoverage();
      pl.uploadShardCoverage(sel, '1'); // `if:` false: nothing uploaded
      expect(pl.lcovArtifacts.listSync(), isEmpty);
      final none = pl.mergeCoverage();
      expect(none.code, isNot(0), reason: 'no lcov to merge');
      expect(none.output, contains('no shard lcov.info to merge'));
    }, timeout: e2eTimeout);

    test('F3: a FULL run puts the heaviest test files on distinct shards '
        '(weights from the PR tree, via the real shard_units.sh)', () {
      pl.select({'tool/ci/x.sh': 'echo 14\n'});
      final universe = pl.universeUnit();
      // Positions 0, 4, 8, 12 of the sorted list: a count-only round-robin
      // would deal all four to shard 1.
      final heavy = [
        for (final i in [0, 4, 8, 12]) universe[i],
      ];
      final out = pl.select({
        'tool/ci/x.sh': 'echo 15\n',
        for (final f in heavy) f: 'void main() {}\n${'// pad\n' * 6000}',
      });
      expect(out, containsPair('unit_shards', '[1,2,3,4]'));
      final per = [
        for (var i = 1; i <= 4; i++)
          File(
            p.join(pl.rt, 'ci', 'shards', 'unit-shard-$i.txt'),
          ).readAsLinesSync(),
      ];
      for (var i = 0; i < 4; i++) {
        expect(
          per[i].where(heavy.contains),
          hasLength(1),
          reason: 'shard ${i + 1}: ${per[i].where(heavy.contains)}',
        );
      }
      expect(per.expand((x) => x).toSet(), universe.toSet());
      // And the proof still holds with the weighted lists.
      pl.runTestJob(out);
      final tr = pl.testsRan(out, floor: 1);
      expect(tr.code, 0, reason: tr.output);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('S-L1: a shard artifact carrying another job\'s stream name is '
        'rejected; unknown events-* artifacts and symlinks too', () {
      final out = pl.select({'tool/ci/x.sh': 'echo 16\n'});
      pl.runTestJob(out);
      expect(pl.testsRan(out, floor: 1).code, 0);

      ({int code, String output}) with_(void Function(Directory dl) t) =>
          pl.testsRan(out, floor: 1, tamper: t);

      // events-unit-1 also uploads a file named like shard 2's stream.
      var r = with_((dl) {
        File(
          p.join(dl.path, 'events-unit-2', 'unit-2-events.json'),
        ).copySync(p.join(dl.path, 'events-unit-1', 'unit-2-events.json'));
      });
      expect(r.code, isNot(0), reason: r.output);
      expect(
        r.output,
        contains("artifact events-unit-1 contains 'unit-2-events.json'"),
      );

      // events-unit-1 uploads ONLY a copy of shard 3's stream (its own is gone):
      // it must not be accepted as shard 1's, nor displace shard 3's.
      r = with_((dl) {
        final d = Directory(p.join(dl.path, 'events-unit-1'));
        for (final f in d.listSync()) {
          f.deleteSync();
        }
        File(
          p.join(dl.path, 'events-unit-3', 'unit-3-events.json'),
        ).copySync(p.join(d.path, 'unit-3-events.json'));
      });
      expect(r.code, isNot(0), reason: r.output);
      expect(r.output, contains("contains 'unit-3-events.json'"));

      // An artifact outside the table.
      r = with_((dl) {
        Directory(p.join(dl.path, 'events-evil')).createSync();
        File(
          p.join(dl.path, 'events-evil', 'unit-1-events.json'),
        ).writeAsStringSync('{}\n');
      });
      expect(r.code, isNot(0), reason: r.output);
      expect(r.output, contains("unknown event artifact 'events-evil'"));

      // A symlinked stream.
      r = with_((dl) {
        final f = File(p.join(dl.path, 'events-unit-1', 'unit-1-events.json'));
        final target = p.join(dl.parent.path, 'real-stream.json');
        f.renameSync(target);
        Link(f.path).createSync(target);
      });
      expect(r.code, isNot(0), reason: r.output);
      expect(r.output, contains('not a regular file'));

      // Bootstrap: a base without collect_events.sh merges flat, loudly.
      final boot = pl.testsRan(out, floor: 1, withCollector: false);
      expect(boot.code, 0, reason: boot.output);
      expect(
        boot.output,
        contains('::warning::base commit has no tool/ci/collect_events.sh'),
      );
    }, timeout: e2eTimeout);
  }, skip: skip);
}
