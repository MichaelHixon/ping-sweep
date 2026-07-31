// ping-sweep (Go) — concurrent host discovery across a /24.
//
// One goroutine per host driving the system pinger; results collected under a
// mutex. Same contract as the rest of the repo:
//
//	go run ./go 192.168.1.0/24     # or 192.168.1
package main

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
)

func ipKey(ip string) uint32 {
	var k uint32
	for _, o := range strings.Split(ip, ".") {
		n, _ := strconv.Atoi(o)
		k = k*256 + uint32(n)
	}
	return k
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: ping-sweep <network>   e.g. 192.168.1.0/24 or 192.168.1")
		os.Exit(2)
	}
	octets := strings.Split(strings.Split(os.Args[1], "/")[0], ".")
	valid := len(octets) >= 3
	if valid {
		for _, o := range octets[:3] {
			if n, err := strconv.Atoi(o); err != nil || n < 0 || n > 255 {
				valid = false
				break
			}
		}
	}
	if !valid {
		fmt.Fprintf(os.Stderr, "invalid network: %s\n", os.Args[1])
		os.Exit(1)
	}
	base := strings.Join(octets[:3], ".")

	// macOS `ping -W` is milliseconds; Linux `-W` is seconds.
	wait := []string{"-W", "1"}
	if runtime.GOOS == "darwin" {
		wait = []string{"-W", "1000"}
	}

	// collect over a channel — "don't communicate by sharing memory; share memory by communicating"
	results := make(chan string, 254)
	var wg sync.WaitGroup

	for i := 1; i <= 254; i++ {
		wg.Add(1)
		go func(h int) {
			defer wg.Done()
			ip := fmt.Sprintf("%s.%d", base, h)
			args := append([]string{"-c", "1"}, wait...)
			args = append(args, "--", ip)
			if exec.Command("ping", args...).Run() == nil {
				results <- ip
			}
		}(i)
	}
	go func() { wg.Wait(); close(results) }()

	var up []string
	for ip := range results {
		up = append(up, ip)
	}

	sort.Slice(up, func(a, b int) bool { return ipKey(up[a]) < ipKey(up[b]) })
	for _, ip := range up {
		fmt.Println(ip)
	}
	plural := "s"
	if len(up) == 1 {
		plural = ""
	}
	fmt.Fprintf(os.Stderr, "%d host%s up on %s.0/24\n", len(up), plural, base)
}
