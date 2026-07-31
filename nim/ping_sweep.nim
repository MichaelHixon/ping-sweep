## ping-sweep (Nim) — concurrent host discovery across a /24.
##
## Fans the system pinger out with `osproc.execProcesses`, which runs external
## commands with bounded parallelism using fork+poll — no root, no manual threads.
## Each child redirects its own output to /dev/null, so the parent never holds 254
## pipes at once (which would blow past the default 256-open-file limit). Same
## contract as every other script in this repo:
##
##     ping-sweep <network>     # 192.168.1.0/24  or  192.168.1
##
## Build (source is ping_sweep.nim — Nim module names can't contain '-'):
##     nim c -d:release --out:ping-sweep ping_sweep.nim

import std/[os, osproc, strutils, algorithm]

const Workers = 64   # bound concurrency (still finishes a /24 in a handful of timeouts)

# "192.168.1.0/24" | "192.168.1.0" | "192.168.1"  ->  "192.168.1"
proc parseBase(arg: string): string =
  let octets = arg.split('/')[0].split('.')
  var ok = octets.len >= 3
  if ok:
    for o in octets[0 .. 2]:
      if o.len notin 1 .. 3 or not o.allCharsInSet(Digits) or o.parseInt notin 0 .. 255:
        ok = false
        break
  if not ok:
    raise newException(ValueError, "invalid network: " & arg)
  octets[0 .. 2].join(".")

# numeric dotted-quad ordering (so .10 sorts after .9, not before).
# Inputs are always validated 4-octet numeric strings here (base is validated,
# `.$i` is an int), so parseInt on each octet is safe by construction.
proc ipLess(a, b: string): int =
  let pa = a.split('.')
  let pb = b.split('.')
  for k in 0 .. 3:
    let c = cmp(pa[k].parseInt, pb[k].parseInt)
    if c != 0: return c
  0

proc main() =
  if paramCount() < 1:
    stderr.writeLine("usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1")
    quit(2)

  var base: string
  try:
    base = parseBase(paramStr(1))
  except ValueError as e:
    stderr.writeLine(e.msg)
    quit(1)

  # macOS `ping -W` is milliseconds; Linux `-W` is seconds.
  let wait = when defined(macosx): "-W 1000" else: "-W 1"

  var hosts: seq[string]
  var cmds: seq[string]
  for i in 1 .. 254:
    let ip = base & "." & $i
    hosts.add(ip)
    # `ip` is a validated dotted-quad (digits and dots only) — safe to place in a
    # shell command; there are no metacharacters it could carry.
    cmds.add("ping -c 1 " & wait & " -- " & ip & " >/dev/null 2>&1")

  var up: seq[string]
  discard execProcesses(
    cmds,
    options = {poEvalCommand, poUsePath},
    n = Workers,
    afterRunEvent = proc(idx: int, p: Process) =
      if p.peekExitCode == 0:
        up.add(hosts[idx]),
  )

  up.sort(ipLess)
  for ip in up:
    echo ip
  let n = up.len
  stderr.writeLine($n & " host" & (if n == 1: "" else: "s") & " up on " & base & ".0/24")

main()
