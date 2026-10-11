#!/usr/bin/env bash
# Collects the per-job JSON event streams for the base-owned `tests-ran` job
# (phase 402 audit S-L1).
#
#   collect_events.sh <download-dir> <events-dir>
#
#   <download-dir>  actions/download-artifact output for `events-*` WITHOUT
#                   merge-multiple: one sub-directory per artifact, named after
#                   it (events-unit-1/, events-tz-tokyo/, ...)
#   <events-dir>    where tests_ran.sh / verify_shards.sh read the streams
#                   (flat: unit-1-events.json, tz-tokyo-events.json, ...)
#
# Why: with `merge-multiple: true` every artifact landed in ONE directory, so a
# compromised unit shard could upload a file named like another job's stream
# (events-unit-1 carrying tz-tokyo-events.json) and overwrite or forge it. Here
# each artifact may carry exactly ONE file name, derived from the artifact's own
# name; anything else is RED (fail closed).
#
#   events-unit-<N>       ->  unit-<N>-events.json   (N: positive integer)
#   events-unit-whole     ->  unit-events.json       (the unsharded fallback)
#   events-tz-kyiv-dst    ->  tz-kyiv-events.json
#   events-tz-tokyo       ->  tz-tokyo-events.json
#   events-tz-honolulu    ->  tz-honolulu-events.json
#   events-golden         ->  golden-events.json
#
# RED: an `events-*` artifact outside this table, a file in an artifact other
# than its one allowed name (any directory, symlink or extra file), an allowed
# file that is a symlink. A MISSING allowed file is not an error here: the
# consumers owe each expected stream and fail closed on its absence.
set -euo pipefail
dl="${1:-}"; out="${2:-}"
[ -n "$dl" ] && [ -n "$out" ] || { echo "usage: collect_events.sh <download-dir> <events-dir>" >&2; exit 2; }
mkdir -p "$out"
[ -d "$dl" ] || { echo "collect_events: no artifacts downloaded ($dl)"; exit 0; }
fail=0
red() { echo "collect_events RED: $*"; fail=1; }
shopt -s nullglob dotglob
for d in "$dl"/*; do
  name="${d##*/}"
  if [ -L "$d" ] || [ ! -d "$d" ]; then red "unexpected entry '$name' (artifacts are directories)"; continue; fi
  case "$name" in
    events-unit-whole) want=unit-events.json ;;
    events-unit-*)
      n="${name#events-unit-}"
      if [[ "$n" =~ ^[1-9][0-9]*$ ]]; then want="unit-$n-events.json"; else red "unknown event artifact '$name'"; continue; fi ;;
    events-tz-kyiv-dst) want=tz-kyiv-events.json ;;
    events-tz-tokyo) want=tz-tokyo-events.json ;;
    events-tz-honolulu) want=tz-honolulu-events.json ;;
    events-golden) want=golden-events.json ;;
    *) red "unknown event artifact '$name'"; continue ;;
  esac
  ok=1
  for f in "$d"/*; do
    b="${f##*/}"
    if [ "$b" != "$want" ]; then red "artifact $name contains '$b' (only $want is accepted from it)"; ok=0; fi
  done
  [ "$ok" -eq 1 ] || continue
  [ -e "$d/$want" ] || continue
  if [ -L "$d/$want" ] || [ ! -f "$d/$want" ]; then red "artifact $name: $want is not a regular file"; continue; fi
  cp "$d/$want" "$out/$want"
done
[ "$fail" -eq 0 ] || exit 1
echo "collect_events: $(find "$out" -maxdepth 1 -name '*-events.json' | wc -l) stream(s) accepted"
