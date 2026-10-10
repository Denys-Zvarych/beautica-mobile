#!/usr/bin/env bash
# Runs ONE list of selected test files in ONE `flutter test` invocation
# (phase 400 D2). Shared by every selective test step in pr-validate.yml
# (unit, goldens, DST rail, Tokyo + Honolulu sweeps).
#
#   run_list.sh <list.txt> <name> [extra flutter test args...]
#
#   list.txt  one repo-relative test path per line (from the selector)
#   name      event-stream basename: writes $RUN_LIST_OUT_DIR/<name>.json
#             (default dir build/ci)
#
# Exit non-zero when:
#   - the list is missing or EMPTY (an empty argument list would make
#     `flutter test` run the WHOLE suite: never silently widen),
#   - any line is not a plain `test/…_test.dart` / `integration_test/…_test.dart`
#     path (no `..`, no dot-dir/dot-file segment: scratch such as a leaked
#     self-test fixture dir is never run), or names a file that does not exist
#     (a stale path never passes),
#   - `flutter test` exits non-zero, or tool/ci/report_failures.sh finds a
#     failing test / truncated stream in the JSON, 0 non-skipped passes, or a
#     listed file with no suite event (the step fails on either).
# FLUTTER (env) overrides the flutter binary (self-test hook).
set -euo pipefail
list="${1:-}"; name="${2:-}"
if [ "$#" -lt 2 ]; then
  echo "usage: run_list.sh <list.txt> <name> [flutter test args...]" >&2; exit 2
fi
shift 2
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flutter_bin="${FLUTTER:-flutter}"
out_dir="${RUN_LIST_OUT_DIR:-build/ci}"

[[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "run_list: bad name '$name'" >&2; exit 2; }
[ -f "$list" ] || { echo "run_list: list '$list' not found" >&2; exit 2; }

files=()
bad=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  if ! [[ "$line" =~ ^(test|integration_test)/[A-Za-z0-9_./-]+_test\.dart$ ]] || [[ "$line" == *..* ]] || [[ "$line" == */.* ]]; then
    echo "run_list: rejected path (not a plain test path): $(printf '%s' "$line" | tr -c 'A-Za-z0-9._/-' '?')" >&2
    bad=1; continue
  fi
  if [ ! -f "$line" ]; then
    echo "run_list: selected test file does not exist: $line" >&2
    bad=1; continue
  fi
  files+=("$line")
done <"$list"
[ "$bad" -eq 0 ] || { echo "run_list RED: invalid entries in $list" >&2; exit 2; }
[ "${#files[@]}" -gt 0 ] || { echo "run_list RED: $list is empty (refusing to run the whole suite)" >&2; exit 2; }

mkdir -p "$out_dir"
events="$out_dir/$name.json"
rm -f "$events"
echo "run_list: ${#files[@]} file(s) from $list -> $events"

frc=0
"$flutter_bin" test --reporter=expanded --file-reporter="json:$events" "$@" "${files[@]}" || frc=$?
rrc=0
bash "$here/report_failures.sh" "$events" "$list" || rrc=$?
if [ "$frc" -ne 0 ] || [ "$rrc" -ne 0 ]; then
  echo "run_list RED: flutter test exit=$frc, report_failures exit=$rrc"
  exit $(( frc > rrc ? frc : rrc ))
fi
echo "run_list green: $name"
