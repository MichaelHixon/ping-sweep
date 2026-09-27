#!/usr/bin/env pwsh
# ping-sweep (PowerShell) — concurrent host discovery across a /24.
#
# Uses Test-Connection with ForEach-Object -Parallel (PowerShell 7+). Same
# contract as the rest of the repo:
#     pwsh powershell/ping-sweep.ps1 <network>     # 192.168.1.0/24  or  192.168.1
# Plain $args, no param block: a named [string] param would swallow "-0.1.2" as a
# parameter name and couldn't tell "" from a missing argument, and a [Parameter()]
# attribute would make this an advanced script that claims -Verbose, -ea, -? …
if ($args.Count -lt 1) {
    [Console]::Error.WriteLine('usage: ping-sweep.ps1 <network>   e.g. 192.168.1.0/24 or 192.168.1')
    exit 2
}
$Network = [string]$args[0]

$octets = ($Network -split '/')[0] -split '\.'
$valid = $octets.Count -ge 3
if ($valid) {
    foreach ($o in $octets[0..2]) {
        # [0-9], not \d (also matches '١'); \z, not $ (also matches before a trailing newline)
        if ($o -notmatch '^[0-9]{1,3}\z' -or [int]$o -gt 255) { $valid = $false; break }
    }
}
if (-not $valid) {
    [Console]::Error.WriteLine("invalid network: $Network")
    exit 1
}
# rebuild from the numeric values: a leading-zero "010" would otherwise be read as octal 8
$prefix = [int[]]$octets[0..2] -join '.'

# ThrottleLimit 64: PowerShell runspaces are heavier than OS threads, so we
# sweep in waves of 64 rather than opening 254 at once.
$up = 1..254 | ForEach-Object -ThrottleLimit 64 -Parallel {
    $ip = "$using:prefix.$_"
    if (Test-Connection -TargetName $ip -Count 1 -TimeoutSeconds 1 -Quiet -ErrorAction SilentlyContinue) {
        $ip
    }
}

# sort by a real 32-bit numeric IP key ([version] models software versions, not IPs)
$up = @($up | Sort-Object {
    $o = $_ -split '\.'
    [int64]$o[0] * 16777216 + [int64]$o[1] * 65536 + [int64]$o[2] * 256 + [int64]$o[3]
})
$up | ForEach-Object { Write-Output $_ }
$plural = if ($up.Count -eq 1) { '' } else { 's' }
[Console]::Error.WriteLine(("{0} host{1} up on {2}.0/24" -f $up.Count, $plural, $prefix))
