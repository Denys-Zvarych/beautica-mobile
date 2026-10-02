#!/usr/bin/env bash
# End-to-end regression harness for scripts/forbid_raw_network_image.sh
# (Phase 076 A2). Complements the guard's own --self-test: copies the SHIPPED
# script into a throwaway repo tree and runs it as a subprocess, exactly as CI
# runs it.
#
# USAGE: bash scripts/test/test_raw_network_image_guard.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE_SRC="$(dirname "$HERE")/forbid_raw_network_image.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# mk <case> : tree with scripts/<gate>, lib/core/media, lib/f. Prints the root.
mk() {
  local r="$TMP/$1"
  mkdir -p "$r/scripts" "$r/lib/core/media" "$r/lib/f"
  cp "$GATE_SRC" "$r/scripts/forbid_raw_network_image.sh"
  printf '%s' "$r"
}

# check <name> <want_rc> <root> [grep-pattern]
check() {
  local name="$1" want="$2" r="$3" pat="${4:-}" out rc
  out="$(cd "$r" && bash scripts/forbid_raw_network_image.sh 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - exit %d, wanted %d\n' "$name" "$rc" "$want"; return
  fi
  if [ -n "$pat" ] && ! grep -aq -- "$pat" <<< "$out"; then
    FAIL=$((FAIL + 1)); printf '  FAIL  %s - output lacks %s\n' "$name" "$pat"; return
  fi
  PASS=$((PASS + 1)); printf '  PASS  %s\n' "$name"
}

echo "== seeded violations go red =="
r="$(mk img)"; printf 'Widget w() => Image.network(u);\n' > "$r/lib/f/a.dart"
check "Image.network( fails" 1 "$r" "a.dart:1"
r="$(mk net)"; printf 'final p = NetworkImage(u);\n' > "$r/lib/f/a.dart"
check "NetworkImage( fails" 1 "$r" "a.dart:1"
r="$(mk cni)"; printf 'Widget w() => CachedNetworkImage(imageUrl: u);\n' > "$r/lib/f/a.dart"
check "CachedNetworkImage( fails" 1 "$r" "a.dart:1"
r="$(mk wrapped)"; printf 'final p = ResizeImage(NetworkImage(u), width: 4);\n' > "$r/lib/f/a.dart"
check "NetworkImage( wrapped in ResizeImage( in CODE fails" 1 "$r" "a.dart:1"
r="$(mk space)"; printf 'final p = NetworkImage (u);\n' > "$r/lib/f/a.dart"
check "'NetworkImage (' with a space fails" 1 "$r" "a.dart:1"
r="$(mk nested)"; mkdir -p "$r/lib/features/x/y"; printf 'a\nb\nImage.network(u);\n' > "$r/lib/features/x/y/z.dart"
check "violation in a nested dir reports its line" 1 "$r" "z.dart:3"
r="$(mk code_then_comment)"; printf 'final p = NetworkImage(u); // raw\n' > "$r/lib/f/a.dart"
check "violation followed by a trailing comment still fails" 1 "$r" "a.dart:1"
r="$(mk crlf)"; printf 'final p = NetworkImage(u);\r\n' > "$r/lib/f/a.dart"
check "CRLF violation fails" 1 "$r" "a.dart:1"

echo "== L1 bypasses go red =="
r="$(mk a_nl_img)"; printf 'Widget w() => Image.network\n(u);\n' > "$r/lib/f/a.dart"
check "(a) Image.network with ( on the next line fails" 1 "$r" "a.dart:1"
r="$(mk a_nl_net)"; printf 'final p = NetworkImage\n  (u);\n' > "$r/lib/f/a.dart"
check "(a) NetworkImage with ( on the next line fails" 1 "$r" "a.dart:1"
r="$(mk b_inline)"; printf '/* x */ NetworkImage(u);\n' > "$r/lib/f/a.dart"
check "(b) /* x */ NetworkImage(u); on one line fails" 1 "$r" "a.dart:1"
r="$(mk c_str)"; printf "final s = 'http://x'; final p = NetworkImage(u);\n" > "$r/lib/f/a.dart"
check "(c) // inside a string literal does not truncate code" 1 "$r" "a.dart:1"
r="$(mk c_str2)"; printf 'final s = "//"; final p = NetworkImage(u);\n' > "$r/lib/f/a.dart"
check "(c) // inside a double-quoted string does not truncate code" 1 "$r" "a.dart:1"
r="$(mk d_new)"; printf 'final f = NetworkImage.new;\n' > "$r/lib/f/a.dart"
check "(d) NetworkImage.new fails" 1 "$r" "a.dart:1"
r="$(mk e_fade)"; printf 'Widget w() => FadeInImage.network(placeholder: p, image: u);\n' > "$r/lib/f/a.dart"
check "(e) FadeInImage.network( fails" 1 "$r" "a.dart:1"
r="$(mk f_bare)"; printf 'final p = CachedNetworkImageProvider(u);\n' > "$r/lib/f/a.dart"
check "(f) bare CachedNetworkImageProvider( fails" 1 "$r" "a.dart:1"
r="$(mk f_second)"; printf 'final p = ResizeImage(other, CachedNetworkImageProvider(u));\n' > "$r/lib/f/a.dart"
check "(f) CachedNetworkImageProvider( as a non-first ResizeImage arg fails" 1 "$r" "a.dart:1"
r="$(mk after_block)"; printf '/*\nfoo\n*/ NetworkImage(u);\n' > "$r/lib/f/a.dart"
check "code after a block comment closes on the same line fails" 1 "$r" "a.dart:3"
r="$(mk str_body)"; printf "final s = 'NetworkImage(u)';\nfinal t = \"\"\"\nImage.network(u)\n\"\"\";\n" > "$r/lib/f/a.dart"
check "NetworkImage( inside string literals passes" 0 "$r"

echo "== comments go green =="
r="$(mk doc)"; printf '/// wraps ResizeImage(NetworkImage(url), …) here\n' > "$r/lib/f/a.dart"
check "/// doc comment mentioning NetworkImage( passes" 0 "$r"
r="$(mk line)"; printf '// Image.network(u) is banned\n' > "$r/lib/f/a.dart"
check "// comment passes" 0 "$r"
r="$(mk block)"; printf '/*\n * CachedNetworkImage(x)\n */\n' > "$r/lib/f/a.dart"
check "block comment passes" 0 "$r"
r="$(mk block_nostar)"; printf '/*\n NetworkImage(u)\n CachedNetworkImage(x)\n*/\n' > "$r/lib/f/a.dart"
check "block-comment body WITHOUT a leading * passes" 0 "$r"
r="$(mk block_nested)"; printf '/* a /* b */ NetworkImage(u) */\n' > "$r/lib/f/a.dart"
check "nested block comment passes" 0 "$r"
r="$(mk trailing)"; printf 'final a = 1; // was NetworkImage(u)\n' > "$r/lib/f/a.dart"
check "trailing comment mentioning NetworkImage( passes" 0 "$r"

echo "== allowed file / look-alikes / exemptions go green =="
r="$(mk allowed)"; printf 'final a = Image.network(u);\nNetworkImage(u);\n' > "$r/lib/core/media/beautica_image.dart"
check "the allowed file passes" 0 "$r"
r="$(mk sibling)"; printf 'NetworkImage(u);\n' > "$r/lib/core/media/other.dart"
check "a SIBLING of the allowed file still fails" 1 "$r" "other.dart:1"
r="$(mk provider)"; printf 'final p = ResizeImage(CachedNetworkImageProvider(u), width: 4);\n' > "$r/lib/f/a.dart"
check "CachedNetworkImageProvider( inside ResizeImage( passes" 0 "$r"
r="$(mk provider_ml)"; printf 'final p = ResizeImage(\n  CachedNetworkImageProvider(u),\n  width: 4);\n' > "$r/lib/f/a.dart"
check "CachedNetworkImageProvider( as multi-line ResizeImage( arg passes" 0 "$r"
r="$(mk lookalike)"; printf 'MyNetworkImage(u);\nfoo_NetworkImage(u);\n' > "$r/lib/f/a.dart"
check "look-alikes (MyNetworkImage, foo_NetworkImage) do not trip" 0 "$r"
r="$(mk api)"; mkdir -p "$r/lib/api"; printf 'NetworkImage(u);\n' > "$r/lib/api/x.dart"
check "generated lib/api is exempt" 0 "$r"
r="$(mk notdart)"; printf 'NetworkImage(u);\n' > "$r/lib/f/a.txt"
check "non-.dart file ignored" 0 "$r"
r="$(mk nolib)"; rm -rf "$r/lib"
check "missing lib/ passes" 0 "$r"
r="$(mk empty)"
check "an empty tree passes" 0 "$r"

echo
echo "raw-network-image guard harness: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
