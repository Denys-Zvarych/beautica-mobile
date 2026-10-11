import 'dart:io';

import 'package:affected_tests/affected_tests.dart';
import 'package:path/path.dart' as p;

/// The real rules.yaml (the rules under test are the shipped ones).
final Rules rules = Rules.fromFile(
  p.join(Directory.current.path, 'rules.yaml'),
);

/// A throwaway mini-repo. [files] maps repo-relative paths to contents.
final class FixtureRepo {
  FixtureRepo(Map<String, String> files)
    : root = Directory.systemTemp.createTempSync('sel_fx_').path {
    for (final e in files.entries) {
      final f = File(p.join(root, e.key))..createSync(recursive: true);
      f.writeAsStringSync(e.value);
    }
  }

  final String root;

  void dispose() => Directory(root).deleteSync(recursive: true);

  Selection run(String changes, {FixtureRepo? base}) => select_(
    root: root,
    changes: parseChanges(changes),
    rules: rules,
    baseRoot: base?.root,
  );
}

Selection select_({
  required String root,
  required List<Change> changes,
  required Rules rules,
  String? baseRoot,
}) => select(root: root, changes: changes, rules: rules, baseRoot: baseRoot);

/// `n` mutually-unrelated unit tests so selections stay under the 60% fallback.
Map<String, String> filler(int n) => {
  for (var i = 0; i < n; i++) 'test/filler/f${i}_test.dart': 'void main() {}\n',
};

String pkg(String path) => "import 'package:beautica_mobile/$path';\n";
