import 'dart:convert';
import 'dart:io';

import 'package:affected_tests/cli.dart' as selector;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/gen_integration_entry.dart' as gen;

/// Phase 401: selection.json -> integration_test/ci_selected_tests.dart.
void main() {
  final pkg = Directory.current.path;
  final appRoot = p.normalize(p.join(pkg, '..', '..', '..'));
  final haveApp = File(
    p.join(appRoot, 'integration_test', 'all_tests_part1.dart'),
  ).existsSync();

  String sel(List<String> flows, {String mode = 'selective'}) =>
      jsonEncode({'mode': mode, 'integration': flows});
  String ip(String n) => 'integration_test/$n';

  // A fake repo with two small part files (4 flows each) for the D3 rule.
  String partSrc(List<String> names) => [
    "import 'package:flutter_test/flutter_test.dart';",
    "import 'package:integration_test/integration_test.dart';",
    for (final n in names) "import '${n}_test.dart' as $n;",
  ].join('\n');
  final p1 = partSrc(['a1', 'a2', 'a3', 'a4']);
  final p2 = partSrc(['b1', 'b2', 'b3', 'b4']);

  group('renderEntry', () {
    test('2 flows are byte-identical to the golden fixture', () {
      final out = gen.renderEntry([
        ip('client_favorites_flow_test.dart'),
        ip('auth_login_flow_test.dart'),
      ]);
      final golden = File(
        p.join(pkg, 'test', 'fixtures', 'integration_entry_2flows.dart.txt'),
      ).readAsStringSync();
      expect(out, golden);
    });

    test('aliases stay unique when basenames clash after _flow stripping', () {
      final flows = [
        ip('foo_flow_test.dart'),
        ip('foo_test.dart'),
        ip('foo_2_test.dart'),
      ];
      final aliases = gen.aliasesFor(flows).values.toList();
      expect(aliases.toSet(), hasLength(3), reason: '$aliases');
      final out = gen.renderEntry(flows);
      expect(RegExp(r' as foo\w*;').allMatches(out), hasLength(3));
      expect(
        RegExp(r'^  group\(', multiLine: true).allMatches(out),
        hasLength(3),
      );
    });

    test('audit 4: no in-band sentinel — no nonce define, no extra group, '
        'only the flow groups', () {
      final out = gen.renderEntry([ip('a_flow_test.dart'), ip('b_test.dart')]);
      expect(out, isNot(contains('CI_SENTINEL_NONCE')));
      expect(out, isNot(contains('fromEnvironment')));
      expect(out, isNot(contains('__ci_done')));
      final groups = RegExp(
        r"^  group\('(\w+)'",
        multiLine: true,
      ).allMatches(out).map((m) => m.group(1)).toList();
      expect(groups, ['a_flow', 'b']);
      expect(
        RegExp(r'^import \x27[a-z_]+_test', multiLine: true).allMatches(out),
        hasLength(2),
      );
    });

    test('the cap counts flows — maxSelectedFlows flows still select', () {
      final flows = [
        for (var i = 0; i < gen.maxSelectedFlows; i++)
          ip(
            'f${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}_flow_test.dart',
          ),
      ];
      final d = gen.decide(
        selectionJson: jsonEncode({'mode': 'selective', 'integration': flows}),
        partSources: [p1, p2],
      );
      expect(d.entry, 'selected', reason: d.why);
      expect(d.count, gen.maxSelectedFlows);
    });

    test('S6: aliases never collide with reserved words or the names the '
        'generated main / test framework use', () {
      final flows = [
        for (final n in [
          'group_flow',
          'test_flow',
          'expect_flow',
          'main_flow',
          'class_flow',
          'if_flow',
          'async_flow',
          'import_flow',
        ])
          ip('${n}_test.dart'),
      ];
      final a = gen.aliasesFor(flows).values.toList();
      expect(a.toSet(), hasLength(flows.length));
      for (final bad in [
        'group',
        'test',
        'expect',
        'main',
        'class',
        'if',
        'async',
        'import',
      ]) {
        expect(a, isNot(contains(bad)), reason: '$a');
      }
      expect(a, containsAll(['group_2', 'test_2', 'class_2', 'if_2']));
      final out = gen.renderEntry(flows);
      expect(out, contains("group('group_flow', group_2.main);"));
    });

    test('duplicates collapse to one import and one group', () {
      final out = gen.renderEntry([ip('x_test.dart'), ip('x_test.dart')]);
      expect(
        RegExp(r'^import \x27x_test', multiLine: true).allMatches(out),
        hasLength(1),
      );
    });
  });

  group('partFlows (Q3)', () {
    test('single- AND double-quoted imports are both read', () {
      expect(
        gen.partFlows(
          "import 'a_test.dart' as a;\n"
          'import "b_test.dart" as b;\n'
          'import "c_test.dart\' as c;\n' // mismatched quotes: ignored
          "import 'package:x/d_test.dart' as d;\n",
        ),
        {'a_test.dart', 'b_test.dart'},
      );
    });

    test('a double-quoted part still drives D3', () {
      final dq = [
        for (final n in ['a1', 'a2', 'a3', 'a4'])
          'import "${n}_test.dart" as $n;',
      ].join('\n');
      expect(
        gen
            .decide(
              selectionJson: sel([
                for (final n in ['a1', 'a2', 'a3']) ip('${n}_test.dart'),
              ]),
              partSources: [dq, p2],
            )
            .entry,
        'parts',
      );
    });
  });

  group('decide (D3 + fail-safe)', () {
    test('S6: a selected path missing on disk -> parts (exists callback)', () {
      final d = gen.decide(
        selectionJson: sel([ip('a1_test.dart'), ip('gone_test.dart')]),
        partSources: [p1, p2],
        exists: (f) => f != ip('gone_test.dart'),
      );
      expect(d.entry, 'parts');
      expect(d.source, isNull);
    });

    test('P4: 41 flows -> parts, 40 -> selected, force bypasses the cap', () {
      String many(int n) =>
          sel([for (var i = 0; i < n; i++) ip('z${i}_test.dart')]);
      final big = [p1, p2];
      expect(
        gen.decide(selectionJson: many(41), partSources: big).entry,
        'parts',
      );
      final ok = gen.decide(selectionJson: many(40), partSources: big);
      expect(ok.entry, 'selected');
      expect(ok.count, 40);
      expect(
        gen
            .decide(
              selectionJson: many(41),
              partSources: big,
              forceSelected: true,
            )
            .entry,
        'selected',
      );
    });

    test('small selection -> selected', () {
      final d = gen.decide(
        selectionJson: sel([ip('a1_test.dart')]),
        partSources: [p1, p2],
      );
      expect(d.entry, 'selected');
      expect(d.source, contains("group('a1', a1.main);"));
    });

    test('>= 70% of ONE part -> parts (3/4 = 75%)', () {
      final d = gen.decide(
        selectionJson: sel([
          for (final n in ['a1', 'a2', 'a3']) ip('${n}_test.dart'),
        ]),
        partSources: [p1, p2],
      );
      expect(d.entry, 'parts');
      expect(d.source, isNull);
    });

    test('just under 70% (2/4 = 50%) -> selected', () {
      final d = gen.decide(
        selectionJson: sel([ip('a1_test.dart'), ip('a2_test.dart')]),
        partSources: [p1, p2],
      );
      expect(d.entry, 'selected');
    });

    test('every flow (hub change) -> parts', () {
      final all = [
        for (final n in ['a1', 'a2', 'a3', 'a4', 'b1', 'b2', 'b3', 'b4'])
          ip('${n}_test.dart'),
      ];
      expect(
        gen.decide(selectionJson: sel(all), partSources: [p1, p2]).entry,
        'parts',
      );
    });

    test('empty list -> none', () {
      expect(
        gen.decide(selectionJson: sel([]), partSources: [p1, p2]).entry,
        'none',
      );
    });

    for (final bad in <String, String>{
      'invalid json': '{nope',
      'mode full':
          '{"mode":"full","integration":["integration_test/a1_test.dart"]}',
      'mode none': '{"mode":"none","integration":[]}',
      'non-string': '{"mode":"selective","integration":[1]}',
      'nested path':
          '{"mode":"selective","integration":["integration_test/patrol/a_test.dart"]}',
      'traversal':
          '{"mode":"selective","integration":["integration_test/../x_test.dart"]}',
      'missing key': '{"mode":"selective"}',
    }.entries) {
      test('fail-safe: ${bad.key} -> parts', () {
        final d = gen.decide(selectionJson: bad.value, partSources: [p1, p2]);
        expect(d.entry, 'parts');
        expect(d.source, isNull);
      });
    }

    test('fail-safe: unreadable (empty) part files -> parts', () {
      expect(
        gen
            .decide(
              selectionJson: sel([ip('a1_test.dart')]),
              partSources: ['', ''],
            )
            .entry,
        'parts',
      );
    });
  });

  const maxFlows = gen.maxSelectedFlows;

  group('CLI', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gen_ie_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ProcessResult runGen(
      String selJson, {
      List<String> extra = const [],
      bool createFlows = true,
    }) {
      final sf = File(p.join(tmp.path, 'selection.json'))
        ..writeAsStringSync(selJson);
      if (createFlows) {
        for (final f in ((jsonDecode(selJson) as Map)['integration'] as List)) {
          File(p.join(tmp.path, f as String)).createSync(recursive: true);
        }
      }
      for (final e in {
        'all_tests_part1.dart': p1,
        'all_tests_part2.dart': p2,
      }.entries) {
        File(p.join(tmp.path, 'integration_test', e.key))
          ..createSync(recursive: true)
          ..writeAsStringSync(e.value);
      }
      return Process.runSync(Platform.resolvedExecutable, [
        p.join(pkg, 'bin', 'gen_integration_entry.dart'),
        '--selection',
        sf.path,
        '--repo',
        tmp.path,
        ...extra,
      ]);
    }

    File entry() =>
        File(p.join(tmp.path, 'integration_test', 'ci_selected_tests.dart'));

    test('selected: writes the file, prints entry=selected, exit 0', () {
      final r = runGen(sel([ip('a1_test.dart')]));
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim().split('\n'), [
        'entry=selected',
        'count=1',
      ]);
      expect(entry().existsSync(), isTrue);
    });

    test('empty list: NO file, exit 0, entry=none', () {
      final r = runGen(sel([]));
      expect(r.exitCode, 0);
      expect((r.stdout as String).trim(), 'entry=none');
      expect(entry().existsSync(), isFalse);
    });

    test('a stale entry from an earlier run is removed on parts', () {
      entry()
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
      final r = runGen(
        sel([
          for (final n in ['a1', 'a2', 'a3']) ip('${n}_test.dart'),
        ]),
      );
      expect((r.stdout as String).trim(), 'entry=parts');
      expect(entry().existsSync(), isFalse);
    });

    test('S1: a PR-committed DANGLING symlink at the entry is replaced, never '
        'written through', () {
      final outside = p.join(tmp.path, 'outside', 'pwned.dart');
      Directory(p.dirname(outside)).createSync(recursive: true);
      Link(entry().path)
        ..parent.createSync(recursive: true)
        ..createSync(outside);
      final r = runGen(sel([ip('a1_test.dart')]));
      expect((r.stdout as String).split('\n').first, 'entry=selected');
      expect(File(outside).existsSync(), isFalse, reason: 'write-through');
      expect(
        FileSystemEntity.typeSync(entry().path, followLinks: false),
        FileSystemEntityType.file,
      );
      expect(entry().readAsStringSync(), contains("group('a1', a1.main);"));
    });

    test('S1: a symlink to an EXISTING file outside is left untouched', () {
      final outside = File(p.join(tmp.path, 'outside', 'precious.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('precious');
      Link(entry().path)
        ..parent.createSync(recursive: true)
        ..createSync(outside.path);
      runGen(sel([ip('a1_test.dart')]));
      expect(outside.readAsStringSync(), 'precious');
      expect(
        FileSystemEntity.typeSync(entry().path, followLinks: false),
        FileSystemEntityType.file,
      );
    });

    test(
      'S1: a dangling symlink is also removed when the decision is parts',
      () {
        Link(entry().path)
          ..parent.createSync(recursive: true)
          ..createSync(p.join(tmp.path, 'outside', 'x.dart'));
        final r = runGen(
          sel([
            for (final n in ['a1', 'a2', 'a3']) ip('${n}_test.dart'),
          ]),
        );
        expect((r.stdout as String).trim(), 'entry=parts');
        expect(
          FileSystemEntity.typeSync(entry().path, followLinks: false),
          FileSystemEntityType.notFound,
        );
      },
    );

    test('S1: a DIRECTORY committed at the entry path is replaced', () {
      Directory(entry().path).createSync(recursive: true);
      File(p.join(entry().path, 'x')).writeAsStringSync('x');
      final r = runGen(sel([ip('a1_test.dart')]));
      expect((r.stdout as String).split('\n').first, 'entry=selected');
      expect(
        FileSystemEntity.typeSync(entry().path, followLinks: false),
        FileSystemEntityType.file,
      );
    });

    test(
      'S1: a symlinked PARENT directory never receives the entry -> parts',
      () {
        final real = Directory(p.join(tmp.path, 'real_it'))..createSync();
        Link(p.join(tmp.path, 'linkdir')).createSync(real.path);
        final r = runGen(
          sel([ip('a1_test.dart')]),
          extra: [
            '--out',
            p.join(tmp.path, 'linkdir', 'ci_selected_tests.dart'),
          ],
        );
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect((r.stdout as String).trim(), 'entry=parts');
        expect(real.listSync(), isEmpty);
      },
    );

    test('Q2: a write failure prints entry=parts, exit 0, no partial file', () {
      final r = runGen(
        sel([ip('a1_test.dart')]),
        extra: ['--out', p.join(tmp.path, 'no', 'such', 'dir', 'x.dart')],
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim(), 'entry=parts');
    });

    test('S6: a selected flow file that does not exist -> parts', () {
      final r = runGen(sel([ip('a1_test.dart')]), createFlows: false);
      expect((r.stdout as String).trim(), 'entry=parts');
      expect(entry().existsSync(), isFalse);
    });

    test('P4: more than $maxFlows flows -> parts, exactly $maxFlows -> '
        'selected, with count', () {
      final big = [for (var i = 0; i < 41; i++) ip('z${i}_test.dart')];
      var r = runGen(sel(big));
      expect((r.stdout as String).trim(), 'entry=parts');
      expect(entry().existsSync(), isFalse);
      r = runGen(sel(big.take(40).toList()));
      expect((r.stdout as String).trim().split('\n'), [
        'entry=selected',
        'count=40',
      ]);
    });

    test('bad usage is fail-safe parts, exit 0', () {
      final r = Process.runSync(Platform.resolvedExecutable, [
        p.join(pkg, 'bin', 'gen_integration_entry.dart'),
        '--bogus',
      ]);
      expect(r.exitCode, 0);
      expect((r.stdout as String).trim(), 'entry=parts');
    });
  });

  group('ledger guard', () {
    test(
      '--all entry == flows of all_tests_part1 U all_tests_part2',
      () {
        final out = p.join(
          Directory.systemTemp.createTempSync('gen_ledger_').path,
          'selection.json',
        );
        addTearDown(
          () => Directory(p.dirname(out)).deleteSync(recursive: true),
        );
        expect(
          selector.run([
            '--all',
            '--repo',
            appRoot,
            '--rules',
            p.join(pkg, 'rules.yaml'),
            '--out',
            out,
          ]),
          0,
        );
        final d = gen.decide(
          selectionJson: File(out)
              .readAsStringSync()
              .replaceFirst('"mode": "full"', '"mode": "selective"')
              .replaceFirst('"mode":"full"', '"mode":"selective"'),
          partSources: [
            for (final f in gen.partFiles)
              File(p.join(appRoot, f)).readAsStringSync(),
          ],
          forceSelected: true,
        );
        expect(d.entry, 'selected');
        expect(d.source, isNot(contains('__ci_done')));
        final generated = RegExp(
          r"^import '([A-Za-z0-9_]+_test\.dart)'",
          multiLine: true,
        ).allMatches(d.source!).map((m) => m.group(1)!).toSet();
        final inParts = <String>{
          for (final f in gen.partFiles)
            ...gen.partFlows(File(p.join(appRoot, f)).readAsStringSync()),
        };
        expect(
          generated.difference(inParts),
          isEmpty,
          reason:
              'flow(s) on disk but in NEITHER all_tests_part1 nor part2: '
              '${(generated.difference(inParts).toList()..sort()).join(', ')}',
        );
        expect(
          inParts.difference(generated),
          isEmpty,
          reason: 'part imports with no flow file on disk',
        );
      },
      skip: haveApp ? false : 'not inside the beautica-mobile tree',
    );
  });
}
