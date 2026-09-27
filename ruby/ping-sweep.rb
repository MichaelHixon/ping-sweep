#!/usr/bin/env ruby
# frozen_string_literal: true
#
# ping-sweep (Ruby) — concurrent host discovery across a /24.
#
# One thread per host driving the system pinger. Ruby's GIL is irrelevant here:
# every thread blocks in a `ping` subprocess, so they wait concurrently and the
# whole /24 finishes in about one ping timeout. No root; same behavior on macOS
# and Linux. Same contract as every other script in this repo:
#
#     ping-sweep.rb <network>     # 192.168.1.0/24  or  192.168.1

# macOS `ping -W` is milliseconds; Linux `-W` is seconds.
WAIT = (RUBY_PLATFORM.include?("darwin") ? %w[-W 1000] : %w[-W 1]).freeze

# "192.168.1" | "192.168.1.<0-255>", optionally + "/24"  ->  "192.168.1"
def parse_base(arg)
  net, slash, suffix = arg.b.partition("/")   # .b: bytes, so invalid UTF-8 can't raise mid-parse
  octets = net.split(".", -1)                 # -1 keeps a trailing empty field, so "1.2.3." fails
  ok = [3, 4].include?(octets.length) &&
       octets.all? { |o| o.match?(/\A\d{1,3}\z/) && o.to_i <= 255 }
  raise ArgumentError, "invalid network: #{arg}" unless ok
  raise ArgumentError, "invalid network: #{arg} (only /24 is supported)" if !slash.empty? && suffix != "24"

  # rebuild from the numeric values: `ping` would read a leading-zero "010" as octal 8
  octets[0, 3].map(&:to_i).join(".")
end

def alive?(ip)
  # Array form (no shell) — the validated `ip` never reaches a shell.
  system("ping", "-c", "1", *WAIT, "--", ip, out: File::NULL, err: File::NULL)
end

def main
  if ARGV.empty?
    warn "usage: ping-sweep.rb <network>   e.g. 192.168.1.0/24 or 192.168.1"
    exit 2
  end

  begin
    base = parse_base(ARGV[0])
  rescue ArgumentError => e
    warn e.message
    exit 1
  end

  # joining threads in creation order keeps `up` sorted by host
  hosts = (1..254).map { |i| "#{base}.#{i}" }
  up = hosts.map { |ip| Thread.new { ip if alive?(ip) } }
            .map(&:value)
            .compact

  puts up
  n = up.length
  warn "#{n} host#{'s' unless n == 1} up on #{base}.0/24"
end

main
