#!/usr/bin/perl
# ping-sweep (Perl) — concurrent host discovery across a /24.
#
# Modernized from the original Net::Ping one-liner:
#   - network is a CLI argument instead of a hardcoded constant
#   - forked concurrency (was strictly sequential)
#   - drives the system pinger, so it needs no root and behaves the same on
#     macOS and Linux (Net::Ping's default TCP-echo probe was unreliable)
use strict;
use warnings;

my $network = shift @ARGV;
unless (defined $network) {
    print STDERR "usage: ping-sweep.pl <network>   e.g. 192.168.1.0/24 or 192.168.1\n";
    exit 2;
}

# accept 192.168.1.0/24, 192.168.1.0, or 192.168.1 -> base "192.168.1"
$network =~ s{/\d+$}{};
my @octets = split /\./, $network;
my $bad = @octets < 3 || grep { !/^\d{1,3}$/ || $_ > 255 } @octets[0 .. 2];
if ($bad) { warn "invalid network: $network\n"; exit 1; }    # exit 1, matching the family
my $base = join('.', @octets[0 .. 2]);

# macOS `ping -W` is milliseconds; Linux `-W` is seconds.
my @wait = ($^O eq 'darwin') ? ('-W', '1000') : ('-W', '1');

my %host_of;
for my $host (1 .. 254) {
    my $pid = fork();
    if (!defined $pid) { warn "fork failed: $!\n"; next; }
    if ($pid == 0) {
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec('ping', '-c', '1', @wait, '--', "$base.$host");
        exit 1;    # exec only returns on failure
    }
    $host_of{$pid} = $host;
}

# wait() returns in completion order; every host shares $base, so sort by host number
my @up;
while ((my $pid = wait()) > 0) {
    push @up, $host_of{$pid} if defined $host_of{$pid} && $? == 0;
}

print "$base.$_\n" for sort { $a <=> $b } @up;
printf STDERR "%d host%s up on %s.0/24\n", scalar(@up), (@up == 1 ? '' : 's'), $base;
