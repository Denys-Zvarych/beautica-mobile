import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The selector maps a golden PNG to the `*_test.dart` files DIRECTLY beside its
/// `goldens/` folder (lib/assets.dart `goldenOwners`). A golden loaded from any
/// other directory would be under-selected silently, so the convention is
/// enforced here.

final _call = RegExp(r'matchesGoldenFile\(\s*(?:(["\x27])((?:(?!\1).)*)\1)?');

/// Violations in [files] (repo-relative posix path -> source). [goldenDirs] are
/// the repo-relative posix paths of every `goldens` directory.
List<String> goldenConventionViolations(
  Map<String, String> files,
  Set<String> goldenDirs,
) {
  final out = <String>[];
  for (final e in files.entries) {
    if (!e.key.endsWith('_test.dart')) continue;
    final beside = p.posix.join(p.posix.dirname(e.key), 'goldens');
    for (final m in _call.allMatches(e.value)) {
      final lit = m.group(2);
      if (lit == null) {
        if (!goldenDirs.contains(beside)) {
          out.add('${e.key}: non-literal golden path, no goldens/ beside it');
        }
        continue;
      }
      if (lit.startsWith('..') ||
          lit.startsWith('/') ||
          lit.contains('/../') ||
          lit.startsWith(RegExp(r'[A-Za-z]:'))) {
        out.add('${e.key}: golden path escapes its directory: $lit');
      } else if (lit.contains('goldens/') && !lit.startsWith('goldens/')) {
        out.add('${e.key}: golden in a goldens/ dir not beside it: $lit');
      } else if (!goldenDirs.contains(beside)) {
        out.add('${e.key}: no goldens/ dir beside the test: $lit');
      }
    }
  }
  return out;
}

Directory _repoRoot() {
  var d = Directory.current.absolute;
  while (true) {
    final f = File(p.join(d.path, 'pubspec.yaml'));
    if (f.existsSync() &&
        RegExp(
          r'^name:\s*beautica_mobile\s*$',
          multiLine: true,
        ).hasMatch(f.readAsStringSync())) {
      return d;
    }
    final parent = d.parent;
    if (parent.path == d.path) {
      throw StateError('root');
    }
    d = parent;
  }
}

void main() {
  group('synthetic tree', () {
    const dirs = {'test/a/goldens'};
    List<String> run(String src, {String path = 'test/a/x_test.dart'}) =>
        goldenConventionViolations({path: src}, dirs);

    test('beside literal is clean', () {
      expect(run("matchesGoldenFile('goldens/x.png')"), isEmpty);
    });
    test('parent-relative literal fails', () {
      expect(run("matchesGoldenFile('../goldens/x.png')"), hasLength(1));
    });
    test('absolute literal fails', () {
      expect(run("matchesGoldenFile('/tmp/x.png')"), hasLength(1));
    });
    test('foreign goldens dir fails', () {
      expect(run("matchesGoldenFile('sub/goldens/x.png')"), hasLength(1));
    });
    test('literal with no goldens dir beside fails', () {
      expect(
        run("matchesGoldenFile('goldens/x.png')", path: 'test/b/y_test.dart'),
        hasLength(1),
      );
    });
    test('non-literal needs goldens beside', () {
      expect(run('matchesGoldenFile(name)'), isEmpty);
      expect(
        run('matchesGoldenFile(name)', path: 'test/b/y_test.dart'),
        hasLength(1),
      );
    });
    test('double-quoted escape fails', () {
      expect(run('matchesGoldenFile("../x.png")'), hasLength(1));
    });
  });

  test('real repo follows the same-directory golden convention', () {
    final root = _repoRoot();
    final files = <String, String>{};
    final dirs = <String>{};
    for (final e in Directory(
      p.join(root.path, 'test'),
    ).listSync(recursive: true, followLinks: false)) {
      final rel = p.posix.joinAll(p.split(p.relative(e.path, from: root.path)));
      if (e is Directory && p.basename(e.path) == 'goldens') dirs.add(rel);
      if (e is File && rel.endsWith('_test.dart')) {
        files[rel] = String.fromCharCodes(e.readAsBytesSync());
      }
    }
    expect(dirs, isNotEmpty);
    expect(goldenConventionViolations(files, dirs), isEmpty);
  });
}
