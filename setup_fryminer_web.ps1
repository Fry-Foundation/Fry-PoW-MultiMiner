#Requires -RunAsAdministrator
<#
.SYNOPSIS
    FryMiner Setup - PowerShell Version for Windows
    Multi-cryptocurrency CPU miner with web interface

.DESCRIPTION
    This script sets up a multi-coin CPU mining environment on Windows with:
    - Support for 35+ cryptocurrencies
    - Web-based configuration interface
    - Automatic 2% dev fee (49 min user / 1 min dev cycling)
    - XMRig, XLArig, and cpuminer-multi support

.NOTES
    DEV FEE DISCLOSURE: FryMiner includes a 2% dev fee to support continued
    development and maintenance. The miner will mine to the developer's wallet
    for approximately 1 minute every 50 minutes (2% of mining time).

    For RandomX-based coins (XMR, Zephyr, Salvium, Yadacoin, Aeon, Unmineable),
    the dev fee is routed through Scala mining for better consolidation.

    Thank you for supporting open source development!
#>

param(
    [switch]$UpdateMode,
    [switch]$SkipInstall,
    [int]$Port = 8080
)

# =============================================================================
# DEV FEE CONFIGURATION (2%)
# Dev fee is time-based: mines for dev wallet 2% of the time
# Cycle: 49 minutes user -> 1 minute dev (repeating)
# =============================================================================
$Script:DEV_FEE_PERCENT = 2
$Script:DEV_FEE_CYCLE_MINUTES = 50
$Script:DEV_FEE_USER_MINUTES = 49
$Script:DEV_FEE_DEV_MINUTES = 1

# Dev wallet addresses by coin/algorithm type
$Script:DevWallets = @{
    XMR = "Ssy2BnsAcJUVZZ2kTiywf61bvYjvPosXzaBcaft9RSvaNNKsFRkcKbaWjMotjATkSbSmeSdX2DAxc1XxpcdxUBGd41oCwwfetG"
    LTC = "ltc1qrdc0wqzs3cwuhxxzkq2khepec2l3c6uhd8l9jy"
    BTC = "bc1qr6ldduupwn4dtqq4dwthv4vp3cg2dx7u3mcgva"
    DOGE = "D5nsUsiivbNv2nmuNE9x2ybkkCTEL4ceHj"
    DASH = "Xff5VZsVpFxpJYazyQ8hbabzjWAmq1TqPG"
    DCR = "DsTSHaQRwE9bibKtq5gCtaYZXSp7UhzMiWw"
    KDA = "k:05178b77e1141ca2319e66cab744e8149349b3f140a676624f231314d483f7a3"
    BCH = "qrsvjp5987h57x8e6tnv430gq4hnq4jy5vf8u5x4d9"
    DERO = "dero1qysrv5fp2xethzatpdf80umh8yu2nk404tc3cw2lwypgynj3qvhtgqq294092"
    ZEPH = "ZEPHsD5WFqKYHXEAqQLj9Nds4ZAS3KbK1Ht98SRy5u9d7Pp2gs6hPpw8UfA1iPgLdUgKpjXx72AjFN1QizwKY2SbXgMzEiQohBn"
    SCALA = "Ssy2BnsAcJUVZZ2kTiywf61bvYjvPosXzaBcaft9RSvaNNKsFRkcKbaWjMotjATkSbSmeSdX2DAxc1XxpcdxUBGd41oCwwfetG"
    VRSC = "RRhFqT2bfXQmsnqtyrVxikhy94KqnVf5nt"
    SAL = "SC1siGvtk7BQ7mkwsjXo57XF4y6SKsX547rfhzHJXGojeRSYoDWknqrJKeYHuMbqhbjSWYvxLppoMdCFjHHhVnrmZUxEc5QdYFj"
    YDA = "1NLFnpcykRcoAMKX35wyzZm2d8ChbQvXB3"
}

# Configuration paths
$Script:BASE = "$env:ProgramData\FryMiner"
$Script:MINERS_DIR = "$Script:BASE\miners"
$Script:CONFIG_FILE = "$Script:BASE\config.txt"
$Script:LOG_FILE = "$Script:BASE\logs\miner.log"
$Script:PID_FILE = "$Script:BASE\miner.pid"
$Script:STOP_FILE = "$Script:BASE\stopped"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[+] $Message" -ForegroundColor Green
    Add-Content -Path "$Script:BASE\logs\setup.log" -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-Administrator {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# ARCHITECTURE DETECTION
# =============================================================================

function Get-SystemArchitecture {
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        "AMD64" {
            Write-Log "Detected architecture: x86_64/AMD64"
            return "x86_64"
        }
        "x86" {
            Write-Log "Detected architecture: x86 32-bit"
            return "x86"
        }
        "ARM64" {
            Write-Log "Detected architecture: ARM64"
            return "arm64"
        }
        default {
            Write-Warning-Custom "Unknown architecture: $arch"
            return "x86_64"
        }
    }
}

# =============================================================================
# DIRECTORY SETUP
# =============================================================================

function Initialize-Directories {
    Write-Log "Creating directory structure..."

    $dirs = @(
        $Script:BASE,
        $Script:MINERS_DIR,
        "$Script:BASE\logs",
        "$Script:BASE\output",
        "$Script:BASE\cgi-bin",
        "$Script:BASE\www"
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Write-Log "Directories created at $Script:BASE"
}

# =============================================================================
# DEPENDENCY INSTALLATION
# =============================================================================

function Install-Dependencies {
    Write-Log "Checking dependencies..."

    # Check for Python (needed for web server)
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        $python = Get-Command python3 -ErrorAction SilentlyContinue
    }

    if (-not $python) {
        Write-Warning-Custom "Python not found. Please install Python 3.x from https://python.org"
        Write-Warning-Custom "Make sure to check 'Add Python to PATH' during installation"
    } else {
        Write-Log "Python found: $($python.Source)"
    }

    # Check for 7-Zip or built-in extraction
    $7zip = Get-Command 7z -ErrorAction SilentlyContinue
    if (-not $7zip) {
        Write-Log "7-Zip not found, will use built-in extraction"
    }

    Write-Log "Dependency check complete"
}

# =============================================================================
# MINING OPTIMIZATIONS
# =============================================================================

function Set-MiningOptimizations {
    Write-Log "Applying mining optimizations..."

    # Set process priority for mining
    Write-Log "  Setting high performance power plan..."
    try {
        $powerPlan = powercfg -getactivescheme
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null  # High Performance GUID
        Write-Log "  Power plan set to High Performance"
    } catch {
        Write-Warning-Custom "  Could not set power plan"
    }

    # Enable large pages privilege (requires admin)
    Write-Log "  Note: For best RandomX performance, enable 'Lock Pages in Memory' privilege"
    Write-Log "  Run: secpol.msc -> Local Policies -> User Rights Assignment -> Lock pages in memory"

    Write-Log "Mining optimizations applied"
}

# =============================================================================
# MINER INSTALLATION - XMRIG
# =============================================================================

function Install-XMRig {
    Write-Log "=== Installing XMRig ==="

    $xmrigPath = "$Script:MINERS_DIR\xmrig.exe"

    # Check if already installed and working
    if (Test-Path $xmrigPath) {
        try {
            $version = & $xmrigPath --version 2>&1 | Select-Object -First 1
            if ($version -match "XMRig") {
                Write-Log "XMRig already installed: $version"
                return $true
            }
        } catch { }
    }

    $arch = Get-SystemArchitecture

    Write-Log "Downloading XMRig for $arch..."

    $downloadUrl = switch ($arch) {
        "x86_64" { "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win64.zip" }
        "x86" { "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win32.zip" }
        default { "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win64.zip" }
    }

    $zipPath = "$Script:MINERS_DIR\xmrig.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

        Write-Log "Extracting XMRig..."
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\xmrig_temp" -Force

        # Find and move the executable
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\xmrig_temp" -Recurse -Filter "xmrig.exe" | Select-Object -First 1
        if ($exeFile) {
            Move-Item -Path $exeFile.FullName -Destination $xmrigPath -Force
            Write-Log "XMRig installed successfully"
        }

        # Cleanup
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\xmrig_temp" -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    } catch {
        Write-Error-Custom "Failed to install XMRig: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - XLARIG
# =============================================================================

function Install-XLArig {
    Write-Log "=== Installing XLArig (Scala miner) ==="

    $xlarigPath = "$Script:MINERS_DIR\xlarig.exe"

    # Check if already installed
    if (Test-Path $xlarigPath) {
        try {
            $version = & $xlarigPath --version 2>&1 | Select-Object -First 1
            if ($version) {
                Write-Log "XLArig already installed"
                return $true
            }
        } catch { }
    }

    $arch = Get-SystemArchitecture
    $version = "5.2.4"

    Write-Log "Downloading XLArig v$version..."

    $downloadUrl = switch ($arch) {
        "x86_64" { "https://github.com/scala-network/XLArig/releases/download/v$version/XLArig-v$version-win64.zip" }
        default { "https://github.com/scala-network/XLArig/releases/download/v$version/XLArig-v$version-win64.zip" }
    }

    $zipPath = "$Script:MINERS_DIR\xlarig.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

        Write-Log "Extracting XLArig..."
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\xlarig_temp" -Force

        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\xlarig_temp" -Recurse -Filter "xlarig.exe" | Select-Object -First 1
        if ($exeFile) {
            Move-Item -Path $exeFile.FullName -Destination $xlarigPath -Force
            Write-Log "XLArig installed successfully"
        }

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\xlarig_temp" -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    } catch {
        Write-Error-Custom "Failed to install XLArig: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - CPUMINER
# =============================================================================

function Install-CPUMiner {
    Write-Log "=== Installing cpuminer-multi ==="

    $cpuminerPath = "$Script:MINERS_DIR\cpuminer.exe"

    if (Test-Path $cpuminerPath) {
        try {
            $version = & $cpuminerPath --version 2>&1 | Select-Object -First 1
            if ($version) {
                Write-Log "cpuminer already installed: $version"
                return $true
            }
        } catch { }
    }

    Write-Log "Downloading cpuminer-multi..."

    # Using cpuminer-multi releases for Windows
    $downloadUrl = "https://github.com/tpruvot/cpuminer-multi/releases/download/v1.3.7-multi/cpuminer-multi-rel1.3.7-x64.zip"
    $zipPath = "$Script:MINERS_DIR\cpuminer.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

        Write-Log "Extracting cpuminer..."
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\cpuminer_temp" -Force

        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\cpuminer_temp" -Recurse -Filter "cpuminer*.exe" | Select-Object -First 1
        if ($exeFile) {
            Move-Item -Path $exeFile.FullName -Destination $cpuminerPath -Force
            Write-Log "cpuminer installed successfully"
        }

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\cpuminer_temp" -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    } catch {
        Write-Error-Custom "Failed to install cpuminer: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - CCMINER (VERUS)
# =============================================================================

function Install-CCMinerVerus {
    Write-Log "=== Installing ccminer-verus (Verus miner) ==="

    $ccminerPath = "$Script:MINERS_DIR\ccminer-verus.exe"

    if (Test-Path $ccminerPath) {
        try {
            $version = & $ccminerPath --version 2>&1 | Select-Object -First 1
            if ($version) {
                Write-Log "ccminer-verus already installed"
                return $true
            }
        } catch { }
    }

    $arch = Get-SystemArchitecture

    Write-Log "Downloading ccminer-verus for $arch..."

    # Using monkins1010/ccminer Verus2.2 release
    $downloadUrl = "https://github.com/monkins1010/ccminer/releases/download/v3.8.3a/ccminer_cpu_x86_64.zip"
    if ($arch -eq "arm64") {
        Write-Warning-Custom "ccminer-verus does not have ARM64 Windows builds. Verus mining may not be available."
        return $false
    }

    $zipPath = "$Script:MINERS_DIR\ccminer-verus.zip"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

        Write-Log "Extracting ccminer-verus..."
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\ccminer_temp" -Force

        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\ccminer_temp" -Recurse -Filter "ccminer*.exe" | Select-Object -First 1
        if ($exeFile) {
            Move-Item -Path $exeFile.FullName -Destination $ccminerPath -Force
            Write-Log "ccminer-verus installed successfully"
        }

        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\ccminer_temp" -Recurse -Force -ErrorAction SilentlyContinue

        return $true
    } catch {
        Write-Error-Custom "Failed to install ccminer-verus: $_"
        return $false
    }
}

# =============================================================================
# AUTO-UPDATE VIA TASK SCHEDULER
# =============================================================================

function Setup-AutoUpdate {
    Write-Log "Setting up automatic daily updates..."

    $updateScript = "$Script:BASE\auto_update.ps1"
    $versionFile = "$Script:BASE\version.txt"

    $updateContent = @"
# FryMiner Automatic Update Script for Windows
`$ErrorActionPreference = "Continue"

`$RepoApi = "https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main"
`$DownloadUrl = "https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_web.ps1"
`$VersionFile = "$Script:BASE\version.txt"
`$ConfigFile = "$Script:BASE\config.txt"
`$LogFile = "$Script:BASE\logs\update.log"
`$PidFile = "$Script:BASE\miner.pid"

function Write-UpdateLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path `$LogFile -Value "[`$timestamp] `$Message" -ErrorAction SilentlyContinue
}

Write-UpdateLog "=== Auto-update check started ==="

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    `$response = Invoke-RestMethod -Uri `$RepoApi -ErrorAction Stop
    `$remoteVer = `$response.sha.Substring(0, 7)
} catch {
    Write-UpdateLog "ERROR: Could not fetch remote version"
    exit 1
}

`$localVer = "none"
if (Test-Path `$VersionFile) {
    `$localVer = (Get-Content `$VersionFile -ErrorAction SilentlyContinue).Trim()
}

Write-UpdateLog "Local version: `$localVer"
Write-UpdateLog "Remote version: `$remoteVer"

if (`$remoteVer -eq `$localVer) {
    Write-UpdateLog "Already up to date"
    exit 0
}

Write-UpdateLog "Update available! Starting update process..."

# Check if miner was running
`$wasMining = `$false
`$minerProcesses = Get-Process -Name "xmrig", "xlarig", "cpuminer", "ccminer-verus" -ErrorAction SilentlyContinue
if (`$minerProcesses) {
    `$wasMining = `$true
    Write-UpdateLog "Stopping mining for update..."
    `$minerProcesses | Stop-Process -Force
    Start-Sleep -Seconds 3
}

# Backup config
if (Test-Path `$ConfigFile) {
    Copy-Item `$ConfigFile "`${ConfigFile}.backup" -Force
    Write-UpdateLog "Config backed up"
}

# Download and run update
`$tempScript = "`$env:TEMP\fryminer_update.ps1"
try {
    Invoke-WebRequest -Uri `$DownloadUrl -OutFile `$tempScript -UseBasicParsing
    Write-UpdateLog "Downloaded update, installing..."
    & powershell -ExecutionPolicy Bypass -File `$tempScript -UpdateMode -SkipInstall 2>&1 | Out-File -FilePath `$LogFile -Append
} catch {
    Write-UpdateLog "ERROR: Failed to download update"
    Remove-Item `$tempScript -Force -ErrorAction SilentlyContinue
    exit 1
}

# Restore config
if (Test-Path "`${ConfigFile}.backup") {
    Copy-Item "`${ConfigFile}.backup" `$ConfigFile -Force
    Write-UpdateLog "Config restored"
}

# Update version
`$remoteVer | Out-File -FilePath `$VersionFile -Encoding UTF8 -Force
Write-UpdateLog "Version updated to `$remoteVer"

# Restart mining if it was running
if (`$wasMining -and (Test-Path `$ConfigFile)) {
    Write-UpdateLog "Restarting mining..."
    `$config = @{}
    Get-Content `$ConfigFile | ForEach-Object {
        if (`$_ -match '(.+?)=(.+)') {
            `$config[`$Matches[1]] = `$Matches[2]
        }
    }
    `$scriptPath = "$Script:BASE\output\`$(`$config['miner'])\start.ps1"
    if (Test-Path `$scriptPath) {
        Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -File `$scriptPath" -WindowStyle Hidden
        Write-UpdateLog "Mining restarted"
    }
}

Write-UpdateLog "=== Update completed ==="
Remove-Item `$tempScript -Force -ErrorAction SilentlyContinue
"@

    $updateContent | Out-File -FilePath $updateScript -Encoding UTF8 -Force

    # Create Task Scheduler task for daily updates at 4 AM
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updateScript`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "4:00AM"
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        Unregister-ScheduledTask -TaskName "FryMinerAutoUpdate" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "FryMinerAutoUpdate" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "FryMiner daily auto-update" -ErrorAction Stop

        Write-Log "Auto-update configured (runs daily at 4 AM via Task Scheduler)"
    } catch {
        Write-Warning-Custom "Could not create scheduled task for auto-update: $_"
        Write-Log "Auto-update script saved to: $updateScript (run manually or add to Task Scheduler)"
    }

    # Save initial version
    if (-not (Test-Path $versionFile)) {
        "initial" | Out-File -FilePath $versionFile -Encoding UTF8 -Force
    }
}

# =============================================================================
# POOL CONFIGURATION
# =============================================================================

function Get-PoolForCoin {
    param([string]$Coin)

    $pools = @{
        "xmr" = "pool.supportxmr.com:3333"
        "scala" = "pool.scalaproject.io:3333"
        "aeon" = "aeon.herominers.com:10650"
        "dero" = "dero-node-sk.mysrv.cloud:10300"
        "zephyr" = "de.zephyr.herominers.com:1123"
        "salvium" = "de.salvium.herominers.com:1228"
        "yadacoin" = "pool.yadacoin.io:3333"
        "verus" = "pool.verus.io:9999"
        "arionum" = "aropool.com:80"
        "btc" = "pool.btc.com:3333"
        "ltc" = "stratum.aikapool.com:7900"
        "doge" = "prohashing.com:3332"
        "dash" = "dash.suprnova.cc:9989"
        "dcr" = "dcr.suprnova.cc:3252"
        "kda" = "pool.woolypooly.com:3112"
        "bch" = "pool.btc.com:3333"
        # Solo/Lottery pools - solopool.org (correct eu1/eu2/eu3 URLs)
        "btc-lotto" = "eu3.solopool.org:8005"
        "bch-lotto" = "eu2.solopool.org:8002"
        "ltc-lotto" = "eu3.solopool.org:8003"
        "doge-lotto" = "eu3.solopool.org:8003"
        "xmr-lotto" = "eu1.solopool.org:8010"
        "etc-lotto" = "eu1.solopool.org:8011"
        "ethw-lotto" = "eu2.solopool.org:8005"
        "kas-lotto" = "eu2.solopool.org:8008"
        "erg-lotto" = "eu1.solopool.org:8001"
        "rvn-lotto" = "eu1.solopool.org:8013"
        "zeph-lotto" = "eu2.solopool.org:8006"
        "dgb-lotto" = "eu1.solopool.org:8004"
        "xec-lotto" = "eu2.solopool.org:8013"
        "fb-lotto" = "eu3.solopool.org:8002"
        "bc2-lotto" = "eu3.solopool.org:8001"
        "xel-lotto" = "eu3.solopool.org:8004"
        "octa-lotto" = "eu2.solopool.org:8004"
        # Unmineable coins
        "shib" = "rx.unmineable.com:3333"
        "ada" = "rx.unmineable.com:3333"
        "sol" = "rx.unmineable.com:3333"
        "zec" = "rx.unmineable.com:3333"
        "etc" = "rx.unmineable.com:3333"
        "rvn" = "rx.unmineable.com:3333"
        "trx" = "rx.unmineable.com:3333"
        "vet" = "rx.unmineable.com:3333"
        "xrp" = "rx.unmineable.com:3333"
        "dot" = "rx.unmineable.com:3333"
        "matic" = "rx.unmineable.com:3333"
        "atom" = "rx.unmineable.com:3333"
        "link" = "rx.unmineable.com:3333"
        "xlm" = "rx.unmineable.com:3333"
        "algo" = "rx.unmineable.com:3333"
        "avax" = "rx.unmineable.com:3333"
        "near" = "rx.unmineable.com:3333"
        "ftm" = "rx.unmineable.com:3333"
        "one" = "rx.unmineable.com:3333"
    }

    if ($pools.ContainsKey($Coin.ToLower())) {
        return $pools[$Coin.ToLower()]
    }

    # Default to Unmineable for other coins
    return "rx.unmineable.com:3333"
}

function Get-AlgorithmForCoin {
    param([string]$Coin)

    $algorithms = @{
        # RandomX coins (XMRig)
        "xmr" = @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false }
        "xmr-lotto" = @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false }
        "aeon" = @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false }
        "zephyr" = @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false }
        "salvium" = @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false }
        "yadacoin" = @{ Algo = "rx/yada"; UseCpuminer = $false; UseXlarig = $false }
        # Scala (XLArig with Panthera)
        "scala" = @{ Algo = "panthera"; UseCpuminer = $false; UseXlarig = $true }
        # Other XMRig coins
        "dero" = @{ Algo = "astrobwt"; UseCpuminer = $false; UseXlarig = $false }
        # cpuminer coins
        "verus" = @{ Algo = "verushash"; UseCpuminer = $false; UseXlarig = $false; UseCCMiner = $true }
        "arionum" = @{ Algo = "argon2d4096"; UseCpuminer = $true; UseXlarig = $false }
        # SHA256d coins
        "btc" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "btc-lotto" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "bch" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "bch-lotto" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "dgb-lotto" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "xec-lotto" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "fb-lotto" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        "bc2-lotto" = @{ Algo = "sha256d"; UseCpuminer = $true; UseXlarig = $false }
        # Scrypt coins
        "ltc" = @{ Algo = "scrypt"; UseCpuminer = $true; UseXlarig = $false }
        "ltc-lotto" = @{ Algo = "scrypt"; UseCpuminer = $true; UseXlarig = $false }
        "doge" = @{ Algo = "scrypt"; UseCpuminer = $true; UseXlarig = $false }
        "doge-lotto" = @{ Algo = "scrypt"; UseCpuminer = $true; UseXlarig = $false }
        # Other cpuminer coins
        "dash" = @{ Algo = "x11"; UseCpuminer = $true; UseXlarig = $false }
        "dcr" = @{ Algo = "decred"; UseCpuminer = $true; UseXlarig = $false }
        "kda" = @{ Algo = "blake2s"; UseCpuminer = $true; UseXlarig = $false }
        # Zephyr lottery (RandomX)
        "zeph-lotto" = @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false }
        # GPU-only coins (noted for reference - not CPU mineable)
        "etc-lotto" = @{ Algo = "etchash"; UseCpuminer = $false; UseXlarig = $false; IsGPUOnly = $true }
        "ethw-lotto" = @{ Algo = "ethash"; UseCpuminer = $false; UseXlarig = $false; IsGPUOnly = $true }
        "kas-lotto" = @{ Algo = "kheavyhash"; UseCpuminer = $false; UseXlarig = $false; IsGPUOnly = $true }
        "erg-lotto" = @{ Algo = "autolykos2"; UseCpuminer = $false; UseXlarig = $false; IsGPUOnly = $true }
        "rvn-lotto" = @{ Algo = "kawpow"; UseCpuminer = $false; UseXlarig = $false; IsGPUOnly = $true }
        "xel-lotto" = @{ Algo = "xelishash"; UseCpuminer = $false; UseXlarig = $false }
        "octa-lotto" = @{ Algo = "ethash"; UseCpuminer = $false; UseXlarig = $false; IsGPUOnly = $true }
    }

    if ($algorithms.ContainsKey($Coin.ToLower())) {
        return $algorithms[$Coin.ToLower()]
    }

    # Default for Unmineable coins (RandomX)
    return @{ Algo = "rx/0"; UseCpuminer = $false; UseXlarig = $false; IsUnmineable = $true }
}

# =============================================================================
# MINING CYCLE SCRIPT GENERATION
# =============================================================================

function New-MiningScript {
    param(
        [string]$Coin,
        [string]$Wallet,
        [string]$Worker,
        [int]$Threads,
        [string]$Pool,
        [string]$Password = "x"
    )

    $algoInfo = Get-AlgorithmForCoin -Coin $Coin
    $algo = $algoInfo.Algo
    $useCpuminer = $algoInfo.UseCpuminer
    $useXlarig = $algoInfo.UseXlarig
    $useCCMiner = $algoInfo.UseCCMiner
    $isUnmineable = $algoInfo.IsUnmineable

    if ([string]::IsNullOrEmpty($Pool)) {
        $Pool = Get-PoolForCoin -Coin $Coin
    }

    # Determine dev wallet
    $devWallet = $Script:DevWallets.SCALA
    $devUseScala = $true
    $devPool = "pool.scalaproject.io:3333"

    switch ($Coin.ToLower()) {
        "ltc" { $devWallet = $Script:DevWallets.LTC; $devUseScala = $false }
        "btc" { $devWallet = $Script:DevWallets.BTC; $devUseScala = $false }
        "doge" { $devWallet = $Script:DevWallets.DOGE; $devUseScala = $false }
        "dash" { $devWallet = $Script:DevWallets.DASH; $devUseScala = $false }
        "dcr" { $devWallet = $Script:DevWallets.DCR; $devUseScala = $false }
        "kda" { $devWallet = $Script:DevWallets.KDA; $devUseScala = $false }
        "bch" { $devWallet = $Script:DevWallets.BCH; $devUseScala = $false }
        "dero" { $devWallet = $Script:DevWallets.DERO; $devUseScala = $false }
        "scala" { $devWallet = $Script:DevWallets.SCALA; $devUseScala = $false }
        "verus" { $devWallet = $Script:DevWallets.VRSC; $devUseScala = $false }
    }

    # For Unmineable, prepend coin ticker
    $userWalletFormatted = $Wallet
    if ($isUnmineable -and $Wallet -notmatch ":") {
        $userWalletFormatted = "$($Coin.ToUpper()):$Wallet"
    }

    $scriptDir = "$Script:BASE\output\$Coin"
    if (-not (Test-Path $scriptDir)) {
        New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
    }

    $scriptPath = "$scriptDir\start.ps1"

    $scriptContent = @"
# FryMiner Start Script - $Coin
# Generated: $(Get-Date)
# Dev fee: 2% (1 min per 50 min cycle)

`$ErrorActionPreference = "Continue"

# Configuration
`$LogFile = "$Script:LOG_FILE"
`$StopFile = "$Script:STOP_FILE"
`$PidFile = "$Script:PID_FILE"
`$MinersDir = "$Script:MINERS_DIR"

# User configuration
`$UserWallet = "$userWalletFormatted"
`$UserPassword = "$Password"
`$Worker = "$Worker"
`$Threads = $Threads
`$Pool = "$Pool"
`$Algo = "$algo"

# Strip any existing protocol prefix from pool URLs (stratum, http, https)
`$Pool = `$Pool -replace '^stratum\+tcp://', '' -replace '^stratum\+ssl://', '' -replace '^stratum://', '' -replace '^https?://', ''

# Dev configuration
`$DevWallet = "$devWallet"
`$DevPool = "$devPool"
`$DevPool = `$DevPool -replace '^stratum\+tcp://', '' -replace '^stratum\+ssl://', '' -replace '^stratum://', '' -replace '^https?://', ''
`$DevUseScala = `$$devUseScala
`$UseCpuminer = `$$useCpuminer
`$UseXlarig = `$$useXlarig
`$UseCCMiner = `$$useCCMiner

# Timing
`$UserMinutes = $Script:DEV_FEE_USER_MINUTES
`$DevMinutes = $Script:DEV_FEE_DEV_MINUTES

function Write-MinerLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path `$LogFile -Value "[`$timestamp] `$Message"
}

function Stop-AllMiners {
    Get-Process -Name "xmrig", "xlarig", "cpuminer", "ccminer-verus" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# Remove stop marker
Remove-Item -Path `$StopFile -Force -ErrorAction SilentlyContinue

Write-MinerLog "========================================"
Write-MinerLog "Starting mining session"
Write-MinerLog "Coin: $Coin"
Write-MinerLog "Pool: $Pool"
Write-MinerLog "Algorithm: $algo"
Write-MinerLog "Wallet: $userWalletFormatted"
Write-MinerLog "Worker: $Worker"
Write-MinerLog "Threads: $Threads"
Write-MinerLog "Dev fee: 2% (1 min per 50 min cycle)"
Write-MinerLog "========================================"

# Main mining loop
while (`$true) {
    # Check if stopped by user
    if (Test-Path `$StopFile) {
        Write-MinerLog "Mining stopped by user"
        Stop-AllMiners
        exit 0
    }

    # ========== USER MINING (98% - 49 minutes) ==========
    Write-MinerLog "Mining for user wallet..."

    if (`$UseXlarig) {
        `$minerPath = "`$MinersDir\xlarig.exe"
        `$minerArgs = "-o `$Pool -u `$UserWallet.`$Worker -p `$UserPassword --threads=`$Threads -a panthera --no-color --donate-level=0"
    } elseif (`$UseCCMiner) {
        `$minerPath = "`$MinersDir\ccminer-verus.exe"
        `$minerArgs = "-a verus -o stratum+tcp://`$Pool -u `$UserWallet.`$Worker -p `$UserPassword -t `$Threads"
    } elseif (`$UseCpuminer) {
        `$minerPath = "`$MinersDir\cpuminer.exe"
        `$minerArgs = "--algo=`$Algo -o stratum+tcp://`$Pool -u `$UserWallet.`$Worker -p `$UserPassword --threads=`$Threads"
    } else {
        `$minerPath = "`$MinersDir\xmrig.exe"
        `$minerArgs = "-o `$Pool -u `$UserWallet.`$Worker -p `$UserPassword --threads=`$Threads -a `$Algo --no-color --donate-level=0"
    }

    Write-MinerLog "Starting: `$minerPath `$minerArgs"
    `$process = Start-Process -FilePath `$minerPath -ArgumentList `$minerArgs -PassThru -NoNewWindow
    `$process.Id | Out-File -FilePath `$PidFile -Force

    # Wait for user mining period (49 minutes)
    `$waitSeconds = `$UserMinutes * 60
    `$waited = 0
    while (`$waited -lt `$waitSeconds) {
        if (Test-Path `$StopFile) {
            Stop-AllMiners
            exit 0
        }
        if (`$process.HasExited) {
            Write-MinerLog "Miner process died, restarting cycle..."
            break
        }
        Start-Sleep -Seconds 10
        `$waited += 10
    }

    Stop-AllMiners

    # Check again if stopped
    if (Test-Path `$StopFile) {
        exit 0
    }

    # ========== DEV FEE MINING (2% - 1 minute) ==========
    Write-MinerLog "Dev fee mining (2%)..."

    if (`$DevUseScala) {
        `$minerPath = "`$MinersDir\xlarig.exe"
        `$minerArgs = "-o `$DevPool -u `$DevWallet.frydev -p x --threads=`$Threads -a panthera --no-color --donate-level=0"
    } elseif (`$UseCCMiner) {
        `$minerPath = "`$MinersDir\ccminer-verus.exe"
        `$minerArgs = "-a verus -o stratum+tcp://`$Pool -u `$DevWallet.frydev -p x -t `$Threads"
    } elseif (`$UseCpuminer) {
        `$minerPath = "`$MinersDir\cpuminer.exe"
        `$minerArgs = "--algo=`$Algo -o stratum+tcp://`$Pool -u `$DevWallet.frydev -p x --threads=`$Threads"
    } else {
        `$minerPath = "`$MinersDir\xmrig.exe"
        `$minerArgs = "-o `$Pool -u `$DevWallet.frydev -p x --threads=`$Threads -a `$Algo --no-color --donate-level=0"
    }

    Write-MinerLog "Dev mining: `$minerPath"
    `$process = Start-Process -FilePath `$minerPath -ArgumentList `$minerArgs -PassThru -NoNewWindow

    # Wait for dev mining period (1 minute)
    `$waitSeconds = `$DevMinutes * 60
    `$waited = 0
    while (`$waited -lt `$waitSeconds) {
        if (Test-Path `$StopFile) {
            Stop-AllMiners
            exit 0
        }
        if (`$process.HasExited) {
            break
        }
        Start-Sleep -Seconds 10
        `$waited += 10
    }

    Stop-AllMiners
}
"@

    $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

    # Save configuration
    @"
miner=$Coin
wallet=$Wallet
worker=$Worker
threads=$Threads
pool=$Pool
password=$Password
"@ | Out-File -FilePath $Script:CONFIG_FILE -Encoding UTF8 -Force

    Write-Log "Mining script created: $scriptPath"
    return $scriptPath
}

# =============================================================================
# WEB SERVER
# =============================================================================

function New-WebInterface {
    Write-Log "Creating web interface..."

    $wwwPath = "$Script:BASE\www"

    # Create main HTML page
    $htmlContent = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FryMiner - CPU Mining Control Panel</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #eee;
        }
        .container { max-width: 900px; margin: 0 auto; padding: 20px; }
        h1 {
            text-align: center;
            padding: 20px;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            font-size: 2.5em;
        }
        .subtitle { text-align: center; color: #888; margin-bottom: 30px; }

        .tabs { display: flex; gap: 5px; margin-bottom: 20px; }
        .tab {
            flex: 1;
            padding: 15px;
            background: #2a2a4a;
            border: none;
            color: #888;
            cursor: pointer;
            border-radius: 10px 10px 0 0;
            transition: all 0.3s;
        }
        .tab:hover { background: #3a3a5a; color: #fff; }
        .tab.active { background: #4a4a6a; color: #00d4ff; }

        .panel {
            background: #2a2a4a;
            padding: 30px;
            border-radius: 0 0 15px 15px;
            display: none;
        }
        .panel.active { display: block; }

        .form-group { margin-bottom: 20px; }
        label { display: block; margin-bottom: 8px; color: #aaa; }
        input, select {
            width: 100%;
            padding: 12px;
            border: 2px solid #4a4a6a;
            background: #1a1a2e;
            color: #fff;
            border-radius: 8px;
            font-size: 16px;
        }
        input:focus, select:focus {
            outline: none;
            border-color: #00d4ff;
        }

        .btn {
            padding: 15px 30px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            font-weight: bold;
            transition: all 0.3s;
        }
        .btn-primary {
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            color: #fff;
        }
        .btn-primary:hover { transform: translateY(-2px); box-shadow: 0 5px 20px rgba(0,212,255,0.4); }
        .btn-danger { background: #e74c3c; color: #fff; }
        .btn-success { background: #27ae60; color: #fff; }

        .status-card {
            background: #1a1a2e;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 10px;
        }
        .status-running { background: #27ae60; box-shadow: 0 0 10px #27ae60; }
        .status-stopped { background: #e74c3c; }

        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
        .stat-box {
            background: #1a1a2e;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .stat-value { font-size: 2em; color: #00d4ff; }
        .stat-label { color: #888; margin-top: 5px; }

        .dev-fee-notice {
            background: rgba(255, 193, 7, 0.1);
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 14px;
            color: #ffc107;
        }

        .coin-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px; margin-bottom: 20px; }
        .coin-btn {
            padding: 15px;
            background: #1a1a2e;
            border: 2px solid #4a4a6a;
            color: #fff;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s;
        }
        .coin-btn:hover { border-color: #00d4ff; }
        .coin-btn.selected { border-color: #00d4ff; background: rgba(0,212,255,0.1); }

        .log-output {
            background: #0a0a1e;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Consolas', monospace;
            font-size: 13px;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>FryMiner</h1>
        <p class="subtitle">Multi-Coin CPU Mining Control Panel (Windows)</p>

        <div class="tabs">
            <button class="tab active" onclick="showTab('configure')">Configure</button>
            <button class="tab" onclick="showTab('monitor')">Monitor</button>
            <button class="tab" onclick="showTab('stats')">Statistics</button>
        </div>

        <div id="configure" class="panel active">
            <div class="dev-fee-notice">
                <strong>Dev Fee Notice:</strong> FryMiner includes a 2% dev fee to support development.
                The miner runs for 49 minutes on your wallet, then 1 minute for the dev (cycling continuously).
            </div>

            <h3 style="margin-bottom: 15px;">Select Cryptocurrency</h3>
            <div class="coin-grid" id="coinGrid">
                <!-- Popular coins -->
                <button class="coin-btn" data-coin="xmr">XMR</button>
                <button class="coin-btn" data-coin="scala">SCALA</button>
                <button class="coin-btn" data-coin="zephyr">ZEPH</button>
                <button class="coin-btn" data-coin="salvium">SAL</button>
                <button class="coin-btn" data-coin="dero">DERO</button>
                <button class="coin-btn" data-coin="verus">VRSC</button>
                <button class="coin-btn" data-coin="aeon">AEON</button>
                <button class="coin-btn" data-coin="yadacoin">YDA</button>
                <button class="coin-btn" data-coin="arionum">ARO</button>
                <!-- SHA256/Scrypt -->
                <button class="coin-btn" data-coin="btc">BTC</button>
                <button class="coin-btn" data-coin="ltc">LTC</button>
                <button class="coin-btn" data-coin="doge">DOGE</button>
                <button class="coin-btn" data-coin="bch">BCH</button>
                <button class="coin-btn" data-coin="dash">DASH</button>
                <button class="coin-btn" data-coin="dcr">DCR</button>
                <button class="coin-btn" data-coin="kda">KDA</button>
                <!-- Solo/Lottery Mining (solopool.org) -->
                <button class="coin-btn" data-coin="btc-lotto">BTC Solo</button>
                <button class="coin-btn" data-coin="bch-lotto">BCH Solo</button>
                <button class="coin-btn" data-coin="ltc-lotto">LTC Solo</button>
                <button class="coin-btn" data-coin="doge-lotto">DOGE Solo</button>
                <button class="coin-btn" data-coin="xmr-lotto">XMR Solo</button>
                <button class="coin-btn" data-coin="zeph-lotto">ZEPH Solo</button>
                <button class="coin-btn" data-coin="dgb-lotto">DGB Solo</button>
                <button class="coin-btn" data-coin="xec-lotto">XEC Solo</button>
                <button class="coin-btn" data-coin="fb-lotto">FB Solo</button>
                <button class="coin-btn" data-coin="etc-lotto">ETC Solo</button>
                <button class="coin-btn" data-coin="ethw-lotto">ETHW Solo</button>
                <button class="coin-btn" data-coin="kas-lotto">KAS Solo</button>
                <button class="coin-btn" data-coin="erg-lotto">ERG Solo</button>
                <button class="coin-btn" data-coin="rvn-lotto">RVN Solo</button>
                <button class="coin-btn" data-coin="bc2-lotto">BC2 Solo</button>
                <button class="coin-btn" data-coin="xel-lotto">XEL Solo</button>
                <button class="coin-btn" data-coin="octa-lotto">OCTA Solo</button>
                <!-- Unmineable tokens -->
                <button class="coin-btn" data-coin="shib">SHIB</button>
                <button class="coin-btn" data-coin="ada">ADA</button>
                <button class="coin-btn" data-coin="sol">SOL</button>
                <button class="coin-btn" data-coin="zec">ZEC</button>
                <button class="coin-btn" data-coin="etc">ETC</button>
                <button class="coin-btn" data-coin="rvn">RVN</button>
                <button class="coin-btn" data-coin="trx">TRX</button>
                <button class="coin-btn" data-coin="vet">VET</button>
                <button class="coin-btn" data-coin="xrp">XRP</button>
                <button class="coin-btn" data-coin="dot">DOT</button>
                <button class="coin-btn" data-coin="matic">MATIC</button>
                <button class="coin-btn" data-coin="atom">ATOM</button>
                <button class="coin-btn" data-coin="link">LINK</button>
                <button class="coin-btn" data-coin="xlm">XLM</button>
                <button class="coin-btn" data-coin="algo">ALGO</button>
                <button class="coin-btn" data-coin="avax">AVAX</button>
                <button class="coin-btn" data-coin="near">NEAR</button>
                <button class="coin-btn" data-coin="ftm">FTM</button>
                <button class="coin-btn" data-coin="one">ONE</button>
            </div>
            <div id="coinInfo" style="background: rgba(0, 212, 255, 0.1); border: 1px solid #00d4ff; padding: 10px; border-radius: 5px; margin-bottom: 15px; display: none;"></div>

            <form id="configForm">
                <input type="hidden" id="selectedCoin" name="miner" value="">

                <div class="form-group">
                    <label>Wallet Address</label>
                    <input type="text" id="wallet" name="wallet" placeholder="Enter your wallet address" required>
                </div>

                <div class="form-group">
                    <label>Worker Name</label>
                    <input type="text" id="worker" name="worker" value="FryWorker" placeholder="Worker name">
                </div>

                <div class="form-group">
                    <label>CPU Threads</label>
                    <input type="number" id="threads" name="threads" value="4" min="1" max="256">
                </div>

                <div class="form-group">
                    <label>Pool (leave empty for default)</label>
                    <input type="text" id="pool" name="pool" placeholder="pool.example.com:3333">
                </div>

                <div class="form-group">
                    <label>Pool Password</label>
                    <input type="text" id="password" name="password" value="x" placeholder="x">
                </div>

                <div style="display: flex; gap: 10px;">
                    <button type="submit" class="btn btn-primary">Save & Start Mining</button>
                    <button type="button" class="btn btn-danger" onclick="stopMining()">Stop Mining</button>
                </div>
            </form>
        </div>

        <div id="monitor" class="panel">
            <div class="status-card">
                <h3><span class="status-indicator" id="statusIndicator"></span> Mining Status: <span id="statusText">Checking...</span></h3>
            </div>

            <h3 style="margin-bottom: 15px;">Live Log</h3>
            <div class="log-output" id="logOutput">Loading logs...</div>
        </div>

        <div id="stats" class="panel">
            <div class="stats-grid">
                <div class="stat-box">
                    <div class="stat-value" id="hashrate">--</div>
                    <div class="stat-label">Hashrate</div>
                </div>
                <div class="stat-box">
                    <div class="stat-value" id="shares">0/0</div>
                    <div class="stat-label">Accepted/Rejected</div>
                </div>
                <div class="stat-box">
                    <div class="stat-value" id="uptime">0h 0m</div>
                    <div class="stat-label">Uptime</div>
                </div>
                <div class="stat-box">
                    <div class="stat-value" id="temp">--°C</div>
                    <div class="stat-label">CPU Temp</div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let selectedCoin = '';
        let isLoadingConfig = false;

        // Default pools for each coin
        const defaultPools = {
            'xmr': 'pool.supportxmr.com:3333',
            'scala': 'pool.scalaproject.io:3333',
            'aeon': 'aeon.herominers.com:10650',
            'dero': 'dero-node-sk.mysrv.cloud:10300',
            'zephyr': 'de.zephyr.herominers.com:1123',
            'salvium': 'de.salvium.herominers.com:1228',
            'yadacoin': 'pool.yadacoin.io:3333',
            'verus': 'pool.verus.io:9999',
            'arionum': 'aropool.com:80',
            'btc': 'pool.btc.com:3333',
            'ltc': 'stratum.aikapool.com:7900',
            'doge': 'prohashing.com:3332',
            'bch': 'pool.btc.com:3333',
            'dash': 'dash.suprnova.cc:9989',
            'dcr': 'dcr.suprnova.cc:3252',
            'kda': 'pool.woolypooly.com:3112',
            // Solo/Lottery pools - solopool.org (correct eu1/eu2/eu3 URLs)
            'btc-lotto': 'eu3.solopool.org:8005',
            'bch-lotto': 'eu2.solopool.org:8002',
            'ltc-lotto': 'eu3.solopool.org:8003',
            'doge-lotto': 'eu3.solopool.org:8003',
            'xmr-lotto': 'eu1.solopool.org:8010',
            'etc-lotto': 'eu1.solopool.org:8011',
            'ethw-lotto': 'eu2.solopool.org:8005',
            'kas-lotto': 'eu2.solopool.org:8008',
            'erg-lotto': 'eu1.solopool.org:8001',
            'rvn-lotto': 'eu1.solopool.org:8013',
            'zeph-lotto': 'eu2.solopool.org:8006',
            'dgb-lotto': 'eu1.solopool.org:8004',
            'xec-lotto': 'eu2.solopool.org:8013',
            'fb-lotto': 'eu3.solopool.org:8002',
            'bc2-lotto': 'eu3.solopool.org:8001',
            'xel-lotto': 'eu3.solopool.org:8004',
            'octa-lotto': 'eu2.solopool.org:8004',
            // Unmineable coins
            'shib': 'rx.unmineable.com:3333',
            'ada': 'rx.unmineable.com:3333',
            'sol': 'rx.unmineable.com:3333',
            'zec': 'rx.unmineable.com:3333',
            'etc': 'rx.unmineable.com:3333',
            'rvn': 'rx.unmineable.com:3333',
            'trx': 'rx.unmineable.com:3333',
            'vet': 'rx.unmineable.com:3333',
            'xrp': 'rx.unmineable.com:3333',
            'dot': 'rx.unmineable.com:3333',
            'matic': 'rx.unmineable.com:3333',
            'atom': 'rx.unmineable.com:3333',
            'link': 'rx.unmineable.com:3333',
            'xlm': 'rx.unmineable.com:3333',
            'algo': 'rx.unmineable.com:3333',
            'avax': 'rx.unmineable.com:3333',
            'near': 'rx.unmineable.com:3333',
            'ftm': 'rx.unmineable.com:3333',
            'one': 'rx.unmineable.com:3333'
        };

        // Fixed pools (cannot be changed) - Unmineable coins only
        const fixedPools = ['shib', 'ada', 'sol', 'zec', 'etc', 'rvn', 'trx', 'vet', 'xrp', 'dot', 'matic', 'atom', 'link', 'xlm', 'algo', 'avax', 'near', 'ftm', 'one'];

        // Coin info messages
        const coinInfo = {
            'btc-lotto': 'Solo lottery mining on solopool.org - very low odds but winner takes full block reward!',
            'bch-lotto': 'Solo lottery mining on solopool.org - very low odds but winner takes full block reward!',
            'ltc-lotto': 'Solo lottery mining with LTC+DOGE merged mining on solopool.org! TIP: Add your DOGE address to receive DOGE rewards too.',
            'doge-lotto': 'Solo lottery mining with DOGE+LTC merged mining on solopool.org! TIP: Add your LTC address to receive LTC rewards too.',
            'xmr-lotto': 'Solo lottery mining on solopool.org - very low odds but winner takes full block reward!',
            'etc-lotto': 'Ethereum Classic solo lottery mining on solopool.org - GPU recommended (Etchash).',
            'ethw-lotto': 'EthereumPoW solo lottery mining on solopool.org - GPU recommended (Ethash).',
            'kas-lotto': 'Kaspa solo lottery mining on solopool.org - ASIC/GPU recommended (KHeavyHash).',
            'erg-lotto': 'Ergo solo lottery mining on solopool.org - GPU recommended (Autolykos2).',
            'rvn-lotto': 'Ravencoin solo lottery mining on solopool.org - GPU required (KAWPOW).',
            'zeph-lotto': 'Zephyr solo lottery mining on solopool.org - CPU mineable (RandomX).',
            'dgb-lotto': 'DigiByte solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
            'xec-lotto': 'eCash solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
            'fb-lotto': 'Fractal Bitcoin solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
            'bc2-lotto': 'Bitcoin II solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
            'xel-lotto': 'Xelis solo lottery mining on solopool.org - CPU/GPU mineable (XelisHash).',
            'octa-lotto': 'OctaSpace solo lottery mining on solopool.org - GPU recommended (Ethash).',
            'zephyr': 'Zephyr is a privacy-focused stablecoin protocol using RandomX.',
            'salvium': 'Salvium is a privacy blockchain with staking. Uses RandomX algorithm.'
        };

        // Tab switching
        function showTab(tabId) {
            document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            event.target.classList.add('active');

            if (tabId === 'monitor') updateLogs();
            if (tabId === 'stats') updateStats();
        }

        // Coin selection
        document.querySelectorAll('.coin-btn').forEach(btn => {
            btn.addEventListener('click', function() {
                document.querySelectorAll('.coin-btn').forEach(b => b.classList.remove('selected'));
                this.classList.add('selected');
                selectedCoin = this.dataset.coin;
                document.getElementById('selectedCoin').value = selectedCoin;

                const poolInput = document.getElementById('pool');
                const infoBox = document.getElementById('coinInfo');

                // Set pool value intelligently
                if (defaultPools[selectedCoin] && !isLoadingConfig) {
                    // Fixed pools (Unmineable) ALWAYS update and disable input
                    if (fixedPools.includes(selectedCoin)) {
                        poolInput.value = defaultPools[selectedCoin];
                        poolInput.disabled = true;
                    }
                    // Non-fixed pools only update if field is empty (preserve custom values)
                    else {
                        if (!poolInput.value) {
                            poolInput.value = defaultPools[selectedCoin];
                        }
                        poolInput.disabled = false;
                    }
                } else {
                    poolInput.disabled = fixedPools.includes(selectedCoin);
                }

                // Show coin info if available
                if (coinInfo[selectedCoin]) {
                    infoBox.innerHTML = coinInfo[selectedCoin];
                    infoBox.style.display = 'block';
                } else {
                    infoBox.style.display = 'none';
                }
            });
        });

        // Form submission
        document.getElementById('configForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            if (!selectedCoin) {
                alert('Please select a cryptocurrency first');
                return;
            }

            const formData = new FormData(this);
            try {
                const response = await fetch('/cgi-bin/save.cgi', {
                    method: 'POST',
                    body: formData
                });
                const result = await response.text();
                alert('Configuration saved! Mining started.');
            } catch (error) {
                alert('Error: ' + error.message);
            }
        });

        // Stop mining
        async function stopMining() {
            try {
                await fetch('/cgi-bin/stop.cgi');
                alert('Mining stopped');
            } catch (error) {
                alert('Error stopping miner');
            }
        }

        // Update logs
        async function updateLogs() {
            try {
                const response = await fetch('/cgi-bin/logs.cgi');
                const logs = await response.text();
                document.getElementById('logOutput').textContent = logs || 'No logs available';
            } catch (error) {
                document.getElementById('logOutput').textContent = 'Error loading logs';
            }
        }

        // Update stats
        async function updateStats() {
            try {
                const response = await fetch('/cgi-bin/stats.cgi');
                const stats = await response.json();
                document.getElementById('hashrate').textContent = stats.hashrate || '--';
                document.getElementById('shares').textContent = `${stats.accepted || 0}/${stats.rejected || 0}`;
                document.getElementById('uptime').textContent = stats.uptime || '0h 0m';
            } catch (error) {
                console.error('Stats error:', error);
            }
        }

        // Check status periodically
        async function checkStatus() {
            try {
                const response = await fetch('/cgi-bin/status.cgi');
                const status = await response.json();
                const indicator = document.getElementById('statusIndicator');
                const text = document.getElementById('statusText');

                if (status.running) {
                    indicator.className = 'status-indicator status-running';
                    text.textContent = 'Running';
                } else {
                    indicator.className = 'status-indicator status-stopped';
                    text.textContent = 'Stopped';
                }
            } catch (error) {
                document.getElementById('statusText').textContent = 'Unknown';
            }
        }

        // Load saved config
        async function loadConfig() {
            try {
                isLoadingConfig = true;
                const response = await fetch('/cgi-bin/load.cgi');
                const config = await response.json();
                if (config.wallet) document.getElementById('wallet').value = config.wallet;
                if (config.worker) document.getElementById('worker').value = config.worker;
                if (config.threads) document.getElementById('threads').value = config.threads;
                if (config.pool) document.getElementById('pool').value = config.pool;
                if (config.password) document.getElementById('password').value = config.password;
                if (config.miner) {
                    selectedCoin = config.miner;
                    document.getElementById('selectedCoin').value = config.miner;
                    document.querySelectorAll('.coin-btn').forEach(btn => {
                        if (btn.dataset.coin === config.miner) btn.classList.add('selected');
                    });
                    // Update pool input disabled state
                    const poolInput = document.getElementById('pool');
                    poolInput.disabled = fixedPools.includes(config.miner);
                    // Show coin info if available
                    const infoBox = document.getElementById('coinInfo');
                    if (coinInfo[config.miner]) {
                        infoBox.innerHTML = coinInfo[config.miner];
                        infoBox.style.display = 'block';
                    }
                }
                isLoadingConfig = false;
            } catch (error) {
                console.error('Load config error:', error);
                isLoadingConfig = false;
            }
        }

        // Initialize
        loadConfig();
        checkStatus();
        setInterval(checkStatus, 5000);
    </script>
</body>
</html>
'@

    $htmlContent | Out-File -FilePath "$wwwPath\index.html" -Encoding UTF8 -Force
    Write-Log "Web interface created"
}

function Start-WebServer {
    param([int]$Port = 8080)

    Write-Log "Starting web server on port $Port..."

    # Create a simple Python CGI server script
    $serverScript = @"
import http.server
import socketserver
import os
import json
import subprocess
import urllib.parse

PORT = $Port
BASE_DIR = r"$($Script:BASE)"
WWW_DIR = os.path.join(BASE_DIR, "www")
CONFIG_FILE = os.path.join(BASE_DIR, "config.txt")
LOG_FILE = os.path.join(BASE_DIR, "logs", "miner.log")
STOP_FILE = os.path.join(BASE_DIR, "stopped")
PID_FILE = os.path.join(BASE_DIR, "miner.pid")
MINERS_DIR = r"$($Script:MINERS_DIR)"

os.chdir(WWW_DIR)

class FryMinerHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/cgi-bin/status.cgi":
            self.send_cgi_response(self.get_status())
        elif self.path == "/cgi-bin/logs.cgi":
            self.send_text_response(self.get_logs())
        elif self.path == "/cgi-bin/stats.cgi":
            self.send_cgi_response(self.get_stats())
        elif self.path == "/cgi-bin/load.cgi":
            self.send_cgi_response(self.load_config())
        elif self.path == "/cgi-bin/stop.cgi":
            self.send_cgi_response(self.stop_mining())
        else:
            super().do_GET()

    def do_POST(self):
        if self.path == "/cgi-bin/save.cgi":
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')
            self.send_text_response(self.save_config(post_data))
        else:
            self.send_error(404)

    def send_cgi_response(self, data):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_text_response(self, text):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(text.encode())

    def get_status(self):
        running = False
        try:
            result = subprocess.run(['tasklist'], capture_output=True, text=True)
            if 'xmrig' in result.stdout.lower() or 'xlarig' in result.stdout.lower() or 'cpuminer' in result.stdout.lower() or 'ccminer' in result.stdout.lower():
                running = True
        except:
            pass
        return {"running": running, "crashed": False}

    def get_logs(self):
        try:
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, 'r') as f:
                    lines = f.readlines()
                    return ''.join(lines[-100:])
        except:
            pass
        return "No logs available"

    def get_stats(self):
        return {"hashrate": "--", "accepted": 0, "rejected": 0, "uptime": "0h 0m"}

    def load_config(self):
        config = {}
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    for line in f:
                        if '=' in line:
                            key, value = line.strip().split('=', 1)
                            config[key] = value
        except:
            pass
        return config

    def save_config(self, post_data):
        params = urllib.parse.parse_qs(post_data)
        miner = params.get('miner', [''])[0]
        wallet = params.get('wallet', [''])[0]
        worker = params.get('worker', ['FryWorker'])[0]
        threads = params.get('threads', ['4'])[0]
        pool = params.get('pool', [''])[0]
        password = params.get('password', ['x'])[0]

        # Save config
        with open(CONFIG_FILE, 'w') as f:
            f.write(f"miner={miner}\\n")
            f.write(f"wallet={wallet}\\n")
            f.write(f"worker={worker}\\n")
            f.write(f"threads={threads}\\n")
            f.write(f"pool={pool}\\n")
            f.write(f"password={password}\\n")

        # Start mining using PowerShell
        script_path = os.path.join(BASE_DIR, "output", miner, "start.ps1")
        if os.path.exists(script_path):
            # Stop existing miners first
            subprocess.run(['taskkill', '/F', '/IM', 'xmrig.exe'], capture_output=True)
            subprocess.run(['taskkill', '/F', '/IM', 'xlarig.exe'], capture_output=True)
            subprocess.run(['taskkill', '/F', '/IM', 'cpuminer.exe'], capture_output=True)
            subprocess.run(['taskkill', '/F', '/IM', 'ccminer-verus.exe'], capture_output=True)
            # Start new mining process
            subprocess.Popen(['powershell', '-ExecutionPolicy', 'Bypass', '-File', script_path],
                           creationflags=subprocess.CREATE_NEW_CONSOLE)

        return f"Configuration saved for {miner}!"

    def stop_mining(self):
        # Create stop marker
        with open(STOP_FILE, 'w') as f:
            f.write('stopped')
        # Kill miner processes
        subprocess.run(['taskkill', '/F', '/IM', 'xmrig.exe'], capture_output=True)
        subprocess.run(['taskkill', '/F', '/IM', 'xlarig.exe'], capture_output=True)
        subprocess.run(['taskkill', '/F', '/IM', 'cpuminer.exe'], capture_output=True)
        subprocess.run(['taskkill', '/F', '/IM', 'ccminer-verus.exe'], capture_output=True)
        return {"status": "stopped"}

with socketserver.TCPServer(("", PORT), FryMinerHandler) as httpd:
    print(f"FryMiner web server running on http://localhost:{PORT}")
    httpd.serve_forever()
"@

    $serverScript | Out-File -FilePath "$Script:BASE\webserver.py" -Encoding UTF8 -Force

    # Start the web server
    $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonPath) {
        $pythonPath = (Get-Command python3 -ErrorAction SilentlyContinue).Source
    }

    if ($pythonPath) {
        Start-Process -FilePath $pythonPath -ArgumentList "`"$Script:BASE\webserver.py`"" -WindowStyle Normal
        Write-Log "Web server started at http://localhost:$Port"
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " FryMiner Web Interface" -ForegroundColor Cyan
        Write-Host " Open your browser to:" -ForegroundColor Cyan
        Write-Host " http://localhost:$Port" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Cyan
    } else {
        Write-Error-Custom "Python not found. Please install Python to use the web interface."
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function Start-FryMinerSetup {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " FryMiner Setup - Windows Edition" -ForegroundColor Cyan
    Write-Host " Multi-Coin CPU Miner" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check admin
    if (-not (Test-Administrator)) {
        Write-Error-Custom "This script requires Administrator privileges."
        Write-Host "Please right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        exit 1
    }

    Write-Log "Starting FryMiner setup..."

    # Detect architecture
    $arch = Get-SystemArchitecture

    # Initialize directories
    Initialize-Directories

    # Install dependencies
    Install-Dependencies

    if (-not $SkipInstall) {
        # Apply optimizations
        Set-MiningOptimizations

        # Install miners
        Install-XMRig
        Install-XLArig
        Install-CPUMiner
        Install-CCMinerVerus
    }

    # Setup auto-update
    Setup-AutoUpdate

    # Create web interface
    New-WebInterface

    # Generate a default mining script for XMR as example
    New-MiningScript -Coin "xmr" -Wallet "YOUR_WALLET_HERE" -Worker "FryWorker" -Threads ([Environment]::ProcessorCount)

    # Start web server
    Start-WebServer -Port $Port

    Write-Host ""
    Write-Log "FryMiner setup complete!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Open http://localhost:$Port in your browser" -ForegroundColor White
    Write-Host "2. Select a cryptocurrency to mine" -ForegroundColor White
    Write-Host "3. Enter your wallet address" -ForegroundColor White
    Write-Host "4. Click 'Save & Start Mining'" -ForegroundColor White
    Write-Host ""
    Write-Host "Files installed to: $Script:BASE" -ForegroundColor Gray
    Write-Host ""
}

# Run setup
Start-FryMinerSetup
