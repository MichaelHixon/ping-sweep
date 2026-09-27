// ping-sweep (Go) — concurrent host discovery across a /24.
//
// One goroutine per host driving the system pinger; live host numbers flow back
// over a channel. Same contract as the rest of the repo:
//
//	go run ./go 192.168.1.0/24     # or 192.168.1
package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"sync"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1")
		os.Exit(2)
	}
	prefix, suffix, hasSlash := strings.Cut(os.Args[1], "/")
	octets := strings.Split(prefix, ".")
	var n [4]int // an optional fourth octet is validated, but its value is ignored
	valid := len(octets) == 3 || len(octets) == 4
	for i := 0; valid && i < len(octets); i++ {
		// base 10, bitSize 8: rejects a sign and anything over 255; len rejects "0010"
		v, err := strconv.ParseUint(octets[i], 10, 8)
		valid = err == nil && len(octets[i]) <= 3
		n[i] = int(v)
	}
	if !valid {
		fmt.Fprintf(os.Stderr, "invalid network: %s\n", os.Args[1])
		os.Exit(1)
	}
	if hasSlash && suffix != "24" {
		fmt.Fprintf(os.Stderr, "invalid network: %s (only /24 is supported)\n", os.Args[1])
		os.Exit(1)
	}
	// rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
	base := fmt.Sprintf("%d.%d.%d", n[0], n[1], n[2])

	// macOS `ping -W` is milliseconds; Linux `-W` is seconds.
	timeout := "1"
	if runtime.GOOS == "darwin" {
		timeout = "1000"
	}

	// collect over a channel — "don't communicate by sharing memory; share memory by communicating"
	results := make(chan int, 254)
	var wg sync.WaitGroup

	for i := 1; i <= 254; i++ {
		wg.Add(1)
		go func(h int) {
			defer wg.Done()
			ip := fmt.Sprintf("%s.%d", base, h)
			if exec.Command("ping", "-c", "1", "-W", timeout, "--", ip).Run() == nil {
				results <- h
			}
		}(i)
	}
	go func() { wg.Wait(); close(results) }()

	var up []int
	for h := range results {
		up = append(up, h)
	}

	// every host shares `base`, so the host number alone orders the output
	slices.Sort(up)
	for _, h := range up {
		fmt.Printf("%s.%d\n", base, h)
	}
	plural := "s"
	if len(up) == 1 {
		plural = ""
	}
	fmt.Fprintf(os.Stderr, "%d host%s up on %s.0/24\n", len(up), plural, base)
}
