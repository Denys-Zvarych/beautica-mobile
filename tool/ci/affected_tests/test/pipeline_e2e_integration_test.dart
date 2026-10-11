@Tags(['e2e', 'e2e-a'])
library;

/// Phase 401 end-to-end (part 2 of 4): plan -> D4 `if` -> `Choose integration
/// entry`, against real and hostile generators. See support_pipeline.dart.

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
      final out = pl.select(
        {'lib/features/foo/foo.dart': 'int foo = 10;\n'},
        planMode: 'full',
        shard: false,
      );
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
}
