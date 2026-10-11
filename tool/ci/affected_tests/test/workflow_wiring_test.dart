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

  group('phase 401 integration job wiring', () {
    List<YamlMap> steps(String job) =>
        ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>().toList();
    YamlMap byId(String id) => steps(
      'integration',
    ).singleWhere((s) => s['id'] == id, orElse: () => YamlMap());
    String script(String id) =>
        ((byId(id)['with'] as YamlMap)['script']).toString();

    test(
      'D4: needs plan; if = label gate AND (full OR integration_count != 0)',
      () {
        final job = jobs['integration'] as YamlMap;
        expect(job['needs'], 'plan');
        final c = job['if'].toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        expect(
          c,
          "(github.event.action != 'labeled' || "
          "github.event.label.name == 'full-ci' || "
          "github.event.label.name == 'run-patrol') && "
          "(needs.plan.outputs.mode == 'full' || "
          "needs.plan.outputs.integration_count != '0')",
        );
        final outs = (jobs['plan'] as YamlMap)['outputs'] as YamlMap;
        expect(
          outs['integration_count'],
          r'${{ steps.sel.outputs.integration_count }}',
        );
      },
    );

    test('full mode: the six part invocations are the pre-401 command lines '
        '(per-part 1500 s bound, own log, attempts identical)', () {
      for (final n in ['1', '2']) {
        final a1 = script('it-part$n-attempt-1');
        expect(
          a1,
          startsWith(
            'timeout --signal=TERM --kill-after=60 1500 flutter test '
            'integration_test/all_tests_part$n.dart > part$n.log 2>&1; ',
          ),
        );
        expect(a1, isNot(contains('ci_selected_tests')));
        expect(script('it-part$n-attempt-2'), a1);
        expect(script('it-part$n-attempt-3'), a1);
        // Only attempt 1 gained an `if:`; 2 and 3 chain off attempt 1's
        // outcome, so a skipped attempt 1 (selected run) skips them too.
        expect(
          byId('it-part$n-attempt-1')['if'],
          "steps.entry.outputs.entry != 'selected'",
        );
        expect(
          byId('it-part$n-attempt-2')['if'],
          "steps.it-part$n-attempt-1.outcome == 'failure'",
        );
      }
    });

    const attemptScript =
        r'bash "$GITHUB_WORKSPACE/trusted/tool/ci/run_it_attempt.sh" '
        r'integration_test/ci_selected_tests.dart selected.log '
        r'"$SEL_BOUND" "$RUNNER_TEMP/it-sel"';

    test('P7/S5: the three selected attempts are ONE base-owned script call '
        '(no inline copy of the timeout/success logic)', () {
      for (var k = 1; k <= 3; k++) {
        final sc = script('it-sel-attempt-$k').trim();
        expect(sc, attemptScript, reason: 'attempt $k');
        expect(sc, isNot(contains('flutter test')));
        final env = byId('it-sel-attempt-$k')['env'] as YamlMap;
        expect(env['SEL_BOUND'], r'${{ steps.entry.outputs.bound }}');
        expect(byId('it-sel-attempt-$k')['continue-on-error'], isTrue);
        expect(
          byId('it-sel-attempt-$k')['if'].toString(),
          startsWith("steps.entry.outputs.entry == 'selected'"),
        );
      }
      // The script lives under tool/ci (forced FULL when edited) and is run
      // from the BASE checkout.
      expect(File('../run_it_attempt.sh').existsSync(), isTrue);
    });

    test('P5: attempt 2 needs 1 failed; attempt 3 needs 1 and 2 failed and '
        'attempt 2 NOT flagged deterministic', () {
      expect(
        byId('it-sel-attempt-2')['if'],
        "steps.entry.outputs.entry == 'selected' && "
        "steps.it-sel-attempt-1.outcome == 'failure'",
      );
      expect(
        byId('it-sel-attempt-3')['if'],
        "steps.entry.outputs.entry == 'selected' && "
        "steps.it-sel-attempt-1.outcome == 'failure' && "
        "steps.it-sel-attempt-2.outcome == 'failure' && "
        "steps.it-sel-attempt-2.outputs.deterministic != 'true'",
      );
    });

    test('entry step: selective only, generator + attempt script from the '
        'BASE checkout, every non-"selected" result falls back to parts', () {
      final e = byId('entry');
      expect(e['if'], "needs.plan.outputs.mode == 'selective'");
      final run = e['run'].toString();
      expect(run, contains(r'$GITHUB_WORKSPACE/trusted/tool/ci'));
      expect(run, contains('gen_integration_entry.dart'));
      expect(run, contains('run_it_attempt.sh'));
      expect(run, contains('entry=parts'));
      final names = steps('integration').map((s) => s['name']).toList();
      expect(
        names.indexOf('Checkout trusted tooling (base commit)'),
        lessThan(names.indexOf(e['name'])),
      );
      final trusted = steps('integration').singleWhere(
        (s) => s['name'] == 'Checkout trusted tooling (base commit)',
      );
      expect((trusted['with'] as YamlMap)['path'], 'trusted');
      expect(
        (trusted['with'] as YamlMap)['ref'],
        r'${{ github.event.pull_request.base.sha || github.sha }}',
      );
      expect(cond(trusted), "needs.plan.outputs.mode == 'selective'");
    });

    test('S1: the entry step deletes any PR-made target BEFORE the generator '
        'runs', () {
      final run = byId('entry')['run'].toString();
      final rm = run.indexOf('rm -rf integration_test/ci_selected_tests.dart');
      final gen = run.indexOf('dart --packages=');
      expect(rm, isNonNegative);
      expect(gen, greaterThan(rm));
    });

    test('S3: the generator runs with an EMPTY packages config (the PR '
        'tree\'s .dart_tool is ignored) and has no package imports', () {
      final run = byId('entry')['run'].toString();
      expect(run, contains(r'dart --packages="$pk" "$gen"'));
      expect(run, contains('{"configVersion":2,"packages":[]}'));
      expect(run, isNot(contains(r'dart "$gen"')));
      final src = File('bin/gen_integration_entry.dart').readAsStringSync();
      final imports = RegExp(
        '^import\\s+[\'"]([^\'"]+)[\'"]',
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)!).toList();
      expect(imports, isNotEmpty);
      expect(
        imports.where((i) => !i.startsWith('dart:')),
        isEmpty,
        reason: 'the generator must stay dart:-only: $imports',
      );
    });

    test('P3/P4: bound = clamp(420 + 45 * count, 600, 1500); the YAML cap '
        'equals the generator cap', () {
      final run = byId('entry')['run'].toString();
      expect(run, contains(r'bound=$((420 + 45 * count))'));
      expect(run, contains(r'[ "$bound" -lt 600 ] && bound=600'));
      expect(run, contains(r'[ "$bound" -gt 1500 ] && bound=1500'));
      expect(run, contains(r'echo "bound=$bound"'));
      final cap = RegExp(r'"\$c" -le (\d+)').firstMatch(run)!.group(1)!;
      final src = File('bin/gen_integration_entry.dart').readAsStringSync();
      expect(
        RegExp(r'const maxSelectedFlows = (\d+);').firstMatch(src)!.group(1),
        cap,
      );
    });

    test('S2: a PR-made trusted/ is removed BEFORE the base checkout, and the '
        'checkout is proven to be the base commit before anything runs', () {
      final names = [for (final s in steps('integration')) s['name']];
      final rm = names.indexOf('Remove any PR-made trusted/ path');
      final co = names.indexOf('Checkout trusted tooling (base commit)');
      final vf = names.indexOf(
        'Verify the trusted checkout is the base commit',
      );
      final ch = names.indexOf(byId('entry')['name']);
      expect(rm, isNonNegative);
      expect(co, greaterThan(rm));
      expect(vf, greaterThan(co));
      expect(ch, greaterThan(vf));
      final rmStep = steps('integration')[rm];
      expect(rmStep['run'], r'rm -rf "$GITHUB_WORKSPACE/trusted"');
      expect(cond(rmStep), "needs.plan.outputs.mode == 'selective'");
      final vs = steps('integration')[vf];
      expect(cond(vs), "needs.plan.outputs.mode == 'selective'");
      expect(vs['run'], contains('rev-parse HEAD'));
      expect(
        (vs['env'] as YamlMap)['EXPECTED_SHA'],
        r'${{ github.event.pull_request.base.sha || github.sha }}',
      );
    });

    test('S4: no `run:` step of the integration job interpolates step '
        'outputs / needs / event data into the script text', () {
      for (final st in steps('integration')) {
        final run = (st['run'] ?? '').toString();
        expect(
          RegExp(r'\$\{\{\s*(steps|needs|github\.event)').hasMatch(run),
          isFalse,
          reason: '${st['name']}',
        );
      }
      final v = steps('integration').singleWhere(
        (s) => s['name'] == 'Verify integration tests passed on some attempt',
      );
      final env = v['env'] as YamlMap;
      expect(env['ENTRY'], r'${{ steps.entry.outputs.entry }}');
      for (var k = 1; k <= 3; k++) {
        expect(env['SEL$k'], '\${{ steps.it-sel-attempt-$k.outcome }}');
      }
    });

    test('verify step accepts the selected attempts only when selected', () {
      final v = steps('integration').singleWhere(
        (s) => s['name'] == 'Verify integration tests passed on some attempt',
      );
      final run = v['run'].toString();
      expect(run, contains(r'"$SEL1" == "success"'));
      expect(run, contains(r'"$SEL3" == "success"'));
      expect(run, contains(r'"$P2A3" == "success"'));
    });

    test('P2: Gradle cache is restored on every run but SAVED only outside '
        'pull_request; SHA-pinned; same key; nothing else caches here', () {
      final restore = byId('gradle-cache');
      final ru = restore['uses'].toString();
      expect(ru, startsWith('actions/cache/restore@'));
      expect(ru, matches(RegExp(r'^actions/cache/restore@[0-9a-f]{40}$')));
      final save = steps(
        'integration',
      ).singleWhere((s) => s['name'] == 'Save Gradle cache');
      expect(save['uses'].toString(), startsWith('actions/cache/save@'));
      expect(
        save['uses'].toString().split('@').last,
        ru.split('@').last,
        reason: 'one pinned version for restore and save',
      );
      expect(cond(save), contains("github.event_name != 'pull_request'"));
      expect(cond(save), contains('success()'));
      final rw = restore['with'] as YamlMap;
      final sw = save['with'] as YamlMap;
      // N1: the SAVE key is the restore step's own computed key, never a
      // second hashFiles() evaluated after the build (key drift).
      expect(sw['key'], r'${{ steps.gradle-cache.outputs.cache-primary-key }}');
      expect(sw['key'].toString(), isNot(contains('hashFiles')));
      expect(sw['path'], rw['path']);
      expect(rw['key'], contains("hashFiles('android/**/*.gradle*'"));
      expect(rw['key'], contains('gradle-wrapper.properties'));
      // SEC-INFO-3: android/gradle.properties decides Gradle inputs too.
      expect(rw['key'], contains("'android/gradle.properties'"));
      expect(rw['key'], contains("'pubspec.lock'"));
      expect(rw['path'].toString(), contains('~/.gradle/caches'));
      expect(rw['path'].toString(), contains('~/.gradle/wrapper'));
      // The combined `actions/cache@` would save from a PR run in its post step.
      for (final st in steps('integration')) {
        expect(
          (st['uses'] ?? '').toString(),
          isNot(matches(RegExp(r'^actions/cache@'))),
          reason: '${st['name']}',
        );
      }
      final names = [for (final st in steps('integration')) st['name']];
      expect(
        names.indexOf('Restore Gradle cache'),
        lessThan(names.indexOf('Run integration tests — part 1 (attempt 1)')),
      );
      expect(
        names.indexOf('Save Gradle cache'),
        greaterThan(
          names.indexOf('Verify integration tests passed on some attempt'),
        ),
      );
    });

    test('P1: the plan checkout stays full-history on pull_request (a bounded '
        'window was measured at <5% of the fetch and dropped, D7)', () {
      final co = ((jobs['plan'] as YamlMap)['steps'] as YamlList)
          .cast<YamlMap>();
      final tree = co.singleWhere(
        (s) => s['name'] == 'Checkout tree under test (full history)',
      );
      expect(
        (tree['with'] as YamlMap)['fetch-depth'].toString(),
        r"${{ github.event_name == 'pull_request' && 0 || 1 }}",
      );
      expect([
        for (final s in co) s['name'],
      ], isNot(contains(startsWith('Deepen history'))));
    });

    test('D5: patrol and integration-profile gating is untouched (native '
        'paths / run-patrol label on PRs; dispatch always)', () {
      final patrol = (jobs['patrol'] as YamlMap)['if']
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      expect(
        patrol,
        "github.event_name == 'workflow_dispatch' || "
        "(github.event_name == 'pull_request' && "
        "(contains(github.event.pull_request.labels.*.name, 'run-patrol') || "
        "needs.plan.outputs.native == 'true'))",
      );
      final prof = (jobs['integration-profile'] as YamlMap)['if']
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      expect(prof, contains("github.event_name == 'workflow_dispatch'"));
      expect(prof, contains("'run-patrol'"));
      expect(prof, isNot(contains('integration_count')));
      expect(patrol, isNot(contains('integration_count')));
    });

    test('no stale commented-out `flutter test integration_test/` example '
        'left above the integration job', () {
      final txt = wfFile.readAsStringSync();
      final head = txt.substring(
        txt.indexOf('# End-to-end integration tests'),
        txt.indexOf('\n  integration:\n'),
      );
      expect(head, isNot(contains('#   flutter test integration_test/\n')));
    });
  }, skip: skip);
}

/// A `dart pub get` NOT followed by `--enforce-lockfile`.
final _bareGet = RegExp(r'dart pub get(?! --enforce-lockfile)');

/// Last pre-400 workflow commit (on dev via PR #81).
const pre400Sha = '7b85cb18c809319fa1fd8519349e307dc9498cf4';
