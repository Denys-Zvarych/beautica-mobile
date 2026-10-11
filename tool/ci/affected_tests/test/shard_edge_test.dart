import 'dart:io';
import 'dart:math';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Phase 402 QA: edges of [shard] / [parseShard] / [shardsFor] that
/// shard_test.dart does not pin (garbage specs, empty and tiny lists, input
/// order, code-unit sort order, and the invariant that ties the shard COUNT to
/// the shard CONTENT: verify_shards.sh turns an empty shard into RED).
void main() {
  group('parseShard + shard() reject out-of-range specs', () {
    test('syntactically bad specs throw FormatException', () {
      for (final s in [
        '',
        'x',
        '1',
        '1/',
        '/4',
        '-1/4',
        '1/-4',
        '1/4/',
        '+1/4',
        ' 1/4',
        '1/4 ',
        '1.0/4',
      ]) {
        expect(() => parseShard(s), throwsFormatException, reason: '"$s"');
      }
    });

    test('well-formed but out-of-range specs parse, then shard() refuses', () {
      for (final s in ['0/4', '5/4', '1/0', '0/0']) {
        final r = parseShard(s);
        expect(
          () => shard(['test/a_test.dart'], r.index, r.count),
          throwsArgumentError,
          reason: s,
        );
      }
    });

    test('a valid spec round-trips', () {
      expect(parseShard('3/4'), (index: 3, count: 4));
    });
  });

  group('shard() edges', () {
    test('empty input: every shard is empty, nothing throws', () {
      for (var i = 1; i <= 4; i++) {
        expect(shard(const [], i, 4), isEmpty);
      }
    });

    test(
      'fewer files than shards: first shards get one, the rest are empty',
      () {
        final f = ['test/c_test.dart', 'test/a_test.dart', 'test/b_test.dart'];
        expect(shard(f, 1, 4), ['test/a_test.dart']);
        expect(shard(f, 2, 4), ['test/b_test.dart']);
        expect(shard(f, 3, 4), ['test/c_test.dart']);
        expect(shard(f, 4, 4), isEmpty);
      },
    );

    test('1/1 is the whole list, sorted', () {
      expect(shard(['test/b_test.dart', 'test/a_test.dart'], 1, 1), [
        'test/a_test.dart',
        'test/b_test.dart',
      ]);
    });

    test('does not mutate the caller\'s list', () {
      final f = ['test/b_test.dart', 'test/a_test.dart'];
      shard(f, 1, 2);
      expect(f, ['test/b_test.dart', 'test/a_test.dart']);
    });

    test('any input permutation yields byte-identical shards', () {
      final base = [
        for (var d = 0; d < 9; d++)
          for (var i = 0; i < 3 + d; i++)
            'test/features/f$d/s$i/x${d}_${i}_test.dart',
        for (var i = 0; i < 12; i++) 'test/core/c${i}_test.dart',
        'test/z_test.dart',
        'test/Z_test.dart',
      ];
      final want = [for (var i = 1; i <= 4; i++) shard(base, i, 4)];
      for (var seed = 0; seed < 5; seed++) {
        final shuffled = [...base]..shuffle(Random(seed));
        for (var i = 1; i <= 4; i++) {
          expect(
            shard(shuffled, i, 4),
            want[i - 1],
            reason: 'seed $seed shard $i',
          );
        }
      }
    });

    test('order is by code unit, never locale (pinned split)', () {
      // 'Z' (0x5A) < '_' (0x5F) < 'a' (0x61). A locale-aware collation would
      // interleave these; the pinned result would then move.
      final f = [
        'test/a_test.dart',
        'test/Z_test.dart',
        'test/_x_test.dart',
        'test/B_test.dart',
      ];
      expect(shard(f, 1, 2), ['test/B_test.dart', 'test/_x_test.dart']);
      expect(shard(f, 2, 2), ['test/Z_test.dart', 'test/a_test.dart']);
    });

    test('one- and two-segment paths do not crash the group key', () {
      final f = ['a_test.dart', 'test/b_test.dart', 'test/x/c_test.dart'];
      final all = [for (var i = 1; i <= 2; i++) ...shard(f, i, 2)]..sort();
      expect(all, [...f]..sort());
    });

    test('a path listed twice is kept twice (partition of the multiset)', () {
      final f = ['test/a_test.dart', 'test/a_test.dart'];
      expect([...shard(f, 1, 2), ...shard(f, 2, 2)], f);
    });
  });

  group('shardsFor is consistent with shard() content', () {
    test(
      'never more shards than files, never an empty shard, none above threshold',
      () {
        for (final t in [1, 7, 80]) {
          for (var c = 1; c <= 5 * t && c <= 450; c++) {
            final n = shardsFor(c, threshold: t);
            final files = [
              for (var i = 0; i < c; i++) 'test/g${i % 5}/f${i}_test.dart',
            ];
            expect(n, inInclusiveRange(1, maxShards), reason: 'c=$c t=$t');
            for (var i = 1; i <= n; i++) {
              final s = shard(files, i, n);
              expect(
                s,
                isNotEmpty,
                reason: 'shard $i/$n of c=$c t=$t is empty',
              );
              if (c <= maxShards * t) {
                expect(
                  s.length,
                  lessThanOrEqualTo(t),
                  reason: 'shard $i/$n of c=$c t=$t over threshold',
                );
              }
            }
          }
        }
      },
    );

    test('is monotonic in count', () {
      var prev = 0;
      for (var c = 0; c <= 500; c++) {
        final n = shardsFor(c, threshold: 80);
        expect(n, greaterThanOrEqualTo(prev), reason: 'c=$c');
        prev = n;
      }
    });

    test(
      'threshold 1 and huge counts stay capped; int-size counts do not overflow',
      () {
        expect(shardsFor(1, threshold: 1), 1);
        expect(shardsFor(2, threshold: 1), 2);
        expect(shardsFor(5, threshold: 1), maxShards);
        expect(shardsFor(1 << 40, threshold: 80), maxShards);
      },
    );
  });

  group('CLI edges', () {
    final bin = p.join(Directory.current.path, 'bin', 'affected_tests.dart');
    ProcessResult cli(List<String> args) =>
        Process.runSync(Platform.resolvedExecutable, [bin, ...args]);

    test(
      '--shards-for stdout is exactly "<n>\\n" (shard_units.sh parses it)',
      () {
        final r = cli(['--shards-for', '161', '--threshold', '80']);
        expect(r.stdout, '3\n');
      },
    );

    test('--shards-for rejects non-integers and negative thresholds', () {
      for (final a in [
        ['--shards-for', '1.5', '--threshold', '80'],
        ['--shards-for', '81', '--threshold', '-80'],
        ['--shards-for', '81', '--threshold', 'x'],
        ['--shards-for', '', '--threshold', '80'],
      ]) {
        expect(cli(a).exitCode, 64, reason: a.join(' '));
      }
    });

    test(
      '--shard-list drops blank lines and CRLF; an empty list gives empty shards',
      () {
        final d = Directory.systemTemp.createTempSync('shard_edge_');
        addTearDown(() => d.deleteSync(recursive: true));
        final f = File(p.join(d.path, 'u.txt'))
          ..writeAsStringSync('test/b_test.dart\r\n\r\n\ntest/a_test.dart\r\n');
        final o = p.join(d.path, 'o.txt');
        expect(
          cli(['--shard-list', f.path, '--shard', '1/1', '--out', o]).exitCode,
          0,
        );
        expect(
          File(o).readAsStringSync(),
          'test/a_test.dart\ntest/b_test.dart\n',
        );

        final e = File(p.join(d.path, 'e.txt'))..writeAsStringSync('');
        expect(
          cli(['--shard-list', e.path, '--shard', '2/4', '--out', o]).exitCode,
          0,
        );
        expect(File(o).readAsStringSync(), '');
      },
    );
  });
}
