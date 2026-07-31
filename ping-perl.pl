#!/usr/bin/perl
use strict;
use Net::Ping;

my $p = Net::Ping->new();
my $net='10.100.1';

for my $ip (1..254) {
    print "$net.$ip\n" if $p->ping("$net.$ip");
    $p->close();
}
