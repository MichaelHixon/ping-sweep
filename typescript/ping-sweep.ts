#!/usr/bin/env bun
// ping-sweep (TypeScript / bun) — concurrent host discovery across a /24.
//
// Fans out one `ping` per host via Bun.spawn (argv array — no shell, no
// injection) and awaits them all with Promise.all. Same contract as the rest:
//     bun typescript/ping-sweep.ts <network>     # 192.168.1.0/24  or  192.168.1

const arg = process.argv[2];
if (arg === undefined) {  // an empty-string argument is invalid (exit 1), not missing
  console.error("usage: ping-sweep.ts <network>   e.g. 192.168.1.0/24 or 192.168.1");
  process.exit(2);
}

// indexOf, not split("/", 2): JS split drops the remainder, so "/24/24" would pass
const slash = arg.indexOf("/");
const octets = (slash < 0 ? arg : arg.slice(0, slash)).split(".");
const validOctet = (o: string) => /^\d{1,3}$/.test(o) && Number(o) <= 255;
if ((octets.length !== 3 && octets.length !== 4) || !octets.every(validOctet)) {
  console.error(`invalid network: ${arg}`);
  process.exit(1);
}
if (slash >= 0 && arg.slice(slash + 1) !== "24") {
  console.error(`invalid network: ${arg} (only /24 is supported)`);
  process.exit(1);
}
// rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
const base = octets.slice(0, 3).map(Number).join(".");

// macOS `ping -W` is milliseconds; Linux `-W` is seconds.
const wait = process.platform === "darwin" ? ["-W", "1000"] : ["-W", "1"];
const hosts = Array.from({ length: 254 }, (_, i) => `${base}.${i + 1}`);

// Promise.all resolves in input order, so results come back sorted by host.
const results = await Promise.all(
  hosts.map(async (ip) => {
    const proc = Bun.spawn(["ping", "-c", "1", ...wait, "--", ip], { stdout: "ignore", stderr: "ignore" });
    return (await proc.exited) === 0 ? ip : null;
  }),
);

const up = results.filter((x): x is string => x !== null);
for (const ip of up) console.log(ip);
console.error(`${up.length} host${up.length === 1 ? "" : "s"} up on ${base}.0/24`);
