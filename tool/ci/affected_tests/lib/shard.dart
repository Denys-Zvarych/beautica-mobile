/// Deterministic split of [files] into [count] shards; returns shard [index]
/// (1-based). Sorted, grouped by the first three path segments, then dealt
/// round-robin with one running counter, so shards are disjoint, their union is
/// the input, and every group is spread across shards.
List<String> shard(List<String> files, int index, int count) {
  if (count < 1 || index < 1 || index > count) {
    throw ArgumentError('shard $index/$count out of range');
  }
  final sorted = [...files]..sort();
  String key(String f) {
    final s = f.split('/');
    return s.take(s.length > 3 ? 3 : s.length - 1).join('/');
  }

  final groups = <String, List<String>>{};
  for (final f in sorted) {
    (groups[key(f)] ??= []).add(f);
  }
  final out = <String>[];
  var i = 0;
  for (final k in groups.keys.toList()..sort()) {
    for (final f in groups[k]!) {
      if (i % count == index - 1) out.add(f);
      i++;
    }
  }
  return out;
}

/// Parses `i/N`.
({int index, int count}) parseShard(String spec) {
  final m = RegExp(r'^(\d+)/(\d+)$').firstMatch(spec);
  if (m == null) throw FormatException('--shard expects i/N, got "$spec"');
  return (index: int.parse(m[1]!), count: int.parse(m[2]!));
}
