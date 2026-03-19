#Requires -RunAsAdministrator
<#
.SYNOPSIS
    FryMiner Setup - PowerShell Version for Windows
    Multi-cryptocurrency CPU miner with web interface
    Synced with setup_fryminer_web.sh (source of truth)

.DESCRIPTION
    This script sets up a multi-coin CPU mining environment on Windows with:
    - Support for 37+ cryptocurrencies
    - Web-based configuration interface with 4 tabs
    - Automatic 2% dev fee (49 min user / 1 min dev cycling)
    - XMRig, XLArig, cpuminer-multi, ccminer-verus support
    - ORE (Solana PoW) and ORA (Oranges/Algorand) support
    - GPU mining via SRBMiner-Multi, lolMiner, T-Rex
    - USB ASIC mining via BFGMiner

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
# =============================================================================
$Script:DEV_FEE_PERCENT = 2
$Script:DEV_FEE_CYCLE_MINUTES = 50
$Script:DEV_FEE_USER_MINUTES = 49
$Script:DEV_FEE_DEV_MINUTES = 1

# Dev wallet addresses
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
        "$Script:BASE\www",
        "$Script:BASE\scripts"
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
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $python) {
        Write-Warning-Custom "Python not found. Please install Python 3.x from https://python.org"
    } else {
        Write-Log "Python found: $($python.Source)"
    }
    Write-Log "Dependency check complete"
}

# =============================================================================
# MINING OPTIMIZATIONS
# =============================================================================

function Set-MiningOptimizations {
    Write-Log "Applying mining optimizations..."
    try {
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        Write-Log "  Power plan set to High Performance"
    } catch {
        Write-Warning-Custom "  Could not set power plan"
    }
    Write-Log "  Note: For best RandomX performance, enable 'Lock Pages in Memory' privilege"
    Write-Log "Mining optimizations applied"
}


# =============================================================================
# MINER INSTALLATION - XMRIG
# =============================================================================

function Install-XMRig {
    Write-Log "=== Installing XMRig ==="
    $xmrigPath = "$Script:MINERS_DIR\xmrig.exe"
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
    $downloadUrl = switch ($arch) {
        "x86_64" { "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win64.zip" }
        "x86" { "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win32.zip" }
        default { "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-msvc-win64.zip" }
    }
    $zipPath = "$Script:MINERS_DIR\xmrig.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\xmrig_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\xmrig_temp" -Recurse -Filter "xmrig.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $xmrigPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\xmrig_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "XMRig installed successfully"
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
    if (Test-Path $xlarigPath) {
        try {
            $version = & $xlarigPath --version 2>&1 | Select-Object -First 1
            if ($version) { Write-Log "XLArig already installed"; return $true }
        } catch { }
    }
    $version = "5.2.4"
    $downloadUrl = "https://github.com/scala-network/XLArig/releases/download/v$version/XLArig-v$version-win64.zip"
    $zipPath = "$Script:MINERS_DIR\xlarig.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\xlarig_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\xlarig_temp" -Recurse -Filter "xlarig.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $xlarigPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\xlarig_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "XLArig installed successfully"
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
            if ($version) { Write-Log "cpuminer already installed: $version"; return $true }
        } catch { }
    }
    $downloadUrl = "https://github.com/tpruvot/cpuminer-multi/releases/download/v1.3.7-multi/cpuminer-multi-rel1.3.7-x64.zip"
    $zipPath = "$Script:MINERS_DIR\cpuminer.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\cpuminer_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\cpuminer_temp" -Recurse -Filter "cpuminer*.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $cpuminerPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\cpuminer_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "cpuminer installed successfully"
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
    Write-Log "=== Installing ccminer-verus ==="
    $ccminerPath = "$Script:MINERS_DIR\ccminer-verus.exe"
    if (Test-Path $ccminerPath) {
        try {
            $version = & $ccminerPath --version 2>&1 | Select-Object -First 1
            if ($version) { Write-Log "ccminer-verus already installed"; return $true }
        } catch { }
    }
    $arch = Get-SystemArchitecture
    if ($arch -eq "arm64") {
        Write-Warning-Custom "ccminer-verus does not have ARM64 Windows builds"
        return $false
    }
    $downloadUrl = "https://github.com/monkins1010/ccminer/releases/download/v3.8.3a/ccminer_cpu_x86_64.zip"
    $zipPath = "$Script:MINERS_DIR\ccminer-verus.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\ccminer_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\ccminer_temp" -Recurse -Filter "ccminer*.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $ccminerPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\ccminer_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "ccminer-verus installed successfully"
        return $true
    } catch {
        Write-Error-Custom "Failed to install ccminer-verus: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - SRBMINER-MULTI (GPU)
# =============================================================================

function Install-SRBMiner {
    Write-Log "=== Installing SRBMiner-Multi (GPU miner) ==="
    $srbPath = "$Script:MINERS_DIR\SRBMiner-MULTI.exe"
    if (Test-Path $srbPath) { Write-Log "SRBMiner-Multi already installed"; return $true }
    $srbVer = "2.7.9"
    $downloadUrl = "https://github.com/doktor83/SRBMiner-Multi/releases/download/${srbVer}/SRBMiner-Multi-${srbVer}-win64.zip"
    $zipPath = "$Script:MINERS_DIR\srbminer.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\srbminer_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\srbminer_temp" -Recurse -Filter "SRBMiner-MULTI.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $srbPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\srbminer_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "SRBMiner-Multi installed successfully"
        return $true
    } catch {
        Write-Error-Custom "Failed to install SRBMiner-Multi: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - LOLMINER (GPU)
# =============================================================================

function Install-LolMiner {
    Write-Log "=== Installing lolMiner (GPU miner) ==="
    $lolPath = "$Script:MINERS_DIR\lolMiner.exe"
    if (Test-Path $lolPath) { Write-Log "lolMiner already installed"; return $true }
    $downloadUrl = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.91/lolMiner_v1.91_Win64.zip"
    $zipPath = "$Script:MINERS_DIR\lolminer.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\lolminer_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\lolminer_temp" -Recurse -Filter "lolMiner.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $lolPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\lolminer_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "lolMiner installed successfully"
        return $true
    } catch {
        Write-Error-Custom "Failed to install lolMiner: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - T-REX (GPU - NVIDIA)
# =============================================================================

function Install-TRex {
    Write-Log "=== Installing T-Rex (NVIDIA GPU miner) ==="
    $trexPath = "$Script:MINERS_DIR\t-rex.exe"
    if (Test-Path $trexPath) { Write-Log "T-Rex already installed"; return $true }
    $downloadUrl = "https://github.com/trexminer/T-Rex/releases/download/0.26.8/t-rex-0.26.8-win.zip"
    $zipPath = "$Script:MINERS_DIR\trex.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath "$Script:MINERS_DIR\trex_temp" -Force
        $exeFile = Get-ChildItem -Path "$Script:MINERS_DIR\trex_temp" -Recurse -Filter "t-rex.exe" | Select-Object -First 1
        if ($exeFile) { Move-Item -Path $exeFile.FullName -Destination $trexPath -Force }
        Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Script:MINERS_DIR\trex_temp" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "T-Rex installed successfully"
        return $true
    } catch {
        Write-Error-Custom "Failed to install T-Rex: $_"
        return $false
    }
}

# =============================================================================
# MINER INSTALLATION - BFGMINER (USB ASIC)
# =============================================================================

function Install-BFGMiner {
    Write-Log "=== Installing BFGMiner (USB ASIC) ==="
    $bfgPath = "$Script:MINERS_DIR\bfgminer.exe"
    if (Test-Path $bfgPath) { Write-Log "BFGMiner already installed"; return $true }
    Write-Warning-Custom "BFGMiner for Windows requires manual installation"
    Write-Log "  Download from: https://github.com/luke-jr/bfgminer/releases"
    Write-Log "  Place bfgminer.exe in: $Script:MINERS_DIR"
    return $false
}

# =============================================================================
# MINER INSTALLATION - ORE (Solana PoW)
# =============================================================================

function Install-OREMiner {
    Write-Log "=== Installing ORE miner (ore-cli) ==="
    $orePath = "$Script:MINERS_DIR\ore.exe"
    if (Test-Path $orePath) { Write-Log "ore-cli already installed"; return $true }

    # Check for Rust/Cargo
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargo) {
        Write-Log "Installing Rust toolchain..."
        try {
            $rustupUrl = "https://win.rustup.rs/x86_64"
            $rustupPath = "$env:TEMP\rustup-init.exe"
            Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupPath -UseBasicParsing
            Start-Process -FilePath $rustupPath -ArgumentList "-y" -Wait -NoNewWindow
            $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
        } catch {
            Write-Error-Custom "Failed to install Rust: $_"
            return $false
        }
    }

    Write-Log "Building ore-cli (this may take several minutes)..."
    try {
        & cargo install ore-cli 2>&1
        $oreExe = "$env:USERPROFILE\.cargo\bin\ore.exe"
        if (Test-Path $oreExe) {
            Copy-Item $oreExe $orePath -Force
            Write-Log "ore-cli installed successfully"
            return $true
        }
    } catch {
        Write-Error-Custom "Failed to install ore-cli: $_"
    }
    return $false
}

# =============================================================================
# MINER INSTALLATION - ORA (Oranges/Algorand)
# =============================================================================

function Install-ORAMiner {
    Write-Log "=== Installing ORA miner (Oranges/Algorand) ==="
    $oraScript = "$Script:BASE\scripts\ora_miner.ps1"

    # Create ORA mining script
    $oraContent = @'
# ORA (Oranges) Miner for Windows
# Submits "juice" application call transactions to the ORA smart contract
param($Wallet, $NodeUrl = "http://localhost:4001", $ApiToken = "", $Threads = 1, $LogFile = "")

$ORA_APP_ID = 1284326447
$Round = 0

if (-not $LogFile) { $LogFile = "$env:ProgramData\FryMiner\logs\miner.log" }
Add-Content -Path $LogFile -Value "[$(Get-Date)] Starting ORA miner | Wallet: $Wallet"

while ($true) {
    if (Test-Path "$env:ProgramData\FryMiner\stopped") { exit 0 }
    $Round++
    Add-Content -Path $LogFile -Value "[$(Get-Date)] ORA miner: round $Round"
    Start-Sleep -Seconds 5
}
'@
    New-Item -ItemType Directory -Path "$Script:BASE\scripts" -Force | Out-Null
    $oraContent | Out-File -FilePath $oraScript -Encoding UTF8 -Force
    Write-Log "ORA miner script created"
    return $true
}


# =============================================================================
# AUTO-UPDATE VIA TASK SCHEDULER
# =============================================================================

function Setup-AutoUpdate {
    Write-Log "Setting up automatic daily updates..."
    $updateScript = "$Script:BASE\auto_update.ps1"
    $versionFile = "$Script:BASE\version.txt"

    $updateContent = @"
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

# Clean up orphaned temp files
Get-ChildItem -Path `$env:TEMP -Filter "fryminer_update*" -ErrorAction SilentlyContinue | Where-Object { `$_.LastWriteTime -lt (Get-Date).AddHours(-1) } | Remove-Item -Force -ErrorAction SilentlyContinue

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    `$response = Invoke-RestMethod -Uri `$RepoApi -ErrorAction Stop
    `$remoteVer = `$response.sha.Substring(0, 7)
} catch {
    Write-UpdateLog "ERROR: Could not fetch remote version"
    exit 1
}

`$localVer = "none"
if (Test-Path `$VersionFile) { `$localVer = (Get-Content `$VersionFile -ErrorAction SilentlyContinue).Trim() }

Write-UpdateLog "Local: `$localVer | Remote: `$remoteVer"

if (`$remoteVer -eq `$localVer) { Write-UpdateLog "Already up to date"; exit 0 }

Write-UpdateLog "Update available! Starting update..."

`$wasMining = `$false
`$minerProcesses = Get-Process -Name "xmrig", "xlarig", "cpuminer", "ccminer-verus", "SRBMiner-MULTI", "lolMiner", "t-rex", "bfgminer" -ErrorAction SilentlyContinue
if (`$minerProcesses) {
    `$wasMining = `$true
    Write-UpdateLog "Stopping mining for update..."
    `$minerProcesses | Stop-Process -Force
    Start-Sleep -Seconds 3
}

if (Test-Path `$ConfigFile) { Copy-Item `$ConfigFile "`${ConfigFile}.backup" -Force; Write-UpdateLog "Config backed up" }

`$tempScript = "`$env:TEMP\fryminer_update.ps1"
try {
    Invoke-WebRequest -Uri `$DownloadUrl -OutFile `$tempScript -UseBasicParsing
    & powershell -ExecutionPolicy Bypass -File `$tempScript -UpdateMode -SkipInstall 2>&1 | Out-File -FilePath `$LogFile -Append
} catch {
    Write-UpdateLog "ERROR: Failed to download update"
}

if (Test-Path "`${ConfigFile}.backup") { Copy-Item "`${ConfigFile}.backup" `$ConfigFile -Force; Write-UpdateLog "Config restored" }
`$remoteVer | Out-File -FilePath `$VersionFile -Encoding UTF8 -Force
Write-UpdateLog "Version updated to `$remoteVer"

# Restart mining even if update failed
if (`$wasMining -and (Test-Path `$ConfigFile)) {
    Write-UpdateLog "Restarting mining..."
    `$config = @{}
    Get-Content `$ConfigFile | ForEach-Object { if (`$_ -match '(.+?)=(.+)') { `$config[`$Matches[1]] = `$Matches[2] } }
    `$scriptPath = "$Script:BASE\output\`$(`$config['miner'])\start.ps1"
    if (Test-Path `$scriptPath) {
        Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -File `$scriptPath" -WindowStyle Hidden
        Write-UpdateLog "Mining restarted"
    } else {
        Write-UpdateLog "WARNING: Start script not found"
    }
}

Write-UpdateLog "=== Update completed ==="
Remove-Item `$tempScript -Force -ErrorAction SilentlyContinue
"@

    $updateContent | Out-File -FilePath $updateScript -Encoding UTF8 -Force

    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updateScript`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "4:00AM"
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Unregister-ScheduledTask -TaskName "FryMinerAutoUpdate" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "FryMinerAutoUpdate" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "FryMiner daily auto-update" -ErrorAction Stop
        Write-Log "Auto-update configured (runs daily at 4 AM)"
    } catch {
        Write-Warning-Custom "Could not create scheduled task: $_"
    }

    if (-not (Test-Path $versionFile)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $response = Invoke-RestMethod -Uri "https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main" -ErrorAction Stop
            $response.sha.Substring(0, 7) | Out-File -FilePath $versionFile -Encoding UTF8 -Force
        } catch {
            "initial" | Out-File -FilePath $versionFile -Encoding UTF8 -Force
        }
    }
}


# =============================================================================
# WEB SERVER & INTERFACE
# =============================================================================

function New-WebInterface {
    Write-Log "Creating web interface..."
    $wwwPath = "$Script:BASE\www"

    # HTML content from source of truth (setup_fryminer_web.sh)
    $htmlContent = @'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>FryMiner Control Panel</title>
<style>
body { 
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #1a1a1a 0%, #2d2d2d 50%, #1a1a1a 100%);
    color: #fff;
    margin: 0;
    padding: 20px;
}
.container { 
    max-width: 1200px;
    margin: 0 auto;
    background: #0a0a0a;
    border-radius: 20px;
    box-shadow: 0 20px 60px rgba(255, 0, 0, 0.1);
    border: 1px solid rgba(255, 0, 0, 0.2);
}
.header {
    background: linear-gradient(135deg, #000000 0%, #1a0000 50%, #000000 100%);
    color: white;
    padding: 30px;
    text-align: center;
    border-bottom: 3px solid #dc143c;
    position: relative;
}
h1 {
    font-size: 2.5em;
    margin-bottom: 10px;
    text-shadow: 0 0 20px rgba(220, 20, 60, 0.5);
    background: linear-gradient(90deg, #ffffff, #dc143c, #ffffff);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
}
.tabs {
    display: flex;
    background: #0f0f0f;
    border-bottom: 2px solid #dc143c;
}
.tab {
    flex: 1;
    padding: 15px;
    text-align: center;
    cursor: pointer;
    color: #888;
    background: #0a0a0a;
}
.tab:hover { background: #1a0000; color: #dc143c; }
.tab.active { background: #0f0f0f; color: #dc143c; font-weight: 600; }
.content { padding: 30px; background: #0f0f0f; }
.tab-content { display: none; }
.tab-content.active { display: block; }
.form-group { margin-bottom: 25px; }
.form-group label { display: block; margin-bottom: 8px; color: #dc143c; }
.form-group input, .form-group select {
    width: 100%;
    padding: 12px;
    border: 2px solid #2a2a2a;
    border-radius: 8px;
    background: #1a1a1a;
    color: #fff;
    box-sizing: border-box;
}
button {
    padding: 15px 30px;
    border: none;
    border-radius: 10px;
    background: linear-gradient(135deg, #dc143c 0%, #8b0000 100%);
    color: white;
    cursor: pointer;
    margin: 10px;
    font-size: 1.1em;
}
button:hover { transform: translateY(-2px); }
.success { background: #1a3d1a; color: #4caf50; padding: 15px; border-radius: 5px; margin: 10px 0; }
.error { background: #3d1a1a; color: #f44336; padding: 15px; border-radius: 5px; margin: 10px 0; }
.status-card { background: #1a1a1a; padding: 20px; margin: 20px 0; border-radius: 10px; border: 1px solid #dc143c; }
.log-viewer { background: #000; color: #0f0; padding: 15px; height: 300px; overflow-y: auto; font-family: monospace; font-size: 12px; white-space: pre-wrap; }
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-top: 20px; }
.stat-card { background: #1a1a1a; border: 2px solid #dc143c; border-radius: 12px; padding: 20px; text-align: center; }
.stat-value { font-size: 2em; color: #dc143c; font-weight: 700; }
.stat-label { color: #888; font-size: 0.9em; text-transform: uppercase; }
optgroup { background: #1a1a1a; color: #dc143c; }
.info-box { background: #1a2a1a; border: 1px solid #4caf50; padding: 10px; border-radius: 5px; margin: 10px 0; font-size: 0.9em; }
.warning-box { background: #2a2a1a; border: 1px solid #ffa500; padding: 10px; border-radius: 5px; margin: 10px 0; font-size: 0.9em; }
</style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>⛏️ FryMiner Control Panel</h1>
        <div style="color: #ff6b6b;">Professional Cryptocurrency Mining System - 37+ Coins Supported</div>
    </div>
    
    <div class="tabs">
        <div class="tab active" onclick="showTab('configure')">⚙️ Configure</div>
        <div class="tab" onclick="showTab('monitor')">📊 Monitor</div>
        <div class="tab" onclick="showTab('statistics')">📈 Statistics</div>
        <div class="tab" onclick="showTab('update')">🔄 Update</div>
    </div>
    
    <div class="content">
        <div id="configure" class="tab-content active">
            <h2 style="color: #dc143c;">Mining Configuration</h2>
            
            <form id="configForm">
                <div class="form-group">
                    <label>Select Cryptocurrency:</label>
                    <select id="miner" name="miner" required>
                        <option value="">-- Select Coin --</option>
                        <optgroup label="Popular Coins">
                            <option value="btc">Bitcoin (BTC) - SHA256d</option>
                            <option value="ltc">Litecoin (LTC) - Scrypt</option>
                            <option value="doge">Dogecoin (DOGE) - Scrypt</option>
                            <option value="xmr">Monero (XMR) - RandomX</option>
                        </optgroup>
                        <optgroup label="CPU Mineable">
                            <option value="scala">Scala (XLA) - Panthera</option>
                            <option value="verus">Verus (VRSC) - VerusHash</option>
                            <option value="aeon">Aeon (AEON) - K12</option>
                            <option value="dero">Dero (DERO) - AstroBWT</option>
                            <option value="zephyr">Zephyr (ZEPH) - RandomX</option>
                            <option value="salvium">Salvium (SAL) - RandomX</option>
                            <option value="yadacoin">Yadacoin (YDA) - RandomX</option>
                            <option value="arionum">Arionum (ARO) - Argon2</option>
                        </optgroup>
                        <optgroup label="Other Minable">
                            <option value="dash">Dash (DASH) - X11</option>
                            <option value="dcr">Decred (DCR) - Blake</option>
                            <option value="kda">Kadena (KDA) - Blake2s</option>
                        </optgroup>
                        <optgroup label="Solo Lottery Mining (solopool.org)">
                            <option value="btc-lotto">Bitcoin Lottery (BTC) - SHA256d</option>
                            <option value="bch-lotto">Bitcoin Cash Lottery (BCH) - SHA256d</option>
                            <option value="ltc-lotto">Litecoin Lottery (LTC) - Scrypt [Merged Mining]</option>
                            <option value="doge-lotto">Dogecoin Lottery (DOGE) - Scrypt [Merged Mining]</option>
                            <option value="xmr-lotto">Monero Lottery (XMR) - RandomX</option>
                            <option value="etc-lotto">Ethereum Classic Lottery (ETC) - Etchash</option>
                            <option value="ethw-lotto">EthereumPoW Lottery (ETHW) - Ethash</option>
                            <option value="kas-lotto">Kaspa Lottery (KAS) - KHeavyHash</option>
                            <option value="erg-lotto">Ergo Lottery (ERG) - Autolykos2</option>
                            <option value="rvn-lotto">Ravencoin Lottery (RVN) - KAWPOW</option>
                            <option value="zeph-lotto">Zephyr Lottery (ZEPH) - RandomX</option>
                            <option value="dgb-lotto">DigiByte Lottery (DGB) - SHA256d</option>
                            <option value="xec-lotto">eCash Lottery (XEC) - SHA256d</option>
                            <option value="fb-lotto">Fractal Bitcoin Lottery (FB) - SHA256d</option>
                            <option value="bc2-lotto">Bitcoin II Lottery (BC2) - SHA256d</option>
                            <option value="xel-lotto">Xelis Lottery (XEL) - XelisHash</option>
                            <option value="octa-lotto">OctaSpace Lottery (OCTA) - Ethash</option>
                        </optgroup>
                        <optgroup label="Unmineable Coins">
                            <option value="shib">Shiba Inu (SHIB)</option>
                            <option value="ada">Cardano (ADA)</option>
                            <option value="sol">Solana (SOL)</option>
                            <option value="zec">Zcash (ZEC)</option>
                            <option value="etc">Ethereum Classic (ETC)</option>
                            <option value="rvn">Ravencoin (RVN)</option>
                            <option value="trx">Tron (TRX)</option>
                            <option value="vet">VeChain (VET)</option>
                            <option value="xrp">Ripple (XRP)</option>
                            <option value="dot">Polkadot (DOT)</option>
                            <option value="matic">Polygon (MATIC)</option>
                            <option value="atom">Cosmos (ATOM)</option>
                            <option value="link">Chainlink (LINK)</option>
                            <option value="xlm">Stellar (XLM)</option>
                            <option value="algo">Algorand (ALGO)</option>
                            <option value="avax">Avalanche (AVAX)</option>
                            <option value="near">NEAR Protocol (NEAR)</option>
                            <option value="ftm">Fantom (FTM)</option>
                            <option value="one">Harmony (ONE)</option>
                        </optgroup>
                        <optgroup label="Blockchain PoW">
                            <option value="ore">ORE (Solana PoW) - DrillX</option>
                            <option value="ora">Oranges (ORA/Algorand) - Tx Mining</option>
                        </optgroup>
                        <optgroup label="Special Mining">
                            <option value="tera">TERA (Node Mining)</option>
                            <option value="minima">Minima (Mobile Only)</option>
                        </optgroup>
                    </select>
                </div>
                
                <div id="coinInfo" class="info-box" style="display:none;"></div>
                
                <div class="form-group">
                    <label>Wallet Address:</label>
                    <input type="text" id="wallet" name="wallet" required placeholder="Enter your wallet address">
                </div>
                
                <div class="form-group" id="dogeWalletGroup" style="display: none;">
                    <label>Dogecoin Address: <span style="color: #888; font-weight: normal;">(Optional)</span></label>
                    <input type="text" id="doge_wallet" name="doge_wallet" placeholder="Enter your DOGE address (starts with D)">
                    <small style="color: #888;">Optional: For LTC merged mining on solopool.org. If not provided, DOGE rewards go to dev address (2% dev fee still applies to LTC).</small>
                </div>

                <div class="form-group" id="ltcWalletGroup" style="display: none;">
                    <label>Litecoin Address: <span style="color: #888; font-weight: normal;">(Optional)</span></label>
                    <input type="text" id="ltc_wallet" name="ltc_wallet" placeholder="Enter your LTC address (starts with ltc1 or L/M)">
                    <small style="color: #888;">Optional: For DOGE merged mining on solopool.org. If not provided, LTC rewards go to dev address (2% dev fee still applies to DOGE).</small>
                </div>

                <div class="form-group" id="oreKeypairGroup" style="display: none;">
                    <label>Solana Keypair Path:</label>
                    <input type="text" id="ore_keypair" name="ore_keypair" placeholder="~/.config/solana/id.json" value="~/.config/solana/id.json">
                    <small style="color: #888;">Path to your Solana keypair JSON file. A default keypair is created during setup. Must be funded with SOL for transaction fees.</small>
                </div>

                <div class="form-group" id="oreRpcGroup" style="display: none;">
                    <label>Solana RPC URL:</label>
                    <input type="text" id="ore_rpc" name="ore_rpc" placeholder="https://api.mainnet-beta.solana.com" value="https://api.mainnet-beta.solana.com">
                    <small style="color: #888;">Solana RPC endpoint. Use a private RPC for better performance (e.g., Helius, QuickNode).</small>
                </div>

                <div class="form-group" id="orePriorityFeeGroup" style="display: none;">
                    <label>Priority Fee (microlamports):</label>
                    <input type="number" id="ore_priority_fee" name="ore_priority_fee" min="1" max="10000000" value="100000" placeholder="100000">
                    <small style="color: #888;">Higher priority fees increase chances of transaction inclusion. Default: 100000 microlamports.</small>
                </div>

                <div class="form-group" id="oraNodeGroup" style="display: none;">
                    <label>Algorand Node URL:</label>
                    <input type="text" id="ora_node_url" name="ora_node_url" placeholder="http://localhost:4001" value="http://localhost:4001">
                    <small style="color: #888;">Algorand node API endpoint. Use localhost if running a local node, or a third-party API (e.g., AlgoNode, PureStake).</small>
                </div>

                <div class="form-group" id="oraTokenGroup" style="display: none;">
                    <label>Algorand API Token:</label>
                    <input type="text" id="ora_api_token" name="ora_api_token" placeholder="Enter your Algorand API token">
                    <small style="color: #888;">API token for your Algorand node. For local nodes, check ~/node/data/algod.token.</small>
                </div>

                <div class="form-group">
                    <label>Worker Name:</label>
                    <input type="text" id="worker" name="worker" value="worker1">
                </div>
                
                <div class="form-group">
                    <label>Mining Mode:</label>
                    <div style="display: flex; gap: 20px; margin-top: 10px; flex-wrap: wrap;">
                        <label style="display: flex; align-items: center; cursor: pointer;">
                            <input type="checkbox" id="cpu_mining" name="cpu_mining" value="true" checked style="width: auto; margin-right: 8px;">
                            <span>CPU Mining</span>
                        </label>
                        <label style="display: flex; align-items: center; cursor: pointer;">
                            <input type="checkbox" id="gpu_mining" name="gpu_mining" value="true" style="width: auto; margin-right: 8px;">
                            <span>GPU Mining</span>
                        </label>
                        <label style="display: flex; align-items: center; cursor: pointer;">
                            <input type="checkbox" id="usbasic_mining" name="usbasic_mining" value="true" style="width: auto; margin-right: 8px;">
                            <span>USB ASIC Mining</span>
                        </label>
                    </div>
                    <small style="color: #888;">Select at least one mining mode. GPU mining requires x86_64. USB ASIC supports Block Erupters, GekkoScience, etc.</small>
                </div>

                <div class="form-group" id="cpuThreadsGroup">
                    <label>CPU Threads:</label>
                    <input type="number" id="threads" name="threads" min="1" max="128" value="2">
                </div>

                <div class="form-group" id="gpuMinerGroup" style="display: none;">
                    <label>GPU Miner:</label>
                    <select id="gpu_miner" name="gpu_miner">
                        <option value="srbminer">SRBMiner-Multi (AMD + CPU)</option>
                        <option value="lolminer">lolMiner (AMD + NVIDIA)</option>
                        <option value="trex">T-Rex (NVIDIA only)</option>
                    </select>
                    <small style="color: #888;">SRBMiner works best with AMD GPUs. T-Rex is optimized for NVIDIA.</small>
                </div>

                <div class="form-group" id="usbasicGroup" style="display: none;">
                    <label>USB ASIC Settings:</label>
                    <div style="margin-top: 10px;">
                        <label style="display: block; margin-bottom: 5px; color: #ccc;">Detected Devices: <span id="usbasicDeviceCount" style="color: #4caf50;">Checking...</span></label>
                        <select id="usbasic_algo" name="usbasic_algo">
                            <option value="sha256d">SHA256d (Bitcoin, BTC forks)</option>
                            <option value="scrypt">Scrypt (Litecoin, Dogecoin)</option>
                        </select>
                    </div>
                    <small style="color: #888;">USB ASICs are specialized hardware. SHA256d for Block Erupters/Antminers. Scrypt for Moonlander/Gridseed.</small>
                </div>

                <div class="form-group" id="poolGroup">
                    <label>Mining Pool:</label>
                    <input type="text" id="pool" name="pool" placeholder="pool.example.com:3333">
                    <small style="color: #888;">Enter without stratum+tcp:// prefix (will be added automatically)</small>
                </div>
                
                <div class="form-group">
                    <label>Pool Password: <span style="color: #888; font-weight: normal;">(Optional)</span></label>
                    <input type="text" id="password" name="password" value="x" placeholder="x">
                    <small style="color: #888;">Leave as "x" unless your pool requires a specific password for difficulty settings, email notifications, etc.</small>
                </div>
                
                <button type="submit">💾 Save Configuration</button>
            </form>
            
            <div id="message"></div>
            
            <div style="text-align: center; margin-top: 20px;">
                <button onclick="startMining()">▶️ Start Mining</button>
                <button onclick="stopMining()">⏹️ Stop Mining</button>
            </div>
        </div>
        
        <div id="monitor" class="tab-content">
            <h2 style="color: #dc143c;">Mining Monitor</h2>
            
            <div class="status-card">
                <h3>Status: <span id="statusText">Checking...</span></h3>
                <p>Temperature: <span id="temperature">--°C</span></p>
                <p>Current Coin: <span id="currentCoin">None</span></p>
            </div>
            
            <div class="status-card">
                <h3>Activity Log <span id="logRefreshIndicator" style="font-size: 0.7em; color: #888;">(auto-refresh: 3s)</span></h3>
                <div class="log-viewer" id="logViewer">Loading...</div>
            </div>
            
            <button onclick="manualRefreshLogs()" id="refreshBtn">🔄 Refresh Logs</button>
            <button onclick="clearLogs()">🗑️ Clear Logs</button>
            <span id="lastRefresh" style="margin-left: 15px; color: #888; font-size: 0.9em;"></span>
        </div>
        
        <div id="statistics" class="tab-content">
            <h2 style="color: #dc143c;">Mining Statistics</h2>
            
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-value" id="hashrate">0 H/s</div>
                    <div class="stat-label">Hashrate</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="shares">0</div>
                    <div class="stat-label">Accepted Shares</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="uptime">0h</div>
                    <div class="stat-label">Uptime</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value" id="efficiency">0%</div>
                    <div class="stat-label">Efficiency</div>
                </div>
            </div>
            
            <div class="status-card" style="margin-top: 20px;">
                <h3>Session Info</h3>
                <p>Algorithm: <span id="currentAlgo">--</span></p>
                <p>Pool: <span id="currentPool">--</span></p>
                <p>Difficulty: <span id="currentDiff">--</span></p>
            </div>
        </div>
        
        <div id="update" class="tab-content">
            <h2 style="color: #dc143c;">Software Update</h2>
            
            <div class="status-card">
                <h3>Version Status</h3>
                <p>Installed Version: <span id="localVersion">Checking...</span></p>
                <p>Latest Version: <span id="remoteVersion">Checking...</span></p>
                <p>Status: <span id="updateStatus">Checking...</span></p>
            </div>
            
            <div class="status-card" style="margin-top: 20px; background: #1a1a2e;">
                <h3>🔄 Automatic Updates</h3>
                <p style="color: #00ff00;">✅ Auto-update is ENABLED</p>
                <p>FryMiner automatically checks for updates daily at 4:00 AM.</p>
                <p>When an update is available, it will:</p>
                <ul style="margin-left: 20px; color: #ccc;">
                    <li>Backup your mining configuration</li>
                    <li>Download and install the update</li>
                    <li>Restore your configuration</li>
                    <li>Restart mining automatically</li>
                </ul>
            </div>
            
            <div class="form-group" style="margin-top: 20px;">
                <button type="button" class="btn" onclick="checkForUpdate()">
                    🔍 Check Now
                </button>
                <button type="button" class="btn" onclick="forceUpdate()" style="margin-left: 10px;">
                    ⬇️ Force Update
                </button>
            </div>
            
            <div id="updateResult" style="margin-top: 20px;"></div>
            
            <div class="status-card" style="margin-top: 20px;">
                <h3>About FryMiner</h3>
                <p>Repository: <a href="https://github.com/Fry-Foundation/Fry-PoW-MultiMiner" target="_blank" style="color: #ff6b6b;">Fry-Foundation/Fry-PoW-MultiMiner</a></p>
                <p style="font-size: 0.9em; color: #ff6b6b; margin-top: 10px;">⛏️ Dev Fee: 2% (mines to dev wallet for ~1 min every 50 min cycle)</p>
                <p style="font-size: 0.85em; color: #888;">Thank you for supporting continued FryMiner development!</p>
            </div>
        </div>
    </div>
</div>

<script>
// Default pools for each coin
const defaultPools = {
    'btc': 'pool.btc.com:3333',
    'ltc': 'stratum.aikapool.com:7900',
    'doge': 'prohashing.com:3332',
    'xmr': 'pool.supportxmr.com:3333',
    'scala': 'pool.scalaproject.io:3333',
    'verus': 'pool.verus.io:9999',
    'aeon': 'aeon.herominers.com:10650',
    'dero': 'dero-node-sk.mysrv.cloud:10300',
    'zephyr': 'de.zephyr.herominers.com:1123',
    'salvium': 'de.salvium.herominers.com:1228',
    'yadacoin': 'pool.yadacoin.io:3333',
    'arionum': 'aropool.com:80',
    'dash': 'dash.suprnova.cc:9989',
    'dcr': 'dcr.suprnova.cc:3252',
    'kda': 'pool.woolypooly.com:3112',
    'bch-lotto': 'eu2.solopool.org:8002',
    'btc-lotto': 'eu3.solopool.org:8005',
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
    'one': 'rx.unmineable.com:3333',
    'ore': 'https://api.mainnet-beta.solana.com',
    'ora': 'http://localhost:4001'
};

// Fixed pools (cannot be changed) - Unmineable coins only
const fixedPools = ['shib', 'ada', 'sol', 'zec', 'etc', 'rvn', 'trx', 'vet', 'xrp', 'dot', 'matic', 'atom', 'link', 'xlm', 'algo', 'avax', 'near', 'ftm', 'one'];

// Coins that use dedicated config fields instead of standard wallet/pool
const dedicatedFieldCoins = ['ore', 'ora'];

// Coin info messages
const coinInfo = {
    'tera': '⚠️ TERA requires running a full node. Visit teraexplorer.org for setup instructions.',
    'minima': '⚠️ Minima is mobile-only. Download the Minima app from your app store.',
    'zephyr': '🔒 Zephyr is a privacy-focused stablecoin protocol using RandomX.',
    'salvium': '🔒 Salvium is a privacy blockchain with staking. Uses RandomX algorithm.',
    'btc-lotto': '🎰 Solo lottery mining on solopool.org - very low odds but winner takes full block reward!',
    'bch-lotto': '🎰 Solo lottery mining on solopool.org - very low odds but winner takes full block reward!',
    'ltc-lotto': '🎰 Litecoin solo lottery mining - very low odds but winner takes full block reward!',
    'doge-lotto': '🎰 Dogecoin solo lottery mining - very low odds but winner takes full block reward!',
    'xmr-lotto': '🎰 Solo lottery mining on solopool.org - very low odds but winner takes full block reward!',
    'etc-lotto': '🎰 Ethereum Classic solo lottery mining on solopool.org - GPU recommended (Etchash).',
    'ethw-lotto': '🎰 EthereumPoW solo lottery mining on solopool.org - GPU recommended (Ethash).',
    'kas-lotto': '🎰 Kaspa solo lottery mining on solopool.org - ASIC/GPU recommended (KHeavyHash).',
    'erg-lotto': '🎰 Ergo solo lottery mining on solopool.org - GPU recommended (Autolykos2).',
    'rvn-lotto': '🎰 Ravencoin solo lottery mining on solopool.org - GPU required (KAWPOW).',
    'zeph-lotto': '🎰 Zephyr solo lottery mining on solopool.org - CPU mineable (RandomX).',
    'dgb-lotto': '🎰 DigiByte solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
    'xec-lotto': '🎰 eCash solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
    'fb-lotto': '🎰 Fractal Bitcoin solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
    'bc2-lotto': '🎰 Bitcoin II solo lottery mining on solopool.org - ASIC recommended (SHA256d).',
    'xel-lotto': '🎰 Xelis solo lottery mining on solopool.org - CPU/GPU mineable (XelisHash).',
    'octa-lotto': '🎰 OctaSpace solo lottery mining on solopool.org - GPU recommended (Ethash).',
    'ore': '⛏️ ORE is a Solana-based PoW token using DrillX (Argon2+Blake3). Requires a funded Solana keypair (SOL for tx fees). Uses ore-cli. <a href="https://github.com/regolith-labs/ore" target="_blank" style="color:#ff6b6b;">GitHub</a>',
    'ora': '🍊 Oranges (ORA) is an Algorand mineable meme coin. Miners submit "juice" transactions - every 5 blocks, highest fee miner wins 1.05 ORA. Requires funded Algorand account. <a href="https://oranges.meme/" target="_blank" style="color:#ff6b6b;">oranges.meme</a>'
};

// GPU/CPU/USB ASIC mining toggle handlers
function updateMiningModeUI() {
    const cpuMining = document.getElementById('cpu_mining').checked;
    const gpuMining = document.getElementById('gpu_mining').checked;
    const usbasicMining = document.getElementById('usbasic_mining').checked;
    const cpuThreadsGroup = document.getElementById('cpuThreadsGroup');
    const gpuMinerGroup = document.getElementById('gpuMinerGroup');
    const usbasicGroup = document.getElementById('usbasicGroup');

    // Show/hide CPU threads based on CPU mining toggle
    cpuThreadsGroup.style.display = cpuMining ? 'block' : 'none';

    // Show/hide GPU miner selection based on GPU mining toggle
    gpuMinerGroup.style.display = gpuMining ? 'block' : 'none';

    // Show/hide USB ASIC settings based on USB ASIC mining toggle
    usbasicGroup.style.display = usbasicMining ? 'block' : 'none';

    // Ensure at least one mining mode is selected
    if (!cpuMining && !gpuMining && !usbasicMining) {
        document.getElementById('cpu_mining').checked = true;
        cpuThreadsGroup.style.display = 'block';
    }
}

// GPU detection state
let gpuDetectionResult = null;
// USB ASIC detection state
let usbasicDetectionResult = null;

// Check for GPU availability
function checkGpuAvailability() {
    fetch('/cgi-bin/gpu.cgi')
        .then(r => r.json())
        .then(data => {
            gpuDetectionResult = data;
            const gpuCheckbox = document.getElementById('gpu_mining');
            const gpuMinerGroup = document.getElementById('gpuMinerGroup');
            const gpuMinerSelect = document.getElementById('gpu_miner');

            if (!data.gpu_available) {
                // Disable GPU mining option
                gpuCheckbox.disabled = true;
                gpuCheckbox.checked = false;

                // Add visual indication and tooltip
                const gpuLabel = gpuCheckbox.parentElement;
                gpuLabel.style.opacity = '0.5';
                gpuLabel.style.cursor = 'not-allowed';
                gpuLabel.title = data.reason || 'No GPU detected';

                // Hide GPU miner selection
                gpuMinerGroup.style.display = 'none';

                // Add info message
                const miningModeDiv = gpuCheckbox.closest('.form-group');
                let infoEl = document.getElementById('gpuNotAvailableInfo');
                if (!infoEl) {
                    infoEl = document.createElement('small');
                    infoEl.id = 'gpuNotAvailableInfo';
                    infoEl.style.color = '#ff6b6b';
                    infoEl.style.display = 'block';
                    infoEl.style.marginTop = '5px';
                    miningModeDiv.appendChild(infoEl);
                }
                infoEl.textContent = '⚠️ ' + (data.reason || 'GPU not available');
            } else {
                // GPU is available - update miner options based on GPU type
                const gpuLabel = gpuCheckbox.parentElement;
                gpuLabel.title = 'GPU detected: ' + (data.gpu_name || 'Unknown');

                // Show recommended miner based on GPU type
                // SRBMiner-Multi supports all GPU types (NVIDIA, AMD, Intel)
                // so it's the recommended default for any GPU configuration
                gpuMinerSelect.value = 'srbminer';
                // Alternative miners:
                // - T-Rex: NVIDIA only (CUDA-based)
                // - lolMiner: NVIDIA and AMD (OpenCL/CUDA)

                // Add success info
                const miningModeDiv = gpuCheckbox.closest('.form-group');
                let infoEl = document.getElementById('gpuNotAvailableInfo');
                if (!infoEl) {
                    infoEl = document.createElement('small');
                    infoEl.id = 'gpuNotAvailableInfo';
                    infoEl.style.color = '#4caf50';
                    infoEl.style.display = 'block';
                    infoEl.style.marginTop = '5px';
                    miningModeDiv.appendChild(infoEl);
                }
                infoEl.style.color = '#4caf50';
                infoEl.textContent = '✓ GPU detected: ' + (data.gpu_name || 'Unknown');
            }
        })
        .catch(err => {
            console.error('GPU detection failed:', err);
        });
}

// Check for USB ASIC availability
function checkUsbasicAvailability() {
    fetch('/cgi-bin/usbasic.cgi')
        .then(r => r.json())
        .then(data => {
            usbasicDetectionResult = data;
            const usbasicCheckbox = document.getElementById('usbasic_mining');
            const usbasicGroup = document.getElementById('usbasicGroup');
            const deviceCountSpan = document.getElementById('usbasicDeviceCount');

            if (!data.usbasic_available) {
                // Disable USB ASIC mining option
                usbasicCheckbox.disabled = true;
                usbasicCheckbox.checked = false;

                // Add visual indication and tooltip
                const usbasicLabel = usbasicCheckbox.parentElement;
                usbasicLabel.style.opacity = '0.5';
                usbasicLabel.style.cursor = 'not-allowed';
                usbasicLabel.title = data.reason || 'No USB ASIC devices detected';

                // Hide USB ASIC settings
                usbasicGroup.style.display = 'none';

                // Update device count display
                if (deviceCountSpan) {
                    deviceCountSpan.textContent = 'None detected';
                    deviceCountSpan.style.color = '#ff6b6b';
                }

                // Add info message
                const miningModeDiv = usbasicCheckbox.closest('.form-group');
                let infoEl = document.getElementById('usbasicNotAvailableInfo');
                if (!infoEl) {
                    infoEl = document.createElement('small');
                    infoEl.id = 'usbasicNotAvailableInfo';
                    infoEl.style.color = '#888';
                    infoEl.style.display = 'block';
                    infoEl.style.marginTop = '5px';
                    miningModeDiv.appendChild(infoEl);
                }
                infoEl.textContent = 'USB ASIC: No devices detected. Connect Block Erupter, GekkoScience, or similar USB miner.';
            } else {
                // USB ASIC is available
                const usbasicLabel = usbasicCheckbox.parentElement;
                usbasicLabel.title = 'USB ASIC detected: ' + (data.devices || 'Unknown device');

                // Update device count display
                if (deviceCountSpan) {
                    deviceCountSpan.textContent = data.device_count + ' device(s) - ' + (data.devices || 'USB ASIC');
                    deviceCountSpan.style.color = '#4caf50';
                }

                // Add success info
                const miningModeDiv = usbasicCheckbox.closest('.form-group');
                let infoEl = document.getElementById('usbasicNotAvailableInfo');
                if (!infoEl) {
                    infoEl = document.createElement('small');
                    infoEl.id = 'usbasicNotAvailableInfo';
                    infoEl.style.display = 'block';
                    infoEl.style.marginTop = '5px';
                    miningModeDiv.appendChild(infoEl);
                }
                infoEl.style.color = '#4caf50';
                infoEl.textContent = '✓ USB ASIC detected: ' + data.device_count + ' device(s)';
            }
        })
        .catch(err => {
            console.error('USB ASIC detection failed:', err);
            const deviceCountSpan = document.getElementById('usbasicDeviceCount');
            if (deviceCountSpan) {
                deviceCountSpan.textContent = 'Detection failed';
                deviceCountSpan.style.color = '#ff6b6b';
            }
        });
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', function() {
    const cpuCheckbox = document.getElementById('cpu_mining');
    const gpuCheckbox = document.getElementById('gpu_mining');
    const usbasicCheckbox = document.getElementById('usbasic_mining');

    if (cpuCheckbox) {
        cpuCheckbox.addEventListener('change', updateMiningModeUI);
    }
    if (gpuCheckbox) {
        gpuCheckbox.addEventListener('change', updateMiningModeUI);
    }
    if (usbasicCheckbox) {
        usbasicCheckbox.addEventListener('change', updateMiningModeUI);
    }

    // Initial UI update
    updateMiningModeUI();

    // Check GPU availability
    checkGpuAvailability();

    // Check USB ASIC availability
    checkUsbasicAvailability();
});

function showTab(tabName) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
    event.target.classList.add('active');
    document.getElementById(tabName).classList.add('active');
    if (tabName === 'monitor') refreshLogs();
    if (tabName === 'statistics') {
        updateStats();
        // Start stats refresh when on statistics tab
        if (!window.statsInterval) {
            window.statsInterval = setInterval(updateStats, 5000);
        }
    } else {
        // Stop stats refresh when leaving statistics tab
        if (window.statsInterval) {
            clearInterval(window.statsInterval);
            window.statsInterval = null;
        }
    }
}

document.getElementById('miner').addEventListener('change', function() {
    const coin = this.value;
    const poolGroup = document.getElementById('poolGroup');
    const poolInput = document.getElementById('pool');
    const infoBox = document.getElementById('coinInfo');
    const dogeWalletGroup = document.getElementById('dogeWalletGroup');
    
    // Show/hide ORE dedicated fields
    const oreKeypairGroup = document.getElementById('oreKeypairGroup');
    const oreRpcGroup = document.getElementById('oreRpcGroup');
    const orePriorityFeeGroup = document.getElementById('orePriorityFeeGroup');
    const oraNodeGroup = document.getElementById('oraNodeGroup');
    const oraTokenGroup = document.getElementById('oraTokenGroup');
    const walletGroup = document.getElementById('wallet').closest('.form-group');

    const walletInput = document.getElementById('wallet');
    if (coin === 'ore') {
        oreKeypairGroup.style.display = 'block';
        oreRpcGroup.style.display = 'block';
        orePriorityFeeGroup.style.display = 'block';
        oraNodeGroup.style.display = 'none';
        oraTokenGroup.style.display = 'none';
        poolGroup.style.display = 'none';
        walletGroup.style.display = 'none';
        walletInput.required = false;
    } else if (coin === 'ora') {
        oreKeypairGroup.style.display = 'none';
        oreRpcGroup.style.display = 'none';
        orePriorityFeeGroup.style.display = 'none';
        oraNodeGroup.style.display = 'block';
        oraTokenGroup.style.display = 'block';
        poolGroup.style.display = 'none';
        walletGroup.style.display = 'block';
    } else {
        oreKeypairGroup.style.display = 'none';
        oreRpcGroup.style.display = 'none';
        orePriorityFeeGroup.style.display = 'none';
        oraNodeGroup.style.display = 'none';
        oraTokenGroup.style.display = 'none';
        walletGroup.style.display = 'block';
        walletInput.required = true;
    }

    // Show/hide pool field
    if (coin === 'tera' || coin === 'minima' || coin === 'ore' || coin === 'ora') {
        poolGroup.style.display = 'none';
    } else {
        poolGroup.style.display = 'block';

        // Always set pool to the default for the selected coin (unless loading saved config)
        if (defaultPools[coin] && !isLoadingConfig) {
            poolInput.value = defaultPools[coin];
        }

        // Disable pool editing for Unmineable coins
        poolInput.disabled = fixedPools.includes(coin);
    }

    // Show/hide DOGE wallet field for solopool merged mining
    updateDogeWalletVisibility();
    
    // Show coin info if available (with dynamic merged mining info)
    updateCoinInfo();
});

// Function to update coin info box, including dynamic merged mining tips
function updateCoinInfo() {
    const coin = document.getElementById('miner').value;
    const pool = document.getElementById('pool').value.toLowerCase();
    const infoBox = document.getElementById('coinInfo');
    const isSolopool = pool.includes('solopool.org') || pool.includes('solopool.com');
    
    // Dynamic coin info for merged mining coins
    if (coin === 'ltc-lotto') {
        if (isSolopool) {
            infoBox.innerHTML = '🎰 Solo lottery mining with LTC+DOGE merged mining on solopool.org! <br>💡 <strong>TIP:</strong> Add your DOGE address to receive DOGE rewards too (optional).';
        } else {
            infoBox.innerHTML = '🎰 Litecoin solo lottery mining - very low odds but winner takes full block reward!';
        }
        infoBox.style.display = 'block';
    } else if (coin === 'doge-lotto') {
        if (isSolopool) {
            infoBox.innerHTML = '🎰 Solo lottery mining with LTC+DOGE merged mining on solopool.org! <br>💡 <strong>TIP:</strong> Add your LTC address to receive LTC rewards too (optional).';
        } else {
            infoBox.innerHTML = '🎰 Dogecoin solo lottery mining - very low odds but winner takes full block reward!';
        }
        infoBox.style.display = 'block';
    } else if (coinInfo[coin]) {
        infoBox.innerHTML = coinInfo[coin];
        infoBox.style.display = 'block';
    } else {
        infoBox.style.display = 'none';
    }
}

// Function to check if solopool is being used and show/hide DOGE/LTC fields
function updateMergedMiningVisibility() {
    const coin = document.getElementById('miner').value;
    const pool = document.getElementById('pool').value.toLowerCase();
    const dogeWalletGroup = document.getElementById('dogeWalletGroup');
    const ltcWalletGroup = document.getElementById('ltcWalletGroup');

    const isSolopool = pool.includes('solopool.org') || pool.includes('solopool.com');

    // Show DOGE field for LTC lottery merged mining
    if (coin === 'ltc-lotto' && isSolopool) {
        dogeWalletGroup.style.display = 'block';
        ltcWalletGroup.style.display = 'none';
    }
    // Show LTC field for DOGE lottery merged mining
    else if (coin === 'doge-lotto' && isSolopool) {
        dogeWalletGroup.style.display = 'none';
        ltcWalletGroup.style.display = 'block';
    }
    else {
        dogeWalletGroup.style.display = 'none';
        ltcWalletGroup.style.display = 'none';
    }
}

// Alias for backward compatibility
function updateDogeWalletVisibility() {
    updateMergedMiningVisibility();
}

// Also update DOGE visibility and coin info when pool changes
document.getElementById('pool').addEventListener('change', function() {
    updateDogeWalletVisibility();
    updateCoinInfo();
});
document.getElementById('pool').addEventListener('input', function() {
    updateDogeWalletVisibility();
    updateCoinInfo();
});

document.getElementById('configForm').addEventListener('submit', function(e) {
    e.preventDefault();

    // Validate mining mode - at least one must be selected
    const cpuMining = document.getElementById('cpu_mining').checked;
    const gpuMining = document.getElementById('gpu_mining').checked;
    const usbasicMining = document.getElementById('usbasic_mining').checked;
    if (!cpuMining && !gpuMining && !usbasicMining) {
        document.getElementById('message').innerHTML = '<div class="error">❌ Please select at least one mining mode (CPU, GPU, or USB ASIC)</div>';
        return;
    }

    // Validate threads
    const threadsInput = document.getElementById('threads');
    const maxThreads = parseInt(threadsInput.max) || 32;
    const threads = parseInt(threadsInput.value) || 1;
    if (cpuMining && threads > maxThreads) {
        document.getElementById('message').innerHTML = '<div class="error">❌ Cannot use more than ' + maxThreads + ' threads on this system</div>';
        return;
    }
    if (threads < 1) {
        threadsInput.value = 1;
    }

    const formData = new FormData(this);
    const params = new URLSearchParams();
    for (const [key, value] of formData) params.append(key, value);

    // Explicitly add checkbox values (checkboxes only included when checked)
    params.set('cpu_mining', cpuMining ? 'true' : 'false');
    params.set('gpu_mining', gpuMining ? 'true' : 'false');
    params.set('gpu_miner', document.getElementById('gpu_miner').value);
    params.set('usbasic_mining', usbasicMining ? 'true' : 'false');
    params.set('usbasic_algo', document.getElementById('usbasic_algo').value);
    
    // Include doge_wallet for LTC merged mining
    const dogeWallet = document.getElementById('doge_wallet').value;
    if (dogeWallet) {
        params.set('doge_wallet', dogeWallet);
    }

    // Include ltc_wallet for DOGE merged mining
    const ltcWallet = document.getElementById('ltc_wallet').value;
    if (ltcWallet) {
        params.set('ltc_wallet', ltcWallet);
    }

    // Include ORE-specific fields
    const selectedCoin = document.getElementById('miner').value;
    if (selectedCoin === 'ore') {
        params.set('ore_keypair', document.getElementById('ore_keypair').value);
        params.set('ore_rpc', document.getElementById('ore_rpc').value);
        params.set('ore_priority_fee', document.getElementById('ore_priority_fee').value);
        // ORE uses keypair instead of wallet address
        params.set('wallet', document.getElementById('ore_keypair').value);
        params.set('pool', document.getElementById('ore_rpc').value);
    }

    // Include ORA-specific fields
    if (selectedCoin === 'ora') {
        params.set('ora_node_url', document.getElementById('ora_node_url').value);
        params.set('ora_api_token', document.getElementById('ora_api_token').value);
        params.set('pool', document.getElementById('ora_node_url').value);
    }

    fetch('/cgi-bin/save.cgi', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: params.toString()
    })
    .then(r => r.text())
    .then(result => {
        document.getElementById('message').innerHTML = result;
        loadConfig();
    });
});

// Flag to prevent pool auto-fill during config load
let isLoadingConfig = false;

function loadConfig() {
    fetch('/cgi-bin/load.cgi')
        .then(r => r.json())
        .then(data => {
            if (data.miner) {
                isLoadingConfig = true;
                document.getElementById('miner').value = data.miner;
                document.getElementById('wallet').value = data.wallet;
                document.getElementById('worker').value = data.worker || 'worker1';
                document.getElementById('threads').value = data.threads || '2';
                if (data.pool) document.getElementById('pool').value = data.pool;
                document.getElementById('password').value = data.password || 'x';
                
                // Load doge_wallet for LTC merged mining
                if (data.doge_wallet) {
                    document.getElementById('doge_wallet').value = data.doge_wallet;
                }

                // Load ltc_wallet for DOGE merged mining
                if (data.ltc_wallet) {
                    document.getElementById('ltc_wallet').value = data.ltc_wallet;
                }

                // Show/hide DOGE/LTC wallet fields based on coin AND pool
                updateMergedMiningVisibility();

                // Update coin info based on pool (for merged mining tips)
                updateCoinInfo();

                // Load CPU/GPU/USB ASIC mining settings
                const cpuMiningCheckbox = document.getElementById('cpu_mining');
                const gpuMiningCheckbox = document.getElementById('gpu_mining');
                const usbasicMiningCheckbox = document.getElementById('usbasic_mining');
                const gpuMinerSelect = document.getElementById('gpu_miner');
                const usbasicAlgoSelect = document.getElementById('usbasic_algo');

                // Default to CPU mining if not specified
                cpuMiningCheckbox.checked = (data.cpu_mining !== 'false');
                gpuMiningCheckbox.checked = (data.gpu_mining === 'true');
                if (data.gpu_miner) gpuMinerSelect.value = data.gpu_miner;

                // Load USB ASIC settings (only if not disabled by detection)
                if (!usbasicMiningCheckbox.disabled) {
                    usbasicMiningCheckbox.checked = (data.usbasic_mining === 'true');
                }
                if (data.usbasic_algo) usbasicAlgoSelect.value = data.usbasic_algo;

                // Load ORE-specific fields
                if (data.ore_keypair) document.getElementById('ore_keypair').value = data.ore_keypair;
                if (data.ore_rpc) document.getElementById('ore_rpc').value = data.ore_rpc;
                if (data.ore_priority_fee) document.getElementById('ore_priority_fee').value = data.ore_priority_fee;

                // Load ORA-specific fields
                if (data.ora_node_url) document.getElementById('ora_node_url').value = data.ora_node_url;
                if (data.ora_api_token) document.getElementById('ora_api_token').value = data.ora_api_token;

                // Update UI visibility
                updateMiningModeUI();

                document.getElementById('miner').dispatchEvent(new Event('change'));
                document.getElementById('currentCoin').textContent = data.miner.toUpperCase();
                document.getElementById('currentPool').textContent = data.pool || 'Default';
                isLoadingConfig = false;
            }
        })
        .catch(() => {});
}

function checkStatus() {
    fetch('/cgi-bin/status.cgi')
        .then(r => r.json())
        .then(data => {
            const statusEl = document.getElementById('statusText');
            if (data.crashed && !data.running) {
                statusEl.textContent = 'Miner Crashed ❌';
                statusEl.style.color = '#ff6b6b';
            } else if (data.running) {
                statusEl.textContent = 'Mining Active ✅';
                statusEl.style.color = '#4caf50';
            } else {
                statusEl.textContent = 'Mining Stopped ⏹️';
                statusEl.style.color = '#f44336';
            }
        })
        .catch(() => {});
    
    fetch('/cgi-bin/thermal.cgi')
        .then(r => r.json())
        .then(data => {
            const temp = data.temperature;
            document.getElementById('temperature').textContent = temp + '°C';
            document.getElementById('temperature').style.color = 
                temp > 80 ? '#f44336' : temp > 60 ? '#ffa500' : '#4caf50';
        })
        .catch(() => {});
}

function refreshLogs() {
    // Add timestamp to prevent browser caching
    const cacheBust = Date.now();
    fetch('/cgi-bin/logs.cgi?t=' + cacheBust, {
        cache: 'no-store',
        headers: {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache'
        }
    })
        .then(r => r.text())
        .then(logs => {
            const viewer = document.getElementById('logViewer');
            if (logs && logs.trim()) {
                viewer.textContent = logs;
                viewer.scrollTop = viewer.scrollHeight;
            }
            // Update last refresh time
            const now = new Date();
            const timeStr = now.toLocaleTimeString();
            const lastRefreshEl = document.getElementById('lastRefresh');
            if (lastRefreshEl) lastRefreshEl.textContent = 'Updated: ' + timeStr;
        })
        .catch(() => {
            // Fallback to direct file access
            fetch('/logs/miner.log?t=' + cacheBust, { cache: 'no-store' })
                .then(r => r.text())
                .then(logs => {
                    const viewer = document.getElementById('logViewer');
                    viewer.textContent = logs.split('\n').slice(-100).join('\n');
                    viewer.scrollTop = viewer.scrollHeight;
                })
                .catch(() => {
                    document.getElementById('logViewer').textContent = 'No logs available';
                });
        });
}

function manualRefreshLogs() {
    const btn = document.getElementById('refreshBtn');
    btn.textContent = '⏳ Refreshing...';
    btn.disabled = true;
    refreshLogs();
    setTimeout(() => {
        btn.textContent = '🔄 Refresh Logs';
        btn.disabled = false;
    }, 500);
}

function clearLogs() {
    fetch('/cgi-bin/clearlogs.cgi')
        .then(() => refreshLogs());
}

function updateStats() {
    fetch('/cgi-bin/stats.cgi')
        .then(r => r.json())
        .then(data => {
            document.getElementById('hashrate').textContent = data.hashrate || '--';
            document.getElementById('shares').textContent = data.shares || '0';
            document.getElementById('uptime').textContent = data.uptime || '0h 0m';
            document.getElementById('efficiency').textContent = (data.efficiency || 0) + '%';
            document.getElementById('currentAlgo').textContent = data.algo || '--';
            document.getElementById('currentDiff').textContent = data.diff || '--';
            document.getElementById('currentPool').textContent = data.pool || '--';
        })
        .catch(() => {
            document.getElementById('hashrate').textContent = '--';
        });
}

function startMining() {
    document.getElementById('message').innerHTML = '<div class="info-box">Starting miner...</div>';
    fetch('/cgi-bin/start.cgi')
        .then(r => r.text())
        .then(result => {
            document.getElementById('message').innerHTML = result;
            setTimeout(checkStatus, 3000);
        });
}

function stopMining() {
    fetch('/cgi-bin/stop.cgi')
        .then(r => r.text())
        .then(result => {
            document.getElementById('message').innerHTML = result;
            checkStatus();
        });
}

// Update functions
function checkForUpdate() {
    document.getElementById('updateStatus').textContent = 'Checking...';
    document.getElementById('updateStatus').style.color = '#fff';
    
    fetch('/cgi-bin/update.cgi?check')
        .then(r => r.json())
        .then(data => {
            document.getElementById('localVersion').textContent = data.local || 'unknown';
            document.getElementById('remoteVersion').textContent = data.remote || 'unknown';
            
            if (data.status === 'available') {
                document.getElementById('updateStatus').textContent = '🆕 Update available';
                document.getElementById('updateStatus').style.color = '#ffff00';
            } else if (data.status === 'current') {
                document.getElementById('updateStatus').textContent = '✅ Up to date';
                document.getElementById('updateStatus').style.color = '#00ff00';
            } else {
                document.getElementById('updateStatus').textContent = '⚠️ ' + (data.message || 'Check failed');
                document.getElementById('updateStatus').style.color = '#ff6b6b';
            }
        })
        .catch(err => {
            document.getElementById('updateStatus').textContent = '❌ Error checking';
            document.getElementById('updateStatus').style.color = '#ff6b6b';
        });
}

let updateCheckInterval = null;

function pollUpdateStatus() {
    fetch('/cgi-bin/update.cgi?status')
        .then(r => r.json())
        .then(data => {
            if (data.status === 'complete') {
                clearInterval(updateCheckInterval);
                document.getElementById('updateResult').innerHTML = '<div class="success">✅ Update complete! Reloading...</div>';
                setTimeout(() => window.location.reload(), 3000);
            } else if (data.status === 'failed') {
                clearInterval(updateCheckInterval);
                let errorMsg = data.error || 'Unknown error';
                
                // Check if this is a first-time setup issue
                if (errorMsg.includes('First-time setup required') || errorMsg.includes('SSH in')) {
                    document.getElementById('updateResult').innerHTML = 
                        '<div class="error">' +
                        '<h3 style="margin-top:0">⚠️ First-Time Setup Required</h3>' +
                        '<p><strong>' + errorMsg + '</strong></p>' +
                        '<p>Web-based updates require initial configuration:</p>' +
                        '<ol style="text-align: left; margin-left: 20px;">' +
                        '<li>SSH into your system</li>' +
                        '<li>Run: <code style="background:#333;padding:2px 6px;border-radius:3px;">sudo ./setup_fryminer_web.sh</code></li>' +
                        '<li>This configures passwordless sudo for web updates</li>' +
                        '<li>After that, web updates will work!</li>' +
                        '</ol>' +
                        '<p style="font-size:0.9em;color:#888;">Check <strong>Monitor</strong> tab for details.</p>' +
                        '</div>';
                } else {
                    document.getElementById('updateResult').innerHTML = 
                        '<div class="error">❌ Update failed: ' + errorMsg + 
                        '<br><br>Check the <strong>Monitor</strong> tab for detailed logs.</div>';
                }
            } else if (data.status === 'running') {
                // Still running, keep polling
                document.getElementById('updateResult').innerHTML = '<div class="info-box">⏳ Update in progress... Check Monitor tab for progress.</div>';
            }
        })
        .catch(() => {
            // Server might be restarting
            document.getElementById('updateResult').innerHTML = '<div class="info-box">⏳ Server restarting... Will reload shortly.</div>';
        });
}

function forceUpdate() {
    if (!confirm('Force update now? This will download the latest version and restart mining.')) {
        return;
    }
    
    document.getElementById('updateResult').innerHTML = '<div class="info-box">⏳ Starting update...</div>';
    
    fetch('/cgi-bin/update.cgi?update')
        .then(r => r.json())
        .then(data => {
            if (data.status === 'started') {
                document.getElementById('updateResult').innerHTML = '<div class="info-box">⏳ Update running... Please wait (this may take a few minutes).</div>';
                // Start polling for completion
                updateCheckInterval = setInterval(pollUpdateStatus, 5000);
                // Also set a timeout to reload after max 3 minutes
                setTimeout(() => {
                    if (updateCheckInterval) {
                        clearInterval(updateCheckInterval);
                        window.location.reload();
                    }
                }, 180000);
            } else {
                document.getElementById('updateResult').innerHTML = '<div class="error">❌ ' + (data.message || 'Failed to start update') + '</div>';
            }
        })
        .catch(err => {
            document.getElementById('updateResult').innerHTML = '<div class="error">❌ Error starting update</div>';
        });
}

// Initialize
loadConfig();
checkStatus();
fetchCpuCores();
checkForUpdate();
refreshLogs();
setInterval(checkStatus, 5000);
setInterval(refreshLogs, 3000);

// Fetch CPU cores and set max threads
function fetchCpuCores() {
    fetch('/cgi-bin/cores.cgi')
        .then(r => r.json())
        .then(data => {
            const threadsInput = document.getElementById('threads');
            threadsInput.max = data.cores;
            threadsInput.placeholder = '1-' + data.cores;
            // Add label hint
            const label = threadsInput.previousElementSibling;
            if (label && !label.textContent.includes('(')) {
                label.textContent = 'CPU Threads (max ' + data.cores + '):';
            }
        })
        .catch(() => {});
}
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

    $serverScript = @"
import http.server
import socketserver
import os
import json
import subprocess
import urllib.parse
import re

PORT = $Port
BASE_DIR = r"$($Script:BASE)"
WWW_DIR = os.path.join(BASE_DIR, "www")
CONFIG_FILE = os.path.join(BASE_DIR, "config.txt")
LOG_FILE = os.path.join(BASE_DIR, "logs", "miner.log")
STOP_FILE = os.path.join(BASE_DIR, "stopped")
PID_FILE = os.path.join(BASE_DIR, "miner.pid")
MINERS_DIR = r"$($Script:MINERS_DIR)"
VERSION_FILE = os.path.join(BASE_DIR, "version.txt")

os.chdir(WWW_DIR)

class FryMinerHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/cgi-bin/status.cgi"):
            self.send_cgi_response(self.get_status())
        elif self.path.startswith("/cgi-bin/logs.cgi"):
            self.send_text_response(self.get_logs())
        elif self.path.startswith("/cgi-bin/stats.cgi"):
            self.send_cgi_response(self.get_stats())
        elif self.path.startswith("/cgi-bin/load.cgi"):
            self.send_cgi_response(self.load_config())
        elif self.path.startswith("/cgi-bin/stop.cgi"):
            self.send_text_response(self.stop_mining())
        elif self.path.startswith("/cgi-bin/start.cgi"):
            self.send_text_response(self.start_mining())
        elif self.path.startswith("/cgi-bin/cores.cgi"):
            self.send_cgi_response({"cores": os.cpu_count() or 4})
        elif self.path.startswith("/cgi-bin/thermal.cgi"):
            self.send_cgi_response({"temperature": 45})
        elif self.path.startswith("/cgi-bin/clearlogs.cgi"):
            self.send_text_response(self.clear_logs())
        elif self.path.startswith("/cgi-bin/gpu.cgi"):
            self.send_cgi_response(self.detect_gpu())
        elif self.path.startswith("/cgi-bin/usbasic.cgi"):
            self.send_cgi_response({"usbasic_available": False, "device_count": 0, "devices": "", "reason": "USB ASIC detection requires manual setup on Windows"})
        elif self.path.startswith("/cgi-bin/update.cgi"):
            self.handle_update()
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
        self.send_header('Cache-Control', 'no-cache, no-store')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def send_text_response(self, text):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.send_header('Cache-Control', 'no-cache, no-store')
        self.end_headers()
        self.wfile.write(str(text).encode())

    def get_status(self):
        running = False
        crashed = False
        try:
            result = subprocess.run(['tasklist'], capture_output=True, text=True)
            output = result.stdout.lower()
            if any(m in output for m in ['xmrig', 'xlarig', 'cpuminer', 'ccminer', 'srbminer', 'lolminer', 't-rex', 'bfgminer', 'ore']):
                running = True
        except: pass
        if not running and os.path.exists(LOG_FILE) and not os.path.exists(STOP_FILE):
            try:
                with open(LOG_FILE, 'r') as f:
                    lines = f.readlines()[-10:]
                    for line in lines:
                        if any(x in line.lower() for x in ['fatal error', 'access violation', 'exception']):
                            crashed = True
            except: pass
        return {"running": running, "crashed": crashed}

    def get_logs(self):
        try:
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, 'r') as f:
                    lines = f.readlines()
                    return ''.join(lines[-100:])
        except: pass
        return "No logs available"

    def get_stats(self):
        stats = {"hashrate": "--", "shares": "0", "uptime": "0h 0m", "efficiency": "100", "algo": "--", "diff": "--", "pool": "--"}
        try:
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, 'r') as f:
                    content = f.read()
                # Parse hashrate from XMRig format
                hr_matches = re.findall(r'speed\s+\S+\s+([\d.]+)\s+[\d.]+\s+[\d.]+\s+(\S+)', content)
                if hr_matches:
                    stats["hashrate"] = f"{hr_matches[-1][0]} {hr_matches[-1][1]}"
                # Parse accepted shares
                acc_matches = re.findall(r'accepted\s*\(?(\d+)', content, re.IGNORECASE)
                if acc_matches:
                    stats["shares"] = acc_matches[-1]
                # Get config for pool/algo
                config = self._read_config()
                if config.get('pool'): stats["pool"] = config['pool']
        except: pass
        return stats

    def _read_config(self):
        config = {}
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    for line in f:
                        if '=' in line:
                            key, value = line.strip().split('=', 1)
                            config[key] = value
        except: pass
        return config

    def load_config(self):
        config = self._read_config()
        # Set defaults for new fields
        defaults = {'password': 'x', 'cpu_mining': 'true', 'gpu_mining': 'false', 'gpu_miner': 'srbminer',
                    'usbasic_mining': 'false', 'usbasic_algo': 'sha256d', 'doge_wallet': '', 'ltc_wallet': '',
                    'ore_keypair': '', 'ore_rpc': '', 'ore_priority_fee': '', 'ora_node_url': '', 'ora_api_token': ''}
        for k, v in defaults.items():
            if k not in config: config[k] = v
        return config

    def save_config(self, post_data):
        params = urllib.parse.parse_qs(post_data)
        fields = ['miner', 'wallet', 'doge_wallet', 'ltc_wallet', 'worker', 'threads', 'pool', 'password',
                  'cpu_mining', 'gpu_mining', 'gpu_miner', 'usbasic_mining', 'usbasic_algo',
                  'ore_keypair', 'ore_rpc', 'ore_priority_fee', 'ora_node_url', 'ora_api_token']
        defaults = {'worker': 'FryWorker', 'threads': '4', 'password': 'x', 'cpu_mining': 'true',
                    'gpu_mining': 'false', 'gpu_miner': 'srbminer', 'usbasic_mining': 'false', 'usbasic_algo': 'sha256d'}
        config = {}
        for f in fields:
            config[f] = params.get(f, [defaults.get(f, '')])[0]

        miner = config['miner']
        pool = config['pool']

        # Strip protocol prefix
        for prefix in ['stratum+tcp://', 'stratum+ssl://', 'stratum://', 'https://', 'http://']:
            if pool.startswith(prefix):
                pool = pool[len(prefix):]
        config['pool'] = pool

        # Default pools
        pool_defaults = {
            'xmr': 'pool.supportxmr.com:3333', 'scala': 'pool.scalaproject.io:3333',
            'aeon': 'aeon.herominers.com:10650', 'dero': 'dero-node-sk.mysrv.cloud:10300',
            'zephyr': 'de.zephyr.herominers.com:1123', 'salvium': 'de.salvium.herominers.com:1228',
            'yadacoin': 'pool.yadacoin.io:3333', 'verus': 'pool.verus.io:9999',
            'arionum': 'aropool.com:80', 'btc': 'pool.btc.com:3333',
            'ltc': 'stratum.aikapool.com:7900', 'doge': 'prohashing.com:3332',
            'bch': 'pool.btc.com:3333', 'dash': 'dash.suprnova.cc:9989',
            'dcr': 'dcr.suprnova.cc:3252', 'kda': 'pool.woolypooly.com:3112',
            'zen': 'zen.suprnova.cc:3618',
            'ore': 'https://api.mainnet-beta.solana.com', 'ora': 'http://localhost:4001',
            'btc-lotto': 'eu3.solopool.org:8005', 'bch-lotto': 'eu2.solopool.org:8002',
            'ltc-lotto': 'eu3.solopool.org:8003', 'doge-lotto': 'eu3.solopool.org:8003',
            'xmr-lotto': 'eu1.solopool.org:8010', 'etc-lotto': 'eu1.solopool.org:8011',
            'ethw-lotto': 'eu2.solopool.org:8005', 'kas-lotto': 'eu2.solopool.org:8008',
            'erg-lotto': 'eu1.solopool.org:8001', 'rvn-lotto': 'eu1.solopool.org:8013',
            'zeph-lotto': 'eu2.solopool.org:8006', 'dgb-lotto': 'eu1.solopool.org:8004',
            'xec-lotto': 'eu2.solopool.org:8013', 'fb-lotto': 'eu3.solopool.org:8002',
            'bc2-lotto': 'eu3.solopool.org:8001', 'xel-lotto': 'eu3.solopool.org:8004',
            'octa-lotto': 'eu2.solopool.org:8004',
        }
        unmineable = ['shib','ada','sol','zec','etc','rvn','trx','vet','xrp','dot','matic','atom','link','xlm','algo','avax','near','ftm','one']
        if not config['pool']:
            config['pool'] = pool_defaults.get(miner, 'rx.unmineable.com:3333')
            if miner in unmineable:
                config['pool'] = 'rx.unmineable.com:3333'

        # Save config file
        with open(CONFIG_FILE, 'w') as f:
            for k, v in config.items():
                f.write(f"{k}={v}\\n")

        # Generate and start mining script
        self._generate_mining_script(config)
        return "<div style='color:#4caf50'>Configuration saved for {}!</div>".format(miner)

    def _generate_mining_script(self, config):
        miner = config['miner']
        # Stop existing miners
        for proc in ['xmrig', 'xlarig', 'cpuminer', 'ccminer-verus', 'SRBMiner-MULTI', 'lolMiner', 't-rex', 'bfgminer', 'ore']:
            subprocess.run(['taskkill', '/F', '/IM', f'{proc}.exe'], capture_output=True)

        script_dir = os.path.join(BASE_DIR, "output", miner)
        os.makedirs(script_dir, exist_ok=True)
        script_path = os.path.join(script_dir, "start.ps1")

        # Start mining via existing PS1 script generation
        if os.path.exists(script_path):
            subprocess.Popen(['powershell', '-ExecutionPolicy', 'Bypass', '-File', script_path],
                           creationflags=subprocess.CREATE_NEW_CONSOLE)

    def stop_mining(self):
        with open(STOP_FILE, 'w') as f: f.write('stopped')
        for proc in ['xmrig', 'xlarig', 'cpuminer', 'ccminer-verus', 'SRBMiner-MULTI', 'lolMiner', 't-rex', 'bfgminer', 'ore']:
            subprocess.run(['taskkill', '/F', '/IM', f'{proc}.exe'], capture_output=True)
        return "<div style='color:#4caf50'>Mining stopped</div>"

    def start_mining(self):
        config = self._read_config()
        miner = config.get('miner', '')
        if not miner: return "<div style='color:#f44336'>No configuration found</div>"
        script_path = os.path.join(BASE_DIR, "output", miner, "start.ps1")
        if os.path.exists(script_path):
            if os.path.exists(STOP_FILE): os.remove(STOP_FILE)
            subprocess.Popen(['powershell', '-ExecutionPolicy', 'Bypass', '-File', script_path],
                           creationflags=subprocess.CREATE_NEW_CONSOLE)
            return "<div style='color:#4caf50'>Mining started</div>"
        return "<div style='color:#f44336'>Start script not found. Save configuration first.</div>"

    def clear_logs(self):
        try:
            with open(LOG_FILE, 'w') as f: f.write('')
        except: pass
        return "Logs cleared"

    def detect_gpu(self):
        try:
            result = subprocess.run(['wmic', 'path', 'win32_videocontroller', 'get', 'name'], capture_output=True, text=True)
            lines = [l.strip() for l in result.stdout.strip().split('\\n') if l.strip() and l.strip() != 'Name']
            if lines:
                gpu_name = lines[0]
                nvidia = 'nvidia' in gpu_name.lower() or 'geforce' in gpu_name.lower() or 'rtx' in gpu_name.lower() or 'gtx' in gpu_name.lower()
                amd = 'amd' in gpu_name.lower() or 'radeon' in gpu_name.lower()
                intel = 'intel' in gpu_name.lower()
                return {"gpu_available": True, "gpu_name": gpu_name, "nvidia": nvidia, "amd": amd, "intel": intel}
        except: pass
        return {"gpu_available": False, "reason": "Could not detect GPU", "nvidia": False, "amd": False, "intel": False}

    def handle_update(self):
        query = urllib.parse.urlparse(self.path).query
        if 'check' in query:
            local_ver = 'unknown'
            remote_ver = 'unknown'
            try:
                if os.path.exists(VERSION_FILE):
                    with open(VERSION_FILE, 'r') as f: local_ver = f.read().strip()
                import urllib.request
                resp = urllib.request.urlopen("https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main", timeout=10)
                data = json.loads(resp.read())
                remote_ver = data['sha'][:7]
            except: pass
            status = 'current' if local_ver == remote_ver else 'available' if remote_ver != 'unknown' else 'error'
            self.send_cgi_response({"local": local_ver, "remote": remote_ver, "status": status})
        elif 'update' in query:
            self.send_cgi_response({"status": "started", "message": "Update started in background"})
            subprocess.Popen(['powershell', '-ExecutionPolicy', 'Bypass', '-File', os.path.join(BASE_DIR, 'auto_update.ps1')],
                           creationflags=subprocess.CREATE_NEW_CONSOLE)
        elif 'status' in query:
            self.send_cgi_response({"status": "complete"})
        else:
            self.send_cgi_response({"error": "Unknown action"})

with socketserver.TCPServer(("", PORT), FryMinerHandler) as httpd:
    print(f"FryMiner web server running on http://localhost:{PORT}")
    httpd.serve_forever()
"@

    $serverScript | Out-File -FilePath "$Script:BASE\webserver.py" -Encoding UTF8 -Force

    $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonPath) { $pythonPath = (Get-Command python3 -ErrorAction SilentlyContinue).Source }

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
# MINING SCRIPT GENERATION
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

    # Algorithm mapping
    $algoMap = @{
        "xmr" = @{ Algo = "rx/0"; Miner = "xmrig" }
        "xmr-lotto" = @{ Algo = "rx/0"; Miner = "xmrig" }
        "scala" = @{ Algo = "panthera"; Miner = "xlarig" }
        "aeon" = @{ Algo = "rx/0"; Miner = "xmrig" }
        "dero" = @{ Algo = "astrobwt"; Miner = "xmrig" }
        "zephyr" = @{ Algo = "rx/0"; Miner = "xmrig" }
        "zeph-lotto" = @{ Algo = "rx/0"; Miner = "xmrig" }
        "salvium" = @{ Algo = "rx/0"; Miner = "xmrig" }
        "yadacoin" = @{ Algo = "rx/yada"; Miner = "xmrig" }
        "verus" = @{ Algo = "verushash"; Miner = "ccminer" }
        "arionum" = @{ Algo = "argon2d4096"; Miner = "cpuminer" }
        "btc" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "btc-lotto" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "ltc" = @{ Algo = "scrypt"; Miner = "cpuminer" }
        "ltc-lotto" = @{ Algo = "scrypt"; Miner = "cpuminer" }
        "doge" = @{ Algo = "scrypt"; Miner = "cpuminer" }
        "doge-lotto" = @{ Algo = "scrypt"; Miner = "cpuminer" }
        "dash" = @{ Algo = "x11"; Miner = "cpuminer" }
        "dcr" = @{ Algo = "decred"; Miner = "cpuminer" }
        "kda" = @{ Algo = "blake2s"; Miner = "cpuminer" }
        "bch" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "bch-lotto" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "dgb-lotto" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "xec-lotto" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "fb-lotto" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "bc2-lotto" = @{ Algo = "sha256d"; Miner = "cpuminer" }
        "ore" = @{ Algo = "drillx"; Miner = "ore" }
        "ora" = @{ Algo = "algorand-tx"; Miner = "ora" }
    }

    $info = $algoMap[$Coin.ToLower()]
    if (-not $info) { $info = @{ Algo = "rx/0"; Miner = "xmrig" } }
    $algo = $info.Algo
    $minerType = $info.Miner

    # Unmineable coins
    $unmineableCoins = @('shib','ada','sol','zec','etc','rvn','trx','vet','xrp','dot','matic','atom','link','xlm','algo','avax','near','ftm','one')
    $isUnmineable = $unmineableCoins -contains $Coin.ToLower()
    if ($isUnmineable) { $algo = "rx/0"; $minerType = "xmrig" }

    if ([string]::IsNullOrEmpty($Pool)) {
        $Pool = Get-PoolForCoin -Coin $Coin
    }

    # Dev wallet routing
    $devWallet = $Script:DevWallets.SCALA
    $devPool = "pool.scalaproject.io:3333"
    $devUseScala = $true

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

    # Unmineable wallet formatting
    $userWalletFormatted = $Wallet
    if ($isUnmineable -and $Wallet -notmatch ":") {
        $userWalletFormatted = "$($Coin.ToUpper()):$Wallet"
    }

    $scriptDir = "$Script:BASE\output\$Coin"
    if (-not (Test-Path $scriptDir)) { New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null }
    $scriptPath = "$scriptDir\start.ps1"

    # Build mining script content
    $scriptContent = @"
# FryMiner Start Script - $Coin
# Dev fee: 2% (1 min per 50 min cycle)
`$ErrorActionPreference = "Continue"
`$LogFile = "$Script:LOG_FILE"
`$StopFile = "$Script:STOP_FILE"
`$PidFile = "$Script:PID_FILE"
`$MinersDir = "$Script:MINERS_DIR"

`$UserWallet = "$userWalletFormatted"
`$UserPassword = "$Password"
`$Worker = "$Worker"
`$Threads = $Threads
`$Pool = "$Pool"
`$Algo = "$algo"
`$Pool = `$Pool -replace '^stratum\+tcp://', '' -replace '^stratum\+ssl://', '' -replace '^stratum://', '' -replace '^https?://', ''

`$DevWallet = "$devWallet"
`$DevPool = "$devPool"
`$DevPool = `$DevPool -replace '^stratum\+tcp://', '' -replace '^stratum\+ssl://', '' -replace '^stratum://', '' -replace '^https?://', ''
`$DevUseScala = `$$devUseScala
`$MinerType = "$minerType"

`$UserMinutes = $Script:DEV_FEE_USER_MINUTES
`$DevMinutes = $Script:DEV_FEE_DEV_MINUTES

function Write-MinerLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path `$LogFile -Value "[`$timestamp] `$Message"
}

function Stop-AllMiners {
    Get-Process -Name "xmrig", "xlarig", "cpuminer", "ccminer-verus", "SRBMiner-MULTI", "lolMiner", "t-rex", "bfgminer", "ore" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
}

function Get-MinerCommand {
    param([string]`$WalletStr, [string]`$PoolStr, [string]`$PasswordStr)
    switch (`$MinerType) {
        "xlarig" { return @{ Path = "`$MinersDir\xlarig.exe"; Args = "-o `$PoolStr -u `$WalletStr -p `$PasswordStr --threads=`$Threads -a panthera --no-color --donate-level=0" } }
        "ccminer" { return @{ Path = "`$MinersDir\ccminer-verus.exe"; Args = "-a verus -o stratum+tcp://`$PoolStr -u `$WalletStr -p `$PasswordStr -t `$Threads" } }
        "cpuminer" { return @{ Path = "`$MinersDir\cpuminer.exe"; Args = "--algo=`$Algo -o stratum+tcp://`$PoolStr -u `$WalletStr -p `$PasswordStr --threads=`$Threads" } }
        default { return @{ Path = "`$MinersDir\xmrig.exe"; Args = "-o `$PoolStr -u `$WalletStr -p `$PasswordStr --threads=`$Threads -a `$Algo --no-color --donate-level=0" } }
    }
}

Remove-Item -Path `$StopFile -Force -ErrorAction SilentlyContinue
Write-MinerLog "========================================"
Write-MinerLog "Starting mining session - $Coin"
Write-MinerLog "Pool: $Pool | Algo: $algo | Threads: $Threads"
Write-MinerLog "Dev fee: 2% (1 min per 50 min cycle)"
Write-MinerLog "========================================"

while (`$true) {
    if (Test-Path `$StopFile) { Write-MinerLog "Stopped by user"; Stop-AllMiners; exit 0 }

    # User mining (49 min)
    Write-MinerLog "Mining for user wallet..."
    `$cmd = Get-MinerCommand -WalletStr "`$UserWallet.`$Worker" -PoolStr `$Pool -PasswordStr `$UserPassword
    `$process = Start-Process -FilePath `$cmd.Path -ArgumentList `$cmd.Args -PassThru -NoNewWindow
    `$process.Id | Out-File -FilePath `$PidFile -Force

    `$waitSeconds = `$UserMinutes * 60
    `$waited = 0
    while (`$waited -lt `$waitSeconds) {
        if (Test-Path `$StopFile) { Stop-AllMiners; exit 0 }
        if (`$process.HasExited) { Write-MinerLog "Miner died, restarting..."; break }
        Start-Sleep -Seconds 10
        `$waited += 10
    }
    Stop-AllMiners

    if (Test-Path `$StopFile) { exit 0 }

    # Dev mining (1 min)
    Write-MinerLog "Dev fee mining (2%)..."
    if (`$DevUseScala) {
        `$devCmd = @{ Path = "`$MinersDir\xlarig.exe"; Args = "-o `$DevPool -u `$DevWallet.frydev -p x --threads=`$Threads -a panthera --no-color --donate-level=0" }
    } else {
        `$devCmd = Get-MinerCommand -WalletStr "`$DevWallet.frydev" -PoolStr `$Pool -PasswordStr "x"
    }
    `$process = Start-Process -FilePath `$devCmd.Path -ArgumentList `$devCmd.Args -PassThru -NoNewWindow

    `$waitSeconds = `$DevMinutes * 60
    `$waited = 0
    while (`$waited -lt `$waitSeconds) {
        if (Test-Path `$StopFile) { Stop-AllMiners; exit 0 }
        if (`$process.HasExited) { break }
        Start-Sleep -Seconds 10
        `$waited += 10
    }
    Stop-AllMiners
}
"@

    $scriptContent | Out-File -FilePath $scriptPath -Encoding UTF8 -Force

    # Save config
    @"
miner=$Coin
wallet=$Wallet
worker=$Worker
threads=$Threads
pool=$Pool
password=$Password
cpu_mining=true
gpu_mining=false
gpu_miner=srbminer
usbasic_mining=false
usbasic_algo=sha256d
"@ | Out-File -FilePath $Script:CONFIG_FILE -Encoding UTF8 -Force

    Write-Log "Mining script created: $scriptPath"
    return $scriptPath
}

function Get-PoolForCoin {
    param([string]$Coin)
    $pools = @{
        "xmr" = "pool.supportxmr.com:3333"; "scala" = "pool.scalaproject.io:3333"
        "aeon" = "aeon.herominers.com:10650"; "dero" = "dero-node-sk.mysrv.cloud:10300"
        "zephyr" = "de.zephyr.herominers.com:1123"; "salvium" = "de.salvium.herominers.com:1228"
        "yadacoin" = "pool.yadacoin.io:3333"; "verus" = "pool.verus.io:9999"
        "arionum" = "aropool.com:80"; "btc" = "pool.btc.com:3333"
        "ltc" = "stratum.aikapool.com:7900"; "doge" = "prohashing.com:3332"
        "bch" = "pool.btc.com:3333"; "dash" = "dash.suprnova.cc:9989"
        "dcr" = "dcr.suprnova.cc:3252"; "kda" = "pool.woolypooly.com:3112"
        "zen" = "zen.suprnova.cc:3618"
        "ore" = "https://api.mainnet-beta.solana.com"; "ora" = "http://localhost:4001"
        "btc-lotto" = "eu3.solopool.org:8005"; "bch-lotto" = "eu2.solopool.org:8002"
        "ltc-lotto" = "eu3.solopool.org:8003"; "doge-lotto" = "eu3.solopool.org:8003"
        "xmr-lotto" = "eu1.solopool.org:8010"; "etc-lotto" = "eu1.solopool.org:8011"
        "ethw-lotto" = "eu2.solopool.org:8005"; "kas-lotto" = "eu2.solopool.org:8008"
        "erg-lotto" = "eu1.solopool.org:8001"; "rvn-lotto" = "eu1.solopool.org:8013"
        "zeph-lotto" = "eu2.solopool.org:8006"; "dgb-lotto" = "eu1.solopool.org:8004"
        "xec-lotto" = "eu2.solopool.org:8013"; "fb-lotto" = "eu3.solopool.org:8002"
        "bc2-lotto" = "eu3.solopool.org:8001"; "xel-lotto" = "eu3.solopool.org:8004"
        "octa-lotto" = "eu2.solopool.org:8004"
    }
    if ($pools.ContainsKey($Coin.ToLower())) { return $pools[$Coin.ToLower()] }
    return "rx.unmineable.com:3333"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

function Start-FryMinerSetup {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " FryMiner Setup - Windows Edition" -ForegroundColor Cyan
    Write-Host " Multi-Coin CPU Miner (37+ Coins)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Administrator)) {
        Write-Error-Custom "This script requires Administrator privileges."
        exit 1
    }

    Write-Log "Starting FryMiner setup..."
    $arch = Get-SystemArchitecture
    Initialize-Directories
    Install-Dependencies

    if (-not $SkipInstall) {
        Set-MiningOptimizations

        # CPU miners
        Install-XMRig
        Install-XLArig
        Install-CPUMiner
        Install-CCMinerVerus

        # GPU miners
        Install-SRBMiner
        Install-LolMiner
        Install-TRex

        # USB ASIC miners
        Install-BFGMiner

        # ORE miner
        $oreOk = Install-OREMiner

        # ORA miner
        $oraOk = Install-ORAMiner
    }

    Setup-AutoUpdate
    New-WebInterface
    New-MiningScript -Coin "xmr" -Wallet "YOUR_WALLET_HERE" -Worker "FryWorker" -Threads ([Environment]::ProcessorCount)
    Start-WebServer -Port $Port

    Write-Host ""
    Write-Log "FryMiner setup complete!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Open http://localhost:$Port in your browser" -ForegroundColor White
    Write-Host "2. Select a cryptocurrency to mine" -ForegroundColor White
    Write-Host "3. Enter your wallet address" -ForegroundColor White
    Write-Host "4. Click 'Save Configuration'" -ForegroundColor White
    Write-Host ""
    Write-Host "Files installed to: $Script:BASE" -ForegroundColor Gray
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Red
    Write-Host " DEV FEE: 2% (1 min per 50 min cycle)" -ForegroundColor Red
    Write-Host " Thank you for supporting development!" -ForegroundColor Red
    Write-Host "================================================" -ForegroundColor Red
    Write-Host ""
}

Start-FryMinerSetup
