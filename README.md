# ping-sweep

**One tool, ten languages.** A host-discovery sweep across a `/24`, implemented the idiomatic way in ten languages — a study in how each one tackles the same problem: parse a network, fan out 254 probes concurrently, collect the hosts that answer.

Revived from a 2018 one-file Perl script into the polyglot collection it was always meant to be.

## The shared contract

Every implementation honors the same interface and behavior:

```
ping-sweep <network>
```

- `<network>` accepts `192.168.1.0/24`, `192.168.1.0`, or just `192.168.1` — the first three octets are what matter.
- Sweeps host octets `.1` through `.254`, **concurrently**.
- Prints each live host as a full IP, one per line, to **stdout** (sorted).
- Prints a one-line summary (`N hosts up on …`) to **stderr**.
- Each of the first three octets is validated as a number in `0–255`; anything else → `invalid network`, exit code `1`.
- Octets are decimal: a leading zero is dropped (`10.010.1` sweeps `10.10.1.0/24`), never passed through for `ping` to read as octal (`010` → 8).
- No argument → usage message, exit code `2`.

Keeping the contract identical is the point: the interesting differences are in *how* each language gets there, not *what* it does. All ten agree on the same target — verified on macOS against loopback, where only `127.0.0.1` answers. (On Linux the whole `127.0.0.0/8` is loopback and every address replies, so a loopback sweep there reports 254 — compare them on a real network instead.)

Note: on a **live** network, single-probe (`-c 1`) sweeps are inherently non-deterministic — devices sleep and wake between probes, so two implementations may disagree by a host or two from run to run. That jitter is the network, not the code; only the loopback comparison is fully deterministic.

## Implementations

| Language | Dir | Probe method | Concurrency model | Root | Status |
|----------|-----|--------------|-------------------|------|--------|
| Perl | [`perl/`](perl/) | system `ping` | `fork()` per host | no | ✅ |
| Python | [`python/`](python/) | system `ping` | `ThreadPoolExecutor` | no | ✅ |
| Bash | [`bash/`](bash/) | system `ping` | background jobs + `wait` | no | ✅ |
| C | [`c/`](c/) | **unprivileged ICMP** (`SOCK_DGRAM`, id-matched) | pthreads | no | ✅ |
| Go | [`go/`](go/) | system `ping` | goroutines + `WaitGroup` | no | ✅ |
| Rust | [`rust/`](rust/) | system `ping` | threads + `mpsc` | no | ✅ |
| TypeScript | [`typescript/`](typescript/) | system `ping` (bun) | `Promise.all` | no | ✅ |
| PowerShell | [`powershell/`](powershell/) | `Test-Connection` | `ForEach-Object -Parallel` | no | ✅ |
| Ruby | [`ruby/`](ruby/) | system `ping` | thread per host (`Thread.new`) | no | ✅ |
| Nim | [`nim/`](nim/) | system `ping` | `execProcesses` (bounded pool of 64) | no | ✅ |

**The C version is the odd one out, on purpose.** It opens an **unprivileged ICMP datagram socket** (`SOCK_DGRAM` + `IPPROTO_ICMP`) and speaks ICMP directly — build the echo request, checksum it, `connect()` to the target so replies are source-filtered, send, and match the reply by a per-host ICMP **id** (which keeps it correct even when many probes share one responder, as on loopback). The other nine lean on an external prober and instead show off their language's concurrency model. That contrast — *be the pinger* vs *orchestrate the pinger* — is the educational payload.

> **Platform note (C only):** verified on macOS. Unprivileged datagram-ICMP works without root on macOS, and on Linux only when `net.ipv4.ping_group_range` includes your gid (not always the default); on Linux the kernel also assigns the ICMP id itself, so the id-match would need to read the kernel-assigned value via `getsockname`. The other nine are portable as-is.

## Running

No build step (scripting):

```bash
perl    perl/ping-sweep.pl        192.168.1.0/24
python3 python/ping-sweep.py      192.168.1.0/24
bash    bash/ping-sweep.sh        192.168.1.0/24
bun     typescript/ping-sweep.ts  192.168.1.0/24
pwsh    powershell/ping-sweep.ps1 192.168.1.0/24
ruby    ruby/ping-sweep.rb        192.168.1.0/24
```

Compiled:

```bash
cc -O2 -pthread c/ping-sweep.c -o c/ping-sweep && ./c/ping-sweep 192.168.1.0/24
(cd go && go run . 192.168.1.0/24)
rustc -O rust/ping-sweep.rs -o rust/ping-sweep && ./rust/ping-sweep 192.168.1.0/24
nim c -d:release --out:nim/ping-sweep nim/ping_sweep.nim && ./nim/ping-sweep 192.168.1.0/24
```

> **Portability note:** every version detects the OS because `ping -W` means *milliseconds* on macOS and *seconds* on Linux. The PowerShell version needs **7.4+** (for `Test-Connection -TimeoutSeconds`).

## Roadmap

- Optional: raw-ICMP variants of the Go and Rust versions (via `golang.org/x/net/icmp` and the `socket2` crate) to match the C approach — turning the collection into a fuller "scripting vs systems" comparison.

## License

MIT © 2026 Michael Hixon
