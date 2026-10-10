import 'dart:io';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

String m(String path) => 'M\t$path\n';

void main() {
  group('T1 shared widget fan-out (REUSE-FIRST / golden trap)', () {
    late FixtureRepo repo;
    setUp(
      () => repo = FixtureRepo({
        'lib/core/widgets/card.dart': 'class Card_ {}\n',
        'lib/features/a/presentation/a_screen.dart': pkg(
          'core/widgets/card.dart',
        ),
        'lib/features/b/presentation/b_screen.dart': pkg(
          'core/widgets/card.dart',
        ),
        'test/features/a/a_screen_test.dart': pkg(
          'features/a/presentation/a_screen.dart',
        ),
        'test/features/b/b_screen_test.dart': pkg(
          'features/b/presentation/b_screen.dart',
        ),
        'test/golden/card_golden_test.dart': pkg('core/widgets/card.dart'),
        'test/golden/other_golden_test.dart': 'void main() {}\n',
        ...filler(40),
      }),
    );
    tearDown(() => repo.dispose());

    test(
      'selects importers in two features and the golden that renders it',
      () {
        final s = repo.run(m('lib/core/widgets/card.dart'));
        expect(s.mode, Mode.selective);
        expect(
          s.unit,
          containsAll([
            'test/features/a/a_screen_test.dart',
            'test/features/b/b_screen_test.dart',
          ]),
        );
        expect(s.golden, ['test/golden/card_golden_test.dart']);
      },
    );
  });

  group('T2 directive kinds all propagate', () {
    test('relative, package:, export chain, part', () {
      final repo = FixtureRepo({
        'lib/leaf.dart': 'int x = 1;\n',
        'lib/rel.dart': "import 'leaf.dart';\n",
        'lib/pkgimp.dart': pkg('leaf.dart'),
        'lib/reexport.dart': "export 'leaf.dart';\n",
        'lib/viaexport.dart': pkg('reexport.dart'),
        'lib/owner.dart': "part 'owner_part.dart';\n",
        'lib/owner_part.dart': "part of 'owner.dart';\n",
        'test/rel_test.dart': pkg('rel.dart'),
        'test/pkg_test.dart': pkg('pkgimp.dart'),
        'test/export_test.dart': pkg('viaexport.dart'),
        'test/part_test.dart': pkg('owner.dart'),
        ...filler(40),
      });
      addTearDown(repo.dispose);
      final viaLeaf = repo.run(m('lib/leaf.dart'));
      expect(
        viaLeaf.unit,
        containsAll([
          'test/rel_test.dart',
          'test/pkg_test.dart',
          'test/export_test.dart',
        ]),
      );
      expect(viaLeaf.unit, isNot(contains('test/part_test.dart')));
      expect(repo.run(m('lib/owner_part.dart')).unit, ['test/part_test.dart']);
    });

    test(
      'a generated *.g.dart change seeds its owner; edges to it are dropped',
      () {
        final repo = FixtureRepo({
          'lib/m.dart': "part 'm.g.dart';\n",
          'test/m_test.dart': pkg('m.dart'),
          ...filler(40),
        });
        addTearDown(repo.dispose);
        expect(repo.run(m('lib/m.g.dart')).unit, ['test/m_test.dart']);
      },
    );

    test(
      'OpenAPI package falls back to rules.yaml packages without api/pubspec.yaml',
      () {
        final repo = FixtureRepo({
          'api/lib/api.dart': 'int a = 1;\n',
          'lib/repo.dart': "import 'package:beautica_api/api.dart';\n",
          'test/repo_test.dart': pkg('repo.dart'),
          ...filler(40),
        });
        addTearDown(repo.dispose);
        expect(repo.run(m('api/lib/api.dart')).unit, ['test/repo_test.dart']);
      },
    );

    test('OpenAPI package imports resolve to api/lib', () {
      final repo = FixtureRepo({
        'api/pubspec.yaml': 'name: beautica_api\n',
        'api/lib/api.dart': 'int a = 1;\n',
        'lib/repo.dart': "import 'package:beautica_api/api.dart';\n",
        'test/repo_test.dart': pkg('repo.dart'),
        ...filler(40),
      });
      addTearDown(repo.dispose);
      expect(repo.run(m('api/lib/api.dart')).unit, ['test/repo_test.dart']);
    });
  });

  group('T3 conditional imports count every branch', () {
    late FixtureRepo repo;
    setUp(
      () => repo = FixtureRepo({
        'lib/stub.dart': 'int a = 1;\n',
        'lib/io.dart': 'int a = 2;\n',
        'lib/web.dart': 'int a = 3;\n',
        'lib/facade.dart':
            "import 'stub.dart'\n    if (dart.library.io) 'io.dart'\n    if (dart.library.js_interop) 'web.dart';\n",
        'test/facade_test.dart': pkg('facade.dart'),
        ...filler(40),
      }),
    );
    tearDown(() => repo.dispose());

    for (final f in ['stub', 'io', 'web']) {
      test('change in $f.dart selects the facade test', () {
        expect(repo.run(m('lib/$f.dart')).unit, ['test/facade_test.dart']);
      });
    }
  });

  group('T4 full_globs / none_globs are enforced with the exact rule', () {
    // Hard-coded on purpose: deleting a rule from rules.yaml must turn a case
    // red (a list derived from rules.yaml would vanish with the rule).
    const fullCases = {
      'pubspec.yaml': 'pubspec.yaml',
      'pubspec.lock': 'pubspec.lock',
      'analysis_options.yaml': 'analysis_options.yaml',
      'dart_test.yaml': 'dart_test.yaml',
      'build.yaml': 'build.yaml',
      'l10n.yaml': 'l10n.yaml',
      'assets/fonts/x.ttf': 'assets/**',
      'api/pubspec.yaml': 'api/pubspec.yaml',
      'api/build.yaml': 'api/build.yaml',
      'test/flutter_test_config.dart': 'test/flutter_test_config.dart',
      'test/helpers/h.dart': 'test/helpers/**',
      'integration_test/support/s.dart': 'integration_test/support/**',
      'integration_test/fixtures/f.json': 'integration_test/fixtures/**',
      'test_driver/integration_test.dart': 'test_driver/**',
      'tool/ci/plan.sh': 'tool/ci/**',
      'scripts/forbid_x.sh': 'scripts/**',
      '.github/workflows/pr-validate.yml': '.github/workflows/**',
    };
    fullCases.forEach((path, glob) {
      test('$path -> full via $glob', () {
        final c = classify(path, rules);
        expect(c.kind, PathKind.full);
        expect(c.rule, 'full: $glob');
      });
    });

    test('non-.dart file under lib/ or test/ -> full', () {
      for (final path in [
        'lib/data/x.json',
        'test/golden/failures/a.png', // not under goldens/ -> still fail-safe
        'test/fixtures/x.json',
        'lib/l10n/notes.txt', // only *.arb is mapped
      ]) {
        final c = classify(path, rules);
        expect(c.kind, PathKind.full, reason: path);
        expect(c.rule, startsWith('full: non-.dart file under'), reason: path);
      }
    });

    const noneCases = {
      'docs/mobile-phases/x.md': 'docs/**',
      'README.md': '**/*.md',
      'lib/features/README.md': '**/*.md',
      '.gitignore': '.gitignore',
      'android/app/build.gradle': 'android/**',
      'ios/Runner/Info.plist': 'ios/**',
      'windows/runner/main.cpp': 'windows/**',
      'scripts/perf/measure_startup.sh': 'scripts/perf/**',
      '.github/workflows/gitleaks.yml': '.github/workflows/gitleaks.yml',
      'api/doc/Foo.txt': 'api/doc/**',
      '.gitleaksignore': '.gitleaksignore',
      '.metadata': '.metadata',
      'beautica_mobile.iml': '*.iml',
      'assets_design/a.png': 'assets_design/**',
      'api/.openapi-generator/FILES': 'api/.openapi-generator/**',
      'api/.openapi-generator-ignore': 'api/.openapi-generator-ignore',
      'api/test/foo_test.dart': 'api/test/**',
      'tool/openapi/api-spec.json': 'tool/openapi/**',
    };
    noneCases.forEach((path, glob) {
      test('$path -> ignored via $glob', () {
        final c = classify(path, rules);
        expect(c.kind, PathKind.none);
        expect(c.rule, 'none: $glob');
      });
    });

    test('every rule in rules.yaml has a case here (no unpinned rule)', () {
      expect({for (final g in rules.full) g.source}, fullCases.values.toSet());
      expect({for (final g in rules.none) g.source}, noneCases.values.toSet());
      expect(
        {
          for (final pi in rules.pathIncludes)
            for (final g in pi.when) g.source,
        },
        {'integration_test/all_tests*.dart'},
      );
      expect(
        {for (final g in rules.goldenAssetGlobs) g.source},
        {'test/**/goldens/*.png'},
      );
      expect({for (final g in rules.arbGlobs) g.source}, {'lib/l10n/*.arb'});
    });

    test('mapped kinds carry their rule names', () {
      expect(classify('lib/l10n/app_uk.arb', rules).kind, PathKind.arb);
      expect(
        classify('test/golden/goldens/a.png', rules).kind,
        PathKind.goldenAsset,
      );
      expect(
        classify('integration_test/all_tests_part2.dart', rules).kind,
        PathKind.mapped,
      );
    });
  });

  group('T5 ledgers expand their whole directory', () {
    late FixtureRepo repo;
    setUp(
      () => repo = FixtureRepo({
        'lib/core/util.dart': 'int u = 1;\n',
        'lib/routing/r.dart': 'int r = 1;\n',
        'lib/features/auth/data/repo.dart': 'int a = 1;\n',
        'lib/features/other/o.dart': 'int o = 1;\n',
        'lib/features/svc/uses_list.dart': 'final servicesListProvider = 1;\n',
        'test/core/a_test.dart': 'void main() {}\n',
        'test/core/network/n_test.dart': 'void main() {}\n',
        'test/routing/nav_ledger_test.dart': 'void main() {}\n',
        'test/features/auth/data/ad_test.dart': 'void main() {}\n',
        'test/features/services/svc_test.dart': 'void main() {}\n',
        'test/ci/wiring_test.dart': 'void main() {}\n',
        'test/build_guards/bg_test.dart': 'void main() {}\n',
        'test/consistency/c_test.dart': 'void main() {}\n',
        'test/integration_aggregator_meta_test.dart': 'void main() {}\n',
        'test/patrol_excluded_from_fast_path_test.dart': 'void main() {}\n',
        ...filler(120),
      }),
    );
    tearDown(() => repo.dispose());

    test('lib/core/** -> test/core/**', () {
      final s = repo.run(m('lib/core/util.dart'));
      expect(
        s.unit,
        containsAll(['test/core/a_test.dart', 'test/core/network/n_test.dart']),
      );
    });
    test('lib/routing/** -> test/routing/**', () {
      expect(
        repo.run(m('lib/routing/r.dart')).unit,
        contains('test/routing/nav_ledger_test.dart'),
      );
    });
    test(
      'lib/features/auth/data/** -> kPiiPaths ledger (core/network + auth/data)',
      () {
        final s = repo.run(m('lib/features/auth/data/repo.dart'));
        expect(
          s.unit,
          containsAll([
            'test/core/network/n_test.dart',
            'test/features/auth/data/ad_test.dart',
          ]),
        );
      },
    );
    test(
      'file mentioning servicesListProvider -> test/features/services/**',
      () {
        expect(
          repo.run(m('lib/features/svc/uses_list.dart')).unit,
          contains('test/features/services/svc_test.dart'),
        );
      },
    );
    test('...but a file that does not mention it does not', () {
      expect(
        repo.run(m('lib/features/other/o.dart')).unit,
        isNot(contains('test/features/services/svc_test.dart')),
      );
    });
    test('an Added lib file re-runs the structural meta tests', () {
      final s = repo.run('A\tlib/features/other/o.dart\n');
      expect(
        s.unit,
        containsAll([
          'test/ci/wiring_test.dart',
          'test/build_guards/bg_test.dart',
          'test/consistency/c_test.dart',
          'test/integration_aggregator_meta_test.dart',
          'test/patrol_excluded_from_fast_path_test.dart',
        ]),
      );
    });
    test('a plain Modify does not', () {
      expect(
        repo.run(m('lib/features/other/o.dart')).unit,
        isNot(contains('test/ci/wiring_test.dart')),
      );
    });
  });

  group('T6 tests reading lib/ source as text', () {
    late FixtureRepo repo;
    setUp(
      () => repo = FixtureRepo({
        'lib/a.dart': 'int a = 1;\n',
        'test/reader_test.dart': "void main() { File('lib/a.dart'); }\n",
        'test/dq_reader_test.dart': 'void main() { File("lib/b.dart"); }\n',
        'test/plain_test.dart': 'void main() {}\n',
        ...filler(40),
      }),
    );
    tearDown(() => repo.dispose());

    test('auto-included on a lib change (both quote styles)', () {
      final s = repo.run(m('lib/a.dart'));
      expect(
        s.unit,
        containsAll(['test/reader_test.dart', 'test/dq_reader_test.dart']),
      );
      expect(s.unit, isNot(contains('test/plain_test.dart')));
    });
    test('not included on a docs-only change', () {
      final s = repo.run(m('docs/x.md'));
      expect(s.mode, Mode.none);
    });
    test('not included on a test-only change', () {
      final s = repo.run(m('test/plain_test.dart'));
      expect(s.unit, ['test/plain_test.dart']);
    });
  });

  group('T7 deleted / renamed Dart files', () {
    test('BASE importers of a deleted lib file are selected', () {
      final base = FixtureRepo({
        'lib/gone.dart': 'int g = 1;\n',
        'lib/mid.dart': pkg('gone.dart'),
        'test/mid_test.dart': pkg('mid.dart'),
        ...filler(40),
      });
      final head = FixtureRepo({
        // mid dropped the import (the diff under test lists only the deletion)
        'lib/mid.dart': 'int m = 1;\n',
        'test/mid_test.dart': pkg('mid.dart'),
        ...filler(40),
      });
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      const d = 'D\tlib/gone.dart\n';
      expect(head.run(d, base: base).unit, contains('test/mid_test.dart'));
      expect(
        head.run(d).unit,
        isNot(contains('test/mid_test.dart')),
        reason: 'without a BASE tree the HEAD graph cannot know',
      );
    });

    test(
      'a dangling HEAD import of a deleted file still selects the importer',
      () {
        final head = FixtureRepo({
          'lib/mid.dart': pkg('gone.dart'),
          'test/mid_test.dart': pkg('mid.dart'),
          ...filler(40),
        });
        addTearDown(head.dispose);
        expect(
          head.run('D\tlib/gone.dart\n').unit,
          contains('test/mid_test.dart'),
        );
      },
    );

    test('rename seeds both the old (BASE) and new (HEAD) path', () {
      final base = FixtureRepo({
        'lib/old.dart': 'int o = 1;\n',
        'test/old_user_test.dart': pkg('old.dart'),
        ...filler(40),
      });
      final head = FixtureRepo({
        'lib/new.dart': 'int o = 1;\n',
        'test/old_user_test.dart': pkg('new.dart'),
        'test/new_user_test.dart': pkg('new.dart'),
        ...filler(40),
      });
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      final s = head.run('R100\tlib/old.dart\tlib/new.dart\n', base: base);
      expect(
        s.unit,
        containsAll(['test/old_user_test.dart', 'test/new_user_test.dart']),
      );
    });

    test('a deleted test file selects nothing that no longer exists', () {
      final head = FixtureRepo({...filler(40)});
      addTearDown(head.dispose);
      final s = head.run('D\ttest/removed_test.dart\n');
      expect(s.unit, isNot(contains('test/removed_test.dart')));
    });
  });

  group('T8 integration flows with the hub cut', () {
    late FixtureRepo repo;
    setUp(
      () => repo = FixtureRepo({
        'lib/main.dart':
            pkg('features/booking/b.dart') + pkg('features/auth/a.dart'),
        'lib/routing/router.dart': pkg('features/booking/b.dart'),
        'lib/features/booking/b.dart': 'int b = 1;\n',
        'lib/features/auth/a.dart': 'int a = 1;\n',
        'integration_test/support/harness.dart': pkg('main.dart'),
        'integration_test/booking_flow_test.dart':
            "import 'support/harness.dart';\n${pkg('features/booking/b.dart')}",
        'integration_test/auth_flow_test.dart':
            "import 'support/harness.dart';\n${pkg('features/auth/a.dart')}",
        ...filler(40),
      }),
    );
    tearDown(() => repo.dispose());

    test('a booking change selects the booking flow only', () {
      final s = repo.run(m('lib/features/booking/b.dart'));
      expect(s.integration, ['integration_test/booking_flow_test.dart']);
    });
    test('a lib/routing change selects ALL flows', () {
      final s = repo.run(m('lib/routing/router.dart'));
      expect(s.integration, [
        'integration_test/auth_flow_test.dart',
        'integration_test/booking_flow_test.dart',
      ]);
    });
    test('a lib/main.dart change selects ALL flows', () {
      expect(repo.run(m('lib/main.dart')).integration.length, 2);
    });
    test('a flow file selects itself', () {
      expect(repo.run(m('integration_test/auth_flow_test.dart')).integration, [
        'integration_test/auth_flow_test.dart',
      ]);
    });
  });

  group('T9 fail-safes', () {
    late FixtureRepo repo;
    setUp(
      () => repo = FixtureRepo({
        'lib/a.dart': 'int a = 1;\n',
        'test/a1_test.dart': pkg('a.dart'),
        'test/a2_test.dart': pkg('a.dart'),
        'test/a3_test.dart': pkg('a.dart'),
        'test/a4_test.dart': pkg('a.dart'),
        'test/unrelated_test.dart': 'void main() {}\n',
      }),
    );
    tearDown(() => repo.dispose());

    test('unknown path -> full', () {
      final s = repo.run(m('Makefile'));
      expect(s.mode, Mode.full);
      expect(s.reasons.single.rule, contains('unknown path'));
    });
    test('docs only -> none', () {
      expect(repo.run(m('docs/a.md') + m('README.md')).mode, Mode.none);
    });
    test('an unknown path next to a normal change still forces full', () {
      expect(repo.run(m('lib/a.dart') + m('Makefile')).mode, Mode.full);
    });
    test('unit selection above 60% -> full', () {
      // 4 of 5 unit tests (80%) import lib/a.dart.
      final s = repo.run(m('lib/a.dart'));
      expect(s.mode, Mode.full);
      expect(s.reasons.last.rule, contains('> 60%'));
    });
    test('exactly 60% is NOT full (strictly greater)', () {
      final r = FixtureRepo({
        'lib/a.dart': 'int a = 1;\n',
        'test/a_test.dart': pkg('a.dart'),
        'test/b_test.dart': pkg('a.dart'),
        'test/c_test.dart': pkg('a.dart'),
        'test/d_test.dart': 'void main() {}\n',
        'test/e_test.dart': 'void main() {}\n',
      });
      addTearDown(r.dispose);
      final s = r.run(m('lib/a.dart'));
      expect(s.unit.length, 3);
      expect(s.mode, Mode.selective);
    });
    test('threshold comes from rules.yaml', () {
      expect(rules.fullThreshold, 0.60);
    });
  });

  group('T10 --shard', () {
    final files = [
      for (final g in ['a', 'b', 'c'])
        for (var i = 0; i < 7; i++) 'test/features/$g/x$i/f${i}_test.dart',
    ];
    test(
      'shards are disjoint, deterministic, and their union is the input',
      () {
        const n = 4;
        final parts = [for (var i = 1; i <= n; i++) shard(files, i, n)];
        expect(
          parts.expand((x) => x).toList()..sort(),
          (List.of(files)..sort()),
        );
        expect(parts.expand((x) => x).toSet().length, files.length);
        expect(
          shard(files.reversed.toList(), 2, n),
          parts[1],
          reason: 'order-independent',
        );
        expect(
          [for (final x in parts) x.length].reduce((a, b) => a > b ? a : b) -
              [for (final x in parts) x.length].reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1),
        );
      },
    );
    test('bad specs are rejected', () {
      expect(
        () => parseShard('0/4'),
        returnsNormally,
      ); // parse only; range is checked in shard()
      expect(() => shard(files, 0, 4), throwsArgumentError);
      expect(() => shard(files, 5, 4), throwsArgumentError);
      expect(() => parseShard('x'), throwsFormatException);
    });
  });

  group('tz sweep', () {
    test('(unit U golden) intersect sweep dirs + the DST rail file', () {
      final repo = FixtureRepo({
        'lib/shared/time/clock.dart': 'int c = 1;\n',
        'test/shared/time/clock_test.dart': pkg('shared/time/clock.dart'),
        'test/features/booking/presentation/bookings_day_rail_test.dart': pkg(
          'shared/time/clock.dart',
        ),
        'test/features/other/o_test.dart': pkg('shared/time/clock.dart'),
        'test/golden/clock_golden_test.dart': pkg('shared/time/clock.dart'),
        ...filler(60),
      });
      addTearDown(repo.dispose);
      final s = repo.run(m('lib/shared/time/clock.dart'));
      expect(s.tzSweep, [
        'test/features/booking/presentation/bookings_day_rail_test.dart',
        'test/shared/time/clock_test.dart',
      ]);
      expect(s.unit, contains('test/features/other/o_test.dart'));
    });
  });

  group('tz sweep covers every configured directory', () {
    // Hard-coded mirror of the pr-validate.yml Tokyo/Honolulu step list.
    const dirs = [
      'test/features/booking/',
      'test/features/schedule/',
      'test/features/home/',
      'test/features/calendar/',
      'test/shared/formatters/',
      'test/shared/time/',
      'test/shared/calendar/',
      'test/core/time/',
      'test/routing/',
    ];
    for (final d in dirs) {
      test(d, () {
        final repo = FixtureRepo({
          'lib/shared/x.dart': 'int x = 1;\n',
          '${d}x_test.dart': pkg('shared/x.dart'),
          ...filler(60),
        });
        addTearDown(repo.dispose);
        expect(repo.run(m('lib/shared/x.dart')).tzSweep, ['${d}x_test.dart']);
      });
    }
    test('rules.yaml lists exactly those directories', () {
      expect(rules.tzDirs, dirs);
    });
  });

  group('hubs', () {
    FixtureRepo withHub(String hubPath) => FixtureRepo({
      'lib/features/booking/b.dart': 'int b = 1;\n',
      hubPath: pkg('features/booking/b.dart'),
      'integration_test/booking_flow_test.dart': pkg('features/booking/b.dart'),
      'integration_test/auth_flow_test.dart': "import '../$hubPath';\n",
      ...filler(40),
    });
    for (final hub in [
      'lib/app.dart',
      'lib/routing/r.dart',
      'integration_test/support/h.dart',
      'test/integration_support/h.dart',
    ]) {
      test(
        'edges into $hub are not followed (change below it selects only the direct flow)',
        () {
          final repo = withHub(hub);
          addTearDown(repo.dispose);
          expect(repo.run(m('lib/features/booking/b.dart')).integration, [
            'integration_test/booking_flow_test.dart',
          ]);
        },
      );
    }
    test('a changed lib/app.dart selects ALL flows', () {
      final repo = withHub('lib/app.dart');
      addTearDown(repo.dispose);
      expect(repo.run(m('lib/app.dart')).integration.length, 2);
    });
    test('a changed test/integration_support hub selects ALL flows', () {
      expect(rules.isHub('test/integration_support/x.dart'), isTrue);
      expect(rules.isHub('integration_test/support/x.dart'), isTrue);
      // No longer a full_glob (graph-expressible): seeds, hub -> all flows.
      final repo = withHub('test/integration_support/h.dart');
      addTearDown(repo.dispose);
      final s = repo.run(m('test/integration_support/h.dart'));
      expect(s.mode, Mode.selective);
      expect(s.integration.length, 2);
    });
  });

  group('structural ledger roots', () {
    for (final added in [
      'test/features/z/new_test.dart',
      'integration_test/new_flow_test.dart',
    ]) {
      test('Added $added re-runs the meta tests', () {
        final repo = FixtureRepo({
          'test/ci/wiring_test.dart': 'void main() {}\n',
          added: 'void main() {}\n',
          ...filler(40),
        });
        addTearDown(repo.dispose);
        expect(
          repo.run('A\t$added\n').unit,
          contains('test/ci/wiring_test.dart'),
        );
      });
    }
    test('Added file outside lib/test/integration_test does not (none)', () {
      final repo = FixtureRepo({
        'test/ci/wiring_test.dart': 'void main() {}\n',
        ...filler(40),
      });
      addTearDown(repo.dispose);
      expect(repo.run('A\tdocs/new.md\n').mode, Mode.none);
    });
  });

  group('universe + structural renames', () {
    test('universe separates unit, golden and top-level flows', () {
      final repo = FixtureRepo({
        'test/a_test.dart': 'void main() {}\n',
        'test/golden/g_golden_test.dart': 'void main() {}\n',
        'test/golden/helpers/h.dart': 'void main() {}\n',
        'integration_test/f_flow_test.dart': 'void main() {}\n',
        'integration_test/patrol/p_test.dart': 'void main() {}\n',
      });
      addTearDown(repo.dispose);
      final u = universe(ImportGraph.build(repo.root, rules), rules);
      expect(u.unit, ['test/a_test.dart']);
      expect(u.golden, ['test/golden/g_golden_test.dart']);
      expect(u.flows, ['integration_test/f_flow_test.dart']);
    });

    test('a Rename of a lib file re-runs the structural meta tests', () {
      final repo = FixtureRepo({
        'lib/new.dart': 'int a = 1;\n',
        'test/ci/wiring_test.dart': 'void main() {}\n',
        ...filler(40),
      });
      addTearDown(repo.dispose);
      expect(
        repo.run('R100\tlib/old.dart\tlib/new.dart\n').unit,
        contains('test/ci/wiring_test.dart'),
      );
    });
  });

  group('Change parsing', () {
    test('status lines incl. renames', () {
      final c = parseChanges('M\ta.dart\nR087\tb.dart\tc.dart\nD\td.dart\n');
      expect(c.map((x) => x.status), ['M', 'R087', 'D']);
      expect(c[1].livePaths, ['c.dart']);
      expect(c[1].gonePaths, ['b.dart']);
      expect(c[2].livePaths, isEmpty);
      expect(() => Change.parse('garbage'), throwsFormatException);
    });
    test('resolveUri ignores dart:, third-party packages and escapes', () {
      const pk = {'beautica_mobile': 'lib'};
      expect(resolveUri('lib/a.dart', 'dart:io', pk), isNull);
      expect(
        resolveUri('lib/a.dart', 'package:flutter/material.dart', pk),
        isNull,
      );
      expect(resolveUri('lib/a.dart', '../../outside.dart', pk), isNull);
      expect(resolveUri('lib/a/b.dart', '../c.dart', pk), 'lib/c.dart');
      expect(
        resolveUri('lib/a.dart', 'package:beautica_mobile/x/y.dart', pk),
        'lib/x/y.dart',
      );
    });
  });

  group('T12 narrowed rules (phase 398 cycle 7)', () {
    // ---- golden PNG -> owning golden test --------------------------------
    Map<String, String> goldens() => {
      'test/golden/a_golden_test.dart':
          "void main() { goldenTest('x', fileName: 'alpha_card_loaded'); }\n",
      'test/golden/b_golden_test.dart':
          "void main() { goldenTest('x', fileName: 'beta_row_\$suffix'); }\n",
      'test/golden/c_golden_test.dart': "void main() { name(c.fileName); }\n",
      'test/golden/d_golden_test.dart':
          "void main() { goldenTest('x', fileName: '\$id'); }\n",
      'test/features/s/presentation/s_golden_test.dart':
          "void main() { goldenTest('x', fileName: 'sched_week'); }\n",
      'test/other/alpha_card_loaded_test.dart':
          "void main() { f('alpha_card_loaded'); }\n",
      ...filler(40),
    };

    test(
      'PNG -> every golden test beside goldens/, regardless of literals',
      () {
        final repo = FixtureRepo(goldens());
        addTearDown(repo.dispose);
        for (final png in [
          'alpha_card_loaded',
          'beta_row_360_1x',
          'anything',
        ]) {
          final s = repo.run(m('test/golden/goldens/$png.png'));
          expect(s.mode, Mode.selective);
          expect(s.golden, [
            'test/golden/a_golden_test.dart',
            'test/golden/b_golden_test.dart',
            'test/golden/c_golden_test.dart',
            'test/golden/d_golden_test.dart',
          ]);
          // same literal in a test in ANOTHER directory is not an owner
          expect(
            s.unit,
            isNot(contains('test/other/alpha_card_loaded_test.dart')),
          );
        }
      },
    );

    test('decoy literal in A + real owner B (\'a_\' + x) -> both selected', () {
      final repo = FixtureRepo({
        'test/golden/a_golden_test.dart':
            "void main() { goldenTest('x', fileName: 'booking_card'); }\n",
        'test/golden/b_golden_test.dart':
            "void main() { goldenTest('x', fileName: 'booking_' + x); }\n",
        'test/golden/c_golden_test.dart':
            "void main() { goldenTest('x', goldenFileName: 'q'); }\n",
        ...filler(40),
      });
      addTearDown(repo.dispose);
      final s = repo.run(m('test/golden/goldens/booking_card.png'));
      expect(
        s.golden,
        containsAll([
          'test/golden/a_golden_test.dart',
          'test/golden/b_golden_test.dart',
        ]),
      );
    });

    test('PNG beside a feature test resolves into the unit bucket', () {
      final repo = FixtureRepo(goldens());
      addTearDown(repo.dispose);
      final s = repo.run(
        m('test/features/s/presentation/goldens/sched_week.png'),
      );
      expect(s.unit, ['test/features/s/presentation/s_golden_test.dart']);
      expect(s.golden, isEmpty);
    });

    for (final unresolved in [
      'test/golden/failures/alpha_card_loaded.png', // not under goldens/
      'test/features/zzz/goldens/alpha_card_loaded.png', // owner dir has no test
    ]) {
      test('unresolved PNG $unresolved -> FULL (fail-safe)', () {
        final repo = FixtureRepo(goldens());
        addTearDown(repo.dispose);
        expect(repo.run(m(unresolved)).mode, Mode.full);
      });
    }

    test('a deleted PNG resolves the same way', () {
      final repo = FixtureRepo(goldens());
      addTearDown(repo.dispose);
      final s = repo.run('D\ttest/golden/goldens/alpha_card_loaded.png\n');
      expect(s.golden, contains('test/golden/a_golden_test.dart'));
    });

    // ---- aggregator entrypoints -------------------------------------------
    test('all_tests_part*.dart -> the two aggregator meta tests only', () {
      final repo = FixtureRepo({
        'integration_test/all_tests_part1.dart': 'void main() {}\n',
        'test/integration_aggregator_meta_test.dart': 'void main() {}\n',
        'test/patrol_excluded_from_fast_path_test.dart': 'void main() {}\n',
        ...filler(40),
      });
      addTearDown(repo.dispose);
      final s = repo.run(m('integration_test/all_tests_part1.dart'));
      expect(s.mode, Mode.selective);
      expect(s.unit, [
        'test/integration_aggregator_meta_test.dart',
        'test/patrol_excluded_from_fast_path_test.dart',
      ]);
    });

    // ---- tool/openapi ------------------------------------------------------
    test('tool/openapi/api-spec.json alone -> mode none', () {
      final repo = FixtureRepo(filler(5));
      addTearDown(repo.dispose);
      expect(repo.run(m('tool/openapi/api-spec.json')).mode, Mode.none);
    });

    // ---- ARB -----------------------------------------------------------------
    String arb(Map<String, Object> m) =>
        '{${m.entries.map((e) => '"${e.key}": ${e.value is String ? '"${e.value}"' : e.value}').join(',')}}';

    FixtureRepo arbRepo(String body) => FixtureRepo({
      'lib/l10n/app_uk.arb': body,
      'lib/features/a/a_screen.dart': 'void f(l) { l.titleA; }\n',
      'lib/features/b/b_screen.dart': 'void f(l) { l.titleB; }\n',
      'test/features/a/a_screen_test.dart': pkg('features/a/a_screen.dart'),
      'test/features/b/b_screen_test.dart': pkg('features/b/b_screen.dart'),
      'test/features/c/by_key_test.dart': 'void main() { l.titleC; }\n',
      'test/features/c/by_text_test.dart':
          "void main() { find.text('Заголовок Д'); }\n",
      'test/l10n/parity_test.dart': 'void main() {}\n',
      'test/arb_reader_test.dart':
          "void main() { File('lib/l10n/app_uk.arb'); }\n",
      ...filler(60),
    });

    final baseArb = arb({'titleA': 'A', 'titleB': 'B', 'titleC': 'C'});

    test(
      'changed key -> its lib consumer chain + key/text mentions + readers',
      () {
        final base = arbRepo(baseArb);
        final head = arbRepo(
          arb({'titleA': 'A2', 'titleB': 'B', 'titleC': 'C'}),
        );
        addTearDown(base.dispose);
        addTearDown(head.dispose);
        final s = head.run(m('lib/l10n/app_uk.arb'), base: base);
        expect(s.mode, Mode.selective);
        expect(s.unit, contains('test/features/a/a_screen_test.dart'));
        expect(s.unit, isNot(contains('test/features/b/b_screen_test.dart')));
        expect(s.unit, isNot(contains('test/features/c/by_key_test.dart')));
        expect(
          s.unit,
          contains('test/l10n/parity_test.dart'),
        ); // include_always
        expect(s.unit, contains('test/arb_reader_test.dart')); // reads .arb
      },
    );

    test('a test that mentions the changed key directly is selected', () {
      final base = arbRepo(baseArb);
      final head = arbRepo(arb({'titleA': 'A', 'titleB': 'B', 'titleC': 'C2'}));
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      final s = head.run(m('lib/l10n/app_uk.arb'), base: base);
      expect(s.unit, contains('test/features/c/by_key_test.dart'));
      expect(s.unit, isNot(contains('test/features/a/a_screen_test.dart')));
    });

    test('a test that finds the OLD rendered text is selected', () {
      final b = arb({'titleD': 'Заголовок Д'});
      final base = arbRepo(b);
      final head = arbRepo(arb({'titleD': 'Інший'}));
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      final s = head.run(m('lib/l10n/app_uk.arb'), base: base);
      expect(s.unit, contains('test/features/c/by_text_test.dart'));
    });

    test('an ADDED key nobody uses selects only the arb readers', () {
      final base = arbRepo(baseArb);
      final head = arbRepo(
        arb({'titleA': 'A', 'titleB': 'B', 'titleC': 'C', 'brandNew': 'N'}),
      );
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      final s = head.run(m('lib/l10n/app_uk.arb'), base: base);
      expect(s.mode, Mode.selective);
      expect(s.unit, [
        'test/arb_reader_test.dart',
        'test/l10n/parity_test.dart',
      ]);
    });

    test('@key metadata edit counts as a change of key', () {
      final base = arbRepo(
        '{"titleA":"A","@titleA":{"description":"x"},"titleB":"B"}',
      );
      final head = arbRepo(
        '{"titleA":"A","@titleA":{"description":"y"},"titleB":"B"}',
      );
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      final s = head.run(m('lib/l10n/app_uk.arb'), base: base);
      expect(s.unit, contains('test/features/a/a_screen_test.dart'));
      expect(s.unit, isNot(contains('test/features/b/b_screen_test.dart')));
    });

    test('no BASE tree -> FULL (cannot diff)', () {
      final head = arbRepo(baseArb);
      addTearDown(head.dispose);
      expect(head.run(m('lib/l10n/app_uk.arb')).mode, Mode.full);
    });

    test('@@locale change -> FULL', () {
      final base = arbRepo('{"@@locale":"uk","titleA":"A"}');
      final head = arbRepo('{"@@locale":"en","titleA":"A"}');
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      expect(head.run(m('lib/l10n/app_uk.arb'), base: base).mode, Mode.full);
    });

    test('unparsable ARB -> FULL', () {
      final base = arbRepo(baseArb);
      final head = arbRepo('{ not json');
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      expect(head.run(m('lib/l10n/app_uk.arb'), base: base).mode, Mode.full);
    });
  });

  group('T13 asset/ARB hardening (phase 398 cycle 8)', () {
    String arbJson(Map<String, String> m) =>
        '{${m.entries.map((e) => '"${e.key}": "${e.value}"').join(',')}}';

    Selection arbRun(
      Map<String, String> before,
      Map<String, String> after,
      Map<String, String> extra,
    ) {
      FixtureRepo mk(Map<String, String> v) => FixtureRepo({
        'lib/l10n/app_uk.arb': arbJson(v),
        ...extra,
        ...filler(60),
      });
      final base = mk(before), head = mk(after);
      addTearDown(base.dispose);
      addTearDown(head.dispose);
      return head.run(m('lib/l10n/app_uk.arb'), base: base);
    }

    test(
      'F1 trailing-space chunk is trimmed: textContaining still finds it',
      () {
        final s = arbRun({'del': 'Видалити '}, {'del': 'Інше'}, {
          'test/features/c/by_text_test.dart':
              "void main() { find.textContaining('Видалити'); }\n",
        });
        expect(s.unit, contains('test/features/c/by_text_test.dart'));
      },
    );

    test('F1 short value (Так) matches as a whole quoted literal only', () {
      final s = arbRun({'yes': 'Так'}, {'yes': 'Ні'}, {
        'test/features/c/yes_test.dart': "void main() { find.text('Так'); }\n",
        'test/features/c/dq_test.dart': 'void main() { find.text("Ні"); }\n',
        'test/features/c/other_test.dart':
            "void main() { find.text('Таксі'); }\n",
      });
      expect(s.unit, contains('test/features/c/yes_test.dart'));
      expect(s.unit, contains('test/features/c/dq_test.dart'));
      expect(s.unit, isNot(contains('test/features/c/other_test.dart')));
    });

    test('non-UTF-8 test file: no crash, selection still correct', () {
      final repo = FixtureRepo({
        'test/golden/a_golden_test.dart': 'void main() {}\n',
        ...filler(40),
      });
      addTearDown(repo.dispose);
      File(p.join(repo.root, 'test/features/bad_test.dart'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([
          ...'void main() { // '.codeUnits,
          0xff,
          0xfe,
          0x0a,
          0x7d,
        ]);
      final s = repo.run(m('test/golden/goldens/x.png'));
      expect(s.mode, Mode.selective);
      expect(s.golden, ['test/golden/a_golden_test.dart']);
    });

    test('CLI: unexpected exception -> exit 70', () {
      final repo = FixtureRepo(filler(3));
      addTearDown(repo.dispose);
      // --changes pointing at a directory -> FileSystemException
      final r = Process.runSync(Platform.resolvedExecutable, [
        'run',
        'bin/affected_tests.dart',
        '--repo',
        repo.root,
        '--changes',
        repo.root,
        '--out',
        p.join(repo.root, 'o', 'selection.json'),
      ]);
      expect(r.exitCode, 70);
      expect(r.stderr, contains('internal error'));
    });

    test('F4 ARB-seeded lib file expands the cardinality ledgers', () {
      final s = arbRun({'t': 'Старе'}, {'t': 'Нове'}, {
        'lib/core/widget.dart': 'void f(l) { l.t; }\n',
        'test/core/ledger_test.dart': 'void main() {}\n',
        'test/routing/nav_test.dart': 'void main() {}\n',
      });
      expect(s.unit, contains('test/core/ledger_test.dart'));
      expect(s.unit, isNot(contains('test/routing/nav_test.dart')));
    });
  });

  group('T11 real-repo invariants', () {
    final repoRoot = p.normalize(
      p.join(Directory.current.path, '..', '..', '..'),
    );
    final haveRepo = File(p.join(repoRoot, 'lib', 'main.dart')).existsSync();

    test(
      'every file under test/helpers/ seeds mode=full',
      () {
        final dir = Directory(p.join(repoRoot, 'test', 'helpers'));
        final files = dir.listSync(recursive: true).whereType<File>().toList();
        expect(files, isNotEmpty);
        for (final f in files) {
          final rel = p.posix.joinAll(
            p.split(p.relative(f.path, from: repoRoot)),
          );
          final s = select(
            root: repoRoot,
            changes: [Change('M', rel)],
            rules: rules,
          );
          expect(s.mode, Mode.full, reason: rel);
        }
      },
      skip: haveRepo ? false : 'not inside the beautica-mobile tree',
    );

    test(
      'the graph sees every *_test.dart under test/ (no unparsed files)',
      () {
        final onDisk = Directory(p.join(repoRoot, 'test'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .length;
        final g = ImportGraph.build(repoRoot, rules);
        final u = universe(g, rules);
        expect(u.unit.length + u.golden.length, onDisk);
        final flows = Directory(p.join(repoRoot, 'integration_test'))
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .length;
        expect(u.flows.length, flows);
      },
      skip: haveRepo ? false : 'not inside the beautica-mobile tree',
    );

    test(
      'rules.yaml tz_sweep mirrors pr-validate.yml (dirs appear in the workflow)',
      () {
        final wf = File(
          p.join(repoRoot, '.github', 'workflows', 'pr-validate.yml'),
        ).readAsStringSync();
        for (final d in rules.tzDirs) {
          expect(wf, contains(d), reason: '$d missing from the TZ sweep steps');
        }
      },
      skip: haveRepo ? false : 'not inside the beautica-mobile tree',
    );

    test(
      'every tracked top-level path class is covered by a rule or fails safe',
      () {
        // Fail-safe sanity: an unknown path is FULL, never "none".
        expect(classify('brand_new_dir/x.txt', rules).kind, PathKind.full);
      },
    );
  });
}
