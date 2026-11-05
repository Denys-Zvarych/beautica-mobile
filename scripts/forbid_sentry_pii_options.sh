#!/usr/bin/env bash
# Phase 410 (R.3 D10) — crash reporting must never ship a PII switch.
#
# THE RULE
# --------
# In lib/core/diagnostics/crash_reporting.dart (the ONE place options are set;
# `//` comments ignored, multi-line assignments handled):
#   - sendDefaultPii, attachScreenshot, attachViewHierarchy,
#     enableUserInteractionBreadcrumbs, enablePrintBreadcrumbs
#       MUST be assigned, and only the literal `false` (a constant, a
#       ternary, `!true` … fail — the SDK default of the two breadcrumb
#       switches is ON);
#   - replay `sessionSampleRate` / `onErrorSampleRate` MUST be assigned, and
#       only a literal 0 / 0.0 (session replay = a screen recording);
#   - `tracesSampleRate` absent or the literal `null` (0 still enables the
#       tracing integrations — D4 "no tracing").
# Anywhere else under lib/ (Dart):
#   - none of the options above may be assigned at all;
#   - `SentryUser(` with `email:` / `username:` / `ipAddress:`;
#   - `sentry_dio`                    (its adapter wraps/replaces the
#                                      cert-pinning adapter; breadcrumbs come
#                                      from RequestIdInterceptor instead).
# Anywhere under lib/ (any file, comments included): a Sentry ingest host
#   (`ingest.…sentry.io`, e.g. a `defaultValue:` DSN).
# Under android/ (*.xml, build output excluded): any `io.sentry.` meta-data
#   (native options would bypass these Dart-side settings).
# And additionally:
#   - pubspec.yaml must not depend on `sentry_dio` or `sentry_logging`;
#   - config/env/*.json must not carry a DSN (`BEAUTICA_SENTRY_DSN` or an
#     `ingest.*sentry.io` host) — the DSN comes only from CI --dart-define.
# scripts/ is NOT scanned (scripts/perf/measure_startup.sh passes a dummy DSN
# to profile builds on purpose).
#
# CI hard-gate (`.github/workflows/pr-validate.yml`); auto-enrolled in
# scripts/verify_guards.sh.
# Self-test:  ./scripts/forbid_sentry_pii_options.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

CR_REL="lib/core/diagnostics/crash_reporting.dart"

# check_options <file> <rel> <mode>: mode `own` = the crash_reporting.dart
# literal rules; mode `other` = no option may be assigned at all. Also flags
# SentryUser(email:/username:/ipAddress:) and sentry_dio in either mode.
check_options() {
  perl -0777 -e '
    my ($file, $rel, $mode) = @ARGV;
    open(my $fh, "<", $file) or exit 0;
    local $/; my $src = <$fh>; close $fh;
    # Strip `//` comments to end of line (keeps `://` in strings), same length
    # newlines kept so offsets map to the original line numbers.
    $src =~ s{(?<!:)//[^\n]*}{}g;
    sub line_of { my ($s, $pos) = @_; return 1 + (substr($s, 0, $pos) =~ tr/\n//); }
    my @false_opts = qw(sendDefaultPii attachScreenshot attachViewHierarchy
                        enableUserInteractionBreadcrumbs enablePrintBreadcrumbs);
    my @zero_opts  = qw(sessionSampleRate onErrorSampleRate);
    # Value = the token up to the next delimiter; the whole expression must END
    # there (`[;,)]` or end of line), so `= false || kPii` is not a literal.
    my $val = qr/\s*(?:=(?!=)|:)\s*([^\s;,)]+)/;
    my $end = qr/\G\s*(?:[;,)]|\n|\z)/;
    for my $opt (@false_opts, @zero_opts, "tracesSampleRate") {
      my $seen = 0;
      while ($src =~ /\b$opt$val/g) {
        my ($v, $pos) = ($1, $-[0]);
        $seen = 1;
        my $after = pos($src);
        $v .= " <expr>" unless $src =~ /$end/gc;
        pos($src) = $after;
        my $ln = line_of($src, $pos);
        if ($mode ne "own") {
          print "$rel:$ln: $opt <- Sentry option set outside $ENV{CR_REL}\n";
        } elsif (grep { $_ eq $opt } @false_opts) {
          print "$rel:$ln: $opt = $v <- must be the literal false\n" if $v ne "false";
        } elsif (grep { $_ eq $opt } @zero_opts) {
          print "$rel:$ln: $opt = $v <- replay rate must be the literal 0\n" if $v !~ /^0(\.0+)?$/;
        } else {
          print "$rel:$ln: $opt = $v <- tracesSampleRate must be null/absent\n" if $v ne "null";
        }
      }
      if ($mode eq "own" && !$seen && $opt ne "tracesSampleRate") {
        print "$rel:1: $opt <- must be explicitly set (literal false/0)\n";
      }
    }
    while ($src =~ /SentryUser\s*\(((?:[^()]|\([^()]*\))*)\)/g) {
      my ($args, $pos) = ($1, $-[0]);
      if ($args =~ /\b(email|username|ipAddress)\s*:/) {
        print "$rel:" . line_of($src, $pos) . ": SentryUser($1:) <- PII user field\n";
      }
    }
    while ($src =~ /sentry_dio/g) {
      print "$rel:" . line_of($src, $-[0]) . ": sentry_dio <- forbidden package\n";
    }
  ' "$1" "$2" "$3"
}

# scan <root>: prints one "path:line: reason" per violation under <root>.
scan() {
  local r="$1"
  local lib="$r/lib"
  if [ -d "$lib" ]; then
    local own="$r/$CR_REL"
    if [ ! -f "$own" ]; then
      echo "$CR_REL: missing <- the Sentry options file this guard pins"
    fi
    local f rel
    while IFS= read -r -d '' f; do
      rel="${f#"$r/"}"
      if [ "$rel" = "$CR_REL" ]; then
        CR_REL="$CR_REL" check_options "$f" "$rel" own
      else
        CR_REL="$CR_REL" check_options "$f" "$rel" other
      fi
    done < <(find "$lib" -type f -name '*.dart' -print0 | sort -z)

    grep -rnE -e 'ingest\.[a-z0-9.-]*sentry\.io' "$lib" 2>/dev/null |
      sed "s|^$r/||; s|\$| <- Sentry ingest host (DSN) in lib/|" || true
  fi

  if [ -d "$r/android" ]; then
    grep -rnE --include='*.xml' --exclude-dir=build --exclude-dir=.gradle \
      --exclude-dir=.cxx -e 'io\.sentry\.' "$r/android" 2>/dev/null |
      sed "s|^$r/||; s|\$| <- native Sentry option under android/|" || true
  fi

  if [ -f "$r/pubspec.yaml" ]; then
    grep -nE '^[[:space:]]*(sentry_dio|sentry_logging)[[:space:]]*:' "$r/pubspec.yaml" |
      sed 's|^|pubspec.yaml:|; s|$| <- forbidden Sentry package|' || true
  fi

  if [ -d "$r/config/env" ]; then
    grep -rnE -e 'BEAUTICA_SENTRY_DSN' -e 'ingest[.a-z0-9-]*sentry\.io' \
      "$r/config/env" 2>/dev/null |
      sed "s|^$r/||; s|\$| <- DSN in a committed env file|" || true
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  # A compliant crash_reporting.dart: every case starts from it.
  GOOD='  void c(SentryFlutterOptions o) {
    o
      ..sendDefaultPii = false
      ..attachScreenshot = false
      // ignore: experimental_member_use
      ..attachViewHierarchy = false
      ..enableUserInteractionBreadcrumbs = false
      ..enablePrintBreadcrumbs = false
      ..tracesSampleRate = null;
    o.replay
      ..sessionSampleRate = 0
      ..onErrorSampleRate = 0.0;
    Sentry.configureScope((Scope s) => s.setUser(SentryUser(id: id)));
  }'
  # setup <rel> <body>: fresh case tree = GOOD crash_reporting.dart + <rel>.
  setup() {
    rm -rf "${tmp:?}/case"
    mkdir -p "$tmp/case/$(dirname "$CR_REL")"
    printf '%s\n' "$GOOD" > "$tmp/case/$CR_REL"
    if [ -n "$1" ]; then
      mkdir -p "$tmp/case/$(dirname "$1")"
      printf '%s\n' "$2" > "$tmp/case/$1"
    fi
  }
  expect_fail() {
    local name="$1"
    setup "$2" "$3"
    if [ -z "$(scan "$tmp/case")" ]; then
      echo "SELF-TEST FAIL: '$name' was not detected" >&2
      exit 1
    fi
  }
  expect_pass() {
    local name="$1"
    setup "$2" "$3"
    local out
    out="$(scan "$tmp/case")"
    if [ -n "$out" ]; then
      echo "SELF-TEST FAIL: '$name' flagged: $out" >&2
      exit 1
    fi
  }
  # own <name> <sed-expr>: GOOD with one edit must FAIL.
  own() {
    local name="$1" body
    body="$(printf '%s\n' "$GOOD" | sed -E "$2")"
    [ "$body" != "$GOOD" ] || { echo "SELF-TEST BUG: '$name' edit did not apply" >&2; exit 1; }
    expect_fail "$name" "$CR_REL" "$body"
  }
  expect_pass good_baseline '' ''
  # --- crash_reporting.dart: literal rules, one falsifying case each ---
  own sendDefaultPii_true 's/sendDefaultPii = false/sendDefaultPii = true/'
  own sendDefaultPii_const 's/sendDefaultPii = false/sendDefaultPii = kPii/'
  own sendDefaultPii_ternary 's/sendDefaultPii = false/sendDefaultPii = x ? false : true/'
  own sendDefaultPii_or_expr 's/sendDefaultPii = false/sendDefaultPii = false || kPii/'
  own sessionSampleRate_expr 's/sessionSampleRate = 0/sessionSampleRate = 0 + kRate/'
  own sendDefaultPii_multiline 's/sendDefaultPii = false/sendDefaultPii =\n          kPii/'
  own sendDefaultPii_missing '/sendDefaultPii/d'
  own attachScreenshot_true 's/attachScreenshot = false/attachScreenshot=true/'
  own attachViewHierarchy_nonliteral 's/attachViewHierarchy = false/attachViewHierarchy = !false/'
  own userInteractionBreadcrumbs_true 's/enableUserInteractionBreadcrumbs = false/enableUserInteractionBreadcrumbs = true/'
  own userInteractionBreadcrumbs_missing '/enableUserInteractionBreadcrumbs/d'
  own printBreadcrumbs_true 's/enablePrintBreadcrumbs = false/enablePrintBreadcrumbs = kDebugMode/'
  own sessionSampleRate_positive 's/sessionSampleRate = 0/sessionSampleRate = 0.1/'
  own sessionSampleRate_const 's/sessionSampleRate = 0/sessionSampleRate = kRate/'
  own onErrorSampleRate_positive 's/onErrorSampleRate = 0.0/onErrorSampleRate = 1.0/'
  own onErrorSampleRate_missing '/onErrorSampleRate/d'
  own tracesSampleRate_zero 's/tracesSampleRate = null/tracesSampleRate = 0/'
  own tracesSampleRate_positive 's/tracesSampleRate = null/tracesSampleRate = 1.0/'
  own sentryUser_email 's/SentryUser\(id: id\)/SentryUser(id: id, email: e)/'
  own sentryUser_username_multiline 's/SentryUser\(id: id\)/SentryUser(\n      id: id,\n      username: u,\n    )/'
  own sentryUser_ip 's/SentryUser\(id: id\)/SentryUser(ipAddress: ip)/'
  expect_pass traces_absent "$CR_REL" "$(printf '%s\n' "$GOOD" | sed '/tracesSampleRate/d')"
  expect_pass commented_true "$CR_REL" "$GOOD
  // never write sendDefaultPii = true here"
  # --- other lib/ files ---
  expect_fail option_outside_owner lib/a.dart '  o..sendDefaultPii = false;'
  expect_fail replay_outside_owner lib/a.dart '  o.replay.sessionSampleRate = 0.1;'
  expect_fail sentryUser_email_elsewhere lib/a.dart 'final u = SentryUser(id: x, email: y);'
  expect_fail sentry_dio_import lib/a.dart "import 'package:sentry_dio/sentry_dio.dart';"
  expect_fail ingest_default_value lib/a.dart "const d = String.fromEnvironment('X', defaultValue: 'https://k@o1.ingest.de.sentry.io/2');"
  expect_fail ingest_in_comment lib/a.dart '// dsn https://k@o0.ingest.sentry.io/0'
  expect_fail ingest_non_dart lib/a.json '{"dsn": "https://k@o0.ingest.us.sentry.io/1"}'
  expect_pass clean_other lib/a.dart "// never write sendDefaultPii = true or sentry_dio here
final u = SentryUser(id: x);"
  # --- android/ ---
  expect_fail android_meta_data android/app/src/main/AndroidManifest.xml '<meta-data android:name="io.sentry.dsn" android:value="x"/>'
  expect_pass android_build_output_ignored android/app/build/x.xml '<meta-data android:name="io.sentry.dsn"/>'
  expect_pass android_clean android/app/src/main/AndroidManifest.xml '<meta-data android:name="flutterEmbedding" android:value="2"/>'
  # --- pubspec / env ---
  expect_fail sentry_dio_pubspec pubspec.yaml '  sentry_dio: 9.30.1'
  expect_fail sentry_logging_pubspec pubspec.yaml '  sentry_logging: ^9.0.0'
  expect_fail dsn_in_env config/env/prod.json '{"BEAUTICA_SENTRY_DSN": "https://k@o1.ingest.de.sentry.io/1"}'
  expect_pass clean_env config/env/prod.json '{"BEAUTICA_ENV": "prod"}'
  # --- scripts/ is out of scope (perf passes a dummy DSN) ---
  expect_pass scripts_not_scanned scripts/perf/x.sh 'DSN=https://k@o0.ingest.sentry.io/0'
  echo "forbid_sentry_pii_options self-test: OK"
  exit 0
fi

violations="$(scan "$root")"
if [ -n "$violations" ]; then
  echo "FAIL: Sentry PII options / forbidden packages / committed DSN (phase 410 D10):" >&2
  printf '%s\n' "$violations" >&2
  echo "In $CR_REL set sendDefaultPii/attachScreenshot/attachViewHierarchy/" >&2
  echo "enableUserInteractionBreadcrumbs/enablePrintBreadcrumbs = false and replay rates = 0" >&2
  echo "(literals), tracesSampleRate null/absent; no SentryUser PII fields, no ingest host in" >&2
  echo "lib/, no io.sentry.* under android/, no sentry_dio/sentry_logging, DSN only via CI." >&2
  exit 1
fi
echo "forbid_sentry_pii_options: OK"
