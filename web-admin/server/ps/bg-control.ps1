<#
    bg-control.ps1 - non-interactive backend for the web-admin panel.

    Mirrors the VM/SSH logic in ../../../battlegroup-management/battlegroup.ps1 but
    emits a single JSON object to stdout and NEVER prompts interactively.

    Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File bg-control.ps1 -Action status
            -Action must be one of: status | start | stop | restart

    All ssh calls use BatchMode=yes so a broken key fails fast (reported as JSON)
    instead of blocking on a "dune@<ip>'s password:" prompt.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('status', 'start', 'stop', 'restart')]
    [string]$Action,

    [string]$VmName = 'dune-awakening'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- Constants (kept in sync with battlegroup-management/battlegroup.ps1) ---
$sshKey            = "$env:LOCALAPPDATA\DuneAwakeningServer\sshKey"
$fileBrowserPort   = 18888
$directorSvcPort   = 11717
$remoteBattlegroup = '/home/dune/.dune/bin/battlegroup'

# Result object we always emit, whatever happens.
$result = [ordered]@{
    ok             = $false
    action         = $Action
    vmName         = $VmName
    vmExists       = $false
    vmState        = 'unknown'
    vmRunning      = $false
    ip             = $null
    directorPort   = $null
    directorUrl    = $null
    fileBrowserUrl = $null
    status         = $null
    output         = $null
    reason         = $null
    error          = $null
    timestamp      = (Get-Date).ToString('o')
}

function Emit($obj) {
    # Force an object (not array) and emit compact-ish JSON on a single stream.
    $json = $obj | ConvertTo-Json -Depth 6
    Write-Output $json
}

# Shared ssh options: no host-key prompts, quiet, only our key, and BatchMode so
# a failed key auth errors out instead of blocking on a password prompt.
$sshCommonArgs = @(
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'LogLevel=QUIET',
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'ConnectTimeout=8',
    '-i', $sshKey
)

function Invoke-RemoteSsh {
    param([string]$Ip, [string]$Command)
    # Returns @{ ExitCode; Output }
    $args = @($sshCommonArgs) + @("dune@$Ip", $Command)
    $raw  = & ssh @args 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = ($raw | Out-String).Trim() }
}

try {
    if (-not (Test-Path $sshKey)) {
        $result.reason = "SSH key not found at $sshKey. Run the initial setup from battlegroup.bat first."
        Emit $result
        return
    }

    # --- VM state via Hyper-V (requires elevation) ---
    $vm = $null
    try {
        $vm = Get-VM -Name $VmName -ErrorAction Stop
    } catch {
        $msg = "$($_.Exception.Message)"
        if ($msg -match 'permission|authorization') {
            # Not elevated / not a Hyper-V admin - distinct from a missing VM.
            $result.reason = "The web admin server is not running as administrator, so it cannot query Hyper-V. Restart it from the battlegroup menu (option g) in an elevated window."
            $result.error  = $msg
            Emit $result
            return
        }
        # Get-VM -Name throws when the named VM does not exist: treat as missing.
        $vm = $null
    }

    $result.vmExists  = [bool]$vm
    $result.vmState   = if ($vm) { "$($vm.State)" } else { 'missing' }
    $result.vmRunning = [bool]($vm -and $vm.State -eq 'Running')

    if ($result.vmRunning) {
        $ip = (Get-VMNetworkAdapter -VMName $VmName).IPAddresses |
              Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
              Select-Object -First 1
        $result.ip = $ip
        if ($ip) {
            $result.fileBrowserUrl = "http://${ip}:$fileBrowserPort/"
        }
    }

    # --- Availability gate (mirrors Get-BgCmdAvailability) ---
    if (-not $result.vmExists) {
        $result.reason = "VM '$VmName' does not exist. Run the initial setup on the host first."
        Emit $result
        return
    }
    if (-not $result.vmRunning) {
        $result.reason = "VM '$VmName' is not running (currently $($result.vmState)). Ask the host owner to start the VM."
        Emit $result
        return
    }
    if (-not $result.ip) {
        $result.reason = "VM is running but has no IP address yet. Try again in a moment."
        Emit $result
        return
    }

    # --- Discover the director NodePort (best-effort, non-fatal) ---
    try {
        $portQuery = "sudo kubectl get svc -A -o jsonpath='{.items[*].spec.ports[?(@.port==$directorSvcPort)].nodePort}' 2>/dev/null"
        $pr = Invoke-RemoteSsh -Ip $result.ip -Command $portQuery
        if ($pr.ExitCode -eq 0 -and $pr.Output -match '^\d+$') {
            $result.directorPort = $pr.Output.Trim()
            $result.directorUrl  = "http://$($result.ip):$($result.directorPort)/"
        }
    } catch { }

    # --- Run the requested action ---
    if ($Action -eq 'status') {
        $sr = Invoke-RemoteSsh -Ip $result.ip -Command "$remoteBattlegroup status"
        $result.status = $sr.Output
        if ($sr.ExitCode -ne 0) {
            $result.reason = "Could not reach the battlegroup over SSH (exit $($sr.ExitCode)). The SSH key may not be authorized on the VM."
            $result.error  = $sr.Output
        } else {
            $result.ok = $true
        }
        Emit $result
        return
    }

    # start | stop | restart
    $ar = Invoke-RemoteSsh -Ip $result.ip -Command "$remoteBattlegroup $Action"
    $result.output = $ar.Output
    if ($ar.ExitCode -ne 0) {
        $result.reason = "Battlegroup '$Action' failed (exit $($ar.ExitCode))."
        $result.error  = $ar.Output
    } else {
        $result.ok = $true
    }
    Emit $result
    return
}
catch {
    $result.error = $_.Exception.Message
    Emit $result
    return
}
