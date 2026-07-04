#Requires -RunAsAdministrator

# Logging Section
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = "$scriptDir\..\.logs\battlegroup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null

. "$scriptDir\vm-utilities.ps1"
. "$scriptDir\web-admin.ps1"

# Start
$vmName = 'dune-awakening'
$sshKey = "$env:LOCALAPPDATA\DuneAwakeningServer\sshKey"
$directorPort = $null

$_vmBaseCommands = @(
    [pscustomobject]@{ Key = "a"; Name = "initial-setup";    Desc = "Run the initial VM setup" }
    [pscustomobject]@{ Key = "b"; Name = "start-vm";         Desc = "Start the VM" }
    [pscustomobject]@{ Key = "c"; Name = "stop-vm";          Desc = "Stop the VM" }
    [pscustomobject]@{ Key = "d"; Name = "rotate-ssh-key";   Desc = "Generate a new SSH key and replace the one authorized on the VM" }
    [pscustomobject]@{ Key = "e"; Name = "change-password";  Desc = "Change the password of the 'dune' user on the VM" }
    [pscustomobject]@{ Key = "f"; Name = "change-vm-ip";     Desc = "Sets the VM IP (Allows for DHCP or static)" }
)

$_bgBaseCommands = @(
    [pscustomobject]@{ Key = "1";  Name = "status";                    Desc = "Shows the status of the selected battlegroup" }
    [pscustomobject]@{ Key = "2";  Name = "start";                     Desc = "Starts the selected battlegroup" }
    [pscustomobject]@{ Key = "3";  Name = "restart";                   Desc = "Restarts the selected battlegroup" }
    [pscustomobject]@{ Key = "4";  Name = "stop";                      Desc = "Stops the selected battlegroup" }
    [pscustomobject]@{ Key = "5";  Name = "update";                    Desc = "Checks for new versions and applies them" }
    [pscustomobject]@{ Key = "6";  Name = "edit";                      Desc = "Edit the battlegroup with the utilities interface" }
    [pscustomobject]@{ Key = "7";  Name = "edit-advanced";             Desc = "(Advanced) Manually edit battlegroup directly with YAML" }
    [pscustomobject]@{ Key = "8";  Name = "change-battlegroup-ip";    Desc = "Change the IP that players connect to" }
    [pscustomobject]@{ Key = "9";  Name = "enable-experimental-swap"; Desc = "(Experimental) Enable experimental swap memory feature to reduce memory requirements for the battlegroup" }
    [pscustomobject]@{ Key = "10";  SubSection = "Database";   Name = "backup";                   Desc = "Take a backup of the battlegroup's database" }
    [pscustomobject]@{ Key = "11"; SubSection = "Database";   Name = "import";                   Desc = "Import a database backup into the selected battlegroup" }
    [pscustomobject]@{ Key = "12"; SubSection = "Logs";       Name = "logs-export";              Desc = "Retrieves logs from all pods in the selected battlegroup" }
    [pscustomobject]@{ Key = "13"; SubSection = "Logs";       Name = "operator-logs-export";     Desc = "Retrieves logs from all operator pods" }
    [pscustomobject]@{ Key = "14"; SubSection = "Monitoring"; Name = "open-file-browser";        Desc = "Open the battlegroup file browser to view and edit ini configs and logs" }
    [pscustomobject]@{ Key = "15"; SubSection = "Monitoring"; Name = "open-director";            Desc = "Open the battlegroup director page to view server, travel and queues status" }
    [pscustomobject]@{ Key = "16"; SubSection = "Monitoring"; Name = "shell-vm";                 Desc = "Connect to the VM via commandline" }
    [pscustomobject]@{ Key = "17"; SubSection = "Monitoring"; Name = "shell-pod";                Desc = "Connect to a pod in the battlegroup via commandline" }
)

$_webBaseCommands = @(
    [pscustomobject]@{ Key = "g"; Name = "web-admin";          Desc = "Start/stop the web admin panel" }
    [pscustomobject]@{ Key = "h"; Name = "web-admin-accounts"; Desc = "Create or reset web admin login accounts" }
)

$vmCommands = $_vmBaseCommands
if ($null -ne $_vmExtraCommands -and $_vmExtraCommands.Count -gt 0) {
    $vmCommands = $_vmBaseCommands + $_vmExtraCommands
}

$bgCommands = $_bgBaseCommands
if ($null -ne $_bgExtraCommands -and $_bgExtraCommands.Count -gt 0) {
    $bgCommands = $_bgBaseCommands + $_bgExtraCommands
}

$webCommands = $_webBaseCommands

function Get-VmCmdAvailability {
    param($cmdName, $vmExists, $vmRunning, $vmState)
    switch ($cmdName) {
        "initial-setup" { return [pscustomobject]@{ Available = $true; Reason = $null } }
        "start-vm" {
            if (-not $vmExists) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' does not exist. Run 'initial-setup' first." } }
            if ($vmRunning)     { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' is already running." } }
            return [pscustomobject]@{ Available = $true; Reason = $null }
        }
        "stop-vm" {
            if (-not $vmExists) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' does not exist. Run 'initial-setup' first." } }
            if (-not $vmRunning) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' is not running (currently $vmState)." } }
            return [pscustomobject]@{ Available = $true; Reason = $null }
        }
        default {
            if (-not $vmExists) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' does not exist. Run 'initial-setup' first." } }
            if (-not $vmRunning) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' is not running. Run 'start-vm' first." } }
            return [pscustomobject]@{ Available = $true; Reason = $null }
        }
    }
}

function Get-BgCmdAvailability {
    param($vmExists, $vmRunning, $vmState)
    if (-not $vmExists) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' does not exist. Run 'initial-setup' first." } }
    if (-not $vmRunning) { return [pscustomobject]@{ Available = $false; Reason = "VM '$vmName' is not running. Run 'start-vm' first." } }
    return [pscustomobject]@{ Available = $true; Reason = $null }
}

while ($true) {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    $vmExists = [bool]$vm
    $vmState = if ($vmExists) { $vm.State } else { 'missing' }
    $vmRunning = $vmExists -and $vm.State -eq 'Running'

    $ip = $null
    if ($vmRunning) {
        $ip = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses |
              Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
              Select-Object -First 1
    }

    $entries = @()
    foreach ($c in $vmCommands) {
        $avail = Get-VmCmdAvailability -cmdName $c.Name -vmExists $vmExists -vmRunning $vmRunning -vmState $vmState
        $entries += [pscustomobject]@{
            Section = 'vm'
            SubSection = $c.SubSection
            Key = $c.Key
            Name = $c.Name
            Desc = $c.Desc
            Available = $avail.Available
            Reason = $avail.Reason
        }
    }
    foreach ($c in $bgCommands) {
        $avail = Get-BgCmdAvailability -vmExists $vmExists -vmRunning $vmRunning -vmState $vmState
        if ($null -ne $_onCheckCmdAvailability)
        {
            $avail = & $_onCheckCmdAvailability
        }
        $entries += [pscustomobject]@{
            Section = 'battlegroup'
            SubSection = $c.SubSection
            Key = $c.Key
            Name = $c.Name
            Desc = $c.Desc
            Available = $avail.Available
            Reason = $avail.Reason
        }
    }
    $webStatus = Get-WebAdminStatus
    $nodeAvailable = [bool](Get-Command node -ErrorAction SilentlyContinue)
    foreach ($c in $webCommands) {
        $desc = $c.Desc
        if ($c.Name -eq 'web-admin') {
            $desc = if ($webStatus.Running) { "RUNNING at $($webStatus.Url) - select to stop" } else { "Stopped - select to start" }
        }
        $available = $true
        $reason = $null
        if (-not $nodeAvailable) { $available = $false; $reason = "Node.js is not installed" }
        $entries += [pscustomobject]@{
            Section = 'web'
            SubSection = $null
            Key = $c.Key
            Name = $c.Name
            Desc = $desc
            Available = $available
            Reason = $reason
        }
    }

    $entryByKey = @{}
    foreach ($e in $entries) { $entryByKey[$e.Key.ToLower()] = $e }

    $prevSection = $null
    $prevSubSection = $null
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        if ($e.Section -ne $prevSection) {
            if ($null -ne $prevSection) { Write-Host "" }
            $header = switch ($e.Section) { 'vm' { "VM commands:" } 'web' { "Web admin:" } default { "Battlegroup commands:" } }
            Write-Host $header
            Write-Host ""
            $prevSubSection = $null
        }
        if ($e.SubSection -and $e.SubSection -ne $prevSubSection) {
            Write-Host (" {0}:" -f $e.SubSection)
        }
        $color = if ($e.Available) { 'White' } else { 'DarkGray' }
        Write-Host ("  {0,2}. {1,-27} {2}" -f $e.Key, $e.Name, $e.Desc) -ForegroundColor $color
        $prevSection = $e.Section
        $prevSubSection = $e.SubSection
    }
    Write-Host ""
    Write-Host ("  {0,2}. {1,-27} {2}" -f "q", "quit", "Exit this script")
    Write-Host ""

    if (-not $vmExists) {
        Write-Host "Some options are unavailable because VM '$vmName' does not exist. Press 'a' to run 'initial-setup'" -ForegroundColor Yellow
        Write-Host ""
    } elseif (-not $vmRunning) {
        Write-Host "Some options are unavailable because VM '$vmName' is currently $($vm.State). Press 'b' to start it or 'a' to re-run the initial setup" -ForegroundColor Yellow
        Write-Host ""
    }

    if ($webStatus.Running) {
        Write-Host "Web admin is running at $($webStatus.Url)" -ForegroundColor Green
        Write-Host ""
    }

    $entry = $null
    while ($null -eq $entry) {
        $selection = (Read-Host "Select an option").Trim().ToLower()
        if ($selection -eq 'q' -or $selection -eq 'quit') { $entry = 'quit'; break }
        if ($entryByKey.ContainsKey($selection)) {
            $entry = $entryByKey[$selection]
        } else {
            Write-Warning "Invalid selection."
        }
    }

    if ($entry -eq 'quit') { break }

    if (-not $entry.Available) {
        Write-Warning $entry.Reason
        continue
    }

    $cmd = $entry.Name

    # --- VM section ---

    if ($cmd -eq "initial-setup") {
        if ($null -ne $_onInitialSetup) {
            & $_onInitialSetup
        }
        . "$scriptDir\initial-setup.ps1"
        continue
    }

    if ($cmd -eq "start-vm") {
        Write-Host "Starting VM '$vmName'..." -ForegroundColor Cyan
        Start-VM -Name $vmName | Out-Null
        do {
            Start-Sleep -Seconds 2
            $vm = Get-VM -Name $vmName
        } while ($vm.State -ne 'Running')
        Write-Host "VM started." -ForegroundColor Green

        $ip = $null
        $timeout = 120
        $elapsed = 0
        $dots = 0
        while (-not $ip -and $elapsed -lt $timeout) {
            $dots = ($dots % 3) + 1
            Write-Host -NoNewline "`rWaiting for VM to acquire an IP address$('.' * $dots)   "
            Start-Sleep -Seconds 1
            $elapsed += 1
            $ip = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses |
                  Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
                  Select-Object -First 1
        }
        Write-Host ""
        if (-not $ip) {
            Write-Warning "Could not determine VM IP after $timeout seconds. Check Hyper-V Manager or run: Get-VMNetworkAdapter -VMName '$vmName'"
        } else {
            Write-Host "VM ready at $ip." -ForegroundColor Green
        }
        continue
    }

    if ($cmd -eq "stop-vm") {
        Write-Host ""
        Write-Host "Stopping VM '$vmName'..." -ForegroundColor Cyan
        Stop-VM -Name $vmName -Force | Out-Null
        Write-Host "VM stopped." -ForegroundColor Green
        continue
    }

    if ($cmd -eq "rotate-ssh-key") {
        Update-SshKey -Ip $ip | Out-Null
        continue
    }

    if ($cmd -eq "change-password") {
        $pw1Sec = Read-Host "Enter new password for 'dune'" -AsSecureString
        $pw2Sec = Read-Host "Confirm new password" -AsSecureString
        $pw1 = [System.Net.NetworkCredential]::new('', $pw1Sec).Password
        $pw2 = [System.Net.NetworkCredential]::new('', $pw2Sec).Password
        if ([string]::IsNullOrEmpty($pw1)) {
            Write-Warning "Password cannot be empty"
            continue
        }
        if ($pw1 -ne $pw2) {
            Write-Warning "Passwords do not match"
            continue
        }
        if (Set-VmPassword -Ip $ip -NewPassword $pw1Sec) {
            Write-Host "Password for 'dune' changed successfully" -ForegroundColor Green
        }
        continue
    }

    if ($cmd -eq "change-vm-ip") {
        Write-Host ""
        Write-Host "Switching IP settings restarts the VM's networking, so it will briefly disconnect and come back on the chosen IP." -ForegroundColor Yellow
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup change-vm-ip"

        # Networking may have just restarted on a new IP. Poll until the VM has a stable IP
        Write-Host "Waiting for VM to acquire an IP address..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
        $newIp = $null
        $waitElapsed = 0
        $waitTimeout = 90
        while (-not $newIp -and $waitElapsed -lt $waitTimeout) {
            $newIp = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses |
                     Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
                     Select-Object -First 1
            if ($newIp) { break }
            Start-Sleep -Seconds 2
            $waitElapsed += 2
        }
        if ($newIp) {
            Write-Host "VM IP address: $newIp" -ForegroundColor Green
        } else {
            Write-Warning "Could not detect the VM's IP after changing network settings. Check Hyper-V Manager or run: Get-VMNetworkAdapter -VMName '$vmName'"
        }
        continue
    }

    # --- Web admin section ---

    if ($cmd -eq "web-admin") {
        if ((Get-WebAdminStatus).Running) { Stop-WebAdmin } else { Start-WebAdmin }
        continue
    }

    if ($cmd -eq "web-admin-accounts") {
        Invoke-WebAdminCreateAdmin
        continue
    }

    # --- Battlegroup section ---

    if ($cmd -eq "open-file-browser") {
        Start-Process "http://${ip}:18888/"
        continue
    }

    if ($cmd -eq "open-director") {
        if (-not $directorPort) {
            $directorNodePort = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" `
                "sudo kubectl get svc -A -o jsonpath='{.items[*].spec.ports[?(@.port==11717)].nodePort}' 2>&1"
            if ($directorNodePort -match '^\d+$') {
                $directorPort = $directorNodePort.Trim()
                if ($null -ne $_onDirectorPortDetected) {
                    & $_onDirectorPortDetected
                }
            }
        }
        if (-not $directorPort) {
            Write-Warning "Could not determine Director port. Is the battlegroup running?"
            continue
        }
        Start-Process "http://${ip}:${directorPort}/"
        continue
    }

    if ($cmd -eq "shell-vm") {
        Write-Host "Opening shell in the VM. You can exit by typing 'exit'" -ForegroundColor Cyan
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip"
        continue
    }

    if ($cmd -eq "shell-pod") {
        $bgPrefix = "funcom-seabass-"
        $nsList = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" "sudo kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name | grep '^$bgPrefix'"
        $namespaces = @($nsList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($namespaces.Count -eq 0) {
            Write-Warning "No battlegroup found."
            continue
        }
        if ($namespaces.Count -eq 1) {
            $ns = $namespaces[0]
        } else {
            Write-Host ""
            for ($i = 0; $i -lt $namespaces.Count; $i++) {
                Write-Host ("  {0,2}. {1}" -f ($i + 1), ($namespaces[$i] -replace "^$bgPrefix",''))
            }
            $ns = $null
            while ($null -eq $ns) {
                $sel = Read-Host "Select battlegroup (1-$($namespaces.Count))"
                if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $namespaces.Count) {
                    $ns = $namespaces[[int]$sel - 1]
                } else {
                    Write-Warning "Invalid selection."
                }
            }
        }

        $podList = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" "sudo kubectl get pods -n '$ns' --no-headers -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.role"
        $pods = @($podList -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object {
            $parts = $_ -split '\s+', 2
            [pscustomobject]@{
                Name    = $parts[0]
                Role    = if ($parts.Count -gt 1 -and $parts[1] -ne '<none>') { $parts[1] } else { '' }
                Display = $parts[0] -replace "^$($ns -replace '^funcom-seabass-','')-",''
            }
        })
        if ($pods.Count -eq 0) {
            Write-Warning "No pods found in namespace '$ns'."
            continue
        }
        Write-Host ""
        Write-Host "Pods in ${ns}:"
        $maxLen = ($pods | ForEach-Object { $_.Display.Length } | Measure-Object -Maximum).Maximum
        for ($i = 0; $i -lt $pods.Count; $i++) {
            Write-Host ("  {0,2}. {1,-$maxLen}  {2}" -f ($i + 1), $pods[$i].Display, $pods[$i].Role)
        }
        $pod = $null
        while ($null -eq $pod) {
            $sel = Read-Host "Select pod (1-$($pods.Count))"
            if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $pods.Count) {
                $pod = $pods[[int]$sel - 1].Name
            } else {
                Write-Warning "Invalid selection."
            }
        }

        Write-Host "Opening shell in $pod. You can exit by typing 'exit'" -ForegroundColor Cyan
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" "sudo kubectl exec -it '$pod' -n '$ns' -- /bin/bash || sudo kubectl exec -it '$pod' -n '$ns' -- /bin/sh"
        continue
    }

    if ($cmd -eq "edit-battlegroup-advanced") {
        Write-Host ""
        Write-Host "WARNING:" -ForegroundColor Red -NoNewline
        Write-Host " You are about to edit the live battlegroup YAML directly in Kubernetes." -ForegroundColor Yellow
        Write-Host "         Mistakes can permanently break the battlegroup, including indentation errors." -ForegroundColor Yellow
        Write-Host "         Take a backup first if you have not already done so, using the utilities interface" -ForegroundColor Yellow
        Write-Host "         The default cluster editor (vi/nano) will open if you continue." -ForegroundColor Yellow
        Write-Host ""
        $confirm = Read-Host "Type YES to continue"
        if ($confirm -ne "YES") {
            Write-Host "Aborted." -ForegroundColor Cyan
            continue
        }

        # Will continue the iteration and execute the command with ssh
    }

    if ($null -ne $_onFinishedIteratingOptions) {
        & $_onFinishedIteratingOptions
    }

    if ($cmd -eq "logs-export") {
        ssh -t -o StrictHostKeyChecking=no -i "$sshKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup logs-export"

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $localDir = Join-Path $env:USERPROFILE "Documents\BattlegroupLogs\Battlegroup_$timestamp"
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        Write-Host ""
        Write-Host "Downloading log files..." -ForegroundColor Cyan
        $tarPath = Join-Path $env:TEMP "dune-bg-logs.tar.gz"
        $proc = Start-Process -FilePath "ssh" -ArgumentList @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "LogLevel=QUIET",
            "-i", "`"$sshKey`"",
            "dune@$ip",
            "tar -czf - -C /tmp/dune-bg-logs ."
        ) -RedirectStandardOutput $tarPath -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "Error: Failed to download log files." -ForegroundColor Red
            Remove-Item $tarPath -ErrorAction SilentlyContinue
            continue
        }
        tar -xzf $tarPath -C $localDir
        Remove-Item $tarPath
        Write-Host "Logs saved to: $localDir" -ForegroundColor Green
    } elseif ($cmd -eq "operator-logs-export") {
        ssh -t -o StrictHostKeyChecking=no -i "$sshKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup operator-logs-export"

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $localDir = Join-Path $env:USERPROFILE "Documents\OperatorLogs\Operators_$timestamp"
        New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        Write-Host ""
        Write-Host "Downloading operator log files..." -ForegroundColor Cyan
        $tarPath = Join-Path $env:TEMP "dune-operator-logs.tar.gz"
        $proc = Start-Process -FilePath "ssh" -ArgumentList @(
            "-o", "StrictHostKeyChecking=no",
            "-o", "LogLevel=QUIET",
            "-i", "`"$sshKey`"",
            "dune@$ip",
            "tar -czf - -C /tmp/dune-operator-logs ."
        ) -RedirectStandardOutput $tarPath -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "Error: Failed to download operator log files." -ForegroundColor Red
            Remove-Item $tarPath -ErrorAction SilentlyContinue
            continue
        }
        tar -xzf $tarPath -C $localDir
        Remove-Item $tarPath
        Write-Host "Operator logs saved to: $localDir" -ForegroundColor Green
    } else {
        ssh -t -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" "/home/dune/.dune/bin/battlegroup $cmd"
    }

    if ($cmd -eq "start" -or $cmd -eq "restart") {
        $resolvedDirectorPort = $null
        $elapsed = 0
        $timeout = 60
        while (-not $resolvedDirectorPort -and $elapsed -lt $timeout)
        {
            $directorNodePort = ssh -o StrictHostKeyChecking=no -o LogLevel=QUIET -i "$sshKey" "dune@$ip" `
                "sudo kubectl get svc -A -o jsonpath='{.items[*].spec.ports[?(@.port==11717)].nodePort}' 2>&1"
            if ($directorNodePort -match '^\d+$')
            {
                $resolvedDirectorPort = $directorNodePort.Trim()
            }
            if (-not $resolvedDirectorPort)
            {
                Start-Sleep -Seconds 5
                $elapsed += 5
            }
        }
        if (!$resolvedDirectorPort)
        {
            Write-Warning "Could not determine Director port from battlegroup after $timeout seconds."
        }
        else {
            $firstDetection = -not $directorPort
            $directorPort = $resolvedDirectorPort
            if ($firstDetection -and $null -ne $_onDirectorPortDetected) {
                & $_onDirectorPortDetected
            }
        }
    }

    if ($null -ne $_onBattlegroupStart -and ($cmd -eq "start" -or $cmd -eq "restart")) {
        & $_onBattlegroupStart
    }
}
