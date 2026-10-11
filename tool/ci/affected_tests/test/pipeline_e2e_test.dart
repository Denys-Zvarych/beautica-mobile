@Tags(['e2e', 'e2e-a'])
library;

/// Phase 400 end-to-end (part 1 of 4; see support_pipeline.dart): the REAL
/// workflow step scripts, executed in order on a synthetic git repo, the way
/// GitHub runs them: Select tests -> resolver -> test job -> tests-ran, the
/// TZ subset, the per-stream fail-closed shapes and full-mode parity with the
/// pre-400 workflow. Split over four files (audit F6) so `dart test` runs the
/// slow scenarios in parallel; each file owns its own fixture repo.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';
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

  group('pipeline e2e: Select tests -> resolver -> test job -> tests-ran', () {
    test('one-feature diff: only that feature\'s unit + golden file run; '
        'no TZ step invokes flutter', () {
      final out = pl.select({'lib/features/foo/foo.dart': 'int foo = 2;\n'});

      expect(out, containsPair('mode', 'selective'));
      expect(out, containsPair('run_all', 'false'));
      expect(out, containsPair('unit_count', '1'));
      expect(out, containsPair('golden_count', '1'));
      expect(out, containsPair('tz_count', '0'));
      expect(out, containsPair('test_count', '2'));

      expect(out, containsPair('unit_shards', '[1]'));
      final calls = pl.runTestJob(out);
      expect(calls.map((c) => c.step), ['Test', 'Golden regression tests']);
      expect(calls[0].files, ['test/features/foo/foo_test.dart']);
      expect(calls[0].args, containsAllInOrder(['--exclude-tags', 'golden']));
      expect(calls[0].args, isNot(contains('--coverage')));
      expect(calls[0].tz, '');
      expect(calls[1].files, ['test/golden/foo_golden_test.dart']);

      final tr = pl.testsRan(out);
      expect(tr.code, 0, reason: tr.output);
      expect(tr.output, contains('events/unit-1-events.json'));
      expect(tr.output, contains('events/golden-events.json'));
    }, timeout: e2eTimeout);

    test(
      'docs-only diff: mode none, unit/tz/golden jobs and tests-ran skipped',
      () {
        final out = pl.select({'docs/readme.md': '# changed\n'});

        expect(out, containsPair('mode', 'none'));
        expect(out, containsPair('selection_count', '0'));
        expect(out, containsPair('test_count', '0'));
        expect(out, containsPair('unit_shard_count', '0'));
        for (final j in ['unit', 'tz-sweeps', 'goldens']) {
          expect(pl.jobRuns(j, out), isFalse, reason: j);
        }
        expect(pl.jobRuns('apk', out), isFalse);
        expect(pl.jobRuns('apk', out, native: true), isTrue, reason: 'D4 APK');
        expect(pl.runTestJob(out), isEmpty);
        final trIf = (jobs['tests-ran'] as YamlMap)['if'].toString();
        expect(trIf, contains("needs.plan.outputs.mode != 'none'"));
        expect(trIf, contains("needs.plan.result == 'success'"));
      },
      timeout: e2eTimeout,
    );

    test('tool/ci/** diff: forced full; 4 unit shards partition the universe '
        'with the pre-400 flags, every other step is the pre-400 command', () {
      final out = pl.select({'tool/ci/x.sh': 'echo 2\n'});

      expect(out, containsPair('mode', 'full'));
      expect(out, containsPair('run_all', 'true'));
      expect(out, containsPair('test_count', 'unknown'));
      expect(out, containsPair('unit_shards', '[1,2,3,4]'));
      expect(out, containsPair('unit_shard_count', '4'));

      final calls = pl.runTestJob(out);
      final want = pl.runPre400();
      expect(calls.map((c) => c.step), [
        'Test',
        'Test',
        'Test',
        'Test',
        'DST rail guards (market zone)',
        'Third-timezone sweep (host-clock leak detector)',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
        'Golden regression tests',
      ]);
      // The four non-unit steps: byte-identical TZ + argv to pre-400.
      String sig(Call c) => '${c.tz}|${c.args.join(' ')}';
      expect(
        [for (final c in calls.where((c) => c.step != 'Test')) sig(c)],
        [for (final c in want.where((c) => c.step != 'Test')) sig(c)],
      );
      // Unit: each shard's flags == the pre-400 flags (file list + the stream
      // name aside), and the shards partition the --all universe exactly.
      final pre = want.singleWhere((c) => c.step == 'Test');
      List<String> flags(Call c) => [
        for (final a in c.args)
          if (!a.endsWith('_test.dart'))
            a.startsWith('--file-reporter=') ? '--file-reporter' : a,
      ]..sort();
      final unitCalls = calls.where((c) => c.step == 'Test').toList();
      for (final c in unitCalls) {
        expect(flags(c), flags(pre));
        expect(c.tz, pre.tz);
        expect(c.files, isNotEmpty);
      }
      expect(
        [for (final c in unitCalls) ...c.files]..sort(),
        pl.universeUnit(),
        reason: 'union of the shards == the --all unit universe',
      );
      expect(
        {for (final c in unitCalls) ...c.files}.length,
        pl.universeUnit().length,
        reason: 'disjoint: no file ran twice',
      );

      final n = pl.universeUnit().length;
      final green = pl.testsRan(out, floor: n);
      expect(green.code, 0, reason: green.output);
      expect(green.output, contains('verify_shards green: 4 shard(s)'));
      expect(green.output, contains('tests-ran green: $n non-skipped'));
      final red = pl.testsRan(out, floor: n + 1);
      expect(red.code, isNot(0), reason: 'min_tests.txt floor must bite');
      expect(red.output, contains('floor is ${n + 1}'));
    }, timeout: e2eTimeout);

    test('plan/guard mode full: selector is never consulted', () {
      final out = pl.select(
        {'lib/features/foo/foo.dart': 'int foo = 3;\n'},
        planMode: 'full',
        shard: false,
      );
      expect(out, containsPair('mode', 'full'));
      expect(
        File(p.join(pl.rt, 'ci', 'sel', 'selection.json')).existsSync(),
        isFalse,
      );
    }, timeout: e2eTimeout);

    test('D7: selector exits non-zero (bad merge-base) -> full, full suite '
        'runs', () {
      final out = pl.select({
        'lib/features/foo/foo.dart': 'int foo = 4;\n',
      }, mergeBase: '0000000000000000000000000000000000000000');

      expect(pl.lastSelectorLog, contains('selector exited 70'));
      expect(out, containsPair('mode', 'full'));
      expect(out, containsPair('run_all', 'true'));
      expect(pl.runTestJob(out).map((c) => c.step), [
        'Test',
        'Test',
        'Test',
        'Test',
        'DST rail guards (market zone)',
        'Third-timezone sweep (host-clock leak detector)',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
        'Golden regression tests',
      ]);
    }, timeout: e2eTimeout);

    test(
      'D7: base without selector/resolver (bootstrap) -> full',
      () {
        final out = pl.select({
          'lib/features/foo/foo.dart': 'int foo = 5;\n',
        }, bootstrap: true);
        expect(out, containsPair('mode', 'full'));
        expect(pl.lastSelectorLog, contains('bootstrap'));
      },
      timeout: e2eTimeout,
    );
  }, skip: skip);

  group('TZ sweep subset (selective)', () {
    test('only selected TZ-eligible files reach Kyiv/Tokyo/Honolulu; a TZ '
        'file outside the selection never runs', () {
      final out = pl.select({'lib/shared/time/clock.dart': 'int clock = 2;\n'});

      expect(out, containsPair('mode', 'selective'));
      expect(out, containsPair('unit_count', '3'));
      expect(out, containsPair('tz_count', '2'));
      expect(out, containsPair('kyiv_count', '1'));
      expect(out, containsPair('golden_count', '0'));
      final tzList = File(
        p.join(pl.testRt, 'sel', 'tz_sweep.txt'),
      ).readAsLinesSync();
      expect(tzList, [railTest, 'test/shared/time/clock_test.dart']);

      final calls = pl.runTestJob(out);
      expect(calls.map((c) => c.step), [
        'Test',
        'DST rail guards (market zone)',
        'Third-timezone sweep (host-clock leak detector)',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
      ]);
      expect(calls[0].files, [
        railTest,
        'test/features/other/o_test.dart',
        'test/shared/time/clock_test.dart',
      ]);
      expect([calls[1].tz, ...calls[1].files], ['Europe/Kyiv', railTest]);
      expect([calls[2].tz, ...calls[2].files], ['Asia/Tokyo', ...tzList]);
      expect([calls[3].tz, ...calls[3].files], ['Pacific/Honolulu', ...tzList]);
      for (final c in calls) {
        expect(c.files, isNot(contains(unrelatedTzTest)), reason: c.step);
      }

      final tr = pl.testsRan(out);
      expect(tr.code, 0, reason: tr.output);
      for (final s in ['unit-1', 'tz-kyiv', 'tz-tokyo', 'tz-honolulu']) {
        expect(tr.output, contains('events/$s-events.json'));
      }
      expect(out, containsPair('tz_zones', '["kyiv-dst","tokyo","honolulu"]'));
    }, timeout: e2eTimeout);

    test(
      'TZ selection without the day-rail file: Kyiv step runs nothing',
      () {
        final out = pl.select({'lib/features/cal/cal.dart': 'int cal = 2;\n'});

        expect(out, containsPair('tz_count', '1'));
        expect(out, containsPair('kyiv_count', '0'));
        expect(out, containsPair('tz_zones', '["tokyo","honolulu"]'));
        final calls = pl.runTestJob(out);
        expect(calls.map((c) => c.step), [
          'Test',
          'Third-timezone sweep (host-clock leak detector)',
          'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
        ]);
        for (final c in calls) {
          expect(c.files, ['test/features/calendar/cal_test.dart']);
        }

        // kyiv_count 0 (base resolver) -> no Kyiv stream is owed.
        final tr = pl.testsRan(out);
        expect(tr.code, 0, reason: tr.output);
        expect(tr.output, isNot(contains('tz-kyiv')));
        expect(tr.output, isNot(contains('no kyiv_count')));

        // (a) The base resolver owes Kyiv: the PR-produced Tokyo stream (no
        // rail suite) cannot talk tests-ran out of it.
        final owed = pl.testsRan({...out, 'kyiv_count': '1'});
        expect(owed.code, isNot(0), reason: owed.output);
        expect(
          owed.output,
          contains(
            'tz-kyiv list has 1 file(s) but '
            'events/tz-kyiv-events.json is missing',
          ),
        );
      },
      timeout: e2eTimeout,
    );
  }, skip: skip);

  group('tests-ran per stream (selective) + fail-closed shapes', () {
    late Map<String, String> sel;
    setUpAll(() {
      if (!haveTools) return;
      sel = pl.select({'lib/shared/time/clock.dart': 'int clock = 3;\n'});
      pl.runTestJob(sel);
    });

    test('one all-skipped stream is RED even though the others passed', () {
      final f = File(p.join(pl.pr, 'build', 'ci', 'tz-honolulu-events.json'));
      final saved = f.readAsStringSync();
      addTearDown(() => f.writeAsStringSync(saved));
      f.writeAsStringSync(
        saved.replaceAll('"skipped":false', '"skipped":true'),
      );
      final tr = pl.testsRan(sel);
      expect(tr.code, isNot(0), reason: tr.output);
      expect(tr.output, contains('0 non-skipped tests passed'));
    });

    test('selection non-empty but no stream at all -> RED', () {
      final tr = pl.testsRan(sel, streams: false);
      expect(tr.code, isNot(0));
      expect(tr.output, contains('no event stream (fail closed)'));
    });

    test('non-zero golden_count but no golden stream -> RED', () {
      expect(sel, containsPair('golden_count', '0'));
      final tr = pl.testsRan({...sel, 'golden_count': '1'});
      expect(tr.code, isNot(0), reason: tr.output);
      expect(tr.output, contains('golden list has 1 file(s)'));
    });

    test('zero golden_count and no golden stream -> green', () {
      expect(sel, containsPair('golden_count', '0'));
      final tr = pl.testsRan(sel);
      expect(tr.code, 0, reason: tr.output);
      expect(tr.output, isNot(contains('golden-events.json')));
    });

    test('each owed stream missing on its own -> RED (unit shard, Tokyo, '
        'Honolulu, Kyiv rail via kyiv_count)', () {
      for (final s in ['unit-1', 'tz-tokyo', 'tz-honolulu', 'tz-kyiv']) {
        final tr = pl.testsRan(sel, drop: {s});
        expect(tr.code, isNot(0), reason: '$s dropped:\n${tr.output}');
        expect(
          tr.output,
          contains('events/$s-events.json is missing'),
          reason: s,
        );
      }
    });

    test('kyiv_count 1 with a Kyiv stream -> green, no fallback warning', () {
      expect(sel, containsPair('kyiv_count', '1'));
      final tr = pl.testsRan(sel);
      expect(tr.code, 0, reason: tr.output);
      expect(tr.output, contains('events/tz-kyiv-events.json'));
      expect(tr.output, isNot(contains('no kyiv_count')));
    });

    test('kyiv_count 1 and the Tokyo stream lost its rail suite: still '
        'owed (base-owned, not inferred) -> RED without a Kyiv stream', () {
      final f = File(p.join(pl.pr, 'build', 'ci', 'tz-tokyo-events.json'));
      final saved = f.readAsStringSync();
      addTearDown(() => f.writeAsStringSync(saved));
      f.writeAsStringSync(
        saved.replaceAll(railTest, 'test/x/renamed_test.dart'),
      );
      final tr = pl.testsRan(sel, drop: {'tz-kyiv'});
      expect(tr.code, isNot(0), reason: tr.output);
      expect(tr.output, contains('events/tz-kyiv-events.json is missing'));
    });

    test('empty kyiv_count (base resolver without the key): Tokyo-stream '
        'fallback + ::warning::, never a silent pass', () {
      final noKey = {...sel}..remove('kyiv_count');
      final green = pl.testsRan(noKey);
      expect(green.code, 0, reason: green.output);
      expect(
        green.output,
        contains(
          '::warning::base resolver has no kyiv_count; '
          'inferring from the Tokyo stream',
        ),
      );
      final red = pl.testsRan(noKey, drop: {'tz-kyiv'});
      expect(red.code, isNot(0), reason: red.output);
      expect(red.output, contains('no kyiv_count'));
      expect(red.output, contains('events/tz-kyiv-events.json is missing'));
    });

    test('non-numeric kyiv_count -> RED (fail closed)', () {
      final tr = pl.testsRan({...sel, 'kyiv_count': 'unknown'});
      expect(tr.code, isNot(0));
      expect(tr.output, contains("tz-kyiv count 'unknown' is not a number"));
    });

    test('non-numeric per-list count -> RED (fail closed)', () {
      final tr = pl.testsRan({...sel, 'tz_count': 'unknown'});
      expect(tr.code, isNot(0));
      expect(tr.output, contains("tz-tokyo count 'unknown' is not a number"));
    });

    test('test_count 0 (integration-only selection): no stream expected', () {
      final tr = pl.testsRan({...sel, 'test_count': '0'}, streams: false);
      expect(tr.code, 0, reason: tr.output);
    });

    test('run_all false with test_count unknown -> RED', () {
      final tr = pl.testsRan({...sel, 'test_count': 'unknown'});
      expect(tr.code, isNot(0));
    });

    test('full with no unit stream -> RED (fail closed)', () {
      final tr = pl.testsRan({
        'run_all': 'true',
        'test_count': 'unknown',
        'unit_shards': '["whole"]',
        'unit_shard_count': '1',
      }, streams: false);
      expect(tr.code, isNot(0));
      expect(tr.output, contains('unit event stream missing'));
    });

    test(
      'full with no shard outputs at all (empty unit_shard_count) -> RED',
      () {
        final tr = pl.testsRan({
          'run_all': 'true',
          'test_count': 'unknown',
        }, streams: false);
        expect(tr.code, isNot(0));
        expect(tr.output, contains('is not a positive number'));
      },
    );

    test('selective: unit_count > 0 but the unit_shard_count output is lost '
        '-> RED', () {
      final tr = pl.testsRan({...sel, 'unit_shard_count': ''});
      expect(tr.code, isNot(0), reason: tr.output);
      expect(tr.output, contains('is not a positive number'));
    });
  }, skip: skip);

  group('full-mode parity with the pre-400 workflow (static)', () {
    // Where each pre-400 step lives after the phase 402 split.
    const jobOf = {
      'Test': 'unit',
      'DST rail guards (market zone)': 'tz-sweeps',
      'Third-timezone sweep (host-clock leak detector)': 'tz-sweeps',
      'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)': 'tz-sweeps',
      'Golden regression tests': 'goldens',
    };

    test('each full branch == pinned pre-400 run, env == pre-400 env + '
        'CI_MODE (the unit step: its whole-suite branch + SHARD)', () {
      for (final name in testSteps) {
        final s = stepOf(jobs, jobOf[name]!, name);
        final env = {
          for (final e in ((s['env'] as YamlMap?) ?? YamlMap()).entries)
            e.key.toString(): e.value.toString(),
        };
        expect(env.remove('CI_MODE'), r'${{ needs.plan.outputs.mode }}');
        if (name == 'Test') {
          // Sharded: the unsharded fallback is the pre-400 command verbatim.
          expect(
            norm(
              branchOf(s['run'].toString(), r'if [ "$SHARD" = "whole" ]; then'),
            ),
            norm(pre400[name]!.run),
            reason: name,
          );
          expect(env.remove('SHARD'), r'${{ matrix.shard }}');
        } else {
          expect(
            norm(fullBranch(s['run'].toString())),
            norm(pre400[name]!.run),
            reason: name,
          );
        }
        expect(env, pre400[name]!.env, reason: name);
      }
    });

    test('the sharded unit command is run_list.sh with the pre-400 flags '
        '(--coverage only in full mode, --exclude-tags golden always)', () {
      final run = stepOf(jobs, 'unit', 'Test')['run'].toString();
      expect(run, contains('flags=(--exclude-tags golden)'));
      expect(
        run,
        contains(
          r'if [ "$CI_MODE" = "full" ]; then '
          r'flags=(--coverage "${flags[@]}"); fi',
        ),
      );
      expect(
        run,
        contains(
          r'bash tool/ci/run_list.sh '
          r'"$RUNNER_TEMP/shards/unit-shard-$SHARD.txt" '
          r'"unit-$SHARD-events" "${flags[@]}"',
        ),
      );
    });

    test('the pinned pre-400 commands match commit $pre400CommitSha', () {
      final r = Process.runSync('git', [
        '-C',
        mobile,
        'show',
        '$pre400CommitSha:.github/workflows/pr-validate.yml',
      ]);
      if (r.exitCode != 0) {
        // CI fetches the commit (selector-tests `Fetch pre-400 parity
        // commit`), so a miss there is RED; only a local shallow clone skips.
        if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
          fail('$pre400CommitSha missing on CI: ${r.stderr}');
        }
        markTestSkipped(
          '$pre400CommitSha not in this clone (shallow checkout)',
        );
        return;
      }
      final old = (loadYaml(r.stdout as String) as YamlMap)['jobs'] as YamlMap;
      for (final name in testSteps) {
        final s = stepOf(old, 'test', name);
        expect(norm(s['run'].toString()), norm(pre400[name]!.run));
        final env = {
          for (final e in ((s['env'] as YamlMap?) ?? YamlMap()).entries)
            e.key.toString(): e.value.toString(),
        };
        expect(env, pre400[name]!.env, reason: name);
        expect(s.containsKey('if'), isFalse, reason: name);
      }
    });

    test('rules.yaml tz_sweep == the Tokyo AND Honolulu full lists exactly '
        '(order too), and the Kyiv file', () {
      for (final name in [
        'Third-timezone sweep (host-clock leak detector)',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
      ]) {
        final full = fullBranch(
          stepOf(jobs, 'tz-sweeps', name)['run'].toString(),
        );
        final dirs = RegExp(
          r'(test/\S*/)',
        ).allMatches(full).map((m) => m.group(1)!).toList();
        expect(dirs, rules.tzDirs, reason: name);
      }
      final kyiv = stepOf(
        jobs,
        'tz-sweeps',
        'DST rail guards (market zone)',
      )['run'].toString();
      expect(rules.tzFiles, [railTest]);
      expect(fullBranch(kyiv), contains('flutter test $railTest '));
      expect(kyiv, contains('grep -qFx $railTest '));
    });

    test('each zone step runs only on its own matrix leg; the zones '
        'expression is the one the harness mirrors', () {
      const legs = {
        'DST rail guards (market zone)': 'kyiv-dst',
        'Third-timezone sweep (host-clock leak detector)': 'tokyo',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)':
            'honolulu',
      };
      for (final e in legs.entries) {
        expect(
          stepOf(jobs, 'tz-sweeps', e.key)['if'],
          "matrix.zone == '${e.value}'",
        );
      }
      final outs = (jobs['plan'] as YamlMap)['outputs'] as YamlMap;
      expect(outs['tz_zones'], tzZonesExpr);
    });
  }, skip: skip);
}
