# Helper functions for controlling the web-admin panel from battlegroup.ps1.
# Dot-sourced by battlegroup.ps1. The web app lives at <repo>\web-admin and is
# a Node.js/Express server; here we start it hidden in the background, stop it,
# and report status (detected by which process is listening on its port).

# Directory of this helper (battlegroup-management), captured at dot-source time.
$script:WebAdminHelperDir = Split-Path -Parent $PSCommandPath

function Get-WebAdminPaths {
    $repoRoot = Split-Path -Parent $script:WebAdminHelperDir
    $root = Join-Path $repoRoot 'web-admin'
    [pscustomobject]@{
        Root          = $root
        ConfigDefault = Join-Path $root 'config\default.json'
        ConfigLocal   = Join-Path $root 'config\local.json'
        DataDir       = Join-Path $root 'data'
        Log           = Join-Path $root 'data\webserver.log'
        ErrLog        = Join-Path $root 'data\webserver.err.log'
        PidFile       = Join-Path $root 'data\webserver.pid'
        UsersFile     = Join-Path $root 'data\users.json'
        NodeModules   = Join-Path $root 'node_modules'
        Server        = Join-Path $root 'server\index.js'
    }
}

function Get-WebAdminConfig {
    # Reads port + publicOrigin from default.json, with local.json overriding.
    $p = Get-WebAdminPaths
    $port = 8477
    $publicOrigin = $null
    foreach ($cfg in @($p.ConfigDefault, $p.ConfigLocal)) {
        if (Test-Path $cfg) {
            try {
                $json = Get-Content $cfg -Raw | ConvertFrom-Json
                if ($json.PSObject.Properties.Name -contains 'port' -and $json.port) { $port = [int]$json.port }
                if ($json.PSObject.Properties.Name -contains 'publicOrigin' -and $json.publicOrigin) { $publicOrigin = [string]$json.publicOrigin }
            } catch { }
        }
    }
    [pscustomobject]@{ Port = $port; PublicOrigin = $publicOrigin }
}

function Get-WebAdminStatus {
    # Running = a 'node' process is listening on the configured port. This is
    # self-correcting across menu restarts (no reliance on a stored PID).
    $cfg = Get-WebAdminConfig
    $running = $false
    $procId = $null
    try {
        $conns = Get-NetTCPConnection -LocalPort $cfg.Port -State Listen -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq 'node') { $running = $true; $procId = $proc.Id; break }
        }
    } catch { }
    $url = if ($cfg.PublicOrigin) { $cfg.PublicOrigin } else { "http://localhost:$($cfg.Port)/" }
    [pscustomobject]@{ Running = $running; ProcessId = $procId; Port = $cfg.Port; Url = $url }
}

function Test-WebAdminHasAccounts {
    $p = Get-WebAdminPaths
    if (-not (Test-Path $p.UsersFile)) { return $false }
    try {
        $u = Get-Content $p.UsersFile -Raw | ConvertFrom-Json
        return (@($u).Count -gt 0)
    } catch { return $false }
}

function Start-WebAdmin {
    $p = Get-WebAdminPaths

    $status = Get-WebAdminStatus
    if ($status.Running) {
        Write-Host "Web admin is already running at $($status.Url)" -ForegroundColor Cyan
        return
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warning "Node.js is not installed or not on PATH. Install it from https://nodejs.org to run the web admin."
        return
    }
    if (-not (Test-Path $p.Server)) {
        Write-Warning "Web admin server not found at $($p.Server)."
        return
    }

    if (-not (Test-Path $p.NodeModules)) {
        Write-Host "Installing web admin dependencies (first run, this can take a minute)..." -ForegroundColor Cyan
        Push-Location $p.Root
        try { & npm install } finally { Pop-Location }
        if (-not (Test-Path $p.NodeModules)) {
            Write-Warning "npm install did not complete successfully. Check the output above."
            return
        }
    }

    if (-not (Test-Path $p.DataDir)) { New-Item -ItemType Directory -Force -Path $p.DataDir | Out-Null }

    Write-Host "Starting web admin..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $node.Source -ArgumentList 'server/index.js' `
                          -WorkingDirectory $p.Root -WindowStyle Hidden `
                          -RedirectStandardOutput $p.Log -RedirectStandardError $p.ErrLog -PassThru
    Set-Content -Path $p.PidFile -Value $proc.Id -ErrorAction SilentlyContinue

    # Wait for it to start listening (up to ~10s).
    $ok = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if ((Get-WebAdminStatus).Running) { $ok = $true; break }
        if ($proc.HasExited) { break }
    }

    if ($ok) {
        $s = Get-WebAdminStatus
        Write-Host "Web admin started. Reachable at $($s.Url)" -ForegroundColor Green
        if (-not (Test-WebAdminHasAccounts)) {
            Write-Host "No web admin accounts exist yet. Use the 'web-admin-accounts' menu option to create one before anyone can log in." -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Web admin did not start listening on port $($p.Port). Check the logs:"
        Write-Warning "  $($p.Log)"
        Write-Warning "  $($p.ErrLog)"
    }
}

function Stop-WebAdmin {
    $status = Get-WebAdminStatus
    if (-not $status.Running) {
        Write-Host "Web admin is not running." -ForegroundColor Cyan
        return
    }
    try {
        Stop-Process -Id $status.ProcessId -Force -ErrorAction Stop
        Write-Host "Web admin stopped." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to stop web admin (PID $($status.ProcessId)): $($_.Exception.Message)"
    }
    $p = Get-WebAdminPaths
    Remove-Item $p.PidFile -Force -ErrorAction SilentlyContinue
}

function Invoke-WebAdminCreateAdmin {
    # Runs the interactive create-admin CLI in the foreground so the user can
    # type a username/password.
    $p = Get-WebAdminPaths
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Warning "Node.js is not installed or not on PATH. Install it from https://nodejs.org first."
        return
    }
    if (-not (Test-Path $p.NodeModules)) {
        Write-Host "Installing web admin dependencies (first run)..." -ForegroundColor Cyan
        Push-Location $p.Root
        try { & npm install } finally { Pop-Location }
    }
    Write-Host ""
    Push-Location $p.Root
    try { & npm run create-admin } finally { Pop-Location }
    Write-Host ""
}
