# ping-sweep

A host-discovery sweep across a `/24`, written ten times in ten languages. Every version takes the same argument, prints the same output and exits with the same codes. That holds the problem constant, so the only thing left to compare is how each language fans out 254 probes and collects the answers. It started as a single Perl script in 2018.

## Writeup

- [Be the Pinger](https://michaelhixon.com/posts/be-the-pinger/): walks through the ten versions and what each one's concurrency looks like.

## The shared contract

```
ping-sweep <network>
```

- `<network>` is three octets (`192.168.1`) or four (`192.168.1.0`, `192.168.1.50`), optionally followed by `/24`. A fourth octet is validated, then ignored: only the first three pick the network.

- Each octet is 1 to 3 ASCII digits with a value of 0 to 255. No sign, no spaces, no empty field.

- Octets are read as decimal. A leading zero is dropped (`10.010.1` sweeps `10.10.1.0/24`), so `ping` never sees `010` and reads it as octal 8.

- Hosts `.1` through `.254` are probed concurrently, one probe per host.

- Live hosts go to stdout, one full IP per line, sorted by host number.

- A one-line summary goes to stderr: `N hosts up on 192.168.1.0/24` (`1 host up` when there is one).

- No argument: usage message on stderr, exit `2`.

- Anything malformed, including an empty argument: `invalid network: <arg>`, exit `1`.

- A well-formed network with any suffix other than exactly `/24`: `invalid network: <arg> (only /24 is supported)`, exit `1`. The tool always sweeps a `/24`, so it refuses rather than sweep a range other than the one asked for.

One runtime quirk sits outside the scripts' reach: `bun` consumes a bare `--`, so `bun typescript/ping-sweep.ts --` sees no argument and exits `2` with the usage message.

## Implementations

| Language | How to run | Probe | Concurrency |
|----------|------------|-------|-------------|
| Perl | `perl perl/ping-sweep.pl <network>` | system `ping` | `fork()` + `exec` per host, reaped with `wait()` |
| Python | `python3 python/ping-sweep.py <network>` | system `ping` | `ThreadPoolExecutor` with 254 workers, `pool.map` |
| Bash | `bash bash/ping-sweep.sh <network>` | system `ping` | one background job per host, each reaped with `wait <pid>` in host order |
| TypeScript | `bun typescript/ping-sweep.ts <network>` | system `ping` via `Bun.spawn` | one process per host, `Promise.all` |
| Ruby | `ruby ruby/ping-sweep.rb <network>` | system `ping` | one `Thread.new` per host, joined in order via `Thread#value` |
| PowerShell | `pwsh powershell/ping-sweep.ps1 <network>` | `Test-Connection` | `ForEach-Object -Parallel -ThrottleLimit 64` |
| C | `cc -O2 -pthread c/ping-sweep.c -o c/ping-sweep && ./c/ping-sweep <network>` | unprivileged ICMP socket | one pthread per host, `pthread_join` |
| Go | `(cd go && go run . <network>)` | system `ping` | one goroutine per host, `sync.WaitGroup`, results over a channel |
| Rust | `rustc -O rust/ping-sweep.rs -o rust/ping-sweep && ./rust/ping-sweep <network>` | system `ping` | one `std::thread` per host, results over `mpsc` |
| Nim | `nim c -d:release --out:nim/ping-sweep nim/ping_sweep.nim && ./nim/ping-sweep <network>` | system `ping` | `osproc.execProcesses`, at most 64 at a time |

Notes on the table:

- **C is the odd one out, on purpose.** It opens a `SOCK_DGRAM` + `IPPROTO_ICMP` socket per host and speaks ICMP itself: build the echo request, checksum it, `connect()` to the target so only that host's replies are delivered, send, then match the reply by a per-host ICMP id. The other nine hand the probe to the system `ping` (or, for PowerShell, to `Test-Connection`) and show off their language's concurrency instead. The writeup's title comes from that contrast.

- **PowerShell and Nim are the two bounded versions.** Both cap concurrency at 64, so a sweep takes a few timeout rounds instead of one. Every other version starts all 254 probes at once.

- **Rust needs no Cargo.** The source uses only `std`, so a bare `rustc` builds it.

- **Nim's source file is `ping_sweep.nim`**, because a Nim module name cannot contain `-`.

- `go run` adds its own `exit status N` line on stderr after a non-zero exit. A binary from `go build` does not.

Compiled binaries (`c/ping-sweep`, `rust/ping-sweep`, `go/ping-sweep`, `nim/ping-sweep`) are gitignored.

## Requirements and privileges

- **No root.** None of the ten calls `sudo` or opens a raw socket. Eight run the unprivileged system `ping`; C uses an unprivileged ICMP datagram socket.

- **The C version is written for macOS.** Linux allows unprivileged ICMP datagram sockets only when `net.ipv4.ping_group_range` includes your group, and the Linux kernel rewrites the echo id, so the reply match in `c/ping-sweep.c` would need the kernel-assigned id (from `getsockname`) there. The source comment says the same.

- **`ping -W` differs by OS.** It is milliseconds on macOS and seconds on Linux, so the eight versions that call `ping` check the OS and pass `-W 1000` or `-W 1`. C sets a one-second `SO_RCVTIMEO`; PowerShell passes `-TimeoutSeconds 1`.

- **Go 1.26 or later**, per `go/go.mod`.

- **PowerShell 7.0 or later**, for `ForEach-Object -Parallel`.

- **bun**, not Node, for the TypeScript version (`Bun.spawn`).

## Tests

There is no automated test suite. Everything in the contract except the sweep itself can be checked offline: a missing or invalid argument exits before any probe is sent. For example:

```
$ python3 python/ping-sweep.py; echo "exit $?"
usage: ping-sweep.py <network>   e.g. 192.168.1.0/24 or 192.168.1
exit 2
$ python3 python/ping-sweep.py 192.168.1.0/16; echo "exit $?"
invalid network: 192.168.1.0/16 (only /24 is supported)
exit 1
$ python3 python/ping-sweep.py 10.010.1.300; echo "exit $?"
invalid network: 10.010.1.300
exit 1
```

Swap in any of the other run commands; the messages and exit codes match. The usage line names the script's own file, or `ping-sweep` for the compiled versions.

On a live network, a single-probe sweep is not deterministic. Devices sleep and wake between probes, so two runs, or two implementations, can differ by a host or two. That is the network, not the code.

## Roadmap

- Raw-ICMP variants of the Go and Rust versions (`golang.org/x/net/icmp`, the `socket2` crate) to match the C approach.

## License

MIT. See [LICENSE](LICENSE).

More projects: [michaelhixon.com/making](https://michaelhixon.com/making/)
