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

import std/[os, osproc, strutils, sequtils]

const Workers = 64   # bound concurrency (still finishes a /24 in a handful of timeouts)

# "192.168.1" | "192.168.1.<0-255>", optionally + "/24"  ->  "192.168.1"
proc parseBase(arg: string): string =
  let parts = arg.split('/', maxsplit = 1)
  let octets = parts[0].split('.')
  # 3 or 4 octets; a fourth is validated but its value ignored
  let ok = octets.len in 3 .. 4 and octets.allIt(
    it.len in 1 .. 3 and it.allCharsInSet(Digits) and it.parseInt <= 255)
  if not ok:
    raise newException(ValueError, "invalid network: " & arg)
  if parts.len == 2 and parts[1] != "24":
    raise newException(ValueError, "invalid network: " & arg & " (only /24 is supported)")
  # rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
  octets[0 .. 2].mapIt($it.parseInt).join(".")

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

  var cmds: seq[string]
  for i in 1 .. 254:
    # base is a validated dotted-quad (digits and dots only) — safe to place in a
    # shell command; there are no metacharacters it could carry.
    cmds.add("ping -c 1 " & wait & " -- " & base & "." & $i & " >/dev/null 2>&1")

  # cmds[idx] probes host idx+1; walking `alive` in order prints hosts sorted.
  # afterRunEvent runs on this thread (execProcesses polls its children), so no race.
  var alive: array[254, bool]
  discard execProcesses(
    cmds,
    options = {poEvalCommand, poUsePath},
    n = Workers,
    afterRunEvent = proc(idx: int, p: Process) =
      if p.peekExitCode == 0:
        alive[idx] = true,
  )

  var n = 0
  for idx, isUp in alive:
    if isUp:
      echo base & "." & $(idx + 1)
      inc n
  stderr.writeLine($n & " host" & (if n == 1: "" else: "s") & " up on " & base & ".0/24")

main()
