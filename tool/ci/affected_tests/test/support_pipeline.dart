/// Shared harness of the pipeline_e2e_*_test.dart files (audit F6 split the old
/// single file so its scenarios run in parallel): the `Pipeline` fixture that
/// executes the REAL workflow step scripts on a synthetic git repo, the stub
/// `flutter`, and the pre-400 command oracle.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support.dart';

const tzZonesExpr =
    r'''${{ (steps.sel.outputs.mode == 'selective' && steps.sel.outputs.kyiv_count != '1') && '["tokyo","honolulu"]' || '["kyiv-dst","tokyo","honolulu"]' }}''';

const pre400CommitSha = '7b85cb18c809319fa1fd8519349e307dc9498cf4';
const railTest =
    'test/features/booking/presentation/bookings_day_rail_test.dart';
const unrelatedTzTest = 'test/core/time/unrelated_test.dart';

const testSteps = [
  'Test',
  'DST rail guards (market zone)',
  'Third-timezone sweep (host-clock leak detector)',
  'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)',
  'Golden regression tests',
];

const tzDirsCmd = r'''
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

/// Verbatim from [pre400CommitSha] (job `test`, the last pre-400 workflow).
const Map<String, ({Map<String, String> env, String run})> pre400 = {
  'Test': (
    env: {},
    run:
        'mkdir -p build/ci\n'
        'flutter test --coverage --reporter=expanded '
        '--file-reporter=json:build/ci/unit-events.json --exclude-tags golden',
  ),
  'DST rail guards (market zone)': (
    env: {'TZ': 'Europe/Kyiv'},
    run: 'flutter test $railTest --reporter=expanded',
  ),
  'Third-timezone sweep (host-clock leak detector)': (
    env: {'TZ': 'Asia/Tokyo'},
    run: tzDirsCmd,
  ),
  'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)': (
    env: {'TZ': 'Pacific/Honolulu'},
    run: tzDirsCmd,
  ),
  'Golden regression tests': (
    env: {},
    run: 'flutter test test/golden/ --reporter=expanded',
  ),
};

/// The upload-artifact name the workflow gives a run_list.sh / flutter stream
/// file (`unit-2-events.json` -> `events-unit-2`, `unit-events.json` ->
/// `events-unit-whole`, `tz-kyiv-events.json` -> `events-tz-kyiv-dst`).
String artifactOfStream(String file) {
  final base = file.replaceFirst(RegExp(r'-events\.json$'), '');
  return switch (base) {
    'unit' => 'events-unit-whole',
    'tz-kyiv' => 'events-tz-kyiv-dst',
    _ => 'events-$base',
  };
}

bool which(String bin) =>
    Process.runSync('bash', ['-c', 'command -v $bin']).exitCode == 0;

YamlMap stepOf(YamlMap jobs, String job, String name) {
  final steps = (jobs[job] as YamlMap)['steps'] as YamlList;
  final hits = [
    for (final s in steps.cast<YamlMap>())
      if (s['name'] == name) s,
  ];
  expect(hits, hasLength(1), reason: '$job: step "$name"');
  return hits.single;
}

/// Body of the `if [ "$CI_MODE" = "full" ]; then ... else|elif` branch.
String fullBranch(String run) =>
    branchOf(run, 'if [ "\$CI_MODE" = "full" ]; then');

/// Body of the `<opener> ... else|elif` branch of [run].
String branchOf(String run, String opener) {
  final lines = run.split('\n');
  final start = lines.indexWhere((l) => l.trim() == opener);
  expect(start, isNot(-1), reason: 'no "$opener" in:\n$run');
  final end = lines.indexWhere(
    (l) => RegExp(r'^\s*(else|elif)\b').hasMatch(l),
    start + 1,
  );
  expect(end, isNot(-1));
  return lines.sublist(start + 1, end).join('\n');
}

List<String> norm(String s) => [
  for (final l in s.split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];

final class Call {
  Call(this.step, this.tz, this.args);
  final String step;
  final String tz;
  final List<String> args;
  List<String> get files => [
    for (final a in args)
      if (a.endsWith('_test.dart')) a,
  ];
}

final class Pipeline {
  Pipeline(this.mobile, this.jobs)
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
    Link(
      p.join(trusted.path, 'shard_units.sh'),
    ).createSync(p.join(mobile, 'tool', 'ci', 'shard_units.sh'));
    Directory(p.join(ws2, 'trusted')).createSync(recursive: true);
    Link(p.join(ws2, 'pr')).createSync(pr);

    final stub = File(p.join(ws, 'bin', 'flutter'))
      ..createSync(recursive: true)
      ..writeAsStringSync(stubFlutter);
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
      railTest: pkg('shared/time/clock.dart'),
      unrelatedTzTest: 'void main() {}\n',
      // 140: big enough that 81 edited files stay under the 60% FULL threshold.
      ...filler(140),
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
  String lastShardLog = '';

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
    // Phase 402: runs the REAL `Shard unit tests` step. Scenarios that only
    // read the `Select tests` outputs opt out (a full one costs ~20 s).
    bool shard = true,
    // Audit D10: extra env for the `Shard unit tests` step only (e.g. a PATH
    // whose `dart` is missing or broken, as after a failed setup-dart / pub get).
    Map<String, String> shardEnv = const {},
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
      stepOf(jobs, 'plan', 'Select tests (selector from the BASE commit)'),
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

    // Phase 402: the REAL `Shard unit tests` step (base shard_units.sh +
    // selector), then the artifact hop ci-unit-shards -> RUNNER_TEMP/shards.
    if (!shard) return out;
    final shOut = File(p.join(rt, 'gh_output_shard'))..writeAsStringSync('');
    final sh = _bash(
      stepOf(jobs, 'plan', 'Shard unit tests (script from the BASE commit)'),
      env: {
        'SHARD_MODE': out['mode'] ?? '',
        'SHARD_UNIT_COUNT': out['unit_count'] ?? '',
        'SHARD_THRESHOLD': out['unit_warn_threshold'] ?? '',
        'GITHUB_WORKSPACE': bootstrap ? ws2 : ws,
        'RUNNER_TEMP': rt,
        'GITHUB_OUTPUT': shOut.path,
        ...shardEnv,
      },
      cwd: pr,
    );
    lastShardLog = '${sh.stdout}\n${sh.stderr}';
    expect(
      sh.exitCode,
      0,
      reason: 'Shard step must never go red: $lastShardLog',
    );
    for (final l in shOut.readAsLinesSync()) {
      final i = l.indexOf('=');
      if (i > 0) out[l.substring(0, i)] = l.substring(i + 1);
    }
    final shardsSrc = Directory(p.join(rt, 'ci', 'shards'));
    if (shardsSrc.existsSync() && out['unit_shards'] != '["whole"]') {
      final dst = Directory(p.join(testRt, 'shards'))..createSync();
      for (final f in shardsSrc.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('unit-')) {
          f.copySync(p.join(dst.path, p.basename(f.path)));
        }
      }
    }
    // plan.outputs.tz_zones (a pure expression, pinned by the static group).
    out['tz_zones'] = out['mode'] == 'selective' && out['kyiv_count'] != '1'
        ? '["tokyo","honolulu"]'
        : '["kyiv-dst","tokyo","honolulu"]';
    return out;
  }

  static const _labelGate =
      "(github.event.action != 'labeled' || "
      "github.event.label.name == 'full-ci' || "
      "github.event.label.name == 'run-patrol')";

  /// Evaluates a split test job's `if:` against the plan outputs, after
  /// pinning its exact text (so the evaluation below cannot drift from it).
  bool jobRuns(String job, Map<String, String> out, {bool native = false}) {
    final cond = (jobs[job] as YamlMap)['if']
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (job == 'apk') {
      expect(
        cond,
        "$_labelGate && (needs.plan.outputs.mode == 'full' || "
        "needs.plan.outputs.native == 'true')",
      );
      return out['mode'] == 'full' || native;
    }
    final key = const {
      'unit': 'unit_count',
      'tz-sweeps': 'tz_count',
      'goldens': 'golden_count',
    }[job]!;
    expect(
      cond,
      "$_labelGate && (needs.plan.outputs.mode == 'full' || "
      "(needs.plan.outputs.mode == 'selective' && "
      "needs.plan.outputs.$key != '0'))",
    );
    return out['mode'] == 'full' ||
        (out['mode'] == 'selective' && out[key] != '0');
  }

  /// The unit universe: every line of the base-computed `unit-all.txt`
  /// (full: `--all`; sorted).
  List<String> universeUnit() =>
      File(p.join(rt, 'ci', 'shards', 'unit-all.txt')).readAsLinesSync()
        ..removeWhere((l) => l.isEmpty)
        ..sort();

  /// Runs the REAL `Test` step of the `unit` job for one matrix [shard].
  /// [fail] makes the stub report that one file as failing.
  ProcessResult runUnitShard(
    Map<String, String> out,
    String shard, {
    String? fail,
  }) {
    final s = stepOf(jobs, 'unit', 'Test');
    final log = File(p.join(ws, 'stub.log'))..writeAsStringSync('');
    return _bash(
      s,
      env: {
        'CI_MODE': out['mode']!,
        'SHARD': shard,
        'RUNNER_TEMP': testRt,
        'STUB_LOG': log.path,
        if (fail != null) 'STUB_FAIL': fail,
      },
      cwd: pr,
    );
  }

  /// Executes the split test jobs in workflow order (unit shards, tz-sweeps
  /// legs, goldens); returns the flutter calls.
  List<Call> runTestJob(Map<String, String> out) {
    final ci = Directory(p.join(pr, 'build', 'ci'));
    if (ci.existsSync()) ci.deleteSync(recursive: true);
    final calls = <Call>[];
    Map<String, String> envOf(YamlMap s, Map<String, String> extra) => {
      for (final e in ((s['env'] as YamlMap?) ?? YamlMap()).entries)
        e.key.toString(): e.value.toString(),
      'CI_MODE': out['mode']!,
      ...extra,
    }..removeWhere((k, v) => v.startsWith(r'${{'));

    if (jobRuns('unit', out)) {
      final s = stepOf(jobs, 'unit', 'Test');
      for (final sh in jsonDecode(out['unit_shards']!) as List) {
        calls.addAll(
          _runLogged('Test', s['run'].toString(), envOf(s, {'SHARD': '$sh'})),
        );
      }
    }
    if (jobRuns('tz-sweeps', out)) {
      const stepZone = {
        'DST rail guards (market zone)': 'kyiv-dst',
        'Third-timezone sweep (host-clock leak detector)': 'tokyo',
        'Fourth-timezone sweep (west-of-Kyiv day-boundary detector)':
            'honolulu',
      };
      for (final zone in jsonDecode(out['tz_zones']!) as List) {
        for (final e in stepZone.entries) {
          final s = stepOf(jobs, 'tz-sweeps', e.key);
          expect(s['if'], "matrix.zone == '${e.value}'", reason: e.key);
          if (e.value != zone) continue;
          calls.addAll(_runLogged(e.key, s['run'].toString(), envOf(s, {})));
        }
      }
    }
    if (jobRuns('goldens', out)) {
      final s = stepOf(jobs, 'goldens', 'Golden regression tests');
      expect(s.containsKey('if'), isFalse, reason: 'job-level if only');
      calls.addAll(
        _runLogged(s['name'].toString(), s['run'].toString(), envOf(s, {})),
      );
    }
    return calls;
  }

  /// The pinned pre-400 commands through the same harness (parity oracle).
  List<Call> runPre400() {
    final calls = <Call>[];
    for (final name in testSteps) {
      final c = pre400[name]!;
      calls.addAll(_runLogged(name, c.run, c.env, pipefail: false));
    }
    return calls;
  }

  List<Call> _runLogged(
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
          Call(
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

  YamlMap step(String job, String name) => stepOf(jobs, job, name);

  /// Runs one REAL workflow step of [job] by name (no GITHUB_OUTPUT plumbing).
  ProcessResult runStep(
    String job,
    String name, {
    required Map<String, String> env,
    required String cwd,
  }) => _bash(stepOf(jobs, job, name), env: env, cwd: cwd, pipefail: false);

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
        stepOf(
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

  Directory get lcovArtifacts => Directory(p.join(ws, 'lcov_artifacts'));

  /// The `unit` job's `Upload shard coverage` hop for [shard]: evaluates the
  /// step's own `if:` (pinned) and, when it fires, stores coverage/lcov.info
  /// as the artifact the step names (`lcov-unit-<shard>`).
  void uploadShardCoverage(Map<String, String> out, String shard) {
    final up = stepOf(jobs, 'unit', 'Upload shard coverage');
    expect(up['if'], "success() && needs.plan.outputs.run_all == 'true'");
    if (out['run_all'] != 'true') return;
    final w = up['with'] as YamlMap;
    final name = w['name'].toString().replaceAll(r'${{ matrix.shard }}', shard);
    final src = File(p.join(pr, w['path'].toString()));
    expect(src.existsSync(), isTrue, reason: 'if-no-files-found: error');
    final dst = Directory(p.join(lcovArtifacts.path, name))
      ..createSync(recursive: true);
    src.copySync(p.join(dst.path, 'lcov.info'));
  }

  void resetCoverage() {
    if (lcovArtifacts.existsSync()) lcovArtifacts.deleteSync(recursive: true);
    lcovArtifacts.createSync(recursive: true);
  }

  /// The `coverage` job: download `lcov-unit-*` into lcov/<artifact>/ and run
  /// the REAL `Merge shard coverage (lcov -a)` step. `sudo` and `lcov` are
  /// stubs (no apt, no lcov on the host): `lcov -a f -a g -o out` concatenates.
  ({int code, String output, String merged, String apt}) mergeCoverage() {
    final dir = Directory(p.join(ws, 'cov_job'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final dl = Directory(p.join(dir.path, 'lcov'))..createSync();
    final dlStep = stepOf(jobs, 'coverage', 'Download shard coverage');
    expect((dlStep['with'] as YamlMap)['pattern'], 'lcov-unit-*');
    for (final a in lcovArtifacts.listSync().whereType<Directory>()) {
      if (!p.basename(a.path).startsWith('lcov-unit-')) continue;
      final d = Directory(p.join(dl.path, p.basename(a.path)))..createSync();
      File(p.join(a.path, 'lcov.info')).copySync(p.join(d.path, 'lcov.info'));
    }
    final bin = Directory(p.join(dir.path, 'stubbin'))..createSync();
    final aptLog = File(p.join(dir.path, 'apt.log'))..writeAsStringSync('');
    File(p.join(bin.path, 'sudo')).writeAsStringSync(
      '#!/usr/bin/env bash\nprintf "%s\\n" "\$*" >>"${aptLog.path}"\nexit 0\n',
    );
    File(p.join(bin.path, 'lcov')).writeAsStringSync(r'''#!/usr/bin/env bash
files=(); out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version) echo "lcov: stub"; exit 0 ;;
    --summary) echo "  lines......: 50.0% (1 of 2 lines)"; exit 0 ;;
    -a) files+=("$2"); shift 2 ;;
    -o) out="$2"; shift 2 ;;
    *) echo "stub lcov: unexpected $1" >&2; exit 1 ;;
  esac
done
cat "${files[@]}" >"$out"
''');
    Process.runSync('chmod', [
      '+x',
      p.join(bin.path, 'sudo'),
      p.join(bin.path, 'lcov'),
    ]);
    final summary = File(p.join(dir.path, 'summary.md'))..writeAsStringSync('');
    final st = stepOf(jobs, 'coverage', 'Merge shard coverage (lcov -a)');
    final r = _bash(
      st,
      env: {
        for (final e in (st['env'] as YamlMap).entries)
          e.key.toString(): e.value.toString(),
        'GITHUB_STEP_SUMMARY': summary.path,
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
      cwd: dir.path,
    );
    final merged = File(p.join(dir.path, 'coverage', 'lcov.info'));
    return (
      code: r.exitCode,
      output: '${r.stdout}\n${r.stderr}',
      merged: merged.existsSync() ? merged.readAsStringSync() : '',
      apt: aptLog.readAsStringSync(),
    );
  }

  /// Runs the REAL `Verify tests actually ran` step (base checkout layout:
  /// tool/ci/tests_ran.sh + min_tests.txt, artifact in events/).
  ({int code, String output}) testsRan(
    Map<String, String> out, {
    int floor = 1,
    bool streams = true,
    Set<String> drop = const {},
    // Test hook: edit the downloaded artifact tree before the step runs.
    void Function(Directory dl)? tamper,
    // false: the base checkout predates collect_events.sh (bootstrap).
    bool withCollector = true,
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
    File(
      p.join(mobile, 'tool', 'ci', 'verify_shards.sh'),
    ).copySync(p.join(dir.path, 'tool', 'ci', 'verify_shards.sh'));
    if (withCollector) {
      File(
        p.join(mobile, 'tool', 'ci', 'collect_events.sh'),
      ).copySync(p.join(dir.path, 'tool', 'ci', 'collect_events.sh'));
    }
    // artifact hop: ci-unit-shards -> shards/ (absent for ["whole"])
    final shardsSrc = Directory(p.join(testRt, 'shards'));
    if (shardsSrc.existsSync() && out['unit_shards'] != '["whole"]') {
      final dst = Directory(p.join(dir.path, 'shards'))..createSync();
      for (final f in shardsSrc.listSync().whereType<File>()) {
        f.copySync(p.join(dst.path, p.basename(f.path)));
      }
    }
    // Artifact hop (audit S-L1): download-artifact WITHOUT merge-multiple puts
    // every `events-*` artifact in its own `events-dl/<artifact>/` directory;
    // the step itself (collect_events.sh) builds `events/`.
    final dl = Directory(p.join(dir.path, 'events-dl'))..createSync();
    final ci = Directory(p.join(pr, 'build', 'ci'));
    if (streams && ci.existsSync()) {
      for (final f in ci.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (name.endsWith('-events.json') &&
            !drop.contains(name.replaceFirst('-events.json', ''))) {
          final art = Directory(p.join(dl.path, artifactOfStream(name)))
            ..createSync();
          f.copySync(p.join(art.path, name));
        }
      }
    }
    tamper?.call(dl);
    final r = _bash(
      stepOf(jobs, 'tests-ran', 'Verify tests actually ran'),
      env: {
        'RUN_ALL': out['run_all'] ?? '',
        'TEST_COUNT': out['test_count'] ?? '',
        'UNIT_COUNT': out['unit_count'] ?? '',
        'GOLDEN_COUNT': out['golden_count'] ?? '',
        'TZ_COUNT': out['tz_count'] ?? '',
        'KYIV_COUNT': out['kyiv_count'] ?? '',
        'UNIT_SHARDS': out['unit_shards'] ?? '',
        'UNIT_SHARD_COUNT': out['unit_shard_count'] ?? '',
      },
      cwd: dir.path,
    );
    return (code: r.exitCode, output: '${r.stdout}\n${r.stderr}');
  }
}

/// Logs `TZ<TAB>arg1\x1farg2\x1f...` per call; writes a passing stream (one
/// suite + one real pass per listed file; [Pipeline.fullPasses] for a
/// whole-suite call) to the --file-reporter path when one is given.
const stubFlutter = r'''#!/usr/bin/env bash
set -eu
{ printf '%s\t' "${TZ:-}"; printf '%s\x1f' "$@"; printf '\n'; } >>"$STUB_LOG"
out=""; cov=0
for a in "$@"; do case "$a" in --file-reporter=json:*) out="${a#--file-reporter=json:}" ;; --coverage) cov=1 ;; esac; done
if [ "$cov" -eq 1 ]; then
  mkdir -p coverage
  # one record per call, named by the first listed file (or all_test for a whole-suite call)
  f="all_test"; for a in "$@"; do case "$a" in *_test.dart) f="$a"; break ;; esac; done
  printf 'TN:\nSF:lib/%s.dart\nDA:1,1\nDA:2,0\nLF:2\nLH:1\nend_of_record\n' "$f" >coverage/lcov.info
fi
[ -n "$out" ] || exit 0
: >"$out"; i=0
rc=0
emit() {
  res=success
  if [ -n "${STUB_FAIL:-}" ] && [ "$1" = "$STUB_FAIL" ]; then res=failure; rc=1; fi
  printf '{"suite":{"id":%d,"path":"%s"},"type":"suite"}\n' "$i" "$1"
  printf '{"test":{"id":%d,"name":"t%d","suiteID":%d},"type":"testStart"}\n' "$((i + 1000))" "$i" "$i"
  printf '{"testID":%d,"result":"%s","skipped":false,"hidden":false,"type":"testDone"}\n' "$((i + 1000))" "$res"
  i=$((i + 1))
}
nfiles=0
for a in "$@"; do case "$a" in *_test.dart) emit "$a" >>"$out"; nfiles=$((nfiles + 1)) ;; esac; done
if [ "$nfiles" -eq 0 ]; then for _ in 1 2 3 4 5; do emit "test/all_test.dart" >>"$out"; done; fi
echo '{"success":true,"type":"done"}' >>"$out"
exit "$rc"
''';
