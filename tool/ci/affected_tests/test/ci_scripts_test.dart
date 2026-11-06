import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 401 audit cycles 1 + 4: behaviour of the base-owned
/// `run_it_attempt.sh` the workflow runs from `trusted/` (S5 / P3 / P5 / P7,
/// selected-flow attempts).
///
/// Cycle 4 (SEC LOW): pass/fail is judged from the host-side JSON test
/// protocol (`--file-reporter json:`), never from stdout, which a test's
/// print() can forge. The streams below are built by [_Stream] in the exact
/// event shapes of a REAL report (test/fixtures/unit_events_real.json, pinned
/// key-for-key by the first test).
void main() {
  final ci = p.normalize(p.join(Directory.current.path, '..'));
  final attempt = p.join(ci, 'run_it_attempt.sh');
  final have = File(attempt).existsSync();
  final skip = have ? false : 'tool/ci/run_it_attempt.sh not found';

  group('run_it_attempt.sh', () {
    late Directory w;
    late File entry;
    late String out; // GITHUB_OUTPUT
    setUp(() {
      w = Directory.systemTemp.createTempSync('it_attempt_');
      Directory(p.join(w.path, 'bin')).createSync();
      // Stand-in `flutter`: records argv, copies $FAKE_EVENTS to the path of
      // its --file-reporter=json:<file> (when set), prints $FAKE_LOG, exits
      // $FAKE_RC (or sleeps).
      _exe(p.join(w.path, 'bin', 'flutter'), '''#!/bin/bash
if [ -n "\${FAKE_SLEEP:-}" ]; then exec sleep "\$FAKE_SLEEP"; fi
echo "\$@" >> "${w.path}/flutter_args"
dest=""
for a in "\$@"; do
  case "\$a" in --file-reporter=json:*) dest="\${a#--file-reporter=json:}" ;; esac
done
if [ -n "\${FAKE_EVENTS:-}" ] && [ -n "\$dest" ]; then cp "\$FAKE_EVENTS" "\$dest"; fi
cat "\$FAKE_LOG"
exit "\${FAKE_RC:-0}"
''');
      // Stand-in `timeout`: records its bound argument, then runs the command.
      Directory(p.join(w.path, 'tbin')).createSync();
      _exe(p.join(w.path, 'tbin', 'timeout'), '''#!/bin/bash
# F3: parse like coreutils timeout: options (-s/-k take a value), then the
# first non-option is the DURATION, the rest is the command.
while [ \$# -gt 0 ]; do
  case "\$1" in
    -s|-k) shift 2 ;;
    -*) shift ;;
    *) break ;;
  esac
done
echo "\$1" >> "${w.path}/timeout_args"
shift
exec "\$@"
''');
      entry = File(p.join(w.path, 'ci_selected_tests.dart'))
        ..writeAsStringSync(
          "void main() {\n  group('master_archive_flow', a.main);\n"
          "  group('notification_bell_flow', b.main);\n}\n",
        );
      out = p.join(w.path, 'gh_output');
      File(out).writeAsStringSync('');
    });
    tearDown(() => w.deleteSync(recursive: true));

    /// Runs one attempt. [events] is the JSON stream the stand-in flutter
    /// writes (null = it writes no file at all); [log] is its stdout.
    ProcessResult run(
      String? events, {
      String log = '',
      int rc = 0,
      String bound = '900',
      Map<String, String> env = const {},
      bool fakeTimeout = true,
      String? label,
    }) {
      final lf = File(p.join(w.path, 'fake.log'))..writeAsStringSync(log);
      final environment = {
        'PATH':
            '${fakeTimeout ? p.join(w.path, 'tbin') : ''}:${p.join(w.path, 'bin')}:${Platform.environment['PATH']}',
        'FLUTTER': p.join(w.path, 'bin', 'flutter'),
        'FAKE_LOG': lf.path,
        'FAKE_RC': '$rc',
        'GITHUB_OUTPUT': out,
        ...env,
      };
      if (events != null) {
        final ef = File(p.join(w.path, 'fake_events.json'))
          ..writeAsStringSync(events);
        environment['FAKE_EVENTS'] = ef.path;
      }
      return Process.runSync(
        'bash',
        [
          attempt,
          entry.path,
          p.join(w.path, 'selected.log'),
          bound,
          p.join(w.path, 'state'),
          ?label,
        ],
        environment: environment,
        includeParentEnvironment: false,
      );
    }

    String gh() => File(out).readAsStringSync();
    String text(ProcessResult r) => '${r.stdout}${r.stderr}';
    File failset() => File(p.join(w.path, 'state', 'failset'));

    // A real github-reporter log (job 114260709916, pr-validate run
    // 38068424570), used as the human stdout the script must NOT judge.
    final realPassLog = _fixture('integration_log_pass.txt');
    const flows = {
      'master_archive_flow': [_T.ok, _T.ok, _T.ok],
      'notification_bell_flow': [_T.ok, _T.ok],
    };
    final pass = _Stream(flows).build();

    test('the JSON builder emits the exact event shapes of a REAL report '
        '(key-for-key against test/fixtures/unit_events_real.json)', () {
      Map<String, Set<String>> shapes(String src) {
        final m = <String, Set<String>>{};
        for (final l in const LineSplitter().convert(src)) {
          final e = jsonDecode(l) as Map<String, dynamic>;
          final t = e['type'] as String;
          final inner = e['group'] ?? e['test'] ?? e['suite'];
          m.putIfAbsent(t, () => {}).addAll([
            ...e.keys,
            if (inner is Map) ...inner.keys.map((k) => '$t.$k'),
          ]);
        }
        return m;
      }

      final real = shapes(_fixture('unit_events_real.json'));
      final mine = shapes(
        _Stream(
          {
            'g': [_T.ok, _T.skip],
          },
          prints: const ['x'],
        ).build(),
      );
      for (final t in ['start', 'suite', 'group', 'testStart', 'testDone']) {
        expect(mine[t], real[t], reason: 'event type $t');
      }
      expect(mine['allSuites'], real['allSuites']);
      expect(mine['done'], real['done']);
    });

    test('the run is pinned to the github reporter + a JSON file reporter in '
        'the state dir; NO --dart-define (audit 4: the nonce is gone)', () {
      run(pass);
      final args = File(p.join(w.path, 'flutter_args')).readAsStringSync();
      expect(args, contains('test --reporter=github '));
      expect(
        args,
        contains('--file-reporter=json:${p.join(w.path, 'state')}/events.json'),
      );
      expect(args, isNot(contains('--dart-define')));
      expect(args, isNot(contains('NONCE')));
    });

    test('all groups fully pass -> pass (rc irrelevant: the emulator-teardown '
        'flake exits non-zero after a real pass)', () {
      for (final rc in [0, 1]) {
        final r = run(pass, rc: rc);
        expect(r.exitCode, 0, reason: text(r));
        expect(text(r), contains('SELECTED FLOWS: All 2 groups ran'));
      }
    });

    test('teardown flake: every testDone present but NO `done` event -> pass '
        '(and `done` success=false with no failing test -> pass)', () {
      expect(run(_Stream(flows, done: null).build()).exitCode, 0);
      final r = run(_Stream(flows, done: false).build(), rc: 1);
      expect(r.exitCode, 0, reason: text(r));
    });

    test('crash mid-group: fewer success testDone than the group testCount '
        '-> FAIL naming the group (the group event is declared up front)', () {
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.ok, _T.ok],
          'notification_bell_flow': [_T.ok, _T.missing],
        }, done: null).build(),
        rc: 1,
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('notification_bell_flow: 1 passed'));
      expect(text(r), contains('of 2 declared'));
      expect(text(r), isNot(contains('master_archive_flow:')));
    });

    test('a selected group that never started (no tests) -> FAIL', () {
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.ok, _T.ok],
          'notification_bell_flow': [_T.missing, _T.missing],
        }, done: null).build(),
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('notification_bell_flow: 0 passed'));
    });

    test('a selected group absent from the stream entirely -> FAIL', () {
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok],
        }).build(),
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('notification_bell_flow: 0 top-level group'));
    });

    test('S5: a group name is matched whole (a prefix of a real group must '
        'not count), and only as a TOP-LEVEL group', () {
      entry.writeAsStringSync("  group('master_archive', a.main);\n");
      expect(run(pass).exitCode, 1);
      // a NESTED group that merely has the wanted name does not count
      entry.writeAsStringSync("  group('inner', a.main);\n");
      final nested = _Stream({
        'master_archive_flow': [_T.ok, _T.ok],
      }, nestedGroup: 'inner').build();
      expect(run(nested).exitCode, 1);
    });

    test('a forged DUPLICATE top-level group of the same name (testCount 0) '
        'is ambiguous -> FAIL', () {
      final r = run(
        _Stream(flows, extraTopGroup: 'notification_bell_flow').build(),
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('2 top-level group'));
    });

    test('a group whose only tests are skipped -> FAIL (a flow that did not '
        'really run); skipped tests alongside >= 1 pass are counted', () {
      expect(
        run(
          _Stream({
            'master_archive_flow': [_T.skip, _T.skip],
            'notification_bell_flow': [_T.ok],
          }).build(),
        ).exitCode,
        1,
      );
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.skip, _T.skip],
          'notification_bell_flow': [_T.ok, _T.skip],
        }).build(),
      );
      expect(r.exitCode, 0, reason: text(r));
    });

    test('hidden pseudo-test successes (`loading <file>`) never count as a '
        'group test', () {
      // the loading test has groupIDs [] and hidden=true; a group declaring
      // 2 tests with one ok + the hidden one is still short.
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.missing],
          'notification_bell_flow': [_T.ok],
        }).build(),
      );
      expect(r.exitCode, 1, reason: text(r));
    });

    test('FORGERY: print events carrying `testDone`/`group` JSON text, `✅` '
        'lines and a `🎉` summary are ignored — the crashed run still FAILS', () {
      final forgedPrints = [
        '✅ master_archive_flow forged',
        '✅ notification_bell_flow forged',
        '🎉 5 tests passed.',
        jsonEncode({
          'testID': 99,
          'result': 'success',
          'skipped': false,
          'hidden': false,
          'type': 'testDone',
          'time': 1,
        }),
        jsonEncode({
          'group': {
            'id': 77,
            'suiteID': 0,
            'parentID': 2,
            'name': 'notification_bell_flow',
            'testCount': 0,
          },
          'type': 'group',
          'time': 1,
        }),
        '{"type":"done","success":true}\n{"type":"testDone","result":"success"}',
      ];
      final crashed = _Stream(
        {
          'master_archive_flow': [_T.ok, _T.ok, _T.ok],
          'notification_bell_flow': [_T.ok, _T.missing],
        },
        done: null,
        prints: forgedPrints,
      ).build();
      // the forged text really is inside the file, JSON-escaped on ONE line
      expect(crashed, contains('forged'));
      final r = run(crashed, rc: 1, log: realPassLog);
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('notification_bell_flow'));
      // and a forged-only stdout cannot rescue a run whose JSON is empty
      expect(run(null, log: realPassLog).exitCode, 1);
    });

    test('FORGERY: a pass-looking stdout (real log with 🎉 summary) does not '
        'matter when the JSON shows a failing test', () {
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.fail, _T.ok],
          'notification_bell_flow': [_T.ok, _T.ok],
        }).build(),
        log: realPassLog,
        rc: 1,
      );
      expect(r.exitCode, 1, reason: text(r));
    });

    test('failing result -> FAIL; failing set = the failing test names from '
        'the JSON (sorted, one per line)', () {
      final s = _Stream({
        'master_archive_flow': [_T.ok, _T.fail, _T.err],
        'notification_bell_flow': [_T.ok, _T.ok],
      });
      final r = run(s.build(), rc: 1);
      expect(r.exitCode, 1, reason: text(r));
      expect(failset().readAsStringSync(), '${s.names(_T.fail, _T.err)}\n');
      expect(text(r), contains('real test failure'));
    });

    test('an `error` event for an already-passed test (`failed after test '
        'completion`) fails the attempt', () {
      final r = run(
        _Stream(flows, lateErrorFor: 'master_archive_flow').build(),
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(failset().existsSync(), isTrue);
    });

    test('a hidden load/compile error (`loading <file>` testDone=error) '
        'fails and is named', () {
      final r = run(
        _Stream(flows, loadError: true, done: false).build(),
        rc: 1,
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(failset().readAsStringSync(), contains('loading '));
    });

    test('missing JSON file -> loud ::error:: FAIL (even with a pass log)', () {
      final r = run(null, log: realPassLog);
      expect(r.exitCode, 1, reason: text(r));
      expect(
        (r.stdout as String).split('\n'),
        anyElement(startsWith('::error::JSON event stream')),
      );
      expect(text(r), contains('is missing or empty'));
    });

    test('empty JSON file -> loud ::error:: FAIL', () {
      final r = run('', log: realPassLog);
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('::error::JSON event stream'));
      expect(text(r), contains('is missing or empty'));
    });

    test('garbage / non-event JSON -> loud ::error:: FAIL', () {
      for (final g in [
        'this is not json\n',
        '{"half":\n',
        '[1,2,3]\n"x"\n42\n',
        '\u0000\u0001\n',
      ]) {
        final r = run(g, log: realPassLog);
        expect(r.exitCode, 1, reason: '$g ${text(r)}');
        expect(text(r), contains('::error::JSON event stream'), reason: g);
      }
    });

    test('a stale events file of a previous attempt is never judged', () {
      expect(run(pass).exitCode, 0);
      final r = run(null); // second attempt: flutter writes nothing
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('::error::JSON event stream'));
    });

    test(
      'SEC-5: `::` workflow commands in the replayed log are neutralised',
      () {
        final r = run(
          pass,
          log: '::add-mask::s3cret\n::stop-commands::tok\n  ::keep::x\n',
        );
        final lines = (r.stdout as String).split('\n');
        // INFO (security, 2026-11-06): a command after leading whitespace is
        // defused too, and to a NON-whitespace form (a runner that trims the
        // line must still not see `::`).
        final cmd = RegExp(r'^\s*::');
        expect(lines.where(cmd.hasMatch), isEmpty, reason: '$lines');
        expect(lines, contains(': :add-mask::s3cret'));
        expect(lines, contains(': :stop-commands::tok'));
        expect(lines, contains('  : :keep::x'));
        // the timeout path replays the same way
        final t = run(null, log: '::add-mask::z\n\t::add-mask::y\n', rc: 124);
        expect((t.stdout as String).split('\n').where(cmd.hasMatch), isEmpty);
      },
    );

    test('hang: timeout rc 124 -> FAIL naming the bound (even with a '
        'complete JSON)', () {
      final r = run(pass, rc: 124);
      expect(r.exitCode, 1);
      expect(text(r), matches(RegExp(r'TIMED OUT after \d+s \(bound 900s')));
    });

    // mobile-perf P1 (2026-11-06): a timeout names elapsed time + the last
    // fully finished group and says "slowness or hang", not "a HANG".
    test('timeout line: elapsed time, bound, last FULLY finished group, '
        '"Slowness or a hang"; no "treat as a HANG" claim', () {
      final partial = _Stream({
        'master_archive_flow': [_T.ok, _T.ok, _T.ok],
        'notification_bell_flow': [_T.ok, _T.missing],
      }, done: null).build();
      final r = run(partial, rc: 124);
      expect(r.exitCode, 1);
      expect(
        text(r),
        matches(
          RegExp(
            r'SELECTED FLOWS: TIMED OUT after \d+s \(bound 900s, rc=124\); '
            r'last fully finished group: master_archive_flow\. '
            r'Slowness or a hang',
          ),
        ),
      );
      expect(text(r), isNot(contains('treat 124/137 as a HANG')));
      expect(text(r), isNot(contains('far under this bound')));
      // nothing finished / no JSON at all -> `none`
      final n = run(null, rc: 137);
      expect(text(n), contains('last fully finished group: none.'));
    });

    test('P1 timeout marker: two timeouts in a row -> deterministic=true on '
        'the 2nd (attempt 3 skipped); the 1st never claims it', () {
      expect(run(null, rc: 124).exitCode, 1);
      expect(gh(), isNot(contains('deterministic')));
      expect(File(p.join(w.path, 'state', 'timedout')).existsSync(), isTrue);
      final r2 = run(null, rc: 124);
      expect(r2.exitCode, 1);
      expect(gh(), contains('deterministic=true'));
      expect(text(r2), contains('previous attempt timed out too'));
    });

    test('P1 timeout marker: any other outcome in between resets it (pass, '
        'real failure, crash, missing JSON)', () {
      final crash = _Stream({
        'master_archive_flow': [_T.ok, _T.cancel, _T.cancel],
        'notification_bell_flow': [_T.cancel, _T.cancel],
      }, done: null).build();
      final fail = _Stream({
        'master_archive_flow': [_T.ok, _T.fail, _T.ok],
        'notification_bell_flow': [_T.ok, _T.ok],
      }).build();
      for (final between in <String?>[pass, fail, crash, null]) {
        File(out).writeAsStringSync('');
        run(null, rc: 124);
        run(between, rc: 1);
        run(null, rc: 124);
        expect(gh(), isNot(contains('deterministic')), reason: '$between');
        run(pass); // reset for the next round
      }
    });

    test('P1 timeout marker: a timeout clears the real-failure memory (a '
        'failure, a timeout, the same failure is NOT deterministic)', () {
      final fail = _Stream({
        'master_archive_flow': [_T.ok, _T.fail, _T.ok],
        'notification_bell_flow': [_T.ok, _T.ok],
      }).build();
      run(fail, rc: 1);
      run(null, rc: 124);
      expect(failset().existsSync(), isFalse);
      run(fail, rc: 1);
      expect(gh(), isNot(contains('deterministic')));
    });

    test('P3: the bound is passed to timeout; garbage falls back to 1500', () {
      File(p.join(w.path, 'timeout_args')).writeAsStringSync('');
      run(pass, bound: '645');
      run(pass, bound: 'abc');
      run(pass, bound: '0');
      expect(File(p.join(w.path, 'timeout_args')).readAsLinesSync(), [
        '645',
        '1500',
        '1500',
      ]);
    });

    test(
      'P3: the bound is really enforced (real timeout, sleeping flutter)',
      () {
        final r = run(
          null,
          bound: '1',
          env: {'FAKE_SLEEP': '30'},
          fakeTimeout: false,
        );
        expect(r.exitCode, 1, reason: text(r));
        expect(text(r), contains('(bound 1s, rc='));
      },
    );

    final failing = _Stream({
      'master_archive_flow': [_T.ok, _T.fail, _T.ok],
      'notification_bell_flow': [_T.ok, _T.ok],
    });

    test('P5 (deterministic-skip): the same failing set twice -> '
        'deterministic=true on attempt 2', () {
      expect(run(failing.build(), rc: 1).exitCode, 1);
      expect(gh(), isNot(contains('deterministic')));
      final r2 = run(failing.build(), rc: 1);
      expect(r2.exitCode, 1);
      expect(gh(), contains('deterministic=true'));
    });

    test('P5: a DIFFERENT failing set is not deterministic', () {
      final other = _Stream({
        'master_archive_flow': [_T.ok, _T.ok, _T.fail],
        'notification_bell_flow': [_T.ok, _T.ok],
      });
      run(failing.build(), rc: 1);
      run(other.build(), rc: 1);
      expect(gh(), isNot(contains('deterministic')));
      // ...but the new set is remembered.
      run(other.build(), rc: 1);
      expect(gh(), contains('deterministic=true'));
    });

    test('P5: a crash / teardown flake between two identical failures resets '
        'the memory (all 3 attempts kept)', () {
      run(failing.build(), rc: 1);
      final crash = _Stream({
        'master_archive_flow': [_T.ok, _T.missing, _T.missing],
        'notification_bell_flow': [_T.missing, _T.missing],
      }, done: null).build();
      expect(run(crash, rc: 1).exitCode, 1); // flake
      run(failing.build(), rc: 1);
      expect(gh(), isNot(contains('deterministic')));
    });

    test('P5: missing JSON between two identical failures also resets', () {
      run(failing.build(), rc: 1);
      run(null, rc: 1);
      run(failing.build(), rc: 1);
      expect(gh(), isNot(contains('deterministic')));
    });

    test('P5: a failure with no nameable test never claims determinism', () {
      // error event with an unknown testID -> name falls back to `test #N`,
      // still a set; an unparseable stream clears state instead.
      run(failing.build(), rc: 1);
      run('garbage\n', rc: 1);
      run(failing.build(), rc: 1);
      expect(gh(), isNot(contains('deterministic')));
    });

    test('P5: a pass clears the memory', () {
      run(failing.build(), rc: 1);
      expect(run(pass).exitCode, 0);
      run(failing.build(), rc: 1);
      expect(gh(), isNot(contains('deterministic')));
    });

    final crashed = _Stream(
      {
        'master_archive_flow': [_T.ok, _T.ok, _T.cancel],
        'notification_bell_flow': [_T.cancel, _T.cancel],
      },
      done: false,
      cancelledTearDownAll: true,
    );

    test('P5 (cancelled): an emulator crash after test 2 (rest testDone '
        'result=error, no error event) is CRASHED/retryable, writes no '
        'failset and is never deterministic', () {
      final r1 = run(crashed.build(), rc: 1);
      expect(r1.exitCode, 1);
      expect(
        text(r1),
        contains(
          'SELECTED FLOWS: CRASHED after master_archive_flow test 1; '
          '4 tests cancelled (emulator/device loss) — retryable',
        ),
      );
      expect(text(r1), isNot(contains('a real test failure/error')));
      expect(failset().existsSync(), isFalse);
      final r2 = run(crashed.build(), rc: 1);
      expect(r2.exitCode, 1);
      expect(text(r2), contains('CRASHED after'));
      expect(gh(), isNot(contains('deterministic')));
    });

    test('P5 (cancelled): one real failure + cancelled tests -> FAILED, the '
        'failset holds ONLY the real failure', () {
      final mixed = _Stream(
        {
          'master_archive_flow': [_T.ok, _T.fail, _T.cancel],
          'notification_bell_flow': [_T.cancel, _T.cancel],
        },
        done: false,
        cancelledTearDownAll: true,
      );
      final r = run(mixed.build(), rc: 1);
      expect(r.exitCode, 1);
      expect(text(r), contains('a real test failure/error'));
      expect(text(r), isNot(contains('CRASHED')));
      expect(failset().readAsStringSync().trim(), 'master_archive_flow test 1');
      expect(mixed.names(_T.fail), 'master_archive_flow test 1');
    });

    // QA 2026-11-06: the device dies before ANY test passed (only cancelled
    // testDone events). Still CRASHED/retryable, naming `none`, never a
    // failset (a real-failure memory here would let the next identical crash
    // claim determinism and skip attempt 3).
    test('CRASHED before any test passed -> "CRASHED after none", '
        'retryable, no failset, never deterministic', () {
      final early = _Stream(
        {
          'master_archive_flow': [_T.cancel, _T.cancel, _T.cancel],
          'notification_bell_flow': [_T.cancel, _T.cancel],
        },
        done: null,
        cancelledTearDownAll: true,
      ).build();
      final r1 = run(early, rc: 1);
      expect(r1.exitCode, 1);
      expect(
        text(r1),
        contains(
          'SELECTED FLOWS: CRASHED after none; 6 tests cancelled '
          '(emulator/device loss) — retryable',
        ),
      );
      expect(failset().existsSync(), isFalse);
      expect(run(early, rc: 1).exitCode, 1);
      expect(gh(), isNot(contains('deterministic')));
    });

    test('F3: the timeout stand-in parses the bound regardless of option '
        'order', () {
      File(p.join(w.path, 'timeout_args')).writeAsStringSync('');
      final t = p.join(w.path, 'tbin', 'timeout');
      for (final args in [
        ['--signal=TERM', '--kill-after=60', '77', 'true'],
        ['-k', '60', '-s', 'TERM', '78', 'true'],
        ['79', 'true'],
      ]) {
        Process.runSync(t, args);
      }
      expect(File(p.join(w.path, 'timeout_args')).readAsLinesSync(), [
        '77',
        '78',
        '79',
      ]);
    });

    test('an entry without any group(...) line can never pass', () {
      entry.writeAsStringSync('void main() {}\n');
      expect(run(pass).exitCode, 1);
    });

    // 2026-11-06: the six full-mode part attempts run this script too
    // (all_tests_part1/2.dart, label `PART 1` / `PART 2`).
    test('parts: the 5th arg labels every verdict line (pass, crash, real '
        'failure, hang); default stays SELECTED FLOWS', () {
      final ok = run(pass, label: 'PART 1');
      expect(ok.exitCode, 0, reason: text(ok));
      expect(text(ok), contains('PART 1: All 2 groups ran'));
      expect(text(ok), isNot(contains('SELECTED FLOWS')));
      final crash = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.cancel, _T.cancel],
          'notification_bell_flow': [_T.cancel, _T.cancel],
        }, done: null).build(),
        rc: 1,
        label: 'PART 2',
      );
      expect(crash.exitCode, 1);
      expect(text(crash), contains('PART 2: CRASHED after'));
      expect(text(crash), contains('retryable'));
      final bad = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.fail, _T.ok],
          'notification_bell_flow': [_T.ok, _T.ok],
        }).build(),
        label: 'PART 2',
      );
      expect(bad.exitCode, 1);
      expect(text(bad), contains('PART 2: FAILED — a real test failure'));
      final hang = run(pass, rc: 124, label: 'PART 1');
      expect(hang.exitCode, 1);
      expect(text(hang), contains('PART 1: TIMED OUT after '));
    });

    test('parts: the label is sanitised (no workflow command / shell '
        'metacharacters reach the log); an all-junk label falls back', () {
      final r = run(pass, label: r'::stop-commands::$(x)`y`');
      expect(text(r), contains('stop-commandsxy: All 2 groups ran'));
      expect(text(r), isNot(contains('::stop')));
      final j = run(pass, label: '::');
      expect(text(j), contains('SELECTED FLOWS: All 2 groups ran'));
    });

    test('parts: a dart-format-WRAPPED group(...) over several lines is a '
        'required group like a one-line one', () {
      entry.writeAsStringSync(
        "void main() {\n  group('master_archive_flow', a.main);\n"
        "  group(\n    'notification_bell_flow',\n    b.main,\n  );\n}\n",
      );
      expect(run(pass).exitCode, 0);
      // the wrapped group is really required: absent from the stream -> FAIL
      final r = run(
        _Stream({
          'master_archive_flow': [_T.ok, _T.ok, _T.ok],
        }).build(),
      );
      expect(r.exitCode, 1, reason: text(r));
      expect(text(r), contains('notification_bell_flow: 0 top-level group'));
    });

    test('parts: a commented-out group(...) is not required', () {
      entry.writeAsStringSync(
        "void main() {\n  group('master_archive_flow', a.main);\n"
        "  group('notification_bell_flow', b.main);\n"
        "  // group('retired_flow', c.main);\n}\n",
      );
      final r = run(pass);
      expect(r.exitCode, 0, reason: text(r));
    });

    test('shards: every group of every REAL generated shard is read (8 '
        'shards of all_tests.dart)', () {
      final repo = p.normalize(p.join(ci, '..', '..'));
      for (var k = 1; k <= 8; k++) {
        final o = p.join(w.path, 'shard$k.dart');
        final g = _gen(['--shard', '$k/8', '--repo', repo, '--out', o]);
        expect(g.exitCode, 0, reason: '${g.stdout}${g.stderr}');
        final src = File(o).readAsStringSync();
        final declared = RegExp(r'\bgroup\(').allMatches(src).length;
        expect(declared, greaterThan(10), reason: 'shard $k');
        entry.writeAsStringSync(src);
        // Nothing in the stream -> every declared group is reported bad.
        final r = run(
          _Stream({
            'unrelated_flow': [_T.ok],
          }).build(),
          label: 'SHARD $k',
        );
        expect(r.exitCode, 1);
        final bad = RegExp(
          r'^  [A-Za-z0-9_]+: 0 top-level',
          multiLine: true,
        ).allMatches(text(r)).length;
        expect(bad, declared, reason: 'shard $k');
      }
    });
  }, skip: skip);

  // mobile-perf P0 (2026-11-06): the FULL suite runs as generated shards of
  // all_tests.dart (gen_integration_entry.dart --shard K/N).
  group('gen_integration_entry.dart --shard K/N', () {
    late Directory r;
    setUp(() {
      r = Directory.systemTemp.createTempSync('it_shard_');
      Directory(p.join(r.path, 'integration_test')).createSync();
    });
    tearDown(() => r.deleteSync(recursive: true));

    /// A repo whose all_tests.dart imports [flows] (name -> testWidgets).
    void repo(Map<String, int> flows) {
      final b = StringBuffer(
        "import 'package:flutter_test/flutter_test.dart';\n",
      );
      for (final f in flows.keys) {
        b.writeln("import '${f}_test.dart' as $f;");
      }
      b.writeln('void main() {');
      for (final f in flows.keys) {
        b.writeln("  group('$f', $f.main);");
        File(
          p.join(r.path, 'integration_test', '${f}_test.dart'),
        ).writeAsStringSync(
          'void main() {\n'
          "  // testWidgets('commented out', (t) async {});\n"
          "${"  testWidgets('t', (t) async {});\n" * flows[f]!}"
          "  test('plain', () {});\n}\n",
        );
      }
      b.writeln('}');
      File(
        p.join(r.path, 'integration_test', 'all_tests.dart'),
      ).writeAsStringSync(b.toString());
    }

    ({int code, String out, String src}) shard(String spec) {
      final o = p.join(r.path, 'integration_test', 'ci_shard_tests.dart');
      final g = _gen(['--shard', spec, '--repo', r.path]);
      final f = File(o);
      return (
        code: g.exitCode,
        out: '${g.stdout}',
        src: f.existsSync() ? f.readAsStringSync() : '',
      );
    }

    Set<String> groups(String src) => {
      for (final m in RegExp(r"group\('([a-z0-9_]+)'").allMatches(src))
        m.group(1)!,
    };

    test('every flow lands in exactly one shard; loads balanced by '
        'testWidgets (commented-out calls and plain test() not counted); '
        'stdout entry=shard / count / tests', () {
      final flows = {
        'a1': 9, 'b2': 7, 'c3': 6, 'd4': 5, 'e5': 4, 'f6': 3, 'g7': 2, //
        'h8': 1, 'i9': 0,
      };
      repo(flows);
      final seen = <String>[];
      final loads = <int>[];
      for (var k = 1; k <= 3; k++) {
        final s = shard('$k/3');
        expect(s.code, 0, reason: s.out);
        final g = groups(s.src);
        seen.addAll(g);
        final lines = s.out.trim().split('\n');
        expect(lines[0], 'entry=shard');
        expect(lines[1], 'count=${g.length}');
        final load = g.fold(0, (a, f) => a + flows[f]!);
        expect(lines[2], 'tests=$load');
        loads.add(load);
        expect(s.src, contains('Shard $k of 3'));
      }
      expect(seen..sort(), flows.keys.toList()..sort());
      // 37 testWidgets over 3 shards: LPT (ties -> fewer flows, low index).
      expect(loads, [12, 13, 12]);
    });

    test('deterministic: the same tree gives byte-identical shards', () {
      repo({'a1': 3, 'b2': 2, 'c3': 2, 'd4': 1});
      final first = shard('2/2').src;
      expect(first, isNotEmpty);
      expect(shard('2/2').src, first);
    });

    test('fail closed: bad K/N, no all_tests.dart, a missing or symlinked '
        'flow, an empty shard -> entry=error, exit 1, no entry file', () {
      repo({'a1': 1, 'b2': 1});
      for (final bad in ['0/2', '3/2', '1/0', 'x', '1-2', '1/2/3', '']) {
        final s = shard(bad);
        expect(s.code, 1, reason: bad);
        expect(s.out.trim(), 'entry=error', reason: bad);
        expect(s.src, isEmpty, reason: bad);
      }
      expect(shard('3/3').out.trim(), 'entry=error', reason: 'empty shard');
      File(p.join(r.path, 'integration_test', 'b2_test.dart')).deleteSync();
      expect(shard('1/2').code, 1, reason: 'missing flow');
      Link(
        p.join(r.path, 'integration_test', 'b2_test.dart'),
      ).createSync(p.join(r.path, 'integration_test', 'a1_test.dart'));
      expect(shard('1/2').code, 1, reason: 'symlinked flow');
      File(p.join(r.path, 'integration_test', 'all_tests.dart')).deleteSync();
      final s = shard('1/1');
      expect(s.code, 1);
      expect(s.src, isEmpty);
    });

    // QA 2026-11-06: all_tests.dart exists but its flow imports are in a
    // shape partFlows does not read (package: URIs) -> refuse, never an
    // "empty" or partial shard set that silently drops every flow.
    test('all_tests.dart with no relative flow import -> entry=error, exit 1, '
        'no entry file (no shard silently runs nothing)', () {
      repo({'a1': 1, 'b2': 1});
      final all = File(p.join(r.path, 'integration_test', 'all_tests.dart'));
      all.writeAsStringSync(
        all.readAsStringSync().replaceAllMapped(
          RegExp(r"^import '([a-z0-9_]+_test\.dart)'", multiLine: true),
          (m) => "import 'package:beautica/${m.group(1)}'",
        ),
      );
      for (final spec in ['1/1', '1/2', '2/2']) {
        final s = shard(spec);
        expect(s.code, 1, reason: spec);
        expect(s.out.trim(), 'entry=error', reason: spec);
        expect(s.src, isEmpty, reason: spec);
      }
    });

    test('a stale entry file is removed even when the shard is refused', () {
      repo({'a1': 1});
      final o = File(p.join(r.path, 'integration_test', 'ci_shard_tests.dart'))
        ..writeAsStringSync("group('stale', s.main);");
      expect(shard('1/1').code, 0);
      expect(o.readAsStringSync(), isNot(contains('stale')));
      o.writeAsStringSync("group('stale', s.main);");
      // refused: the stale file must not survive as a "shard"
      File(p.join(r.path, 'integration_test', 'a1_test.dart')).deleteSync();
      expect(shard('1/1').code, 1);
      expect(o.existsSync(), isFalse);
    });

    test('REAL tree: 8 shards cover all_tests.dart exactly once, each '
        'within one heaviest flow of the mean', () {
      final repoRoot = p.normalize(
        p.join(Directory.current.path, '..', '..', '..'),
      );
      final all = File(
        p.join(repoRoot, 'integration_test', 'all_tests.dart'),
      ).readAsStringSync();
      final want = {
        for (final m in RegExp(
          r"^import '([a-z0-9_]+)_test\.dart'",
          multiLine: true,
        ).allMatches(all))
          m.group(1)!,
      };
      final seen = <String>[];
      final tests = <int>[];
      for (var k = 1; k <= 8; k++) {
        final o = p.join(r.path, 'real$k.dart');
        final g = _gen(['--shard', '$k/8', '--repo', repoRoot, '--out', o]);
        expect(g.exitCode, 0, reason: '${g.stdout}${g.stderr}');
        final src = File(o).readAsStringSync();
        seen.addAll(
          RegExp(
            r"^import '([a-z0-9_]+)_test\.dart'",
            multiLine: true,
          ).allMatches(src).map((m) => m.group(1)!),
        );
        tests.add(
          int.parse(
            RegExp(
              r'^tests=(\d+)$',
              multiLine: true,
            ).firstMatch('${g.stdout}')!.group(1)!,
          ),
        );
      }
      expect(seen.length, want.length, reason: 'no flow in two shards');
      expect(seen.toSet(), want);
      tests.sort();
      expect(tests.last - tests.first, lessThanOrEqualTo(10), reason: '$tests');
      expect(tests.reduce((a, b) => a + b), greaterThan(400));
      // mobile-perf cycle 2 P1: the selected cap is at most ONE shard (above
      // it the 8 parallel shards finish sooner than one serial run).
      final src = File('bin/gen_integration_entry.dart').readAsStringSync();
      int constant(String n) =>
          int.parse(RegExp('const $n = (\\d+);').firstMatch(src)!.group(1)!);
      expect(constant('maxSelectedTests'), lessThanOrEqualTo(tests.last));
      expect(
        constant('maxSelectedTests'),
        greaterThanOrEqualTo(tests.first - 10),
        reason: 'still about one shard, not a token cap',
      );
      expect(
        constant('maxSelectedFlows'),
        lessThanOrEqualTo(seen.length ~/ 8 + 1),
      );
    });
  });

  // mobile-perf cycle 2 P2: the debug APK is built once, outside the
  // attempt bound, with the inputs `flutter test <entry>` uses (exact
  // `-Pdart-defines` parity is impossible, see the script header).
  group('prebuild_it_apk.sh', () {
    final script = p.join(ci, 'prebuild_it_apk.sh');
    late Directory w;
    late File argv;
    late File entry;
    setUp(() {
      w = Directory.systemTemp.createTempSync('it_prebuild_');
      argv = File(p.join(w.path, 'argv'))..writeAsStringSync('');
      Directory(p.join(w.path, 'integration_test')).createSync();
      entry = File(p.join(w.path, 'integration_test', 'ci_shard_tests.dart'))
        ..writeAsStringSync('void main() {}\n');
      // Fake flutter: logs one argv line per call; fails the first
      // $FAKE_FAILS calls.
      File(p.join(w.path, 'flutter'))..writeAsStringSync(
        '#!/usr/bin/env bash\n'
        'echo "\$*" >>"${argv.path}"\n'
        'n=\$(wc -l <"${argv.path}")\n'
        '[ "\$n" -gt "\${FAKE_FAILS:-0}" ]\n',
      );
      Process.runSync('chmod', ['+x', p.join(w.path, 'flutter')]);
    });
    tearDown(() => w.deleteSync(recursive: true));

    ProcessResult run(String rel, {int fails = 0}) => Process.runSync(
      'bash',
      [script, rel],
      workingDirectory: w.path,
      environment: {
        'FLUTTER': p.join(w.path, 'flutter'),
        'FAKE_FAILS': '$fails',
      },
    );

    test('one debug x64 build of the ABSOLUTE entry with flutter test\'s '
        'integration define; exit 0', () {
      final r = run('integration_test/ci_shard_tests.dart');
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final abs = p.join(
        Directory(w.path).resolveSymbolicLinksSync(),
        'integration_test',
        'ci_shard_tests.dart',
      );
      expect(argv.readAsLinesSync(), [
        'build apk --debug --target-platform android-x64 -t $abs '
            '--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false',
      ]);
    });

    test('a failed build is retried once; two failures exit 1', () {
      var r = run('integration_test/ci_shard_tests.dart', fails: 1);
      expect(r.exitCode, 0, reason: '${r.stdout}');
      expect(argv.readAsLinesSync(), hasLength(2));
      argv.writeAsStringSync('');
      r = run('integration_test/ci_shard_tests.dart', fails: 2);
      expect(r.exitCode, 1);
      expect(argv.readAsLinesSync(), hasLength(2));
      expect('${r.stdout}', contains('::error::prebuild'));
    });

    test('a missing, empty or symlinked entry fails before any build', () {
      expect(run('integration_test/nope.dart').exitCode, 1);
      entry.writeAsStringSync('');
      expect(run('integration_test/ci_shard_tests.dart').exitCode, 1);
      entry.writeAsStringSync('void main() {}\n');
      Link(
        p.join(w.path, 'integration_test', 'link.dart'),
      ).createSync(entry.path);
      expect(run('integration_test/link.dart').exitCode, 1);
      expect(argv.readAsStringSync(), isEmpty);
    });
  });

  // PR #137: emulator-leg memory hygiene + diagnostics. Real bash against
  // stand-in adb / gradlew / pkill / sudo / free / ps.
  group('it_diag.sh', () {
    final script = p.join(ci, 'it_diag.sh');
    late Directory w;
    late File calls;
    setUp(() {
      w = Directory.systemTemp.createTempSync('it_diag_');
      calls = File(p.join(w.path, 'calls'))..writeAsStringSync('');
      final bin = Directory(p.join(w.path, 'bin'))..createSync();
      void fake(String name, String body) {
        final f = File(p.join(bin.path, name))
          ..writeAsStringSync('#!/usr/bin/env bash\n$body\n');
        Process.runSync('chmod', ['+x', f.path]);
      }

      // adb: streaming logcat blocks until killed; -d dumps and exits.
      fake(
        'adb',
        'echo "adb \$*" >>"${calls.path}"\n'
            'if [ "\$2" = "-d" ]; then echo "TAIL-LINE"; exit 0; fi\n'
            'echo "STREAM-LINE"; exec sleep 300',
      );
      fake('pkill', 'echo "pkill \$*" >>"${calls.path}"; exit 1');
      fake('free', 'echo "Mem: 15990 14000 120"');
      fake('ps', 'echo "4300000 qemu-system-x86"');
      fake(
        'sudo',
        'echo "sudo \$*" >>"${calls.path}"\n'
            'printf "%s\\n" "[t] usb ok" '
            '"[t] Out of memory: Killed process 4242 (qemu-system-x86)"',
      );
      Directory(p.join(w.path, 'android')).createSync();
      final gw = File(p.join(w.path, 'android', 'gradlew'))
        ..writeAsStringSync(
          '#!/usr/bin/env bash\necho "gradlew \$*" >>"${calls.path}"; exit 1\n',
        );
      Process.runSync('chmod', ['+x', gw.path]);
    });
    tearDown(() => w.deleteSync(recursive: true));

    ProcessResult go(List<String> args) => Process.runSync(
      'bash',
      [script, ...args],
      workingDirectory: w.path,
      environment: {
        'PATH': '${p.join(w.path, 'bin')}:${Platform.environment['PATH']}',
        'IT_DIAG_INTERVAL': '1',
      },
    );

    test('stop-build-daemons: gradlew --stop in android/ + pkill the Kotlin '
        'daemon; exit 0 even when both fail', () {
      final r = go(['stop-build-daemons']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(calls.readAsLinesSync(), [
        'gradlew --stop -q',
        'pkill -f KotlinCompileDaemon',
      ]);
    });

    test('run: the command\'s exit code is kept (0 and 3); logcat stream, '
        'logcat tail, memory samples and host.txt (OOM lines) are written; '
        'the streaming logcat is stopped', () {
      final d = p.join(w.path, 'diag', 'attempt-1');
      final ok = go(['run', d, '--', 'bash', '-c', 'sleep 2; echo CMD-OUT']);
      expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
      expect('${ok.stdout}', contains('CMD-OUT'));
      expect(
        File(p.join(d, 'logcat.txt')).readAsStringSync(),
        contains('STREAM-LINE'),
      );
      expect(
        File(p.join(d, 'logcat-tail.txt')).readAsStringSync(),
        contains('TAIL-LINE'),
      );
      expect(
        File(p.join(d, 'host-mem.txt')).readAsStringSync(),
        allOf(contains('Mem: 15990'), contains('qemu-system-x86')),
      );
      final host = File(p.join(d, 'host.txt')).readAsStringSync();
      expect(host, contains('Killed process 4242'));
      expect(host, isNot(contains('usb ok')), reason: 'OOM lines only');
      expect(calls.readAsStringSync(), contains('adb logcat -d -t 2000'));
      expect(calls.readAsStringSync(), contains('sudo -n dmesg -T'));
      final left = Process.runSync('pgrep', ['-f', 'sleep 300']);
      expect('${left.stdout}'.trim(), isEmpty, reason: 'logcat stream left');

      final bad = go(['run', d, '--', 'bash', '-c', 'exit 3']);
      expect(bad.exitCode, 3);
    });

    test('host never fails; bad usage / unknown subcommand exit 2', () {
      final d = p.join(w.path, 'h');
      expect(go(['host', d]).exitCode, 0);
      expect(File(p.join(d, 'host.txt')).existsSync(), isTrue);
      expect(go(['run', d, 'bash', '-c', 'true']).exitCode, 2);
      expect(go(['run', d, '--']).exitCode, 2);
      expect(go(['nope']).exitCode, 2);
      expect(go([]).exitCode, 2);
    });
  });
}

/// `cancel` = package:test's shape for a test cancelled by device/emulator
/// loss: `testDone result=error` with NO `error` event for its testID.
enum _T { ok, skip, fail, err, cancel, missing }

/// A JSON test-protocol stream in the exact shapes of a real
/// `flutter test --file-reporter json:` report (see unit_events_real.json).
final class _Stream {
  _Stream(
    this.flows, {
    this.done = true,
    this.prints = const [],
    this.nestedGroup,
    this.lateErrorFor,
    this.loadError = false,
    this.extraTopGroup,
    this.cancelledTearDownAll = false,
  });

  /// Adds a hidden `(tearDownAll)` pseudo-test cancelled like the rest
  /// (`testDone result=error`, no `error` event), as on a real device loss.
  final bool cancelledTearDownAll;

  /// group name -> per-test outcome.
  final Map<String, List<_T>> flows;

  /// true / false = a `done` event with that success; null = no `done` event.
  final bool? done;
  final List<String> prints;
  final String? nestedGroup;
  final String? lateErrorFor;
  final bool loadError;

  /// A second TOP-LEVEL group event carrying this name (a forged duplicate).
  final String? extraTopGroup;

  static const _path =
      '/work/beautica-mobile/integration_test/ci_selected.dart';
  static const _meta = {'skip': false, 'skipReason': null};

  String _testName(String g, int i) => '$g test $i';

  /// Names of the tests with [outcomes], in stream order, sorted + joined by
  /// newline (the failset file format).
  String names(_T a, [_T? b]) {
    final n = <String>[];
    for (final e in flows.entries) {
      for (var i = 0; i < e.value.length; i++) {
        if (e.value[i] == a || e.value[i] == b) n.add(_testName(e.key, i));
      }
    }
    return (n..sort()).join('\n');
  }

  String build() {
    final ev = <Map<String, Object?>>[];
    var t = 0;
    Map<String, Object?> e(String type, Map<String, Object?> body) => {
      ...body,
      'type': type,
      'time': t += 7,
    };
    var id = 0;
    ev.add({
      'protocolVersion': '0.1.1',
      'runnerVersion': '1.30.0',
      'pid': 4242,
      'type': 'start',
      'time': 0,
    });
    ev.add(
      e('suite', {
        'suite': {'id': 0, 'platform': 'vm', 'path': _path},
      }),
    );
    final loadId = ++id;
    ev.add(
      e('testStart', {
        'test': {
          'id': loadId,
          'name': 'loading $_path',
          'suiteID': 0,
          'groupIDs': <int>[],
          'metadata': _meta,
          'line': null,
          'column': null,
          'url': null,
        },
      }),
    );
    ev.add(
      e('testDone', {
        'testID': loadId,
        'result': loadError ? 'error' : 'success',
        'skipped': false,
        'hidden': true,
      }),
    );
    final total = flows.values.fold<int>(0, (a, b) => a + b.length);
    final rootId = ++id;
    Map<String, Object?> group(int gid, int? parent, String name, int count) =>
        e('group', {
          'group': {
            'id': gid,
            'suiteID': 0,
            'parentID': parent,
            'name': name,
            'metadata': _meta,
            'testCount': count,
            'line': parent == null ? null : 12,
            'column': parent == null ? null : 3,
            'url': parent == null ? null : 'file://$_path',
          },
        });
    ev.add(group(rootId, null, '', total));
    final gids = <String, int>{};
    for (final f in flows.entries) {
      gids[f.key] = ++id;
      ev.add(group(gids[f.key]!, rootId, f.key, f.value.length));
    }
    if (extraTopGroup != null) ev.add(group(++id, rootId, extraTopGroup!, 0));
    int? nestedId;
    if (nestedGroup != null) {
      nestedId = ++id;
      ev.add(group(nestedId, gids.values.first, nestedGroup!, 1));
    }
    for (final f in flows.entries) {
      for (var i = 0; i < f.value.length; i++) {
        final tid = ++id;
        ev.add(
          e('testStart', {
            'test': {
              'id': tid,
              'name': _testName(f.key, i),
              'suiteID': 0,
              'groupIDs': [
                rootId,
                gids[f.key]!,
                if (nestedId != null && i == 0 && f.key == flows.keys.first)
                  nestedId,
              ],
              'metadata': _meta,
              'line': 40 + i,
              'column': 5,
              'url': 'file://$_path',
            },
          }),
        );
        for (final m in i == 0 ? prints : const <String>[]) {
          ev.add(
            e('print', {'testID': tid, 'messageType': 'print', 'message': m}),
          );
        }
        switch (f.value[i]) {
          case _T.ok:
            ev.add(
              e('testDone', {
                'testID': tid,
                'result': 'success',
                'skipped': false,
                'hidden': false,
              }),
            );
            if (lateErrorFor == f.key && i == 0) {
              ev.add(
                e('error', {
                  'testID': tid,
                  'error': 'late async error',
                  'stackTrace': '#0 main',
                  'isFailure': false,
                }),
              );
            }
          case _T.skip:
            ev.add(
              e('testDone', {
                'testID': tid,
                'result': 'success',
                'skipped': true,
                'hidden': false,
              }),
            );
          case _T.fail || _T.err:
            final failure = f.value[i] == _T.fail;
            ev.add(
              e('error', {
                'testID': tid,
                'error': 'Expected: <1> Actual: <2>',
                'stackTrace': '#0 main',
                'isFailure': failure,
              }),
            );
            ev.add(
              e('testDone', {
                'testID': tid,
                'result': failure ? 'failure' : 'error',
                'skipped': false,
                'hidden': false,
              }),
            );
          case _T.cancel:
            ev.add(
              e('testDone', {
                'testID': tid,
                'result': 'error',
                'skipped': false,
                'hidden': false,
              }),
            );
          case _T.missing:
            break; // started, never finished: the device died here
        }
      }
    }
    if (cancelledTearDownAll) {
      final tid = ++id;
      ev.add(
        e('testStart', {
          'test': {
            'id': tid,
            'name': '(tearDownAll)',
            'suiteID': 0,
            'groupIDs': [rootId],
            'metadata': _meta,
            'line': null,
            'column': null,
            'url': null,
          },
        }),
      );
      ev.add(
        e('testDone', {
          'testID': tid,
          'result': 'error',
          'skipped': false,
          'hidden': true,
        }),
      );
    }
    ev.add({'type': 'allSuites', 'count': 1, 'time': t += 7});
    if (done != null) ev.add(e('done', {'success': done}));
    return '${ev.map(jsonEncode).join('\n')}\n';
  }
}

/// Runs the REAL generator (dart:-only) with an empty packages config, from
/// tool/ci/affected_tests (the test cwd), like the workflow does.
ProcessResult _gen(List<String> args) {
  final pk = File(p.join(Directory.systemTemp.path, 'gen_empty_pk_$pid.json'))
    ..writeAsStringSync('{"configVersion":2,"packages":[]}');
  return Process.runSync(Platform.resolvedExecutable, [
    '--packages=${pk.path}',
    p.join(Directory.current.path, 'bin', 'gen_integration_entry.dart'),
    ...args,
  ]);
}

String _fixture(String name) => File(
  p.join(Directory.current.path, 'test', 'fixtures', name),
).readAsStringSync();

void _exe(String path, String body) {
  File(path).writeAsStringSync(body);
  Process.runSync('chmod', ['+x', path]);
}
