import 'dart:io';

/// Deterministic split of [files] into [count] shards; returns shard [index]
/// (1-based), sorted by path.
///
/// Longest-processing-time-first greedy (phase 402 audit F3): files are taken
/// heaviest first (ties: path in code-unit order) and each goes to the shard
/// with the smallest running total (ties: the lowest shard number). Shards are
/// therefore disjoint, their union is the input, and the same input gives the
/// same split in any input order. [weights] maps a path to its cost proxy
/// (see [fileWeights]); a missing path or a non-positive weight counts as 1,
/// so without weights every file weighs 1 and the split is the count-balanced
/// round-robin over the sorted list (sizes differ by at most 1).
///
/// With `files.length >= count` no shard is empty: every earlier file made its
/// shard's total positive, so each of the first [count] files lands on a
/// different, still-empty shard.
List<String> shard(
  List<String> files,
  int index,
  int count, {
  Map<String, int>? weights,
}) {
  if (count < 1 || index < 1 || index > count) {
    throw ArgumentError('shard $index/$count out of range');
  }
  int weight(String f) {
    final w = weights?[f] ?? 1;
    return w < 1 ? 1 : w;
  }

  final order = [...files]
    ..sort((a, b) {
      final byWeight = weight(b).compareTo(weight(a));
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  final load = List<int>.filled(count, 0);
  final mine = <String>[];
  for (final f in order) {
    var best = 0;
    for (var s = 1; s < count; s++) {
      if (load[s] < load[best]) best = s;
    }
    load[best] += weight(f);
    if (best == index - 1) mine.add(f);
  }
  return mine..sort();
}

/// Fixed per-file cost, in bytes-equivalents, added to every file's size
/// (phase 402 audit cycle 2, N1).
///
/// Every test file pays a cost independent of its size: the compile/load of its
/// suite and the spawn of its isolate. Bytes alone under-weigh small files, so
/// shards of many small files finished earlier than a shard holding one large
/// file. The median test file in this repo is ~11 KB; 15 KB makes the fixed
/// cost roughly the same order as the median file's size-driven cost. This is a
/// first estimate, NOT a measurement: recalibrate K from the per-shard wall
/// times of the first real CI run (phase doc, "Audit-fix cycle 2").
const shardFileOverheadBytes = 15 * 1024;

/// Cost proxy for [paths] (repo-relative): `size + overhead`, where size is the
/// file size in bytes under [root] (1 for anything that is not a readable
/// regular file) and [overhead] is the per-file fixed cost
/// ([shardFileOverheadBytes]). No per-file timing is recorded in CI yet; bytes
/// track the run cost of a test file, the overhead its compile/spawn cost, and
/// both are free to compute. Computed in the base-owned `plan` job, so a PR can
/// only skew the balance, never the partition (verify_shards.sh proves that).
Map<String, int> fileWeights(
  String root,
  Iterable<String> paths, {
  int overhead = shardFileOverheadBytes,
}) {
  final out = <String, int>{};
  for (final path in paths) {
    var size = 1;
    try {
      final st = FileStat.statSync('$root/$path');
      if (st.type == FileSystemEntityType.file && st.size > 0) size = st.size;
    } on FileSystemException {
      // unreadable: size 1
    }
    out[path] = size + overhead;
  }
  return out;
}

/// Parses `i/N`.
({int index, int count}) parseShard(String spec) {
  final m = RegExp(r'^(\d+)/(\d+)$').firstMatch(spec);
  if (m == null) throw FormatException('--shard expects i/N, got "$spec"');
  return (index: int.parse(m[1]!), count: int.parse(m[2]!));
}

/// Shard count of every FULL run (`--all --shard i/4`, phase 402 D3).
const fullShards = 4;

/// Upper bound on selective shards (phase 402 D3a).
const maxShards = 4;

/// Number of `unit` shards for a selective list of [count] files (phase 402
/// D3a): one shard up to [threshold] files, then `ceil(count / threshold)`,
/// capped at [maxShards]. 0 files -> 0 shards (nothing to run).
///
/// [threshold] is the single `UNIT_WARN_THRESHOLD` of resolve_selection.sh
/// (phase 400 D9); it is a REQUIRED argument so this package never carries a
/// second literal of it.
int shardsFor(int count, {required int threshold}) {
  if (threshold < 1) throw ArgumentError('threshold must be >= 1: $threshold');
  if (count < 0) throw ArgumentError('count must be >= 0: $count');
  if (count == 0) return 0;
  final n = (count + threshold - 1) ~/ threshold;
  return n > maxShards ? maxShards : n;
}
