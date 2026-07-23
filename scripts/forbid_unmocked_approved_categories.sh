#!/usr/bin/env bash
# Unmocked approvedCategoriesProvider gate (2026-06-24 fixture-footgun safeguard).
#
# THE FOOTGUN THIS GUARDS
# -----------------------
# `ServiceForm` embeds `_CategoryDropdown`, which `ref.watch`es
# `approvedCategoriesProvider` (service_repository.dart, @Riverpod keepAlive).
# That provider sources from `categoryRequestApiProvider → the real
# authenticated Dio` — it does NOT flow through `serviceRepositoryProvider`. So
# a test that mounts `ServiceForm(...)` and overrides ONLY the repo fake leaves
# `approvedCategoriesProvider` hitting the real Dio under `flutter test`. With no
# backend that:
#   (a) leaks a 15s connect-timeout Timer (pending-timer test failures — this
#       bit app_router_test + role_landing_chrome_test), and
#   (b) resolves the provider to an ERROR AsyncValue, so `_CategoryDropdown`
#       paints the category field with `SelectFieldState.error` (the 0xFFB0452F
#       red ring AT REST) — a silently-wrong golden (it bit services_form_golden).
#
# This footgun has bitten THREE fixtures (app_router_test,
# role_landing_chrome_test, services_form_golden_test), each fixed by adding
#   approvedCategoriesProvider.overrideWith((ref) async => const <…>[])
# The behaviour guard for the resting state lives in
# service_form_category_field_resting_state_test.dart; THIS grep gate is the
# structural ratchet that stops the NEXT ServiceForm fixture from re-introducing
# the same omission.
#
# THE RULE
# --------
# Any test / integration_test file that MOUNTS `ServiceForm(` MUST also mention
# `approvedCategoriesProvider` (i.e. override it). The trigger is the constructor
# CALL `ServiceForm(`, not the bare type name — files that merely import or name
# `ServiceForm` in prose/helpers without mounting it are NOT gated (verified
# against the corpus: every current mounting file already complies, zero false
# positives). A deliberate exception (e.g. a test that intentionally exercises
# the un-overridden provider) is unblocked with an
# `// approved-categories-ok: <reason>` comment anywhere in the file.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_unmocked_approved_categories.sh --self-test

set -euo pipefail

# The constructor-mount trigger and the required-override / annotation tokens.
mount_pattern='ServiceForm[(]'
required_token='approvedCategoriesProvider'
annotation='//[[:space:]]*approved-categories-ok:'

# ---------------------------------------------------------------------------
# is_offender <file> → prints the file path if it mounts ServiceForm( without
# the required override and without the unblock annotation.
#
# Whole-file scan: the `ServiceForm(` mount and the `approvedCategoriesProvider`
# override usually live many lines apart (mount in the body, override in a
# `_overrides()`/setUp helper), so per-line proximity is wrong here — file-level
# presence is the correct granularity.
# ---------------------------------------------------------------------------
is_offender() {
  local f="$1"
  grep -Eq "$mount_pattern" "$f" || return 1            # not a mounting file
  grep -Eq "$annotation" "$f" && return 1               # explicitly unblocked
  grep -q "$required_token" "$f" && return 1            # override present
  printf '%s\n' "$f"
}

# ---------------------------------------------------------------------------
# Self-test mode: assert the verdicts on pinned fixture snippets.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # (1) mounts ServiceForm, no override → OFFENDER
  cat > "$tmp/bad.dart" <<'EOF'
void main() {
  testWidgets('x', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [serviceRepositoryProvider.overrideWithValue(fake)],
      child: ServiceForm(onSubmit: (_) async {}),
    ));
  });
}
EOF

  # (2) mounts ServiceForm + has override → OK
  cat > "$tmp/good.dart" <<'EOF'
void main() {
  testWidgets('x', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        serviceRepositoryProvider.overrideWithValue(fake),
        approvedCategoriesProvider.overrideWith((ref) async => const []),
      ],
      child: ServiceForm(onSubmit: (_) async {}),
    ));
  });
}
EOF

  # (3) mounts ServiceForm, no override BUT annotated → OK
  cat > "$tmp/unblocked.dart" <<'EOF'
// approved-categories-ok: this test exercises the un-overridden error path
void main() {
  await t.pumpWidget(ServiceForm(onSubmit: (_) async {}));
}
EOF

  # (4) names ServiceForm in prose/import but never mounts it → OK
  cat > "$tmp/mention.dart" <<'EOF'
// helpers for driving ServiceForm dropdowns
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
Future<void> open(WidgetTester t) async {}
EOF

  flagged=""
  for snip in bad good unblocked mention; do
    out="$(is_offender "$tmp/$snip.dart" || true)"
    [ -n "$out" ] && flagged="$flagged $snip"
  done
  flagged="$(printf '%s' "$flagged" | tr -s ' ' | sed 's/^ //')"

  if [ "$flagged" != "bad" ]; then
    echo "SELF-TEST FAIL: expected exactly 'bad' flagged, got: '$flagged'"
    exit 1
  fi
  echo "SELF-TEST PASS: only the un-overridden ServiceForm mount is flagged;"
  echo "                overridden / annotated / mention-only files are clean."
  exit 0
fi

# All test + integration_test Dart files.
mapfile -t files < <(
  {
    find test -type f -name '*.dart' 2>/dev/null || true
    find integration_test -type f -name '*.dart' 2>/dev/null || true
  } | sort -u
)

[ "${#files[@]}" -eq 0 ] && exit 0

offenders=""
for f in "${files[@]}"; do
  hit="$(is_offender "$f" || true)"
  [ -n "$hit" ] && offenders+="$hit"$'\n'
done
offenders="$(printf '%s' "$offenders" | sed '/^$/d')"

if [ -n "$offenders" ]; then
  echo "ServiceForm mounted without overriding approvedCategoriesProvider:"
  echo "$offenders"
  echo
  echo "ServiceForm embeds _CategoryDropdown, which watches"
  echo "approvedCategoriesProvider — sourced from the REAL Dio, NOT from"
  echo "serviceRepositoryProvider. Without an override it hits the real network"
  echo "under 'flutter test', leaking a 15s connect-timeout Timer and painting"
  echo "the category field's error ring at rest (a silently-wrong golden)."
  echo "Add to the test's overrides list:"
  echo "    approvedCategoriesProvider.overrideWith("
  echo "      (ref) async => const <ServiceCategoryOption>[],"
  echo "    ),"
  echo "If the test DELIBERATELY exercises the un-overridden provider, annotate:"
  echo "    // approved-categories-ok: <why the real provider is intended here>"
  exit 1
fi

exit 0
