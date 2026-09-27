#!/usr/bin/env python3
"""ping-sweep (Python) — concurrent host discovery across a /24.

Drives the system pinger from a thread pool, so it needs no root and behaves
the same on macOS and Linux. Same contract as every other script in this repo:

    ping-sweep.py <network>     # 192.168.1.0/24  or  192.168.1
"""
import platform
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

# macOS `ping -W` is milliseconds; Linux `-W` is seconds.
WAIT = ["-W", "1000"] if platform.system() == "Darwin" else ["-W", "1"]


def parse_base(arg: str) -> str:
    """192.168.1.0/24 | 192.168.1.0 | 192.168.1  ->  '192.168.1'"""
    octets = arg.split("/")[0].split(".")
    if len(octets) < 3 or not all(
        re.fullmatch("[0-9]{1,3}", o) and int(o) <= 255 for o in octets[:3]
    ):
        raise ValueError(f"invalid network: {arg}")
    # rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
    return ".".join(str(int(o)) for o in octets[:3])


def alive(ip: str) -> bool:
    return subprocess.run(
        ["ping", "-c", "1", *WAIT, "--", ip],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: ping-sweep.py <network>   e.g. 192.168.1.0/24 or 192.168.1",
              file=sys.stderr)
        sys.exit(2)

    try:
        base = parse_base(sys.argv[1])
    except ValueError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
    hosts = [f"{base}.{i}" for i in range(1, 255)]

    # pool.map yields results in input order, so `up` is already sorted by host
    with ThreadPoolExecutor(max_workers=len(hosts)) as pool:
        up = [ip for ip, ok in zip(hosts, pool.map(alive, hosts)) if ok]

    for ip in up:
        print(ip)
    print(f"{len(up)} host{'' if len(up) == 1 else 's'} up on {base}.0/24",
          file=sys.stderr)


if __name__ == "__main__":
    main()
