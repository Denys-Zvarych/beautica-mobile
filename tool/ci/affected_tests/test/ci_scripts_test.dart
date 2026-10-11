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
        expect(text(r), contains('All 2 selected groups ran'));
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
        expect(lines.where((l) => l.startsWith('::add-mask::')), isEmpty);
        expect(lines.where((l) => l.startsWith('::stop-commands::')), isEmpty);
        expect(lines, contains(' ::add-mask::s3cret'));
        expect(lines, contains(' ::stop-commands::tok'));
        // the timeout path replays the same way
        final t = run(null, log: '::add-mask::z\n', rc: 124);
        expect(
          (t.stdout as String).split('\n').where((l) => l.startsWith('::add-')),
          isEmpty,
        );
      },
    );

    test('hang: timeout rc 124 -> FAIL naming the bound (even with a '
        'complete JSON)', () {
      final r = run(pass, rc: 124);
      expect(r.exitCode, 1);
      expect(text(r), contains('TIMED OUT after 900s'));
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
        expect(text(r), contains('TIMED OUT after 1s'));
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
  }, skip: skip);
}

enum _T { ok, skip, fail, err, missing }

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
  });

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
          case _T.missing:
            break; // started, never finished: the device died here
        }
      }
    }
    ev.add({'type': 'allSuites', 'count': 1, 'time': t += 7});
    if (done != null) ev.add(e('done', {'success': done}));
    return '${ev.map(jsonEncode).join('\n')}\n';
  }
}

String _fixture(String name) => File(
  p.join(Directory.current.path, 'test', 'fixtures', name),
).readAsStringSync();

void _exe(String path, String body) {
  File(path).writeAsStringSync(body);
  Process.runSync('chmod', ['+x', path]);
}
