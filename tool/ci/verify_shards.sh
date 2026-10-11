#!/usr/bin/env bash
# Count invariant for the sharded `unit` job (phase 402, D2/D3 + "Tests / proof").
# Runs in the base-owned `tests-ran` job: it consumes the shard LISTS that the
# base-owned plan wrote and the JSON event streams the PR-code shards wrote, and
# proves that no test file was dropped, doubled or swapped between them.
#
#   verify_shards.sh <events-dir> <shards-dir> <n>
#
#   <events-dir>   holds unit-<i>-events.json for i in 1..n (run_list.sh output)
#   <shards-dir>   holds unit-all.txt and unit-shard-<i>.txt for i in 1..n
#
# Exit 1 unless ALL of:
#   1. the shard lists partition unit-all.txt: every list non-empty, their union
#      is exactly unit-all.txt, no path appears twice;
#   2. shard i's stream loaded EXACTLY the suites of list i (every listed file
#      has a `suite` event, no unlisted file ran, none ran twice);
#   3. no stream for a shard index outside 1..n exists (a planted
#      unit-9-events.json is not silently ignored);
#   4. every stream has >= 1 non-skipped passing test.
# Since the unsharded `flutter test --exclude-tags golden` runs exactly the
# `--all` unit universe, "the shards ran a partition of that universe" is the
# per-file form of "sum of shard testDone counts == unsharded count". The
# remaining quantity (the absolute count) is held by the min_tests.txt floor via
# tests_ran.sh on the joined streams (the workflow step does that next).
# Prints per-shard and total non-skipped pass counts.
set -euo pipefail
ev="${1:-}"; sh="${2:-}"; n="${3:-}"
[ -d "$ev" ] && [ -d "$sh" ] || { echo "verify_shards RED: events/shards dir missing"; exit 1; }
[[ "$n" =~ ^[1-9][0-9]*$ ]] || { echo "verify_shards RED: shard count '$n' is not a positive number"; exit 1; }
all="$sh/unit-all.txt"
[ -s "$all" ] || { echo "verify_shards RED: $all missing or empty"; exit 1; }

fail=0
red() { echo "verify_shards RED: $*"; fail=1; }

# 3. no stream outside 1..n
shopt -s nullglob
for f in "$ev"/unit-*-events.json; do
  b="${f##*/}"; idx="${b#unit-}"; idx="${idx%-events.json}"
  if ! [[ "$idx" =~ ^[1-9][0-9]*$ ]] || [ "$idx" -gt "$n" ]; then red "unexpected stream $b (shards are 1..$n)"; fi
done

# 1. the lists partition unit-all.txt
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: >"$tmp/joined"
for ((i = 1; i <= n; i++)); do
  l="$sh/unit-shard-$i.txt"
  if [ ! -s "$l" ]; then red "$l missing or empty"; continue; fi
  cat "$l" >>"$tmp/joined"
done
LC_ALL=C sort "$tmp/joined" >"$tmp/joined.s"
LC_ALL=C sort "$all" >"$tmp/all.s"
cmp -s "$tmp/joined.s" "$tmp/all.s" || red "shard lists do not add up to unit-all.txt (a file was dropped, added or doubled): $(wc -l <"$tmp/joined.s") listed in shards vs $(wc -l <"$tmp/all.s") in unit-all.txt"
dups="$(uniq -d <"$tmp/joined.s" | head -3 | tr '\n' ' ')"
[ -z "$dups" ] || red "path(s) in more than one shard: $dups"

# 2 + 4. each stream == its list
total=0
for ((i = 1; i <= n; i++)); do
  s="$ev/unit-$i-events.json"; l="$sh/unit-shard-$i.txt"
  if [ ! -s "$s" ]; then red "events/unit-$i-events.json is missing or empty (shard $i never reported)"; continue; fi
  [ -s "$l" ] || continue
  jq -R -s -r 'split("\n") | map(fromjson? // empty) | map(select(.type == "suite")) | .[].suite.path' <"$s" >"$tmp/suites" 2>/dev/null \
    || { red "unit-$i-events.json is unparseable"; continue; }
  # A suite path is attributed to the LONGEST listed path it equals or ends
  # with (at a "/" boundary), so when one listed path is a suffix of another
  # ("test/a_test.dart" vs "pkg/test/a_test.dart") the choice never depends on
  # awk's hash iteration order (audit Q-L3). Every attributed suite must also
  # carry the SAME prefix (the checkout root; "" for relative paths): a
  # suffix-only match through a different directory is then caught, not
  # silently counted for the shorter listed path.
  res="$(awk 'NR == FNR { if ($0 != "") want[$0] = 1; next }
    { s = $0; if (s == "") next; hit = ""; hl = 0
      for (w in want) {
        lw = length(w)
        if (lw > hl && (s == w || (length(s) > lw && substr(s, length(s) - lw) == "/" w))) { hit = w; hl = lw }
      }
      if (hit == "") extra++
      else { seen[hit]++; pre = substr(s, 1, length(s) - hl); if (!(pre in roots)) { roots[pre] = 1; nroots++ } } }
    END { for (w in want) { if (!(w in seen)) miss++; else if (seen[w] > 1) dup++ }
          printf "%d %d %d %d", miss + 0, extra + 0, dup + 0, nroots + 0 }' "$l" "$tmp/suites")"
  read -r miss extra dup nroots <<<"$res"
  [ "$miss" -eq 0 ] || red "shard $i: $miss listed file(s) never loaded as a suite"
  [ "$extra" -eq 0 ] || red "shard $i: $extra suite(s) ran that are not in its list"
  [ "$dup" -eq 0 ] || red "shard $i: $dup file(s) loaded more than once"
  [ "$nroots" -le 1 ] || red "shard $i: suite paths do not share one checkout root ($nroots different prefixes): a suite was matched to a listed file through a different directory"
  p="$(jq -R -s -r 'split("\n") | map(fromjson? // empty)
        | map(select(.type == "testDone" and .result == "success" and (.skipped // false) == false and (.hidden // false) == false))
        | length' <"$s")"
  case "$p" in '' | *[!0-9]*) red "unit-$i-events.json: unparseable event stream"; continue ;; esac
  [ "$p" -gt 0 ] || red "shard $i: 0 non-skipped tests passed"
  echo "verify_shards: shard $i: $(wc -l <"$l") file(s), $p non-skipped passes"
  total=$((total + p))
done
[ "$fail" -eq 0 ] || exit 1
echo "verify_shards green: $n shard(s), $(wc -l <"$all") file(s) partitioned, $total non-skipped passes in total"
