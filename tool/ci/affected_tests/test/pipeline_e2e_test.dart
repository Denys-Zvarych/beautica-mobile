import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

/// Phase 400 end-to-end: the REAL workflow step scripts, executed in order on
/// a synthetic git repo, the way GitHub runs them.
///
///   plan:  `Select tests` (base selector + resolve_selection.sh, real)
///   test:  the five test steps (`if:` evaluated, `run:` executed with a stub
///          `flutter` that logs argv + TZ and writes a passing JSON stream)
///   tests-ran: `Verify tests actually ran` (real tests_ran.sh)
///
/// Plus full-mode parity: every `full` branch is the pre-400 command + env,
/// pinned below from commit [_pre400Sha] (the last pre-400 workflow).
void main() {
  final mobile = p.normalize(p.join(Directory.current.path, '..', '..', '..'));
  final wfFile = File(
    p.join(mobile, '.github', 'workflows', 'pr-validate.yml'),
  );
  final haveTools =
      wfFile.existsSync() &&
      _which('git') &&
      _which('jq') &&
      _which('bash') &&
      _which('dart');
  final skip = haveTools
      ? false
      : 'needs the beautica-mobile tree + git/jq/dart';

  late YamlMap jobs;
  late _Pipeline pl;
  setUpAll(() {
    if (!haveTools) return;
    jobs = (loadYaml(wfFile.readAsStringSync()) as YamlMap)['jobs'] as YamlMap;
    pl = _Pipeline(mobile, jobs);
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

      final calls = pl.runTestJob(out);
      expect(calls.map((c) => c.step), ['Test', 'Golden regression tests']);
      expect(calls[0].files, ['test/features/foo/foo_test.dart']);
      expect(calls[0].args, containsAllInOrder(['--exclude-tags', 'golden']));
      expect(calls[0].args, isNot(contains('--coverage')));
      expect(calls[0].tz, '');
      expect(calls[1].files, ['test/golden/foo_golden_test.dart']);

      final tr = pl.testsRan(out);
      expect(tr.code, 0, reason: tr.output);
      expect(tr.output, contains('events/unit-events.json'));
      expect(tr.output, contains('events/golden-events.json'));
    }, timeout: e2eTimeout);

    test(
      'docs-only diff: mode none, test job and tests-ran skipped',
      () {
        final out = pl.select({'docs/readme.md': '# changed\n'});

        expect(out, containsPair('mode', 'none'));
        expect(out, containsPair('selection_count', '0'));
        expect(out, containsPair('test_count', '0'));
        expect(pl.testJobRuns(out, native: false), isFalse);
        expect(pl.testJobRuns(out, native: true), isTrue, reason: 'D4 APK');
        expect(pl.runTestJob(out), isEmpty);
        expect(
          (jobs['tests-ran'] as YamlMap)['if'].toString().trim(),
          "needs.test.result == 'success'",
          reason: 'a skipped test job must skip tests-ran too',
        );
      },
      timeout: e2eTimeout,
    );

    test('tool/ci/** diff: forced full; every step runs the pre-400 command '
        'with the pre-400 env', () {
      final out = pl.select({'tool/ci/x.sh': 'echo 2\n'});

      expect(out, containsPair('mode', 'full'));
      expect(out, containsPair('run_all', 'true'));
      expect(out, containsPair('test_count', 'unknown'));

      final calls = pl.runTestJob(out);
      final want = pl.runPre400();
      expect(calls.map((c) => c.step), _testSteps);
      expect(
        [for (final c in calls) '${c.tz}|${c.args.join(' ')}'],
        [for (final c in want) '${c.tz}|${c.args.join(' ')}'],
      );

      final green = pl.testsRan(out, floor: _Pipeline.fullPasses);
      expect(green.code, 0, reason: green.output);
      final red = pl.testsRan(out, floor: _Pipeline.fullPasses + 1);
      expect(red.code, isNot(0), reason: 'min_tests.txt floor must bite');
      expect(red.output, contains('floor is ${_Pipeline.fullPasses + 1}'));
    }, timeout: e2eTimeout);

    test('plan/guard mode full: selector is never consulted', () {
      final out = pl.select({
        'lib/features/foo/foo.dart': 'int foo = 3;\n',
      }, planMode: 'full');
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
      expect(pl.runTestJob(out).map((c) => c.step), _testSteps);
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

  group('phase 401: integration entry (plan -> D4 if -> Choose entry)', () {
    // The `integration` job's D4 `if:` reduced to the plan outputs it reads.
    bool integrationRuns(Map<String, String> out) {
      final cond = (jobs['integration'] as YamlMap)['if'].toString();
      expect(
        cond,
        contains(
          "(needs.plan.outputs.mode == 'full' || "
          "needs.plan.outputs.integration_count != '0')",
        ),
      );
      return out['mode'] == 'full' || out['integration_count'] != '0';
    }

    test('integration_count is the length of the selection\'s integration '
        'list; one changed flow selects exactly that flow', () {
      final out = pl.select({'integration_test/x_test.dart': '// c\n'});
      expect(out, containsPair('mode', 'selective'));
      expect(out, containsPair('integration_count', '1'));
      expect(
        File(p.join(pl.testRt, 'sel', 'integration.txt')).readAsLinesSync(),
        ['integration_test/x_test.dart'],
      );
      expect(integrationRuns(out), isTrue);
    });

    test('docs-only (mode none) -> integration_count 0 -> job skipped', () {
      final out = pl.select({'docs/readme.md': '# changed\n'});
      expect(out, containsPair('mode', 'none'));
      expect(out, containsPair('integration_count', '0'));
      expect(integrationRuns(out), isFalse);
    });

    test('a unit-only selection (no flow) -> integration skipped', () {
      final out = pl.select({'lib/features/foo/foo.dart': 'int foo = 9;\n'});
      expect(out, containsPair('mode', 'selective'));
      expect(out, containsPair('integration_count', '0'));
      expect(integrationRuns(out), isFalse);
    });

    test('non-selective plan (push/dispatch/nightly) -> full -> job runs, '
        'and no entry is chosen (parts)', () {
      final out = pl.select({
        'lib/features/foo/foo.dart': 'int foo = 10;\n',
      }, planMode: 'full');
      expect(out, containsPair('mode', 'full'));
      expect(out, containsPair('integration_count', 'unknown'));
      expect(integrationRuns(out), isTrue);
      final s = pl.step(
        'integration',
        'Choose integration entry (selected '
            'flows or the two parts)',
      );
      expect(s['if'], "needs.plan.outputs.mode == 'selective'");
    });

    test(
      'selective: the REAL Choose step writes the entry for the one flow',
      () {
        final out = pl.select({'integration_test/x_test.dart': '// c2\n'});
        final r = pl.chooseEntry(
          out,
          partFlows: [
            ['x', for (var i = 0; i < 9; i++) 'p1_$i'],
            [for (var i = 0; i < 10; i++) 'p2_$i'],
          ],
        );
        expect(r.outputs['entry'], 'selected', reason: r.log);
        final entry = File(r.entryPath);
        expect(entry.existsSync(), isTrue);
        expect(entry.readAsStringSync(), contains("group('x', x.main);"));
        expect(r.summary, contains("group('x', x.main);"));
      },
    );

    test('D3: the flow IS most of a part -> parts, no file', () {
      final out = pl.select({'integration_test/x_test.dart': '// c3\n'});
      final r = pl.chooseEntry(
        out,
        partFlows: [
          ['x'],
          ['y', 'z'],
        ],
      );
      expect(r.outputs['entry'], 'parts', reason: r.log);
      expect(File(r.entryPath).existsSync(), isFalse);
    });

    test('bootstrap: base has no generator -> parts (fail-safe)', () {
      final out = pl.select({'integration_test/x_test.dart': '// c4\n'});
      final r = pl.chooseEntry(
        out,
        partFlows: [
          ['x', for (var i = 0; i < 9; i++) 'p1_$i'],
          [for (var i = 0; i < 10; i++) 'p2_$i'],
        ],
        withGenerator: false,
      );
      expect(r.outputs['entry'], 'parts', reason: r.log);
      expect(File(r.entryPath).existsSync(), isFalse);
    });

    group('audit cycle 1: Choose step against hostile / broken generators', () {
      final parts = [
        ['x', for (var i = 0; i < 9; i++) 'p1_$i'],
        [for (var i = 0; i < 10; i++) 'p2_$i'],
      ];
      var n = 0;
      Map<String, String> one() =>
          pl.select({'integration_test/x_test.dart': '// audit ${n++}\n'});

      String fake(String body) =>
          "import 'dart:io';\n"
          'void main(List<String> a) {\n'
          "  final repo = a[a.indexOf('--repo') + 1];\n"
          '$body\n}\n';
      String writes(String stdoutLines) => fake(
        "  File('\$repo/integration_test/ci_selected_tests.dart')"
        ".writeAsStringSync('// fake\\n');\n$stdoutLines",
      );

      test(
        'Q1: a CRASHING generator -> parts, step exits 0, no entry file',
        () {
          final r = pl.chooseEntry(
            one(),
            partFlows: parts,
            fakeGenerator: fake("  stderr.writeln('boom'); exit(70);"),
          );
          expect(r.outputs['entry'], 'parts', reason: r.log);
          expect(r.outputs['bound'], '1500');
          expect(File(r.entryPath).existsSync(), isFalse);
        },
      );

      test('Q1: a generator that prints NO entry= line -> parts', () {
        final r = pl.chooseEntry(
          one(),
          partFlows: parts,
          fakeGenerator: fake("  print('hello');"),
        );
        expect(r.outputs['entry'], 'parts', reason: r.log);
        expect(File(r.entryPath).existsSync(), isFalse);
      });

      test('Q1: entry=selected but a file left behind with no/odd count -> '
          'parts and the file is removed', () {
        for (final lines in [
          "  print('entry=selected');",
          "  print('entry=selected'); print('count=abc');",
          "  print('entry=selected'); print('count=0');",
          "  print('entry=selected'); print('count=41');",
          "  print('entry=selected'); print('count=2'); print('entry=parts');",
          "  print('entry=parts'); print('count=2');",
        ]) {
          final r = pl.chooseEntry(
            one(),
            partFlows: parts,
            fakeGenerator: writes(lines),
          );
          expect(r.outputs['entry'], 'parts', reason: '$lines\n${r.log}');
          expect(File(r.entryPath).existsSync(), isFalse, reason: lines);
        }
      });

      test('P3: bound = clamp(420 + 45 * count, 600, 1500)', () {
        const want = {
          1: '600',
          3: '600',
          4: '600',
          5: '645',
          10: '870',
          24: '1500',
          25: '1500',
          40: '1500',
        };
        want.forEach((count, bound) {
          final r = pl.chooseEntry(
            one(),
            partFlows: parts,
            fakeGenerator: writes(
              "  print('entry=selected'); print('count=$count');",
            ),
          );
          expect(r.outputs['entry'], 'selected', reason: r.log);
          expect(r.outputs['count'], '$count');
          expect(r.outputs['bound'], bound, reason: 'count=$count');
          expect(r.summary, contains('per-attempt bound ${bound}s'));
        });
      });

      test('base without run_it_attempt.sh -> parts even if the generator '
          'says selected', () {
        final r = pl.chooseEntry(
          one(),
          partFlows: parts,
          withAttemptScript: false,
          fakeGenerator: writes("  print('entry=selected'); print('count=2');"),
        );
        expect(r.outputs['entry'], 'parts', reason: r.log);
        expect(File(r.entryPath).existsSync(), isFalse);
      });

      final realGen = File(
        p.join(
          p.normalize(p.join(Directory.current.path, '..', '..', '..')),
          'tool',
          'ci',
          'affected_tests',
          'bin',
          'gen_integration_entry.dart',
        ),
      ).readAsStringSync();

      test('S1: a PR-committed dangling symlink at the entry path is not '
          'written through (REAL generator)', () {
        final outside = p.join(pl.ws, 'outside_target.dart');
        final r = pl.chooseEntry(
          one(),
          partFlows: parts,
          fakeGenerator: realGen,
          beforeStep: (pr) => Link(
            p.join(pr, 'integration_test', 'ci_selected_tests.dart'),
          ).createSync(outside),
        );
        expect(File(outside).existsSync(), isFalse, reason: 'write-through');
        expect(r.outputs['entry'], 'selected', reason: r.log);
        expect(
          FileSystemEntity.typeSync(r.entryPath, followLinks: false),
          FileSystemEntityType.file,
        );
      });

      test('S1: the workflow step itself clears a planted symlink even when '
          'the generator is absent (parts)', () {
        final outside = p.join(pl.ws, 'outside_target2.dart');
        final r = pl.chooseEntry(
          one(),
          partFlows: parts,
          withGenerator: false,
          beforeStep: (pr) => Link(
            p.join(pr, 'integration_test', 'ci_selected_tests.dart'),
          ).createSync(outside),
        );
        expect(r.outputs['entry'], 'parts', reason: r.log);
        expect(
          FileSystemEntity.typeSync(r.entryPath, followLinks: false),
          FileSystemEntityType.notFound,
        );
        expect(File(outside).existsSync(), isFalse);
      });

      test('S3: a hostile .dart_tool/package_config.json in the PR tree does '
          'not reach the generator', () {
        final r = pl.chooseEntry(
          one(),
          partFlows: parts,
          fakeGenerator: realGen,
          beforeStep: (pr) =>
              File(p.join(pr, '.dart_tool', 'package_config.json'))
                ..createSync(recursive: true)
                ..writeAsStringSync('{ not json'),
        );
        expect(r.outputs['entry'], 'selected', reason: r.log);
      });
    });

    group('S2: trusted/ shadowing', () {
      late Directory w;
      setUp(() => w = Directory.systemTemp.createTempSync('s2_'));
      tearDown(() => w.deleteSync(recursive: true));

      void plant() {
        // What a PR can commit at the top level: files, and a symlink.
        File(p.join(w.path, 'trusted', 'tool', 'ci', 'run_it_attempt.sh'))
          ..createSync(recursive: true)
          ..writeAsStringSync('echo pwned');
      }

      ProcessResult remove() => pl.runStep(
        'integration',
        'Remove any PR-made trusted/ path',
        env: {'GITHUB_WORKSPACE': w.path, 'RUNNER_TEMP': w.path},
        cwd: w.path,
      );
      ProcessResult verify(String expected) => pl.runStep(
        'integration',
        'Verify the trusted checkout is the base commit',
        env: {
          'GITHUB_WORKSPACE': w.path,
          'RUNNER_TEMP': w.path,
          'EXPECTED_SHA': expected,
        },
        cwd: w.path,
      );
      String git(String dir, List<String> a) {
        final r = Process.runSync('git', [
          '-C',
          dir,
          '-c',
          'user.email=t@t',
          '-c',
          'user.name=t',
          '-c',
          'commit.gpgsign=false',
          ...a,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        return (r.stdout as String).trim();
      }

      test('remove clears a PR-made directory AND a PR-made symlink', () {
        plant();
        expect(remove().exitCode, 0);
        expect(Directory(p.join(w.path, 'trusted')).existsSync(), isFalse);
        final outside = Directory(p.join(w.path, 'elsewhere'))..createSync();
        Link(p.join(w.path, 'trusted')).createSync(outside.path);
        expect(remove().exitCode, 0);
        expect(
          FileSystemEntity.typeSync(
            p.join(w.path, 'trusted'),
            followLinks: false,
          ),
          FileSystemEntityType.notFound,
        );
        expect(outside.existsSync(), isTrue, reason: 'target not followed');
      });

      test('verify passes for a genuine checkout at the base sha', () {
        // The workspace itself is the (PR) repo, as in the job.
        git(w.path, ['init', '-q', '-b', 'main']);
        File(p.join(w.path, 'f')).writeAsStringSync('pr');
        git(w.path, ['add', '-A']);
        git(w.path, ['commit', '-q', '-m', 'pr']);
        final t = p.join(w.path, 'trusted');
        Directory(t).createSync();
        git(t, ['init', '-q', '-b', 'main']);
        File(p.join(t, 'g')).writeAsStringSync('base');
        git(t, ['add', '-A']);
        git(t, ['commit', '-q', '-m', 'base']);
        final base = git(t, ['rev-parse', 'HEAD']);
        final ok = verify(base);
        expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
        final wrong = verify(git(w.path, ['rev-parse', 'HEAD']));
        expect(wrong.exitCode, isNot(0), reason: 'HEAD != base sha');
      });

      test('verify FAILS for a PR-planted plain directory (no .git) even '
          'inside a git workspace whose HEAD is the expected sha', () {
        git(w.path, ['init', '-q', '-b', 'main']);
        plant();
        git(w.path, ['add', '-A']);
        git(w.path, ['commit', '-q', '-m', 'pr']);
        final r = verify(git(w.path, ['rev-parse', 'HEAD']));
        expect(r.exitCode, isNot(0), reason: '${r.stdout}${r.stderr}');
      });

      test('verify FAILS for a symlinked trusted/ pointing at a real repo', () {
        final real = Directory(p.join(w.path, 'real'))..createSync();
        git(real.path, ['init', '-q', '-b', 'main']);
        File(p.join(real.path, 'g')).writeAsStringSync('x');
        git(real.path, ['add', '-A']);
        git(real.path, ['commit', '-q', '-m', 'x']);
        Link(p.join(w.path, 'trusted')).createSync(real.path);
        final r = verify(git(real.path, ['rev-parse', 'HEAD']));
        expect(r.exitCode, isNot(0), reason: '${r.stdout}${r.stderr}');
      });
    });
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
      expect(tzList, [_rail, 'test/shared/time/clock_test.dart']);

      final calls = pl.runTestJob(out);
      expect(calls.map((c) => c.step), [
        'Test',
        'DST rail guards (market zone)',
        'Third-timezone sweep (host-clock leak detector)',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
      ]);
      expect(calls[0].files, [
        _rail,
        'test/features/other/o_test.dart',
        'test/shared/time/clock_test.dart',
      ]);
      expect([calls[1].tz, ...calls[1].files], ['Europe/Kyiv', _rail]);
      expect([calls[2].tz, ...calls[2].files], ['Asia/Tokyo', ...tzList]);
      expect([calls[3].tz, ...calls[3].files], ['Pacific/Honolulu', ...tzList]);
      for (final c in calls) {
        expect(c.files, isNot(contains(_unrelatedTz)), reason: c.step);
      }

      final tr = pl.testsRan(out);
      expect(tr.code, 0, reason: tr.output);
      for (final s in ['unit', 'tz-kyiv', 'tz-tokyo', 'tz-honolulu']) {
        expect(tr.output, contains('events/$s-events.json'));
      }
    }, timeout: e2eTimeout);

    test(
      'TZ selection without the day-rail file: Kyiv step runs nothing',
      () {
        final out = pl.select({'lib/features/cal/cal.dart': 'int cal = 2;\n'});

        expect(out, containsPair('tz_count', '1'));
        expect(out, containsPair('kyiv_count', '0'));
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

    test('each owed stream missing on its own -> RED (unit, Tokyo, Honolulu, '
        'Kyiv rail via kyiv_count)', () {
      for (final s in ['unit', 'tz-tokyo', 'tz-honolulu', 'tz-kyiv']) {
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
      f.writeAsStringSync(saved.replaceAll(_rail, 'test/x/renamed_test.dart'));
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
      }, streams: false);
      expect(tr.code, isNot(0));
      expect(tr.output, contains('unit event stream missing'));
    });
  }, skip: skip);

  group('full-mode parity with the pre-400 workflow (static)', () {
    test('each full branch == pinned pre-400 run, env == pre-400 env + '
        'CI_MODE', () {
      for (final name in _testSteps) {
        final s = _step(jobs, 'test', name);
        final full = _fullBranch(s['run'].toString());
        expect(_norm(full), _norm(_pre400[name]!.run), reason: name);
        final env = {
          for (final e in ((s['env'] as YamlMap?) ?? YamlMap()).entries)
            e.key.toString(): e.value.toString(),
        };
        expect(env.remove('CI_MODE'), r'${{ needs.plan.outputs.mode }}');
        expect(env, _pre400[name]!.env, reason: name);
      }
    });

    test('the pinned pre-400 commands match commit $_pre400Sha', () {
      final r = Process.runSync('git', [
        '-C',
        mobile,
        'show',
        '$_pre400Sha:.github/workflows/pr-validate.yml',
      ]);
      if (r.exitCode != 0) {
        // CI fetches the commit (selector-tests `Fetch pre-400 parity
        // commit`), so a miss there is RED; only a local shallow clone skips.
        if (Platform.environment['GITHUB_ACTIONS'] == 'true') {
          fail('$_pre400Sha missing on CI: ${r.stderr}');
        }
        markTestSkipped('$_pre400Sha not in this clone (shallow checkout)');
        return;
      }
      final old = (loadYaml(r.stdout as String) as YamlMap)['jobs'] as YamlMap;
      for (final name in _testSteps) {
        final s = _step(old, 'test', name);
        expect(_norm(s['run'].toString()), _norm(_pre400[name]!.run));
        final env = {
          for (final e in ((s['env'] as YamlMap?) ?? YamlMap()).entries)
            e.key.toString(): e.value.toString(),
        };
        expect(env, _pre400[name]!.env, reason: name);
        expect(s.containsKey('if'), isFalse, reason: name);
      }
    });

    test('rules.yaml tz_sweep == the Tokyo AND Honolulu full lists exactly '
        '(order too), and the Kyiv file', () {
      for (final name in [
        'Third-timezone sweep (host-clock leak detector)',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
      ]) {
        final full = _fullBranch(_step(jobs, 'test', name)['run'].toString());
        final dirs = RegExp(
          r'(test/\S*/)',
        ).allMatches(full).map((m) => m.group(1)!).toList();
        expect(dirs, rules.tzDirs, reason: name);
      }
      final kyiv = _step(
        jobs,
        'test',
        'DST rail guards (market zone)',
      )['run'].toString();
      expect(rules.tzFiles, [_rail]);
      expect(_fullBranch(kyiv), contains('flutter test $_rail '));
      expect(kyiv, contains('grep -qFx $_rail '));
    });
  }, skip: skip);
}

const _pre400Sha = '7b85cb18c809319fa1fd8519349e307dc9498cf4';
const _rail = 'test/features/booking/presentation/bookings_day_rail_test.dart';
const _unrelatedTz = 'test/core/time/unrelated_test.dart';

const _testSteps = [
  'Test',
  'DST rail guards (market zone)',
  'Third-timezone sweep (host-clock leak detector)',
  'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
  'Golden regression tests',
];

const _tzDirsCmd = r'''
flutter test \
  test/features/booking/ \
  test/features/schedule/ \
  test/features/home/ \
  test/features/calendar/ \
  test/shared/formatters/ \
  test/shared/time/ \
  test/shared/calendar/ \
  test/core/time/ \
  test/routing/ \
  --reporter=expanded
''';

/// Verbatim from [_pre400Sha] (job `test`, the last pre-400 workflow).
const Map<String, ({Map<String, String> env, String run})> _pre400 = {
  'Test': (
    env: {},
    run:
        'mkdir -p build/ci\n'
        'flutter test --coverage --reporter=expanded '
        '--file-reporter=json:build/ci/unit-events.json --exclude-tags golden',
  ),
  'DST rail guards (market zone)': (
    env: {'TZ': 'Europe/Kyiv'},
    run: 'flutter test $_rail --reporter=expanded',
  ),
  'Third-timezone sweep (host-clock leak detector)': (
    env: {'TZ': 'Asia/Tokyo'},
    run: _tzDirsCmd,
  ),
  'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)': (
    env: {'TZ': 'Pacific/Honolulu'},
    run: _tzDirsCmd,
  ),
  'Golden regression tests': (
    env: {},
    run: 'flutter test test/golden/ --reporter=expanded',
  ),
};

bool _which(String bin) =>
    Process.runSync('bash', ['-c', 'command -v $bin']).exitCode == 0;

YamlMap _step(YamlMap jobs, String job, String name) {
  final steps = (jobs[job] as YamlMap)['steps'] as YamlList;
  final hits = [
    for (final s in steps.cast<YamlMap>())
      if (s['name'] == name) s,
  ];
  expect(hits, hasLength(1), reason: '$job: step "$name"');
  return hits.single;
}

/// Body of the `if [ "$CI_MODE" = "full" ]; then ... else|elif` branch.
String _fullBranch(String run) {
  final lines = run.split('\n');
  final start = lines.indexWhere(
    (l) => l.trim() == 'if [ "\$CI_MODE" = "full" ]; then',
  );
  expect(start, isNot(-1), reason: 'no full branch in:\n$run');
  final end = lines.indexWhere(
    (l) => RegExp(r'^\s*(else|elif)\b').hasMatch(l),
    start + 1,
  );
  expect(end, isNot(-1));
  return lines.sublist(start + 1, end).join('\n');
}

List<String> _norm(String s) => [
  for (final l in s.split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

final _condRe = RegExp(
  r"^needs\.plan\.outputs\.mode == 'full' \|\| \(needs\.plan\.outputs\.mode "
  r"== 'selective' && needs\.plan\.outputs\.(\w+) != '0'\)$",
);

final class _Call {
  _Call(this.step, this.tz, this.args);
  final String step;
  final String tz;
  final List<String> args;
  List<String> get files => [
    for (final a in args)
      if (a.endsWith('_test.dart')) a,
  ];
}

final class _Pipeline {
  _Pipeline(this.mobile, this.jobs)
    : ws = Directory.systemTemp.createTempSync('pipe_e2e_').path {
    final sel = p.join(mobile, 'tool', 'ci', 'affected_tests');
    final trusted = Directory(p.join(ws, 'trusted', 'tool', 'ci'))
      ..createSync(recursive: true);
    Link(p.join(trusted.path, 'affected_tests')).createSync(sel);
    Link(
      p.join(trusted.path, 'resolve_selection.sh'),
    ).createSync(p.join(mobile, 'tool', 'ci', 'resolve_selection.sh'));
    Link(
      p.join(trusted.path, 'run_it_attempt.sh'),
    ).createSync(p.join(mobile, 'tool', 'ci', 'run_it_attempt.sh'));
    Directory(p.join(ws2, 'trusted')).createSync(recursive: true);
    Link(p.join(ws2, 'pr')).createSync(pr);

    final stub = File(p.join(ws, 'bin', 'flutter'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_stubFlutter);
    Process.runSync('chmod', ['+x', stub.path]);

    final files = <String, String>{
      'lib/features/foo/foo.dart': 'int foo = 1;\n',
      'lib/features/cal/cal.dart': 'int cal = 1;\n',
      'lib/shared/time/clock.dart': 'int clock = 1;\n',
      'test/features/foo/foo_test.dart': pkg('features/foo/foo.dart'),
      'test/golden/foo_golden_test.dart': pkg('features/foo/foo.dart'),
      'test/features/calendar/cal_test.dart': pkg('features/cal/cal.dart'),
      'test/shared/time/clock_test.dart': pkg('shared/time/clock.dart'),
      'test/features/other/o_test.dart': pkg('shared/time/clock.dart'),
      _rail: pkg('shared/time/clock.dart'),
      _unrelatedTz: 'void main() {}\n',
      ...filler(60),
      'api/lib/x.dart': '\n',
      'api/pubspec.yaml': 'name: beautica_api\n',
      'integration_test/x_test.dart': 'void main() {}\n',
      'docs/readme.md': '# r\n',
      'tool/ci/x.sh': 'echo 1\n',
      for (final s in ['run_list.sh', 'report_failures.sh'])
        'tool/ci/$s': File(p.join(mobile, 'tool', 'ci', s)).readAsStringSync(),
    };
    for (final e in files.entries) {
      (File(
        p.join(pr, e.key),
      )..createSync(recursive: true)).writeAsStringSync(e.value);
    }
    _git(['init', '-q', '-b', 'main']);
    _git(['add', '-A']);
    _git(['commit', '-q', '-m', 'base']);
    baseSha = _git(['rev-parse', 'HEAD']).trim();
  }

  static const fullPasses = 5;

  final String mobile;
  final YamlMap jobs;
  final String ws;
  String get ws2 => '$ws-bootstrap';
  String get pr => p.join(ws, 'pr');
  String get rt => p.join(ws, 'rt');
  String get testRt => p.join(ws, 'rt_test');
  late final String baseSha;
  String lastSelectorLog = '';

  void dispose() {
    for (final d in [ws, ws2]) {
      if (Directory(d).existsSync()) Directory(d).deleteSync(recursive: true);
    }
  }

  String _git(List<String> a) {
    final r = Process.runSync('git', [
      '-C',
      pr,
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      '-c',
      'commit.gpgsign=false',
      ...a,
    ]);
    expect(r.exitCode, 0, reason: '${a.join(' ')}: ${r.stderr}');
    return r.stdout as String;
  }

  /// Host env minus everything that could route a step around the stub
  /// `flutter` (or move what it writes): run_list.sh prefers `FLUTTER` over
  /// PATH and honours `RUN_LIST_OUT_DIR`; `BASH_ENV`/`ENV` and exported
  /// `BASH_FUNC_*` functions could define a `flutter` that shadows the stub;
  /// `UNIT_WARN_THRESHOLD` steers resolve_selection.sh.
  Map<String, String> get _baseEnv {
    final env = Map<String, String>.of(Platform.environment)
      ..remove('TZ')
      ..remove('GITHUB_OUTPUT')
      ..remove('GITHUB_STEP_SUMMARY')
      ..remove('FLUTTER')
      ..remove('RUN_LIST_OUT_DIR')
      ..remove('BASH_ENV')
      ..remove('ENV')
      ..remove('UNIT_WARN_THRESHOLD')
      ..removeWhere((k, _) => k.startsWith('BASH_FUNC_'));
    env['PATH'] = '${p.join(ws, 'bin')}:${env['PATH']}';
    return env;
  }

  /// Commits [changes] on top of base and runs the REAL `Select tests` step.
  /// Returns its GITHUB_OUTPUT (last value per key).
  Map<String, String> select(
    Map<String, String> changes, {
    String planMode = 'selective',
    String? mergeBase,
    bool bootstrap = false,
  }) {
    _git(['checkout', '-q', '-f', '-B', 'scenario', baseSha]);
    _git(['clean', '-qfdx']);
    for (final e in changes.entries) {
      File(p.join(pr, e.key)).writeAsStringSync(e.value);
    }
    _git(['commit', '-q', '-am', 'scenario']);

    for (final d in [rt, testRt]) {
      if (Directory(d).existsSync()) Directory(d).deleteSync(recursive: true);
    }
    Directory(p.join(rt, 'ci')).createSync(recursive: true);
    Directory(testRt).createSync(recursive: true);
    File(p.join(rt, 'ci', 'changes.txt')).writeAsStringSync(
      _git([
        '-c',
        'core.quotepath=false',
        'diff',
        '--name-status',
        '-M',
        baseSha,
        'HEAD',
      ]),
    );
    final ghOut = File(p.join(rt, 'gh_output'))..writeAsStringSync('');
    final r = _bash(
      _step(jobs, 'plan', 'Select tests (selector from the BASE commit)'),
      env: {
        'PLAN_MODE': planMode,
        'GUARD_MODE': '',
        'MERGE_BASE': mergeBase ?? baseSha,
        'GITHUB_WORKSPACE': bootstrap ? ws2 : ws,
        'RUNNER_TEMP': rt,
        'GITHUB_OUTPUT': ghOut.path,
      },
      cwd: pr,
    );
    lastSelectorLog = '${r.stdout}\n${r.stderr}';
    expect(r.exitCode, 0, reason: 'Select tests step must never go red here');
    final out = <String, String>{};
    for (final l in ghOut.readAsLinesSync()) {
      final i = l.indexOf('=');
      if (i > 0) out[l.substring(0, i)] = l.substring(i + 1);
    }
    // upload-artifact (plan) -> download-artifact (test, path RUNNER_TEMP/sel)
    if (out['mode'] == 'selective') {
      final dst = Directory(p.join(testRt, 'sel'))..createSync();
      for (final f in Directory(p.join(rt, 'ci', 'sel')).listSync()) {
        if (f is File) f.copySync(p.join(dst.path, p.basename(f.path)));
      }
    }
    return out;
  }

  bool testJobRuns(Map<String, String> out, {required bool native}) {
    final cond = (jobs['test'] as YamlMap)['if'].toString();
    expect(
      cond,
      contains(
        "(needs.plan.outputs.mode != 'none' || "
        "needs.plan.outputs.native == 'true')",
      ),
    );
    return out['mode'] != 'none' || native;
  }

  /// Executes the five test steps in workflow order; returns the flutter calls.
  List<_Call> runTestJob(Map<String, String> out) {
    final ci = Directory(p.join(pr, 'build', 'ci'));
    if (ci.existsSync()) ci.deleteSync(recursive: true);
    if (!testJobRuns(out, native: false)) return const [];
    final steps = ((jobs['test'] as YamlMap)['steps'] as YamlList)
        .cast<YamlMap>()
        .where((s) => _testSteps.contains(s['name']))
        .toList();
    expect(steps.map((s) => s['name']), _testSteps, reason: 'step order');
    final calls = <_Call>[];
    for (final s in steps) {
      final m = _condRe.firstMatch(s['if'].toString().trim());
      expect(m, isNotNull, reason: '${s['name']}: if: ${s['if']}');
      final runs =
          out['mode'] == 'full' ||
          (out['mode'] == 'selective' && out[m!.group(1)!] != '0');
      if (!runs) continue;
      final env = {
        for (final e in ((s['env'] as YamlMap?) ?? YamlMap()).entries)
          e.key.toString(): e.value.toString(),
      };
      env['CI_MODE'] = out['mode']!;
      calls.addAll(_runLogged(s['name'].toString(), s['run'].toString(), env));
    }
    return calls;
  }

  /// The pinned pre-400 commands through the same harness (parity oracle).
  List<_Call> runPre400() {
    final calls = <_Call>[];
    for (final name in _testSteps) {
      final c = _pre400[name]!;
      calls.addAll(_runLogged(name, c.run, c.env, pipefail: false));
    }
    return calls;
  }

  List<_Call> _runLogged(
    String name,
    String run,
    Map<String, String> env, {
    bool pipefail = true,
  }) {
    final log = File(p.join(ws, 'stub.log'))..writeAsStringSync('');
    final r = _bash(
      YamlMap.wrap({'run': run}),
      env: {...env, 'RUNNER_TEMP': testRt, 'STUB_LOG': log.path},
      cwd: pr,
      pipefail: pipefail,
    );
    expect(r.exitCode, 0, reason: '$name:\n${r.stdout}\n${r.stderr}');
    return [
      for (final l in log.readAsLinesSync())
        if (l.isNotEmpty)
          _Call(
            name,
            l.split('\t').first,
            l.split('\t')[1].split('\x1f')..removeLast(),
          ),
    ];
  }

  ProcessResult _bash(
    YamlMap step, {
    required Map<String, String> env,
    required String cwd,
    bool pipefail = true,
  }) {
    final script = File(p.join(ws, 'step.sh'))
      ..writeAsStringSync(step['run'].toString());
    return Process.runSync(
      'bash',
      [
        '--noprofile',
        '--norc',
        '-e',
        if (pipefail) ...['-o', 'pipefail'],
        script.path,
      ],
      workingDirectory: cwd,
      environment: {..._baseEnv, ...env},
      includeParentEnvironment: false,
    );
  }

  YamlMap step(String job, String name) => _step(jobs, job, name);

  /// Runs one REAL workflow step of [job] by name (no GITHUB_OUTPUT plumbing).
  ProcessResult runStep(
    String job,
    String name, {
    required Map<String, String> env,
    required String cwd,
  }) => _bash(_step(jobs, job, name), env: env, cwd: cwd, pipefail: false);

  /// Runs the REAL `Choose integration entry` step of the `integration` job.
  /// The job checks the PR out at $GITHUB_WORKSPACE with the base commit's
  /// tooling at $GITHUB_WORKSPACE/trusted, so `pr` doubles as that workspace
  /// here (trusted/ is linked in for the step and removed after).
  /// [partFlows] = the flow basenames of all_tests_part1/2 (untracked files).
  ({Map<String, String> outputs, String log, String summary, String entryPath})
  chooseEntry(
    Map<String, String> out, {
    required List<List<String>> partFlows,
    bool withGenerator = true,
    String? fakeGenerator,
    bool withAttemptScript = true,
    void Function(String pr)? beforeStep,
  }) {
    final trustedLink = Link(p.join(pr, 'trusted'));
    final partFiles = <File>[];
    for (var i = 0; i < partFlows.length; i++) {
      partFiles.add(
        File(p.join(pr, 'integration_test', 'all_tests_part${i + 1}.dart'))
          ..writeAsStringSync(
            [
              "import 'package:flutter_test/flutter_test.dart';",
              for (final n in partFlows[i]) "import '${n}_test.dart' as $n;",
            ].join('\n'),
          ),
      );
    }
    if (fakeGenerator != null) {
      // A REAL directory standing in for the checkout of the base commit, with
      // a stand-in generator (crash / odd output scenarios).
      final bin = Directory(
        p.join(pr, 'trusted', 'tool', 'ci', 'affected_tests', 'bin'),
      )..createSync(recursive: true);
      File(
        p.join(bin.path, 'gen_integration_entry.dart'),
      ).writeAsStringSync(fakeGenerator);
      if (withAttemptScript) {
        Link(
          p.join(pr, 'trusted', 'tool', 'ci', 'run_it_attempt.sh'),
        ).createSync(p.join(mobile, 'tool', 'ci', 'run_it_attempt.sh'));
      }
    } else if (withGenerator) {
      trustedLink.createSync(p.join(ws, 'trusted'));
    } else {
      Directory(p.join(pr, 'trusted')).createSync();
    }
    final ghOut = File(p.join(ws, 'entry_gh_output'))..writeAsStringSync('');
    final ghSum = File(p.join(ws, 'entry_gh_summary'))..writeAsStringSync('');
    final entryPath = p.join(pr, 'integration_test', 'ci_selected_tests.dart');
    try {
      beforeStep?.call(pr);
      final r = _bash(
        _step(
          jobs,
          'integration',
          'Choose integration entry (selected flows or the two parts)',
        ),
        env: {
          'GITHUB_WORKSPACE': pr,
          'RUNNER_TEMP': testRt,
          'GITHUB_OUTPUT': ghOut.path,
          'GITHUB_STEP_SUMMARY': ghSum.path,
        },
        cwd: pr,
        pipefail: false,
      );
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      final outputs = <String, String>{};
      for (final l in ghOut.readAsLinesSync()) {
        final i = l.indexOf('=');
        if (i > 0) outputs[l.substring(0, i)] = l.substring(i + 1);
      }
      final summary = ghSum.readAsStringSync();
      return (
        outputs: outputs,
        log: '${r.stdout}\n${r.stderr}',
        summary: summary,
        entryPath: entryPath,
      );
    } finally {
      if (trustedLink.existsSync()) {
        trustedLink.deleteSync();
      } else if (Directory(p.join(pr, 'trusted')).existsSync()) {
        Directory(p.join(pr, 'trusted')).deleteSync(recursive: true);
      }
      for (final f in partFiles) {
        f.deleteSync();
      }
    }
  }

  /// Runs the REAL `Verify tests actually ran` step (base checkout layout:
  /// tool/ci/tests_ran.sh + min_tests.txt, artifact in events/).
  ({int code, String output}) testsRan(
    Map<String, String> out, {
    int floor = 1,
    bool streams = true,
    Set<String> drop = const {},
  }) {
    final dir = Directory(p.join(ws, 'tests_ran'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    Directory(p.join(dir.path, 'tool', 'ci')).createSync(recursive: true);
    File(
      p.join(mobile, 'tool', 'ci', 'tests_ran.sh'),
    ).copySync(p.join(dir.path, 'tool', 'ci', 'tests_ran.sh'));
    File(
      p.join(dir.path, 'tool', 'ci', 'min_tests.txt'),
    ).writeAsStringSync('$floor\n');
    final ev = Directory(p.join(dir.path, 'events'))..createSync();
    final ci = Directory(p.join(pr, 'build', 'ci'));
    if (streams && ci.existsSync()) {
      for (final f in ci.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (name.endsWith('-events.json') &&
            !drop.contains(name.replaceFirst('-events.json', ''))) {
          f.copySync(p.join(ev.path, p.basename(f.path)));
        }
      }
    }
    final r = _bash(
      _step(jobs, 'tests-ran', 'Verify tests actually ran'),
      env: {
        'RUN_ALL': out['run_all'] ?? '',
        'TEST_COUNT': out['test_count'] ?? '',
        'UNIT_COUNT': out['unit_count'] ?? '',
        'GOLDEN_COUNT': out['golden_count'] ?? '',
        'TZ_COUNT': out['tz_count'] ?? '',
        'KYIV_COUNT': out['kyiv_count'] ?? '',
      },
      cwd: dir.path,
    );
    return (code: r.exitCode, output: '${r.stdout}\n${r.stderr}');
  }
}

/// Logs `TZ<TAB>arg1\x1farg2\x1f...` per call; writes a passing stream (one
/// suite + one real pass per listed file; [_Pipeline.fullPasses] for a
/// whole-suite call) to the --file-reporter path when one is given.
const _stubFlutter = r'''#!/usr/bin/env bash
set -eu
{ printf '%s\t' "${TZ:-}"; printf '%s\x1f' "$@"; printf '\n'; } >>"$STUB_LOG"
out=""
for a in "$@"; do case "$a" in --file-reporter=json:*) out="${a#--file-reporter=json:}" ;; esac; done
[ -n "$out" ] || exit 0
: >"$out"; i=0
emit() {
  printf '{"suite":{"id":%d,"path":"%s"},"type":"suite"}\n' "$i" "$1"
  printf '{"test":{"id":%d,"name":"t%d","suiteID":%d},"type":"testStart"}\n' "$((i + 1000))" "$i" "$i"
  printf '{"testID":%d,"result":"success","skipped":false,"hidden":false,"type":"testDone"}\n' "$((i + 1000))"
  i=$((i + 1))
}
nfiles=0
for a in "$@"; do case "$a" in *_test.dart) emit "$a" >>"$out"; nfiles=$((nfiles + 1)) ;; esac; done
if [ "$nfiles" -eq 0 ]; then for _ in 1 2 3 4 5; do emit "test/all_test.dart" >>"$out"; done; fi
echo '{"success":true,"type":"done"}' >>"$out"
''';
