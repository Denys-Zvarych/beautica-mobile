import 'dart:convert';
import 'dart:io';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Phase 402: file-level sharding of the `unit` list (D2/D3/D3a).
void main() {
  group('shardsFor (D3a: ceil(count / threshold), max 4)', () {
    const t = 80;
    test('boundaries 0 / 1 / 80 / 81 / 160 / 161 / 240 / 241 / 320 / 400', () {
      final got = {
        for (final c in [0, 1, 80, 81, 160, 161, 240, 241, 320, 321, 400])
          c: shardsFor(c, threshold: t),
      };
      expect(got, {
        0: 0,
        1: 1,
        80: 1,
        81: 2,
        160: 2,
        161: 3,
        240: 3,
        241: 4,
        320: 4,
        321: 4,
        400: 4,
      });
    });

    test('follows the threshold it is given (no second literal inside)', () {
      expect(shardsFor(150, threshold: 150), 1);
      expect(shardsFor(151, threshold: 150), 2);
      expect(shardsFor(81, threshold: 100), 1);
      expect(shardsFor(101, threshold: 100), 2);
    });

    test('bad input is rejected, never defaulted', () {
      expect(() => shardsFor(5, threshold: 0), throwsArgumentError);
      expect(() => shardsFor(-1, threshold: 80), throwsArgumentError);
    });

    test('a FULL run is 4 shards and selective never exceeds it', () {
      expect(fullShards, 4);
      expect(maxShards, 4);
      expect(shardsFor(100000, threshold: 1), maxShards);
    });
  });

  group('shard() partitions the list (union == input, disjoint, stable)', () {
    // Shaped like the real tree: many feature dirs, uneven sizes.
    final files = [
      for (var d = 0; d < 23; d++)
        for (var i = 0; i < 5 + d * 3 % 11; i++)
          'test/features/f$d/presentation/s${d}_${i}_test.dart',
      for (var i = 0; i < 40; i++) 'test/core/c${i}_test.dart',
    ];

    for (final n in [1, 2, 3, 4]) {
      test('N=$n: union == input, disjoint, deterministic, balanced', () {
        final parts = [for (var i = 1; i <= n; i++) shard(files, i, n)];
        final all = parts.expand((x) => x).toList();
        expect(all.length, files.length, reason: 'no file doubled or dropped');
        expect(all.toSet().length, files.length, reason: 'disjoint');
        expect(all.toList()..sort(), List.of(files)..sort());
        for (var i = 1; i <= n; i++) {
          expect(
            shard(files.reversed.toList(), i, n),
            parts[i - 1],
            reason: 'order-independent',
          );
          expect(shard(files, i, n), parts[i - 1], reason: 'repeatable');
        }
        final sizes = [for (final x in parts) x.length]..sort();
        expect(sizes.last - sizes.first, lessThanOrEqualTo(1));
      });
    }

    test('every shard of a 4-way split is non-empty for a realistic tree', () {
      for (var i = 1; i <= 4; i++) {
        expect(shard(files, i, 4), isNotEmpty);
      }
    });
  });

  group('shard() weighted longest-first greedy (audit F3)', () {
    // 7,6,5,4,3,2 over 2 shards. LPT by hand: 7->A(7) 6->B(6) 5->B(11)
    // 4->A(11) 3->A(14, tie A=B=11 goes to the LOWEST shard) 2->B(13).
    final w = {
      'test/g7_test.dart': 7,
      'test/g6_test.dart': 6,
      'test/g5_test.dart': 5,
      'test/g4_test.dart': 4,
      'test/g3_test.dart': 3,
      'test/g2_test.dart': 2,
    };
    final files = w.keys.toList();

    test('pinned split: heaviest first, least-loaded shard, tie -> lowest', () {
      expect(shard(files, 1, 2, weights: w), [
        'test/g3_test.dart',
        'test/g4_test.dart',
        'test/g7_test.dart',
      ]);
      expect(shard(files, 2, 2, weights: w), [
        'test/g2_test.dart',
        'test/g5_test.dart',
        'test/g6_test.dart',
      ]);
    });

    test('weights beat counts: the heavy files are spread over distinct '
        'shards while a count-only split would stack them', () {
      final all = [
        for (var i = 0; i < 40; i++)
          'test/f${i.toString().padLeft(2, '0')}_test.dart',
      ];
      // Positions 0, 4, 8, 12 of the sorted list: round-robin by count puts ALL
      // four on shard 1.
      final heavy = {
        for (final i in [0, 4, 8, 12]) all[i]: 1000,
      };
      expect(
        shard(all, 1, 4).where(heavy.containsKey),
        hasLength(4),
        reason: 'unweighted control: shard 1 holds every heavy file',
      );
      for (var i = 1; i <= 4; i++) {
        expect(
          shard(all, i, 4, weights: heavy).where(heavy.containsKey),
          hasLength(1),
          reason: 'shard $i holds exactly one heavy file',
        );
      }
      final loads = [
        for (var i = 1; i <= 4; i++)
          shard(
            all,
            i,
            4,
            weights: heavy,
          ).fold<int>(0, (a, f) => a + (heavy[f] ?? 1)),
      ]..sort();
      expect(loads.last - loads.first, lessThanOrEqualTo(1000));
    });

    test(
      'partition: union == input, disjoint, any input order, repeatable',
      () {
        final all = [
          for (var d = 0; d < 9; d++)
            for (var i = 0; i < 4 + d; i++) 'test/d$d/s${d}_${i}_test.dart',
        ];
        final wt = {
          for (var i = 0; i < all.length; i++) all[i]: 1 + (i * 37) % 11,
        };
        for (final n in [1, 2, 3, 4]) {
          final parts = [
            for (var i = 1; i <= n; i++) shard(all, i, n, weights: wt),
          ];
          expect(parts.expand((x) => x).toList()..sort(), [...all]..sort());
          expect(parts.expand((x) => x).toSet(), hasLength(all.length));
          for (var i = 1; i <= n; i++) {
            expect(
              shard(all.reversed.toList(), i, n, weights: wt),
              parts[i - 1],
            );
            expect(parts[i - 1], [...parts[i - 1]]..sort(), reason: 'sorted');
            expect(parts[i - 1], isNotEmpty);
          }
        }
      },
    );

    test('equal weights tie-break by path, so equal weights == no weights', () {
      final all = [for (var i = 0; i < 23; i++) 'test/x${i}_test.dart'];
      final ones = {for (final f in all) f: 5};
      for (var i = 1; i <= 4; i++) {
        expect(shard(all, i, 4, weights: ones), shard(all, i, 4));
      }
    });

    test('missing, zero and negative weights count as 1', () {
      final f = ['test/a_test.dart', 'test/b_test.dart', 'test/c_test.dart'];
      final plain = [for (var i = 1; i <= 2; i++) shard(f, i, 2)];
      for (final wt in [
        <String, int>{},
        {'test/a_test.dart': 0, 'test/b_test.dart': -9},
      ]) {
        expect([
          for (var i = 1; i <= 2; i++) shard(f, i, 2, weights: wt),
        ], plain);
      }
    });

    test('with at least as many files as shards no shard is empty, '
        'whatever the weights', () {
      for (var n = 1; n <= 4; n++) {
        for (var c = n; c <= n + 6; c++) {
          final all = [for (var i = 0; i < c; i++) 'test/e${i}_test.dart'];
          final wt = {all.first: 1 << 30}; // one huge file
          for (var i = 1; i <= n; i++) {
            expect(
              shard(all, i, n, weights: wt),
              isNotEmpty,
              reason: 'c=$c n=$n shard $i',
            );
          }
        }
      }
    });

    test('fileWeights: size + K; missing, directory and empty -> 1 + K', () {
      final d = Directory.systemTemp.createTempSync('weights_');
      addTearDown(() => d.deleteSync(recursive: true));
      File(p.join(d.path, 'big_test.dart')).writeAsStringSync('x' * 500);
      File(p.join(d.path, 'empty_test.dart')).writeAsStringSync('');
      Directory(p.join(d.path, 'dir_test.dart')).createSync();
      const k = shardFileOverheadBytes;
      expect(
        fileWeights(d.path, [
          'big_test.dart',
          'empty_test.dart',
          'dir_test.dart',
          'nope_test.dart',
        ]),
        {
          'big_test.dart': 500 + k,
          'empty_test.dart': 1 + k,
          'dir_test.dart': 1 + k,
          'nope_test.dart': 1 + k,
        },
      );
    });

    // Audit cycle 2, N1: the per-file fixed cost K is part of the weight, so
    // many small files and one large file balance by size + K, not by bytes.
    test('K is the documented ~15 KB constant', () {
      expect(shardFileOverheadBytes, 15 * 1024);
    });

    test('N1: one large file vs many small files balance per size + K', () {
      final d = Directory.systemTemp.createTempSync('weights_n1_');
      addTearDown(() => d.deleteSync(recursive: true));
      const kb = 1024;
      final files = <String>['large_test.dart'];
      File(
        p.join(d.path, 'large_test.dart'),
      ).writeAsStringSync('x' * (150 * kb));
      for (var i = 0; i < 12; i++) {
        final name = 'small${i.toString().padLeft(2, '0')}_test.dart';
        File(p.join(d.path, name)).writeAsStringSync('x' * (11 * kb));
        files.add(name);
      }
      int load(List<String> part, Map<String, int> wt) =>
          part.fold(0, (a, f) => a + wt[f]!);
      List<List<String>> split(Map<String, int> wt) => [
        for (var i = 1; i <= 2; i++) shard(files, i, 2, weights: wt),
      ];

      // Bytes only (K = 0): the large file sits ALONE against 12 small ones.
      final bytesOnly = split(fileWeights(d.path, files, overhead: 0));
      final aloneIdx = bytesOnly.indexWhere(
        (s) => s.contains('large_test.dart'),
      );
      expect(bytesOnly[aloneIdx], ['large_test.dart']);

      // size + K: small files cost 26 KB each, the large one 165 KB, so the
      // large file's shard takes 3 smalls and the loads differ by < one small.
      final wt = fileWeights(d.path, files);
      expect(wt['large_test.dart'], 150 * kb + shardFileOverheadBytes);
      expect(wt['small00_test.dart'], 11 * kb + shardFileOverheadBytes);
      final parts = split(wt);
      final big = parts.firstWhere((s) => s.contains('large_test.dart'));
      final other = parts.firstWhere((s) => !s.contains('large_test.dart'));
      expect(big, hasLength(4));
      expect(other, hasLength(9));
      expect(
        (load(big, wt) - load(other, wt)).abs(),
        lessThan(11 * kb + shardFileOverheadBytes),
      );
      expect(
        parts.expand((x) => x).toList()..sort(),
        [...files]..sort(),
        reason: 'still a partition',
      );
    });
  });

  group('CLI', () {
    final bin = p.join(Directory.current.path, 'bin', 'affected_tests.dart');
    ProcessResult cli(List<String> args) =>
        Process.runSync(Platform.resolvedExecutable, [bin, ...args]);

    test('--shards-for prints only the count', () {
      final r = cli(['--shards-for', '81', '--threshold', '80']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect((r.stdout as String).trim(), '2');
      expect(
        (cli(['--shards-for', 'full']).stdout as String).trim(),
        '$fullShards',
      );
      expect(
        (cli(['--shards-for', '0', '--threshold', '80']).stdout as String)
            .trim(),
        '0',
      );
    });

    test('--shards-for without --threshold (or garbage) exits 64', () {
      for (final a in [
        ['--shards-for', '81'],
        ['--shards-for', '81', '--threshold', '0'],
        ['--shards-for', 'x', '--threshold', '80'],
        ['--shards-for', '-3', '--threshold', '80'],
      ]) {
        expect(cli(a).exitCode, 64, reason: a.join(' '));
      }
    });

    test('--shard-list shards a plain list; union == list over i=1..N', () {
      final d = Directory.systemTemp.createTempSync('shard_list_');
      addTearDown(() => d.deleteSync(recursive: true));
      final list = [
        for (var i = 0; i < 37; i++) 'test/features/a$i/x_test.dart',
      ];
      final f = File(p.join(d.path, 'unit.txt'))
        ..writeAsStringSync(list.map((l) => '$l\n').join());
      final got = <String>[];
      for (var i = 1; i <= 4; i++) {
        final out = p.join(d.path, 's$i.txt');
        final r = cli([
          '--shard-list',
          f.path,
          '--shard',
          '$i/4',
          '--out',
          out,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        got.addAll(File(out).readAsLinesSync());
      }
      expect(got.length, list.length);
      expect(got.toSet(), list.toSet());
    });

    test('--shard-list --weights-root spreads heavy files; without it the '
        'split is count-only (audit F3)', () {
      final d = Directory.systemTemp.createTempSync('shard_w_');
      addTearDown(() => d.deleteSync(recursive: true));
      final list = [
        for (var i = 0; i < 20; i++)
          'test/f${i.toString().padLeft(2, '0')}_test.dart',
      ];
      for (final f in list) {
        final heavy = const {0, 4, 8, 12}.contains(list.indexOf(f));
        File(p.join(d.path, f))
          ..createSync(recursive: true)
          ..writeAsStringSync(heavy ? 'x' * 5000 : 'x');
      }
      final lf = File(p.join(d.path, 'u.txt'))
        ..writeAsStringSync(list.map((l) => '$l\n').join());
      List<String> shardOf(int i, {required bool weighted}) {
        final out = p.join(d.path, 'o$i${weighted ? 'w' : ''}.txt');
        final r = cli([
          '--shard-list',
          lf.path,
          '--shard',
          '$i/4',
          '--out',
          out,
          if (weighted) ...['--weights-root', d.path],
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        return File(out).readAsLinesSync();
      }

      final heavyFiles = {
        for (final i in [0, 4, 8, 12]) list[i],
      };
      expect(
        shardOf(1, weighted: false).where(heavyFiles.contains),
        hasLength(4),
        reason: 'control: count-only stacks them on shard 1',
      );
      final got = <String>[];
      for (var i = 1; i <= 4; i++) {
        final s = shardOf(i, weighted: true);
        expect(s.where(heavyFiles.contains), hasLength(1), reason: 'shard $i');
        got.addAll(s);
      }
      expect(got.toList()..sort(), [...list]..sort());
    });

    test('--shard-list rejects a missing --shard / --out / list / range', () {
      final d = Directory.systemTemp.createTempSync('shard_list_');
      addTearDown(() => d.deleteSync(recursive: true));
      final f = File(p.join(d.path, 'u.txt'))..writeAsStringSync('a\n');
      final o = p.join(d.path, 'o.txt');
      for (final a in [
        ['--shard-list', f.path, '--out', o],
        ['--shard-list', f.path, '--shard', '1/4'],
        ['--shard-list', '${f.path}.nope', '--shard', '1/4', '--out', o],
        ['--shard-list', f.path, '--shard', '5/4', '--out', o],
        ['--shard-list', f.path, '--shard', 'x', '--out', o],
      ]) {
        expect(cli(a).exitCode, 64, reason: a.join(' '));
      }
    });

    test('--all --shard i/4: the four unit lists partition the universe', () {
      final repo = FixtureRepo({
        'lib/a.dart': 'int a = 1;\n',
        ...filler(23),
        'test/golden/g_golden_test.dart': 'void main() {}\n',
      });
      addTearDown(repo.dispose);
      List<String> unitOf(String shardSpec) {
        final out = p.join(repo.root, 'o', shardSpec.replaceAll('/', '_'));
        final args = [
          '--all',
          '--repo',
          repo.root,
          '--rules',
          p.join(Directory.current.path, 'rules.yaml'),
          '--out',
          p.join(out, 'selection.json'),
          if (shardSpec != 'all') ...['--shard', shardSpec],
        ];
        final r = cli(args);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        return const LineSplitter().convert(
          File(p.join(out, 'unit.txt')).readAsStringSync(),
        );
      }

      final universe = unitOf('all');
      expect(universe.length, 23, reason: 'golden dir is not a unit file');
      final parts = [for (var i = 1; i <= 4; i++) unitOf('$i/4')];
      expect(parts.expand((x) => x).toList()..sort(), universe..sort());
      expect(parts.expand((x) => x).toSet().length, 23);
    });
  });
}
