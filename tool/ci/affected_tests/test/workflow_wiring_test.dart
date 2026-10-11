import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Phase 400 audit (P1/P3/S3) wiring pins on `.github/workflows/pr-validate.yml`.
///
/// - D8 (supersedes P1): no cache of any kind feeds the selector. The `plan`
///   job has no `actions/cache` step, and the selector's Dart setup + pub get
///   run only on a `selective` verdict, never gated on the event name.
/// - P3: `Set up Java 17` runs only in the `apk` job (phase 402 moved it).
/// - S3: tests-ran checks every selective event stream on its own (no
///   aggregate `cat` that lets one stream's passes mask an all-skipped one).
/// - Phase 402: the `validate` / `test` split (gates, unit shards, tz legs,
///   goldens, apk, coverage), the shared flutter-setup action, the shard
///   outputs, and tests-ran across shards.
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

    // Phase 402: a FULL run shards through the selector too (`--all`), so the
    // selector's Dart setup + pub get run on every plan: NO `if:` at all (the
    // old exact `== 'selective'` condition is gone; "never gated on the event
    // name" still holds because there is no condition to gate on).
    test('selector steps run on every plan (no if:), uncached, no PUB_*', () {
      for (final name in [
        'Set up Dart (selector)',
        'Selector pub get (base commit)',
      ]) {
        final s = step('plan', name);
        expect(s.containsKey('if'), isFalse, reason: name);
        // D10: tolerated ONLY in full mode; the exact expression is pinned in
        // the 'phase 402 audit cycle 1' group below.
        expect(s.containsKey('continue-on-error'), isTrue, reason: name);
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
    test(
      'apk job: Java 17 + the APK builds; the job `if` is the APK '
      'condition; no other split job sets up Java except gates (openapi)',
      () {
        final apkIf = ((jobs['apk'] as YamlMap)['if'] as String)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        expect(apkIf, contains("needs.plan.outputs.mode == 'full'"));
        expect(apkIf, contains("needs.plan.outputs.native == 'true'"));
        expect(step('apk', 'Set up Java 17').containsKey('if'), isFalse);
        step('apk', 'Build APK (debug)');
        for (final j in ['unit', 'tz-sweeps', 'goldens', 'coverage']) {
          final names = [
            for (final s in ((jobs[j] as YamlMap)['steps'] as YamlList))
              (s as YamlMap)['name'].toString(),
          ];
          expect(names, isNot(contains('Set up Java 17')), reason: j);
        }
      },
    );
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
      // F6: three legs split by tag, cores-wide, no `|| true`; an unknown leg
      // is an error, never a silent no-op.
      expect(
        run,
        contains(r'fast) dart test --concurrency="$(nproc)" -x e2e ;;'),
      );
      expect(
        run,
        contains(
          r'e2e-a | e2e-b) dart test --concurrency="$(nproc)" -t "$LEG" ;;',
        ),
      );
      expect(run, contains('exit 1'));
      expect(run, isNot(contains('|| true')));
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
        p.join('test', 'support_pipeline.dart'),
      ).readAsStringSync();
      expect(e2e, contains("const pre400CommitSha = '$pre400Sha';"));
    });

    test('runs on every non-noop event, like gates (no path gate)', () {
      final job = jobs['selector-tests'] as YamlMap;
      final gates = jobs['gates'] as YamlMap;
      expect(job['if'], gates['if']);
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
      // Unit streams are per shard (phase 402): verify_unit -> verify_shards.sh.
      expect(run, contains('verify_unit'));
      for (final o in [
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

  group('phase 402 job split wiring', () {
    List<YamlMap> steps(String job) =>
        ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>().toList();
    List<String> needsOf(String job) {
      final n = (jobs[job] as YamlMap)['needs'];
      if (n == null) return const [];
      return n is YamlList ? [for (final x in n) x.toString()] : [n.toString()];
    }

    String flat(Object? o) =>
        o.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final actionFile = File(
      p.join(
        wfFile.parent.parent.path,
        'actions',
        'flutter-setup',
        'action.yml',
      ),
    );

    test('D1: gates, unit, tz-sweeps, goldens, apk, coverage exist; the old '
        '`validate` is gone and `test` is only the bootstrap aggregator', () {
      for (final j in [
        'gates-fast',
        'gates',
        'unit',
        'tz-sweeps',
        'goldens',
        'apk',
        'coverage',
      ]) {
        expect(jobs.containsKey(j), isTrue, reason: j);
      }
      expect(jobs.containsKey('validate'), isFalse);
      for (final st in steps('test')) {
        expect((st['run'] ?? '').toString(), isNot(contains('flutter')));
        expect(st.containsKey('uses'), isFalse);
      }
      // Audit F2: coverage is non-blocking, so the aggregator (which an OLD
      // base gate.sh reads) must not inherit its failures.
      expect(needsOf('test'), ['unit', 'tz-sweeps', 'goldens', 'apk']);
      expect(
        ((jobs['test'] as YamlMap)['if']).toString(),
        contains('always()'),
      );
    });

    test(
      'D1: unit / tz-sweeps / goldens need plan, apk needs plan + '
      'gates-fast (N2); coverage needs plan + unit; gates starts at once',
      () {
        for (final j in ['unit', 'tz-sweeps', 'goldens']) {
          expect(needsOf(j), ['plan'], reason: j);
        }
        expect(needsOf('apk'), ['plan', 'gates-fast']);
        expect(needsOf('coverage'), ['plan', 'unit']);
        expect(needsOf('gates'), isEmpty);
        expect(needsOf('gates-fast'), isEmpty);
      },
    );

    test(
      'ci-gate needs EVERY other job (a job missing here is never judged)',
      () {
        expect(
          needsOf('ci-gate').toSet(),
          jobs.keys.map((k) => k.toString()).toSet()..remove('ci-gate'),
        );
      },
    );

    test('D1: unit matrix = fromJSON(plan.unit_shards), fail-fast off, no '
        'include/exclude; tz-sweeps matrix = fromJSON(plan.tz_zones)', () {
      final u = (jobs['unit'] as YamlMap)['strategy'] as YamlMap;
      expect(u['fail-fast'], isFalse);
      final um = u['matrix'] as YamlMap;
      expect(um.keys.map((k) => '$k').toList(), ['shard']);
      expect(
        um['shard'],
        r"${{ fromJSON(needs.plan.outputs.unit_shards || '[1]') }}",
      );
      final t = (jobs['tz-sweeps'] as YamlMap)['strategy'] as YamlMap;
      expect(t['fail-fast'], isFalse);
      final tm = t['matrix'] as YamlMap;
      expect(tm.keys.map((k) => '$k').toList(), ['zone']);
      expect(
        tm['zone'],
        r'''${{ fromJSON(needs.plan.outputs.tz_zones || '["tokyo"]') }}''',
      );
    });

    test(
      'job `if:`s: label gate + (full or the job\'s own list non-empty)',
      () {
        const label =
            "(github.event.action != 'labeled' || "
            "github.event.label.name == 'full-ci' || "
            "github.event.label.name == 'run-patrol')";
        for (final e in {
          'unit': 'unit_count',
          'tz-sweeps': 'tz_count',
          'goldens': 'golden_count',
        }.entries) {
          expect(
            flat((jobs[e.key] as YamlMap)['if']),
            "$label && (needs.plan.outputs.mode == 'full' || "
            "(needs.plan.outputs.mode == 'selective' && "
            "needs.plan.outputs.${e.value} != '0'))",
            reason: e.key,
          );
        }
        expect(
          flat((jobs['coverage'] as YamlMap)['if']),
          "$label && needs.plan.outputs.run_all == 'true' && "
          "needs.unit.result == 'success'",
        );
      },
    );

    test('D5: every app job uses the ONE flutter-setup action; the selector '
        'jobs never do (D8: no cache feeds the selector)', () {
      // Audit S-L4: integration, integration-profile and patrol use it too.
      for (final j in [
        'gates',
        'unit',
        'tz-sweeps',
        'goldens',
        'apk',
        'integration',
        'integration-profile',
        'patrol',
      ]) {
        final uses = [for (final st in steps(j)) (st['uses'] ?? '').toString()];
        expect(
          uses.where((u) => u == './.github/actions/flutter-setup'),
          hasLength(1),
          reason: j,
        );
        expect(
          uses.where((u) => u.startsWith('subosito/flutter-action')),
          isEmpty,
          reason: '$j: no second copy of the Flutter setup',
        );
        final runs = steps(
          j,
        ).map((st) => (st['run'] ?? '').toString()).join('\n');
        expect(runs, isNot(contains('flutter pub get')), reason: j);
        expect(runs, isNot(contains('build_runner')), reason: j);
      }
      for (final j in ['plan', 'selector-tests']) {
        for (final st in steps(j)) {
          expect(
            (st['uses'] ?? '').toString(),
            isNot(startsWith('./')),
            reason: '$j: ${st['name']}',
          );
        }
      }
    });

    test('flutter-setup action: Flutter 3.41, SHA-pinned, pub cache keyed on '
        'the lock + codegen inputs, pub get then build_runner, no output '
        'cache', () {
      expect(actionFile.existsSync(), isTrue);
      final y = loadYaml(actionFile.readAsStringSync()) as YamlMap;
      final st = ((y['runs'] as YamlMap)['steps'] as YamlList).cast<YamlMap>();
      expect((y['runs'] as YamlMap)['using'], 'composite');
      final fl = st.first;
      expect(
        fl['uses'],
        matches(RegExp(r'^subosito/flutter-action@[0-9a-f]{40}$')),
      );
      final w = fl['with'] as YamlMap;
      expect(w['flutter-version'], '3.41.x');
      expect(w['cache'], isTrue);
      expect(w['pub-cache-key'], contains("hashFiles('pubspec.lock'"));
      expect(w['pub-cache-key'], contains('build.yaml'));
      expect(
        [for (final x in st) x['name']],
        ['Set up Flutter', 'Pub get', 'Codegen (build_runner)'],
      );
      for (final x in st.skip(1)) {
        expect(x['shell'], 'bash');
      }
      expect(st[1]['run'], 'flutter pub get');
      expect(
        st[2]['run'],
        'dart run build_runner build --delete-conflicting-outputs',
      );
      expect(actionFile.readAsStringSync(), isNot(contains('actions/cache')));
    });

    test('every external action in the jobs and the composite is pinned to a '
        '40-hex SHA', () {
      final pin = RegExp(r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$');
      void check(String where, Object? stepsY) {
        for (final st in (stepsY as YamlList).cast<YamlMap>()) {
          final u = (st['uses'] ?? '').toString();
          if (u.isEmpty || u.startsWith('./')) continue;
          expect(u, matches(pin), reason: '$where: ${st['name']}');
        }
      }

      for (final j in jobs.entries) {
        check(j.key.toString(), (j.value as YamlMap)['steps']);
      }
      final comp = loadYaml(actionFile.readAsStringSync()) as YamlMap;
      check('flutter-setup', (comp['runs'] as YamlMap)['steps']);
    });

    test('D2/D3a: the shard step passes the resolver\'s threshold, runs the '
        'BASE script, and no second threshold literal exists', () {
      final st = step('plan', 'Shard unit tests (script from the BASE commit)');
      final env = st['env'] as YamlMap;
      expect(env['SHARD_MODE'], r'${{ steps.sel.outputs.mode }}');
      expect(env['SHARD_UNIT_COUNT'], r'${{ steps.sel.outputs.unit_count }}');
      expect(
        env['SHARD_THRESHOLD'],
        r'${{ steps.sel.outputs.unit_warn_threshold }}',
      );
      final names = [for (final x in steps('plan')) x['name']];
      expect(
        names.indexOf('Shard unit tests (script from the BASE commit)'),
        greaterThan(
          names.indexOf('Select tests (selector from the BASE commit)'),
        ),
      );
      final ci = Directory('..').absolute.path;
      final shardSh = File(p.join(ci, 'shard_units.sh')).readAsStringSync();
      expect(shardSh, isNot(contains('80')));
      expect(shardSh, isNot(matches(RegExp(r'THRESHOLD:-\d'))));
      final cli = File('lib/cli.dart').readAsStringSync();
      expect(
        cli,
        isNot(matches(RegExp('threshold\\s*(\\?\\?|=)\\s*[\'"]?\\d'))),
      );
      final resolver = File(
        p.join(ci, 'resolve_selection.sh'),
      ).readAsStringSync();
      expect(
        RegExp(r'^unit_warn_default=\d+', multiLine: true).allMatches(resolver),
        hasLength(1),
      );
      // The shard count of a full run comes from the selector, not the script.
      expect(shardSh, contains('--shards-for full'));
    });

    test('plan outputs: unit_shards / unit_shard_count come from the shard '
        'step; the shard-list artifact is uploaded only for real shards', () {
      final outs = (jobs['plan'] as YamlMap)['outputs'] as YamlMap;
      expect(
        outs['unit_shards'],
        r"${{ steps.shard.outputs.unit_shards || '[1]' }}",
      );
      expect(
        outs['unit_shard_count'],
        r"${{ steps.shard.outputs.unit_shard_count || '0' }}",
      );
      final up = step('plan', 'Upload unit shard lists');
      expect((up['with'] as YamlMap)['name'], 'ci-unit-shards');
      expect(cond(up), contains('["whole"]'));
      expect(cond(up), contains("unit_shard_count != '0'"));
    });

    test('unit job: lists from the plan artifact (not the selector), '
        'per-shard stream + lcov (full only) artifacts', () {
      final dl = step('unit', 'Download unit shard lists');
      expect((dl['with'] as YamlMap)['name'], 'ci-unit-shards');
      expect(cond(dl), "matrix.shard != 'whole'");
      final run = step('unit', 'Test')['run'].toString();
      expect(run, isNot(contains('affected_tests')));
      expect(run, isNot(contains('dart ')));
      final ev = step('unit', 'Upload unit event stream');
      expect(cond(ev), 'always()');
      expect(
        (ev['with'] as YamlMap)['name'],
        r'events-unit-${{ matrix.shard }}',
      );
      final cov = step('unit', 'Upload shard coverage');
      expect(cond(cov), "success() && needs.plan.outputs.run_all == 'true'");
      expect(
        (cov['with'] as YamlMap)['name'],
        r'lcov-unit-${{ matrix.shard }}',
      );
      expect((cov['with'] as YamlMap)['path'], 'coverage/lcov.info');
    });

    test('D4: coverage merges every shard lcov with lcov -a and uploads '
        'once', () {
      final dl = step('coverage', 'Download shard coverage');
      expect((dl['with'] as YamlMap)['pattern'], 'lcov-unit-*');
      final m = step(
        'coverage',
        'Merge shard coverage (lcov -a)',
      )['run'].toString();
      // S-L3: pinned version, no recommends (never a bare `install lcov`).
      expect(
        m,
        contains(
          r'apt-get install -y -qq --no-install-recommends "lcov=$LCOV_VERSION"',
        ),
      );
      expect(m, isNot(contains('install -y -qq lcov')));
      expect(m, contains(r'args+=(-a "$f")'));
      expect(m, contains('-o coverage/lcov.info'));
      for (final n in [
        'Upload coverage (pull_request, tokenless)',
        'Upload coverage (push / dispatch, with token)',
      ]) {
        expect(
          (step('coverage', n)['with'] as YamlMap)['file'],
          'coverage/lcov.info',
        );
      }
      for (final j in jobs.entries) {
        if (j.key == 'coverage') continue;
        for (final st in steps(j.key.toString())) {
          expect(
            (st['uses'] ?? '').toString(),
            isNot(startsWith('codecov/')),
            reason: '${j.key}',
          );
        }
      }
    });

    test('tests-ran: needs the three test jobs, runs on a sound plan with no '
        'failed job, base-owned scripts, all event artifacts merged', () {
      expect(needsOf('tests-ran'), ['plan', 'unit', 'tz-sweeps', 'goldens']);
      final c = flat((jobs['tests-ran'] as YamlMap)['if']);
      expect(c, contains('always()'));
      expect(c, contains("needs.plan.result == 'success'"));
      expect(c, contains("needs.plan.outputs.mode != 'none'"));
      expect(c, contains("!contains(needs.*.result, 'failure')"));
      expect(c, contains("!contains(needs.*.result, 'cancelled')"));
      expect(c, contains("github.event.action != 'labeled'"));
      final co = steps('tests-ran').first;
      expect(
        (co['with'] as YamlMap)['sparse-checkout'].toString(),
        allOf(
          contains('tool/ci/tests_ran.sh'),
          contains('tool/ci/verify_shards.sh'),
          contains('tool/ci/collect_events.sh'),
          contains('tool/ci/min_tests.txt'),
        ),
      );
      final dl = step('tests-ran', 'Download event streams');
      final w = dl['with'] as YamlMap;
      expect(w['pattern'], 'events-*');
      // S-L1: one directory per artifact; never merged into one.
      expect(w.containsKey('merge-multiple'), isFalse);
      expect(w['path'], 'events-dl');
      final env =
          step('tests-ran', 'Verify tests actually ran')['env'] as YamlMap;
      expect(env['UNIT_SHARDS'], r'${{ needs.plan.outputs.unit_shards }}');
      expect(
        env['UNIT_SHARD_COUNT'],
        r'${{ needs.plan.outputs.unit_shard_count }}',
      );
    });

    test('no combined actions/cache step anywhere (it saves from PR runs)', () {
      for (final j in jobs.entries) {
        for (final st in steps(j.key.toString())) {
          expect(
            (st['uses'] ?? '').toString(),
            isNot(startsWith('actions/cache@')),
            reason: '${j.key}: ${st['name']}',
          );
        }
      }
    });
  }, skip: skip);

  group('phase 402 audit cycle 1 wiring', () {
    List<YamlMap> steps(String job) =>
        ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>().toList();
    String flat(Object? o) =>
        o.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    String runs(String job) =>
        steps(job).map((st) => (st['run'] ?? '').toString()).join('\n');
    final mobile = wfFile.parent.parent.parent;

    // D10 ------------------------------------------------------------------
    test('D10: both selector setup steps tolerate a failure ONLY in full '
        'mode (exact expression); no other plan step does', () {
      const expr =
          r"${{ (steps.guard.outputs.mode || steps.plan.outputs.mode) == 'full' }}";
      for (final n in [
        'Set up Dart (selector)',
        'Selector pub get (base commit)',
      ]) {
        expect(step('plan', n)['continue-on-error'], expr, reason: n);
      }
      for (final st in steps('plan')) {
        final n = '${st['name']}';
        if (n == 'Set up Dart (selector)' ||
            n == 'Selector pub get (base commit)') {
          continue;
        }
        expect(
          st.containsKey('continue-on-error'),
          isFalse,
          reason: 'plan step "$n" must stay a hard failure',
        );
      }
      // The expression reads the ids it names.
      expect(
        step('plan', 'Compute plan (planner from the BASE commit)')['id'],
        'plan',
      );
      expect(
        step('plan', 'Guard - CI machinery changes force full')['id'],
        'guard',
      );
    });

    test('D10: the shard step runs after both and falls back with the '
        'documented warning', () {
      final names = [for (final x in steps('plan')) x['name']];
      final shard = names.indexOf(
        'Shard unit tests (script from the BASE commit)',
      );
      expect(shard, greaterThan(names.indexOf('Set up Dart (selector)')));
      expect(
        shard,
        greaterThan(names.indexOf('Selector pub get (base commit)')),
      );
      expect(
        step(
          'plan',
          'Shard unit tests (script from the BASE commit)',
        ).containsKey('if'),
        isFalse,
      );
      final su = File(
        p.join(mobile.path, 'tool', 'ci', 'shard_units.sh'),
      ).readAsStringSync();
      expect(
        su,
        contains('::warning::selector unavailable, unsharded fallback'),
      );
    });

    // F1 -------------------------------------------------------------------
    test('F1: gates-fast needs no toolchain: checkout + run steps only, no '
        'dart/flutter/java/build_runner anywhere in it', () {
      final job = jobs['gates-fast'] as YamlMap;
      expect(job.containsKey('needs'), isFalse);
      expect(flat(job['if']), flat((jobs['gates'] as YamlMap)['if']));
      expect((job['permissions'] as YamlMap)['contents'], 'read');
      for (final st in steps('gates-fast')) {
        final uses = (st['uses'] ?? '').toString();
        expect(
          uses.isEmpty || uses.startsWith('actions/checkout@'),
          isTrue,
          reason: 'gates-fast: ${st['name']} uses $uses',
        );
      }
      final r = runs('gates-fast');
      for (final bad in [
        'dart ',
        'flutter',
        'build_runner',
        'java',
        'gradle',
      ]) {
        expect(r, isNot(contains(bad)), reason: 'gates-fast runs "$bad"');
      }
      expect(job['timeout-minutes'], lessThanOrEqualTo(10));
    });

    test('F1: every scripts/forbid_*.sh gate is enforced in gates-fast, except '
        'the two that need the toolchain (they stay in gates)', () {
      const needsToolchain = {
        'forbid_raw_ui_strings.sh', // runs `dart tool/lints/...`
        'forbid_bare_keepalive_family_invalidation.sh', // reads *.g.dart
      };
      final fast = runs('gates-fast');
      final slow = runs('gates');
      final scripts = [
        for (final f in Directory(p.join(mobile.path, 'scripts')).listSync())
          if (f is File &&
              RegExp(r'forbid_.*\.sh$').hasMatch(p.basename(f.path)))
            p.basename(f.path),
      ];
      expect(scripts.length, greaterThan(30));
      for (final sc in scripts) {
        final inv = RegExp(
          '^\\s*\\./scripts/${RegExp.escape(sc)}\\s*\$',
          multiLine: true,
        );
        if (needsToolchain.contains(sc)) {
          expect(inv.hasMatch(slow), isTrue, reason: '$sc must stay in gates');
          expect(
            inv.hasMatch(fast),
            isFalse,
            reason: '$sc needs the toolchain',
          );
        } else {
          expect(
            inv.hasMatch(fast),
            isTrue,
            reason: '$sc must run in gates-fast',
          );
          expect(
            inv.hasMatch(slow),
            isFalse,
            reason: '$sc must not be duplicated',
          );
        }
      }
      // The self-test runner (it executes forbid_raw_ui_strings --self-test,
      // i.e. dart) is a gates step.
      expect(slow, contains('./scripts/verify_guards.sh --self-test'));
      expect(fast, isNot(contains('verify_guards.sh')));
    });

    test('F1: gates (the toolchain job) no longer carries the grep-only '
        'guards, and gates-fast is a ci-gate need', () {
      expect(
        (jobs['ci-gate'] as YamlMap)['needs'] as YamlList,
        containsAll(['gates-fast', 'gates']),
      );
      expect(
        flat((jobs['gates-fast'] as YamlMap)['name']),
        isNot(flat((jobs['gates'] as YamlMap)['name'])),
      );
    });

    // F2 / S-L2 / S-L3 -------------------------------------------------------
    test('F2: coverage is non-blocking and light: job continue-on-error, no '
        'checkout, read-only token, needs only plan + unit', () {
      final job = jobs['coverage'] as YamlMap;
      expect(job['continue-on-error'], isTrue);
      expect((job['permissions'] as YamlMap)['contents'], 'read');
      expect((job['needs'] as YamlList).toList(), ['plan', 'unit']);
      for (final st in steps('coverage')) {
        expect(
          (st['uses'] ?? '').toString(),
          isNot(startsWith('actions/checkout')),
          reason: 'nothing in the tree is read',
        );
      }
      expect(job['timeout-minutes'], lessThanOrEqualTo(15));
    });

    test('S-L2: codecov is tokenless on pull_request; the token step runs '
        'only off pull_request; the secret is referenced nowhere else', () {
      final tokenless = step(
        'coverage',
        'Upload coverage (pull_request, tokenless)',
      );
      final withToken = step(
        'coverage',
        'Upload coverage (push / dispatch, with token)',
      );
      expect(tokenless['if'], "github.event_name == 'pull_request'");
      expect(withToken['if'], "github.event_name != 'pull_request'");
      expect((tokenless['with'] as YamlMap).containsKey('token'), isFalse);
      expect(
        (withToken['with'] as YamlMap)['token'],
        r'${{ secrets.CODECOV_TOKEN }}',
      );
      for (final st in [tokenless, withToken]) {
        expect((st['with'] as YamlMap)['fail_ci_if_error'], isFalse);
        expect(st['uses'], startsWith('codecov/codecov-action@'));
      }
      expect(
        RegExp('secrets\\.CODECOV_TOKEN').allMatches(wfFile.readAsStringSync()),
        hasLength(1),
      );
      expect((wf['permissions'] as YamlMap)['contents'], 'read');
    });

    test('S-L3: lcov is pinned to the noble version, installed without '
        'recommends, and the version is logged', () {
      final m = step('coverage', 'Merge shard coverage (lcov -a)');
      expect((m['env'] as YamlMap)['LCOV_VERSION'], '2.0-4ubuntu2');
      final run = m['run'].toString();
      expect(run, contains('--no-install-recommends "lcov=\$LCOV_VERSION"'));
      expect(run, contains('lcov --version'));
    });

    // F5 ---------------------------------------------------------------------
    test('F5: apk is a debug|release matrix; every step touching a signing '
        'secret is release-only AND off pull_request', () {
      final job = jobs['apk'] as YamlMap;
      final strat = job['strategy'] as YamlMap;
      expect(strat['fail-fast'], isFalse);
      expect(((strat['matrix'] as YamlMap)['variant'] as YamlList).toList(), [
        'debug',
        'release',
      ]);
      expect(needsOfJob(job), ['plan', 'gates-fast']); // N2
      var secretSteps = 0;
      for (final st in steps('apk')) {
        final blob = '${st['env']} ${st['run']} ${st['with']}';
        if (blob.contains('secrets.')) {
          secretSteps++;
          final c = flat(st['if']);
          expect(
            c,
            contains("github.event_name != 'pull_request'"),
            reason: '${st['name']}',
          );
          expect(
            c,
            contains("matrix.variant == 'release'"),
            reason: '${st['name']}',
          );
        }
      }
      expect(secretSteps, 2, reason: 'keystore decode + signed release build');
      expect(
        flat(step('apk', 'Build APK (debug)')['if']),
        "matrix.variant == 'debug'",
      );
      expect(
        flat(
          step('apk', 'Build APK (release, compile check, no secrets)')['if'],
        ),
        "github.event_name == 'pull_request' && matrix.variant == 'release'",
      );
      // The job id is unchanged: gate.sh / jobRuns / `test` read needs.apk.
      expect(jobs.containsKey('apk'), isTrue);
    });

    // F6 ---------------------------------------------------------------------
    test('F6: selector-tests = three parallel legs split by tag; every '
        'pipeline_e2e file carries e2e + exactly one of e2e-a / e2e-b', () {
      final strat = (jobs['selector-tests'] as YamlMap)['strategy'] as YamlMap;
      expect(strat['fail-fast'], isFalse);
      expect(((strat['matrix'] as YamlMap)['leg'] as YamlList).toList(), [
        'fast',
        'e2e-a',
        'e2e-b',
      ]);
      expect(
        (step('selector-tests', 'Selector dart test')['env'] as YamlMap)['LEG'],
        r'${{ matrix.leg }}',
      );
      final pkg = Directory.current;
      final declared =
          (loadYaml(File(p.join(pkg.path, 'dart_test.yaml')).readAsStringSync())
                  as YamlMap)['tags']
              as YamlMap;
      expect(declared.keys, containsAll(['e2e', 'e2e-a', 'e2e-b']));
      final tagLine = RegExp(r"^@Tags\(\[(.*)\]\)", multiLine: true);
      final byFile = <String, List<String>>{};
      for (final f in Directory(
        p.join(pkg.path, 'test'),
      ).listSync(recursive: true)) {
        if (f is File && f.path.endsWith('_test.dart')) {
          final m = tagLine.firstMatch(f.readAsStringSync());
          if (m != null) {
            byFile[p.basename(f.path)] = m
                .group(1)!
                .split(',')
                .map((t) => t.trim().replaceAll("'", ''))
                .toList();
          }
        }
      }
      expect(byFile, {
        'pipeline_e2e_test.dart': ['e2e', 'e2e-a'],
        'pipeline_e2e_integration_test.dart': ['e2e', 'e2e-a'],
        'pipeline_e2e_sharding_test.dart': ['e2e', 'e2e-b'],
        'pipeline_e2e_audit1_test.dart': ['e2e', 'e2e-b'],
      });
    });

    // S-L1 -------------------------------------------------------------------
    test('S-L1: tests-ran never merge-multiples; the base-owned collector '
        'builds events/ before any check', () {
      final run = step(
        'tests-ran',
        'Verify tests actually ran',
      )['run'].toString();
      expect(run, contains('collect_events.sh'));
      // The collector's verdict gates the step: never `|| true`-ed away.
      expect(
        run,
        contains(
          r'bash "$col" events-dl events || { echo "::error::tests-ran RED',
        ),
      );
      expect(
        run.indexOf('collect_events.sh'),
        lessThan(run.indexOf('verify_unit()')),
      );
      expect(
        run.indexOf('collect_events.sh'),
        greaterThan(run.indexOf('tests_ran.sh; skipping')),
      );
      for (final j in jobs.entries) {
        for (final st in steps(j.key.toString())) {
          final w = st['with'];
          if (w is YamlMap) {
            expect(
              w.containsKey('merge-multiple'),
              isFalse,
              reason: '${j.key}: ${st['name']}',
            );
          }
        }
      }
      expect(
        File(
              p.join(mobile.path, 'tool', 'ci', 'collect_events.sh'),
            ).statSync().mode &
            0x40,
        isNot(0),
        reason: 'executable',
      );
    });
  }, skip: skip);

  group('phase 402 audit cycle 2 wiring', () {
    List<YamlMap> steps(String job) =>
        ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>().toList();
    List<String> needsOf(String job) {
      final n = (jobs[job] as YamlMap)['needs'];
      if (n == null) return const [];
      return n is YamlList ? [for (final x in n) x.toString()] : [n.toString()];
    }

    // N2 ---------------------------------------------------------------------
    test(
      'N2: apk yields to the unit shards: it also needs gates-fast, stays '
      'required by ci-gate, and the unit shards do NOT wait for gates-fast',
      () {
        expect(needsOf('apk'), containsAll(['plan', 'gates-fast']));
        expect(needsOf('ci-gate'), contains('apk'));
        expect(needsOf('unit'), ['plan']);
        expect(
          needsOf('gates-fast'),
          isEmpty,
          reason: 'gates-fast starts at once',
        );
        // gate.sh must still demand apk (a skipped apk in a full run is RED).
        final gate = File(
          p.join(wfFile.parent.parent.parent.path, 'tool', 'ci', 'gate.sh'),
        ).readAsStringSync();
        expect(gate, contains('for j in unit tz-sweeps goldens apk; do'));
      },
    );

    // N-L2 -------------------------------------------------------------------
    const trusted = 'ci-trusted-secrets';
    // The ONLY accepted `environment:` expressions: each evaluates to the
    // empty string (= no environment) on a pull_request event.
    final okEnvironment = {
      'coverage':
          r"${{ github.event_name != 'pull_request' && '" +
          trusted +
          r"' || '' }}",
      'apk':
          r"${{ (github.event_name != 'pull_request' && matrix.variant == "
              r"'release') && '" +
          trusted +
          r"' || '' }}",
    };

    test('N-L2: every job that references a secret declares the '
        '$trusted environment; no other job names one', () {
      final withSecrets = <String>{};
      final withEnv = <String>{};
      for (final j in jobs.entries) {
        final job = j.value as YamlMap;
        if (job.containsKey('environment')) withEnv.add(j.key.toString());
        final blob = job.toString();
        final refs = RegExp(r'secrets\.([A-Za-z0-9_]+)')
            .allMatches(blob)
            .map((m) => m.group(1)!)
            .where((n) => n != 'GITHUB_TOKEN');
        if (refs.isNotEmpty) withSecrets.add(j.key.toString());
      }
      expect(withSecrets, {'apk', 'coverage'});
      expect(withEnv, withSecrets);
    });

    test('N-L2: the environment expression is the pull_request-safe form '
        '(empty string on pull_request), never a bare literal', () {
      for (final e in okEnvironment.entries) {
        final env = (jobs[e.key] as YamlMap)['environment'];
        expect(env, isA<String>(), reason: e.key);
        expect(
          env.toString().replaceAll(RegExp(r'\s+'), ' ').trim(),
          e.value,
          reason: '${e.key}: must be "<non-PR> && env || \'\'"',
        );
        expect(env.toString(), startsWith(r'${{'));
        // A pull_request run takes the `|| ''` branch: the guard is a
        // conjunction headed by the != 'pull_request' test.
        expect(env.toString(), contains("github.event_name != 'pull_request'"));
        expect(env.toString(), endsWith("|| '' }}"));
      }
    });

    test('N-L2: the apk environment is the signed release leg only (the '
        'debug leg and every PR evaluate to no environment)', () {
      final env = (jobs['apk'] as YamlMap)['environment'].toString();
      expect(env, contains("matrix.variant == 'release'"));
    });

    test(
      'N-L2: the secret-using steps keep their own guards (belt and '
      'braces: a PR never reaches them even if the environment is empty)',
      () {
        expect(
          step(
            'coverage',
            'Upload coverage (push / dispatch, with token)',
          )['if'],
          "github.event_name != 'pull_request'",
        );
        for (final st in steps('apk')) {
          if ('${st['env']}'.contains('secrets.')) {
            expect(
              st['if'].toString().replaceAll(RegExp(r'\s+'), ' '),
              contains("github.event_name != 'pull_request'"),
              reason: '${st['name']}',
            );
          }
        }
      },
    );

    // N-L1 -------------------------------------------------------------------
    test('N-L1: PR coverage is documented best-effort; both codecov steps '
        'stay SHA-pinned (v4) with fail_ci_if_error false', () {
      final src = wfFile.readAsStringSync();
      expect(src, contains('PR coverage is BEST-EFFORT'));
      expect(src, contains('dev / main runs'));
      for (final n in [
        'Upload coverage (pull_request, tokenless)',
        'Upload coverage (push / dispatch, with token)',
      ]) {
        final st = step('coverage', n);
        expect(
          st['uses'],
          matches(RegExp(r'^codecov/codecov-action@[0-9a-f]{40}$')),
          reason: n,
        );
        expect((st['with'] as YamlMap)['fail_ci_if_error'], isFalse);
      }
    });
  }, skip: skip);

  // N-L3 ---------------------------------------------------------------------
  group('phase 402 audit cycle 2: test tag legs (N-L3)', () {
    test('every file under test/ tagged e2e carries exactly one of e2e-a / '
        'e2e-b, and neither leg tag appears without e2e', () {
      final root = Directory(p.join(Directory.current.path, 'test'));
      expect(root.existsSync(), isTrue);
      var scanned = 0;
      final bad = <String>[];
      for (final f in root.listSync(recursive: true)) {
        if (f is! File) continue;
        scanned++;
        // latin1: never trip on a non-UTF-8 fixture (grep -a lesson).
        final v = tagViolation(f.readAsStringSync(encoding: latin1));
        if (v != null) bad.add('${p.relative(f.path, from: root.path)}: $v');
      }
      expect(scanned, greaterThan(10));
      expect(bad, isEmpty);
    });

    test(
      'tagViolation: a file tagged e2e alone is red; the two legs are '
      'exclusive; leg tags need e2e; test-level e2e tags need the file tag',
      () {
        String file(String tags) => '@Tags($tags)\nlibrary;\nvoid main() {}\n';
        expect(tagViolation(file("['e2e']")), isNotNull);
        expect(tagViolation(file("['e2e', 'e2e-a', 'e2e-b']")), isNotNull);
        expect(tagViolation(file("['e2e-a']")), isNotNull);
        expect(tagViolation(file("['e2e-b']")), isNotNull);
        expect(tagViolation(file('["e2e", "e2e-a"]')), isNull);
        expect(tagViolation(file("['e2e', 'e2e-b']")), isNull);
        expect(tagViolation(file("['slow']")), isNull);
        expect(tagViolation('void main() {}\n'), isNull);
        // multi-line annotation
        expect(tagViolation("@Tags([\n  'e2e',\n])\nlibrary;\n"), isNotNull);
        expect(
          tagViolation("@Tags([\n  'e2e',\n  'e2e-a',\n])\nlibrary;\n"),
          isNull,
        );
        // a test-level e2e tag in an untagged file would run in NO leg
        expect(
          tagViolation(
            "void main() {\n  test('x', () {}, "
            'ta'
            "gs: 'e2e');\n}\n",
          ),
          isNotNull,
        );
        expect(
          tagViolation(
            "@Tags(['e2e', 'e2e-a'])\nlibrary;\nvoid main() {\n  test('x', () {}, "
            'ta'
            "gs: 'e2e');\n}\n",
          ),
          isNull,
        );
      },
    );
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

  // Phase 402 D14 + security review: the CI-paths guard is base-owned like the
  // planner/selector; the PR copy runs only behind the base-lacks-it check.
  group('phase 402 D14 base-owned CI-paths guard', () {
    test('guard step runs trusted/ ci_paths_guard.sh, PR copy only as a '
        'warned bootstrap fallback', () {
      final g = step('plan', 'Guard - CI machinery changes force full');
      expect(g['id'], 'guard');
      expect(g['working-directory'], 'pr');
      expect(cond(g), "github.event_name == 'pull_request'");
      expect((g['env'] as YamlMap).keys.toSet(), {'BASE_SHA', 'HEAD_SHA'});
      final lines = [
        for (final l in g['run'].toString().split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ];
      expect(lines, [
        r'g="$GITHUB_WORKSPACE/trusted/tool/ci/ci_paths_guard.sh"',
        r'if [ ! -f "$g" ]; then',
        'echo "::warning::ci_paths_guard bootstrap: base lacks the script, '
            'using PR copy"',
        r'g="$GITHUB_WORKSPACE/pr/tool/ci/ci_paths_guard.sh"',
        'fi',
        r'bash "$g"',
      ]);
      // trusted/ is the base commit and carries tool/ci (sparse checkout).
      final t = step('plan', 'Checkout trusted tooling (base commit)');
      expect((t['with'] as YamlMap)['path'], 'trusted');
      expect((t['with'] as YamlMap)['sparse-checkout'], 'tool/ci');
    });
  }, skip: skip);

  // Phase 402 D14: one `Enable KVM` composite for the three emulator jobs; a
  // local `uses: ./` loads from the PR head, so never in the trusted jobs.
  group('phase 402 D14 enable-kvm composite', () {
    List<YamlMap> steps(String job) =>
        ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>().toList();

    test('integration, integration-profile and patrol use it; no inline '
        'udevadm left', () {
      for (final j in ['integration', 'integration-profile', 'patrol']) {
        final kvm = step(j, 'Enable KVM');
        expect(kvm['uses'], './.github/actions/enable-kvm', reason: j);
        expect(kvm.containsKey('run'), isFalse, reason: j);
      }
      expect(wfFile.readAsStringSync(), isNot(contains('udevadm')));
      final action = File(
        p.join(
          wfFile.parent.parent.path,
          'actions',
          'enable-kvm',
          'action.yml',
        ),
      );
      final y = loadYaml(action.readAsStringSync()) as YamlMap;
      expect((y['runs'] as YamlMap)['using'], 'composite');
      expect(
        action.readAsStringSync(),
        contains('udevadm trigger --name-match=kvm'),
      );
    });

    test('no local `uses: ./` in plan, tests-ran or ci-gate', () {
      for (final j in ['plan', 'tests-ran', 'ci-gate']) {
        for (final st in steps(j)) {
          expect(
            (st['uses'] ?? '').toString(),
            isNot(startsWith('./')),
            reason: '$j: ${st['name']}',
          );
        }
      }
    });
  }, skip: skip);

  // Phase 402 D14: a workflow comment is <= 3 lines (what/why + a
  // `# why: docs/ci/<topic>.md#<anchor>` pointer); narratives live in docs/ci.
  group('phase 402 D14 comment hygiene', () {
    test('no run of more than 4 consecutive comment lines', () {
      final offenders = longCommentRuns(wfFile.readAsStringSync(), 4);
      expect(offenders, isEmpty, reason: 'move the text to docs/ci/');
    });

    test('the gate itself flags a 5-line run and passes a 4-line one', () {
      String block(int n) => [for (var i = 0; i < n; i++) '  # c$i'].join('\n');
      expect(longCommentRuns('a: 1\n${block(4)}\nb: 2', 4), isEmpty);
      expect(longCommentRuns('a: 1\n${block(5)}\nb: 2', 4), ['2-6 (5)']);
      // Comment lines inside a `run:` body count too, and EOF closes a run.
      expect(longCommentRuns('run: |\n${block(5)}', 4), ['2-6 (5)']);
    });

    test('every `# why:` pointer names an existing docs/ci file + anchor', () {
      final docs = p.join(wfFile.parent.parent.parent.path, 'docs', 'ci');
      final ptr = RegExp(r'# why: docs/ci/([\w.-]+\.md)#([\w-]+)\s*$');
      final bad = <String>[];
      var n = 0;
      for (final l in wfFile.readAsLinesSync()) {
        if (!l.contains('# why:')) continue;
        n++;
        final m = ptr.firstMatch(l);
        final f = m == null ? null : File(p.join(docs, m[1]));
        if (m == null ||
            !f!.existsSync() ||
            !f.readAsStringSync().contains('<a id="${m[2]}"></a>')) {
          bad.add(l.trim());
        }
      }
      expect(n, greaterThan(50));
      expect(bad, isEmpty);
    });
  }, skip: skip);
}

/// 1-based `start-end (length)` of every run of consecutive comment lines
/// (first non-blank char `#`) in [src] longer than [max].
List<String> longCommentRuns(String src, int max) {
  final out = <String>[];
  final lines = src.split('\n');
  var start = -1;
  for (var i = 0; i <= lines.length; i++) {
    final isComment = i < lines.length && lines[i].trimLeft().startsWith('#');
    if (isComment) {
      if (start < 0) start = i;
      continue;
    }
    if (start >= 0 && i - start > max) {
      out.add('${start + 1}-$i (${i - start})');
    }
    start = -1;
  }
  return out;
}

/// `needs` of a job node as a list.
List<String> needsOfJob(YamlMap job) {
  final n = job['needs'];
  if (n == null) return const [];
  return n is YamlList ? [for (final x in n) x.toString()] : [n.toString()];
}

/// A `dart pub get` NOT followed by `--enforce-lockfile`.
final _bareGet = RegExp(r'dart pub get(?! --enforce-lockfile)');

/// Last pre-400 workflow commit (on dev via PR #81).
const pre400Sha = '7b85cb18c809319fa1fd8519349e307dc9498cf4';

/// N-L3: why [src] (a file under test/) breaks the selector-tests leg split, or
/// null. A file tagged `e2e` must carry exactly one of `e2e-a` / `e2e-b` (the
/// `fast` leg is `-x e2e`, the others `-t e2e-a` / `-t e2e-b`: an `e2e` file
/// with neither leg tag would run in NO leg, one with both in two); the leg
/// tags without `e2e` would run the file in `fast` AND a leg.
String? tagViolation(String src) {
  final tags = <String>{};
  for (final m in RegExp(
    r'^@Tags\(([\s\S]*?)\)\s*$',
    multiLine: true,
  ).allMatches(src)) {
    tags.addAll(_quoted(m.group(1)!));
  }
  final fileTags = {...tags};
  // test()/group() level tags (outside the file annotation).
  for (final m in RegExp(
    r"""\btags:\s*(\[[^\]]*\]|'[^']*'|"[^"]*")""",
  ).allMatches(src)) {
    tags.addAll(_quoted(m.group(1)!));
  }
  if (tags.isEmpty) return null;
  final legs = tags.where((t) => t == 'e2e-a' || t == 'e2e-b').length;
  if (!fileTags.contains('e2e')) {
    return tags.contains('e2e') || legs > 0
        ? 'uses an e2e / leg tag without a file-level @Tags([e2e, e2e-x])'
        : null;
  }
  final fileLegs = fileTags.where((t) => t == 'e2e-a' || t == 'e2e-b').length;
  return fileLegs == 1
      ? null
      : 'tagged e2e with $fileLegs of e2e-a/e2e-b (need exactly one)';
}

Iterable<String> _quoted(String s) =>
    RegExp(r"""['"]([^'"]*)['"]""").allMatches(s).map((m) => m.group(1)!);
