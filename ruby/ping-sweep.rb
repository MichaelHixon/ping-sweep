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

# "192.168.1.0/24" | "192.168.1.0" | "192.168.1"  ->  "192.168.1"
def parse_base(arg)
  octets = arg.split("/").first.to_s.split(".")
  ok = octets.length >= 3 &&
       octets[0, 3].all? { |o| o.match?(/\A\d{1,3}\z/) && (0..255).cover?(o.to_i) }
  raise ArgumentError, "invalid network: #{arg}" unless ok

  octets[0, 3].join(".")
end

def alive?(ip)
  # macOS `ping -W` is milliseconds; Linux `-W` is seconds.
  wait = RUBY_PLATFORM.include?("darwin") ? %w[-W 1000] : %w[-W 1]
  # Array form (no shell) — the validated `ip` never reaches a shell.
  system("ping", "-c", "1", *wait, "--", ip, out: File::NULL, err: File::NULL)
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

  hosts = (1..254).map { |i| "#{base}.#{i}" }
  up = hosts.map { |ip| Thread.new(ip) { |h| alive?(h) ? h : nil } }
            .map(&:value)
            .compact

  up.sort_by! { |ip| ip.split(".").map(&:to_i) }
  puts up
  n = up.length
  warn "#{n} host#{'s' unless n == 1} up on #{base}.0/24"
end

main
