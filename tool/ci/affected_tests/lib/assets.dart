import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Read [f] as text, tolerating malformed UTF-8 (a bad byte must not crash the
/// selector; it is replaced, never dropped).
String readTextSync(File f) =>
    utf8.decode(f.readAsBytesSync(), allowMalformed: true);

/// The golden test files that own the committed image [png]: every `*_test.dart`
/// DIRECTLY in the directory that holds the `goldens/` folder (the alchemist
/// layout). No name matching: a golden image selects all its siblings, so a
/// decoy literal can never steer a change away from the real owner. Empty when
/// the layout does not match -> caller must go FULL.
List<String> goldenOwners(String png, Iterable<String> tests) {
  final dir = p.posix.dirname(png);
  if (p.posix.basename(dir) != 'goldens') return const [];
  final owner = p.posix.dirname(dir);
  return [
    for (final t in tests)
      if (p.posix.dirname(t) == owner) t,
  ];
}

/// What changed in one ARB file between BASE and HEAD, or null = cannot tell
/// (caller goes FULL).
///
/// [keys] are message ids (the `@key` metadata folds into `key`); [chunks] are
/// the placeholder-free fragments of the old and new values (tests find widgets
/// by rendered text, not only by key).
({Set<String> keys, Set<String> chunks})? arbDelta(
  String? baseText,
  String? headText,
) {
  Map<String, Object?>? parse(String? t) {
    if (t == null) return const {};
    try {
      final v = jsonDecode(t);
      return v is Map<String, Object?> ? v : null;
    } on FormatException {
      return null;
    }
  }

  final base = parse(baseText), head = parse(headText);
  if (base == null || head == null) return null;
  final keys = <String>{}, chunks = <String>{};
  for (final k in {...base.keys, ...head.keys}) {
    if (jsonEncode(base[k]) == jsonEncode(head[k])) continue;
    if (k.startsWith('@@')) return null; // locale / global metadata
    keys.add(k.startsWith('@') ? k.substring(1) : k);
    for (final v in [base[k], head[k]]) {
      if (v is! String) continue;
      for (final raw in v.split(RegExp(r'[{}]'))) {
        final c = raw.trim();
        if (c.isEmpty) continue;
        if (c.length >= 4) {
          chunks.add(c);
        } else {
          // too short to substring-scan safely: match it as a whole literal
          chunks
            ..add("'$c'")
            ..add('"$c"');
        }
      }
    }
  }
  return (keys: keys, chunks: chunks);
}

final _ident = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

/// Identifier tokens of a source text.
Set<String> identifiers(String text) => {
  for (final m in _ident.allMatches(text)) m.group(0)!,
};
