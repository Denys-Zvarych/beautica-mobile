import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Phase 400 audit (P1/P3/S3) wiring pins on `.github/workflows/pr-validate.yml`.
///
/// - D8 (supersedes P1): no cache of any kind feeds the selector. The `plan`
///   job has no `actions/cache` step, and the selector's Dart setup + pub get
///   run only on a `selective` verdict, never gated on the event name.
/// - P3: `Set up Java 17` in the `test` job runs only when an APK build can.
/// - S3: tests-ran checks every selective event stream on its own (no
///   aggregate `cat` that lets one stream's passes mask an all-skipped one).
void main() {
  final wfFile = File(
    p.normalize(
      p.join(
        Directory.current.path,
        '..',
        '..',
        '..',
        '.github',
        'workflows',
        'pr-validate.yml',
      ),
    ),
  );
  final haveWf = wfFile.existsSync();
  final skip = haveWf ? false : 'not inside the beautica-mobile tree';

  late YamlMap wf;
  late YamlMap jobs;
  setUpAll(() {
    if (!haveWf) return;
    wf = loadYaml(wfFile.readAsStringSync()) as YamlMap;
    jobs = wf['jobs'] as YamlMap;
  });

  YamlMap step(String job, String name) {
    final steps = (jobs[job] as YamlMap)['steps'] as YamlList;
    final hits = [
      for (final s in steps.cast<YamlMap>())
        if (s['name'] == name) s,
    ];
    expect(hits, hasLength(1), reason: '$job: step "$name"');
    return hits.single;
  }

  String cond(YamlMap s) => (s['if'] ?? '').toString();

  group('D8 no cache feeds the selector', () {
    test('plan job has no actions/cache step (restore, save or plain)', () {
      final steps = (jobs['plan'] as YamlMap)['steps'] as YamlList;
      for (final s in steps.cast<YamlMap>()) {
        expect(
          (s['uses'] ?? '').toString(),
          isNot(startsWith('actions/cache')),
          reason: 'plan: ${s['name']}',
        );
      }
    });

    // Exact match (audit L2): `contains("== 'selective'")` also accepted
    // `... == 'selective' || always()`.
    const selectiveOnly =
        "(steps.guard.outputs.mode || steps.plan.outputs.mode) == 'selective'";

    test('selector steps run on selective only (exact if:)', () {
      for (final name in [
        'Set up Dart (selector)',
        'Selector pub get (base commit)',
      ]) {
        final s = step('plan', name);
        expect(cond(s), selectiveOnly, reason: name);
        expect(s.containsKey('continue-on-error'), isFalse, reason: name);
        final env = (s['env'] as YamlMap?) ?? YamlMap();
        expect(
          env.keys.map((k) => k.toString()).where((k) => k.startsWith('PUB_')),
          isEmpty,
          reason: '$name: no PUB_* env override may redirect the pub cache',
        );
      }
    });

    test('selector pub get failure is a warning (D7), not a skip of the '
        'fetch', () {
      final run = step(
        'plan',
        'Selector pub get (base commit)',
      )['run'].toString();
      // Architect FIX NOW (2026-10-10): uncached (D8), so every archive is
      // downloaded and its lockfile sha256 actually checked.
      expect(run, contains('(cd "\$d" && dart pub get --enforce-lockfile)'));
      expect(run, contains('|| echo "::warning::selector pub get failed'));
      expect(_bareGet.hasMatch(run), isFalse, reason: 'every pub get pinned');
    });

    test('no PUB_CACHE / PUB_HOSTED_URL at workflow or plan-job env', () {
      for (final (where, env) in [
        ('workflow', wf['env']),
        ('plan job', (jobs['plan'] as YamlMap)['env']),
      ]) {
        final keys = env is YamlMap
            ? env.keys.map((k) => k.toString()).toList()
            : const <String>[];
        expect(keys, isNot(contains('PUB_CACHE')), reason: where);
        expect(keys, isNot(contains('PUB_HOSTED_URL')), reason: where);
      }
    });

    test('no other step in any job saves a cache from a PR run', () {
      for (final j in jobs.entries) {
        final steps = (j.value as YamlMap)['steps'] as YamlList?;
        for (final s in (steps ?? YamlList()).cast<YamlMap>()) {
          final uses = (s['uses'] ?? '').toString();
          if (!uses.startsWith('actions/cache/save@')) continue;
          expect(
            cond(s),
            contains("github.event_name != 'pull_request'"),
            reason: '${j.key}: ${s['name']}',
          );
        }
      }
    }, skip: skip);
  }, skip: skip);

  group('P3 Java only for the APK builds', () {
    test('test job: Set up Java 17 shares the APK condition', () {
      final java = step('test', 'Set up Java 17');
      final apk = step('test', 'Build APK (debug)');
      expect(cond(apk), contains("needs.plan.outputs.mode == 'full'"));
      expect(cond(java), contains("needs.plan.outputs.mode == 'full'"));
      expect(cond(java), contains("needs.plan.outputs.native == 'true'"));
      expect(cond(java), contains("github.event_name != 'pull_request'"));
    });
  }, skip: skip);

  group('L1 selector tests run in CI', () {
    test('selector-tests job runs dart test in tool/ci/affected_tests', () {
      final job = jobs['selector-tests'] as YamlMap?;
      expect(job, isNotNull, reason: 'selector-tests job missing');
      final s = step('selector-tests', 'Selector dart test');
      expect(s['working-directory'], 'tool/ci/affected_tests');
      final run = s['run'].toString();
      expect(run, contains('dart pub get --enforce-lockfile'));
      expect(_bareGet.hasMatch(run), isFalse, reason: 'every pub get pinned');
      expect(
        RegExp(r'^dart test\s*$', multiLine: true).hasMatch(run),
        isTrue,
        reason: 'a bare `dart test` line (no `|| true`, no filter)',
      );
      expect(s.containsKey('if'), isFalse);
      expect(s.containsKey('continue-on-error'), isFalse);
      expect(job!.containsKey('continue-on-error'), isFalse);
    });

    test('fetches the pre-400 parity commit before dart test (no cache, '
        'no continue-on-error, no own if:)', () {
      final s = step('selector-tests', 'Fetch pre-400 parity commit');
      expect(
        s['run'].toString().trim(),
        'git fetch --no-tags --depth=1 origin $pre400Sha',
      );
      expect(s.containsKey('if'), isFalse);
      expect(s.containsKey('continue-on-error'), isFalse);
      expect(s.containsKey('uses'), isFalse);
      final names = [
        for (final st
            in ((jobs['selector-tests'] as YamlMap)['steps'] as YamlList)
                .cast<YamlMap>())
          st['name'],
      ];
      expect(
        names.indexOf('Fetch pre-400 parity commit'),
        lessThan(names.indexOf('Selector dart test')),
      );
      // Same SHA the parity test pins.
      final e2e = File(
        p.join('test', 'pipeline_e2e_test.dart'),
      ).readAsStringSync();
      expect(e2e, contains("const _pre400Sha = '$pre400Sha';"));
    });

    test('runs on every non-noop event, like validate (no path gate)', () {
      final job = jobs['selector-tests'] as YamlMap;
      final validate = jobs['validate'] as YamlMap;
      expect(job['if'], validate['if']);
      expect(job.containsKey('needs'), isFalse, reason: 'off plan path');
    });

    test('same uncached Dart as the selector step (D8)', () {
      final mine = step('selector-tests', 'Set up Dart (selector tests)');
      final plan = step('plan', 'Set up Dart (selector)');
      expect(mine['uses'], plan['uses']);
      expect(
        (mine['with'] as YamlMap)['sdk'],
        (plan['with'] as YamlMap)['sdk'],
      );
      final steps = (jobs['selector-tests'] as YamlMap)['steps'] as YamlList;
      for (final st in steps.cast<YamlMap>()) {
        expect(
          (st['uses'] ?? '').toString(),
          isNot(startsWith('actions/cache')),
          reason: 'selector-tests: ${st['name']}',
        );
        final env = (st['env'] as YamlMap?) ?? YamlMap();
        expect(
          env.keys.map((k) => k.toString()).where((k) => k.startsWith('PUB_')),
          isEmpty,
        );
      }
    });

    test('ci-gate needs selector-tests (a failure is RED)', () {
      final needs = (jobs['ci-gate'] as YamlMap)['needs'] as YamlList;
      expect(needs, contains('selector-tests'));
    });
  }, skip: skip);

  group('S3 tests-ran per stream', () {
    test('selective streams are checked one by one, never concatenated', () {
      final run = step(
        'tests-ran',
        'Verify tests actually ran',
      )['run'].toString();
      expect(run, contains(r'for st in "${streams[@]}"; do'));
      expect(run, contains(r'bash "$chk" "$st" selective'));
      // QA INFO: every non-empty list owes its stream (not only existing).
      for (final o in [
        r'owe unit "$UNIT_COUNT"',
        r'owe golden "$GOLDEN_COUNT"',
        r'owe tz-tokyo "$TZ_COUNT"',
        r'owe tz-honolulu "$TZ_COUNT"',
        r'owe tz-kyiv "$KYIV_COUNT"',
      ]) {
        expect(run, contains(o));
      }
      expect(run, isNot(contains('all-events.json')));
    });

    test('Kyiv stream owed from the base resolver (plan.outputs.kyiv_count '
        '<- steps.sel), Tokyo inference only as a warned fallback', () {
      final outputs = (jobs['plan'] as YamlMap)['outputs'] as YamlMap;
      expect(outputs['kyiv_count'], r'${{ steps.sel.outputs.kyiv_count }}');
      final s = step('tests-ran', 'Verify tests actually ran');
      final env = s['env'] as YamlMap;
      expect(env['KYIV_COUNT'], r'${{ needs.plan.outputs.kyiv_count }}');
      final run = s['run'].toString();
      final primary = run.indexOf(r'if [ -n "${KYIV_COUNT:-}" ]; then');
      final owe = run.indexOf(r'owe tz-kyiv "$KYIV_COUNT"');
      final warn = run.indexOf(
        '::warning::base resolver has no kyiv_count; '
        'inferring from the Tokyo stream',
      );
      final infer = run.indexOf('events/tz-tokyo-events.json >/dev/null');
      expect(primary, isNot(-1));
      expect(owe, greaterThan(primary));
      expect(warn, greaterThan(owe), reason: 'fallback is the else branch');
      expect(infer, greaterThan(warn), reason: 'inference only after warning');
    });
  }, skip: skip);
}

/// A `dart pub get` NOT followed by `--enforce-lockfile`.
final _bareGet = RegExp(r'dart pub get(?! --enforce-lockfile)');

/// Last pre-400 workflow commit (on dev via PR #81).
const pre400Sha = '7b85cb18c809319fa1fd8519349e307dc9498cf4';
