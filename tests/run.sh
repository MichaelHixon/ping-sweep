#!/bin/bash
# Runs all ten implementations against every row of tests/cases.tsv and prints a pass count per
# implementation and in total. Exit 0 when every check that ran passed, 1 otherwise.
#
#   bash tests/run.sh [cases-file]
#
# Only argument parsing is exercised:
#   - A fake ping goes first on PATH and answers only for host .1. Eight implementations call ping.
#   - C (its own ICMP socket) and PowerShell (Test-Connection) do not call ping, so they run only
#     rows expecting exit 1 or 2. Every other row is skipped for them.
#   - Every input is built on TEST-NET-1 (192.0.2.0/24), a range reserved for documentation.
#   - On macOS every run also sits inside sandbox-exec with outbound IP denied, so no probe leaves.
#     On other systems a parser regression in C or PowerShell would send probes to 192.0.2.0/24.
# An implementation whose toolchain is missing, or that fails to build, is reported as skipped.

set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cases="${1:-$root/tests/cases.tsv}"
[[ -r $cases ]] || { echo "cannot read $cases" >&2; exit 2; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ping-sweep-tests.XXXXXX")" || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/fake" "$tmp/bin"
cat >"$tmp/fake/ping" <<'EOF'
#!/bin/sh
# fake ping: only host .1 answers
for last; do :; done
case "$last" in *.1) exit 0 ;; *) exit 2 ;; esac
EOF
chmod +x "$tmp/fake/ping"
export PATH="$tmp/fake:$PATH" LC_ALL=C

sandbox=()
if [[ $(uname -s) == Darwin ]] && command -v sandbox-exec >/dev/null; then
  sandbox=(sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))')
fi

pwsh=$(command -v pwsh || command -v pwsh-preview || true)
names=(perl python bash typescript ruby c go rust nim powershell)
cmds=() skip=()
add() { cmds+=("$1"); skip+=("$2"); }   # $2: empty, or why the implementation is skipped
need() { command -v "$1" >/dev/null || { echo "$1 not installed"; return 1; }; }
build() { "$@" >"$tmp/build.log" 2>&1 || { echo "build failed: $(head -1 "$tmp/build.log")"; return 1; }; }

r=$(need perl) && add "perl $root/perl/ping-sweep.pl" "" || add "" "$r"
r=$(need python3) && add "python3 $root/python/ping-sweep.py" "" || add "" "$r"
add "bash $root/bash/ping-sweep.sh" ""
r=$(need bun) && add "bun $root/typescript/ping-sweep.ts" "" || add "" "$r"
r=$(need ruby) && add "ruby $root/ruby/ping-sweep.rb" "" || add "" "$r"
r=$(need cc && build cc -O2 -pthread "$root/c/ping-sweep.c" -o "$tmp/bin/c") && add "$tmp/bin/c" "" || add "" "$r"
r=$(need go && cd "$root/go" && build go build -o "$tmp/bin/go" .) && add "$tmp/bin/go" "" || add "" "$r"
r=$(need rustc && build rustc -O "$root/rust/ping-sweep.rs" -o "$tmp/bin/rust") && add "$tmp/bin/rust" "" || add "" "$r"
r=$(need nim && build nim c --hints:off -d:release --nimcache:"$tmp/nimcache" --out:"$tmp/bin/nim" "$root/nim/ping_sweep.nim") \
  && add "$tmp/bin/nim" "" || add "" "$r"
[[ -n $pwsh ]] && add "$pwsh -NoProfile -File $root/powershell/ping-sweep.ps1" "" || add "" "pwsh not installed"

pass=() fail=() skipped=()
for i in "${!names[@]}"; do pass[i]=0 fail[i]=0 skipped[i]=0; done
rows=0 failures=""

decode() { [[ $1 == '""' ]] && return; printf '%b' "$1"; }

while IFS=$'\t' read -r input want_rc want_err want_out; do
  [[ -z $input || $input == \#* ]] && continue
  rows=$((rows + 1))
  arg=$(decode "$input"; printf x); arg=${arg%x}   # the x keeps $(...) from eating a trailing newline
  [[ $want_err == '*' || $want_err == glob:* ]] || decode "$want_err" >"$tmp/want.err"
  [[ $want_err == '*' || $want_err == glob:* ]] || printf '\n' >>"$tmp/want.err"
  decode "$want_out" >"$tmp/want.out"; [[ $want_out == '""' ]] || printf '\n' >>"$tmp/want.out"
  for i in "${!names[@]}"; do
    # C and PowerShell run only rows expecting exit 1 or 2. If a parser regression accepts one of them,
    # it sweeps 192.0.2.0/24; outside the macOS sandbox those probes would really be sent.
    if [[ -n ${skip[i]} ]] || { [[ $want_rc != 1 && $want_rc != 2 ]] && [[ ${names[i]} == c || ${names[i]} == powershell ]]; }; then
      skipped[i]=$((skipped[i] + 1)); continue
    fi
    # ${a[@]+"${a[@]}"}: bash 3.2 treats an empty array as unset under set -u
    if [[ $input == '<none>' ]]; then
      ${sandbox[@]+"${sandbox[@]}"} ${cmds[i]} >"$tmp/out" 2>"$tmp/err"
    else
      ${sandbox[@]+"${sandbox[@]}"} ${cmds[i]} "$arg" >"$tmp/out" 2>"$tmp/err"
    fi
    rc=$? ok=1
    [[ $rc == "$want_rc" ]] || ok=0
    cmp -s "$tmp/out" "$tmp/want.out" || ok=0
    case $want_err in
      '*') ;;
      glob:*) err=$(cat "$tmp/err"); [[ $err == ${want_err#glob:} ]] || ok=0 ;;
      *) cmp -s "$tmp/err" "$tmp/want.err" || ok=0 ;;
    esac
    if ((ok)); then pass[i]=$((pass[i] + 1)); else
      fail[i]=$((fail[i] + 1))
      failures+="  ${names[i]}: [$input] exit $rc (want $want_rc), stderr: $(head -c 120 "$tmp/err" | tr '\n' '~')"$'\n'
    fi
  done
done <"$cases"

printf '%-11s %6s %6s %8s  %s\n' implementation passed failed skipped note
tp=0 tf=0 ts=0
for i in "${!names[@]}"; do
  note=${skip[i]}
  [[ -z $note && ${skipped[i]} -gt 0 ]] && note="rows that would sweep skipped: does not call ping"
  printf '%-11s %6d %6d %8d  %s\n' "${names[i]}" "${pass[i]}" "${fail[i]}" "${skipped[i]}" "$note"
  tp=$((tp + pass[i])) tf=$((tf + fail[i])) ts=$((ts + skipped[i]))
done
printf '%-11s %6d %6d %8d  %s\n' total "$tp" "$tf" "$ts" "$rows cases x ${#names[@]} implementations"
[[ ${#sandbox[@]} -gt 0 ]] || echo "note: sandbox-exec unavailable; the fake ping is the only probe guard"
[[ -n $failures ]] && printf 'failures:\n%s' "$failures"
((tf == 0 && tp > 0))
