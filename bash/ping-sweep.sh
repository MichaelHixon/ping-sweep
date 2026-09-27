#!/usr/bin/env bash
# ping-sweep (Bash) — concurrent host discovery across a /24.
#
# Pure shell: backgrounds one `ping` per host and waits. No root, no deps.
# Same contract as every other script in this repo:
#     ping-sweep.sh <network>     # 192.168.1.0/24  or  192.168.1
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: ping-sweep.sh <network>   e.g. 192.168.1.0/24 or 192.168.1" >&2
  exit 2
fi

# one regex over the whole argument (`read` would stop at an embedded newline):
# three octets, an optional fourth (validated, value ignored), an optional /suffix
# BASH_REMATCH: [1..3] octets · [5] fourth octet · [6] "/suffix"
if [[ ! "$1" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(\.([0-9]{1,3}))?(/.*)?$ ]] ||
   (( 10#${BASH_REMATCH[1]} > 255 || 10#${BASH_REMATCH[2]} > 255 || 10#${BASH_REMATCH[3]} > 255 ||
      10#${BASH_REMATCH[5]:-0} > 255 )); then
  echo "invalid network: $1" >&2
  exit 1
fi
if [[ -n ${BASH_REMATCH[6]} && ${BASH_REMATCH[6]} != /24 ]]; then
  echo "invalid network: $1 (only /24 is supported)" >&2
  exit 1
fi
# rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
base="$((10#${BASH_REMATCH[1]})).$((10#${BASH_REMATCH[2]})).$((10#${BASH_REMATCH[3]}))"

# macOS `ping -W` is milliseconds; Linux `-W` is seconds.
if [[ "$(uname)" == "Darwin" ]]; then wait_flag=(-W 1000); else wait_flag=(-W 1); fi

pids=()
for i in {1..254}; do
  ping -c 1 "${wait_flag[@]}" -- "$base.$i" >/dev/null 2>&1 &
  pids[i]=$!
done

# reap each job in host order: its exit status says up/down, and the output comes out sorted
count=0
for i in {1..254}; do
  if wait "${pids[i]}"; then
    echo "$base.$i"
    count=$((count + 1))
  fi
done
s=s; [[ "$count" -eq 1 ]] && s=
echo "$count host$s up on $base.0/24" >&2
