#!/bin/sh
# FryMiner Setup - COMPLETE RESTORED VERSION
# Fixed stratum URL doubling, all 35+ coins restored
# Monitor and Statistics tabs included
# Fixed cpuminer-multi build for ARM64 S905X CPUs
# Added Zephyr (ZEPH) and Salvium (SAL) support
#
# ============================================================================
# DEV FEE DISCLOSURE: FryMiner includes a 2% dev fee to support continued
# development and maintenance. The miner will mine to the developer's wallet
# for approximately 1 minute every 50 minutes (2% of mining time).
# 
# For RandomX-based coins (XMR, Zephyr, Salvium, Yadacoin, Aeon, Unmineable),
# the dev fee is routed through Scala mining for better consolidation.
#
# Thank you for supporting open source development!
# ============================================================================

# DO NOT USE set -e - it causes silent failures
# set -e

# =============================================================================
# DEV FEE CONFIGURATION (2%)
# Dev fee is time-based: mines for dev wallet 2% of the time
# Cycle: 49 minutes user -> 1 minute dev (repeating)
# =============================================================================
DEV_FEE_PERCENT=2
DEV_FEE_CYCLE_MINUTES=50  # Total cycle length
DEV_FEE_USER_MINUTES=49   # Mine for user
DEV_FEE_DEV_MINUTES=1     # Mine for dev

# Dev wallet addresses by coin/algorithm type
DEV_WALLET_XMR="482R7WT5xYVKa2SYHaDtSGWQPv82sgwfSVBGfjV5wez2hbnVTiDRGHb7AEsP5NLGDrBNfFgacPkNSEToGYissp2GRRiSUyo"
DEV_WALLET_LTC="ltc1qrdc0wqzs3cwuhxxzkq2khepec2l3c6uhd8l9jy"
DEV_WALLET_BTC="bc1qr6ldduupwn4dtqq4dwthv4vp3cg2dx7u3mcgva"
DEV_WALLET_DOGE="D5nsUsiivbNv2nmuNE9x2ybkkCTEL4ceHj"
DEV_WALLET_DASH="Xff5VZsVpFxpJYazyQ8hbabzjWAmq1TqPG"
DEV_WALLET_DCR="DsTSHaQRwE9bibKtq5gCtaYZXSp7UhzMiWw"
DEV_WALLET_KDA="k:05178b77e1141ca2319e66cab744e8149349b3f140a676624f231314d483f7a3"
DEV_WALLET_BCH="qrsvjp5987h57x8e6tnv430gq4hnq4jy5vf8u5x4d9"
DEV_WALLET_DERO="dero1qysrv5fp2xethzatpdf80umh8yu2nk404tc3cw2lwypgynj3qvhtgqq294092"
DEV_WALLET_ZEPH="ZEPHsD5WFqKYHXEAqQLj9Nds4ZAS3KbK1Ht98SRy5u9d7Pp2gs6hPpw8UfA1iPgLdUgKpjXx72AjFN1QizwKY2SbXgMzEiQohBn"
DEV_WALLET_SCALA="Ssy2BnsAcJUVZZ2kTiywf61bvYjvPosXzaBcaft9RSvaNNKsFRkcKbaWjMotjATkSbSmeSdX2DAxc1XxpcdxUBGd41oCwwfetG"
DEV_WALLET_VRSC="RRhFqT2bfXQmsnqtyrVxikhy94KqnVf5nt"
DEV_WALLET_SAL="SC1siGvtk7BQ7mkwsjXo57XF4y6SKsX547rfhzHJXGojeRSYoDWknqrJKeYHuMbqhbjSWYvxLppoMdCFjHHhVnrmZUxEc5QdYFj"
DEV_WALLET_YDA="1NLFnpcykRcoAMKX35wyzZm2d8ChbQvXB3"
# For Unmineable tokens, route dev fee to Scala
DEV_WALLET_UNMINEABLE="$DEV_WALLET_SCALA"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

# Root check - smarter handling for UPDATE_MODE
check_root_or_permissions() {
    # If we're root, all good
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    
    # If running as UPDATE_MODE from web interface, check if we have necessary permissions
    if [ "$UPDATE_MODE" = "true" ]; then
        # First, try to get sudo
        if sudo -n true 2>/dev/null; then
            # Re-exec with sudo
            log "Re-executing with sudo..."
            exec sudo -E UPDATE_MODE=true sh "$0" "$@"
        fi
        
        # Check if we can write to key directories (or create them)
        CAN_WRITE=true
        
        # Check /opt/frynet-config
        if [ -d /opt/frynet-config ]; then
            [ -w /opt/frynet-config ] || CAN_WRITE=false
        elif [ -w /opt ]; then
            mkdir -p /opt/frynet-config 2>/dev/null || CAN_WRITE=false
        else
            CAN_WRITE=false
        fi
        
        # Check /usr/local/bin
        if [ -d /usr/local/bin ]; then
            [ -w /usr/local/bin ] || CAN_WRITE=false
        elif [ -w /usr/local ]; then
            mkdir -p /usr/local/bin 2>/dev/null || CAN_WRITE=false
        else
            CAN_WRITE=false
        fi
        
        # Check /opt/miners
        if [ -d /opt/miners ]; then
            [ -w /opt/miners ] || CAN_WRITE=false
        elif [ -w /opt ]; then
            mkdir -p /opt/miners 2>/dev/null || CAN_WRITE=false
        else
            CAN_WRITE=false
        fi
        
        if [ "$CAN_WRITE" = "true" ]; then
            log "Running in UPDATE_MODE with sufficient permissions"
            return 0
        fi
        
        warn "UPDATE_MODE: Insufficient permissions and no sudo access"
        warn "Web update requires one of:"
        warn "  - Running as root"
        warn "  - Passwordless sudo configured"
        warn "  - Write access to /opt/frynet-config, /usr/local/bin, /opt/miners"
        return 1
    fi
    
    # Normal mode - require root
    return 1
}

if ! check_root_or_permissions; then
    die "Run as root (sudo)."
fi

PORT=8080
BASE=/opt/frynet-config
MINERS_DIR=/opt/miners

# Detect architecture - supports ALL CPU architectures
detect_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH_TYPE="x86_64"
            log "Detected architecture: x86_64/amd64"
            ;;
        aarch64|arm64)
            ARCH_TYPE="arm64"
            log "Detected architecture: ARM64/AArch64"
            ;;
        armv8*|armv9*)
            ARCH_TYPE="arm64"
            log "Detected architecture: ARMv8/ARMv9 (using ARM64 build)"
            ;;
        armv7*|armhf|armv7l)
            ARCH_TYPE="armv7"
            log "Detected architecture: ARMv7"
            ;;
        armv6*|armv6l)
            ARCH_TYPE="armv6"
            log "Detected architecture: ARMv6 (Raspberry Pi 1/Zero)"
            ;;
        armv5*|armv4*|arm)
            ARCH_TYPE="armv5"
            log "Detected architecture: ARMv5/ARMv4 (legacy ARM)"
            ;;
        i686|i386|i586)
            ARCH_TYPE="x86"
            log "Detected architecture: x86 32-bit"
            ;;
        riscv64)
            ARCH_TYPE="riscv64"
            log "Detected architecture: RISC-V 64-bit"
            ;;
        ppc64le|ppc64)
            ARCH_TYPE="ppc64"
            log "Detected architecture: PowerPC 64-bit"
            ;;
        mips|mipsel|mips64)
            ARCH_TYPE="mips"
            log "Detected architecture: MIPS"
            ;;
        *)
            ARCH_TYPE="unknown"
            warn "Unknown architecture: $ARCH - will attempt generic build"
            ;;
    esac
}

# Auto-update function - AUTOMATIC daily updates from GitHub
setup_auto_update() {
    log "Setting up automatic daily updates..."
    
    UPDATE_DIR="/opt/frynet-config"
    UPDATE_SCRIPT="$UPDATE_DIR/auto_update.sh"
    VERSION_FILE="$UPDATE_DIR/version.txt"
    
    # Create the auto-update script
    cat > "$UPDATE_SCRIPT" <<'AUTOUPDATE'
#!/bin/sh
# FryMiner Automatic Update Script
# Runs daily via cron, preserves config, restarts mining

REPO_API="https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main"
DOWNLOAD_URL="https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_web.sh"
VERSION_FILE="/opt/frynet-config/version.txt"
CONFIG_FILE="/opt/frynet-config/config.txt"
CONFIG_BACKUP="/opt/frynet-config/config.txt.backup"
LOG_FILE="/opt/frynet-config/logs/update.log"
PID_FILE="/opt/frynet-config/miner.pid"

log_msg() {
    echo "[$(date)] $1" >> "$LOG_FILE"
}

# Get remote version (commit SHA)
get_remote_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -s "$REPO_API" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$REPO_API" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7
    fi
}

# Get local version
get_local_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" 2>/dev/null
    else
        echo "none"
    fi
}

log_msg "=== Auto-update check started ==="

REMOTE_VER=$(get_remote_version)
LOCAL_VER=$(get_local_version)

log_msg "Local version: $LOCAL_VER"
log_msg "Remote version: $REMOTE_VER"

if [ -z "$REMOTE_VER" ]; then
    log_msg "ERROR: Could not fetch remote version (network issue?)"
    exit 1
fi

if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
    log_msg "Already up to date"
    exit 0
fi

log_msg "Update available! Starting update process..."

# Check if miner was running and stop it before updating
WAS_MINING=false
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        WAS_MINING=true
        log_msg "Miner is running, stopping mining for update..."

        # Create stop marker
        touch /opt/frynet-config/stopped 2>/dev/null

        # Stop all mining processes gracefully first
        pkill -TERM -f "xmrig" 2>/dev/null || true
        pkill -TERM -f "xlarig" 2>/dev/null || true
        pkill -TERM -f "cpuminer" 2>/dev/null || true
        pkill -TERM -f "SRBMiner-MULTI" 2>/dev/null || true
        pkill -TERM -f "lolMiner" 2>/dev/null || true
        pkill -TERM -f "t-rex" 2>/dev/null || true
        pkill -TERM -f "bfgminer" 2>/dev/null || true
        pkill -TERM -f "cgminer" 2>/dev/null || true

        # Wait for graceful shutdown
        sleep 3

        # Force kill any remaining
        pkill -9 -f "xmrig" 2>/dev/null || true
        pkill -9 -f "xlarig" 2>/dev/null || true
        pkill -9 -f "cpuminer" 2>/dev/null || true
        pkill -9 -f "SRBMiner-MULTI" 2>/dev/null || true
        pkill -9 -f "lolMiner" 2>/dev/null || true
        pkill -9 -f "t-rex" 2>/dev/null || true
        pkill -9 -f "bfgminer" 2>/dev/null || true
        pkill -9 -f "cgminer" 2>/dev/null || true

        sleep 2
        log_msg "Mining stopped for update"
    fi
fi

# Backup current config
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CONFIG_BACKUP"
    log_msg "Config backed up"
fi

# Download new version
TEMP_SCRIPT="/tmp/fryminer_update_$$.sh"
if command -v curl >/dev/null 2>&1; then
    curl -sL -o "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null
else
    wget -q -O "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null
fi

if [ ! -s "$TEMP_SCRIPT" ]; then
    log_msg "ERROR: Failed to download update"
    rm -f "$TEMP_SCRIPT"
    exit 1
fi

log_msg "Downloaded update, installing..."

# Run the update script
chmod +x "$TEMP_SCRIPT"
sh "$TEMP_SCRIPT" >> "$LOG_FILE" 2>&1
UPDATE_STATUS=$?

if [ $UPDATE_STATUS -eq 0 ]; then
    # Restore config
    if [ -f "$CONFIG_BACKUP" ]; then
        cp "$CONFIG_BACKUP" "$CONFIG_FILE"
        log_msg "Config restored"
    fi
    
    # Update version file
    echo "$REMOTE_VER" > "$VERSION_FILE"
    log_msg "Version updated to $REMOTE_VER"
    
    # Restart mining if it was running before
    if [ "$WAS_MINING" = "true" ] && [ -f "$CONFIG_FILE" ]; then
        log_msg "Restarting mining..."
        sleep 3

        # Remove stop marker so mining can start
        rm -f /opt/frynet-config/stopped 2>/dev/null

        # Source config and find start script
        . "$CONFIG_FILE"
        SCRIPT_FILE="/opt/frynet-config/output/$miner/start.sh"

        if [ -f "$SCRIPT_FILE" ]; then
            # Kill any existing miners (just in case)
            pkill -9 -f "xmrig" 2>/dev/null || true
            pkill -9 -f "xlarig" 2>/dev/null || true
            pkill -9 -f "cpuminer" 2>/dev/null || true
            # GPU miners
            pkill -9 -f "SRBMiner-MULTI" 2>/dev/null || true
            pkill -9 -f "lolMiner" 2>/dev/null || true
            pkill -9 -f "t-rex" 2>/dev/null || true
            # USB ASIC miners
            pkill -9 -f "bfgminer" 2>/dev/null || true
            pkill -9 -f "cgminer" 2>/dev/null || true
            sleep 2

            # Start miner - script handles its own logging
            nohup sh "$SCRIPT_FILE" >/dev/null 2>&1 &
            NEW_PID=$!
            echo "$NEW_PID" > "$PID_FILE"
            log_msg "Mining restarted with PID $NEW_PID"
        else
            log_msg "WARNING: Start script not found at $SCRIPT_FILE"
            log_msg "Mining was active but cannot auto-restart."
            log_msg "Please re-save configuration via web interface to regenerate start script."
            # Also log to miner log for visibility in the Activity tab
            MINER_LOG="/opt/frynet-config/logs/miner.log"
            echo "[$(date)] WARNING: Auto-update completed but start script missing" >> "$MINER_LOG"
            echo "[$(date)] Expected: $SCRIPT_FILE" >> "$MINER_LOG"
            echo "[$(date)] Please click 'Save' in web interface to regenerate and restart mining" >> "$MINER_LOG"
        fi
    fi
    
    log_msg "=== Update completed successfully ==="
else
    log_msg "ERROR: Update failed with status $UPDATE_STATUS"
    # Restore backup config on failure
    if [ -f "$CONFIG_BACKUP" ]; then
        cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    fi
fi

rm -f "$TEMP_SCRIPT"
AUTOUPDATE
    chmod 755 "$UPDATE_SCRIPT"
    
    # Set initial version from GitHub (with timeout to prevent hanging)
    log "Fetching current version from GitHub..."
    CURRENT_VER=""
    if command -v curl >/dev/null 2>&1; then
        CURRENT_VER=$(curl -s --connect-timeout 5 --max-time 10 "https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7)
    elif command -v wget >/dev/null 2>&1; then
        CURRENT_VER=$(wget -qO- --timeout=10 "https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7)
    fi
    
    if [ -n "$CURRENT_VER" ]; then
        echo "$CURRENT_VER" > "$VERSION_FILE"
        log "Version set to: $CURRENT_VER"
    else
        echo "unknown" > "$VERSION_FILE"
        warn "Could not fetch version (will update on next check)"
    fi
    
    # Setup daily cron job (skip if cron not available)
    if command -v crontab >/dev/null 2>&1; then
        log "Setting up daily auto-update cron job..."
        
        # Ensure cron service is running
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
            systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true
        elif command -v service >/dev/null 2>&1; then
            service cron start 2>/dev/null || service crond start 2>/dev/null || true
        fi
        
        # Remove any existing fryminer cron entries
        (crontab -l 2>/dev/null || echo "") | grep -v "fryminer\|auto_update" > /tmp/crontab.tmp 2>/dev/null || true
        
        # Add new cron job - runs at 4 AM daily
        echo "0 4 * * * /opt/frynet-config/auto_update.sh >/dev/null 2>&1" >> /tmp/crontab.tmp
        
        crontab /tmp/crontab.tmp 2>/dev/null && log "Cron job installed" || warn "Could not set up cron job"
        rm -f /tmp/crontab.tmp
    else
        warn "crontab not available - auto-update cron job not installed"
        log "You can manually run: /opt/frynet-config/auto_update.sh"
    fi
    
    # Create update log
    touch /opt/frynet-config/logs/update.log 2>/dev/null || true
    chmod 666 /opt/frynet-config/logs/update.log 2>/dev/null || true
    
    log "Auto-update configured"
}

# Set hostname
set_hostname() {
    log "Setting hostname..."
    MAC=$(ip link 2>/dev/null | grep -m 1 'link/ether' | awk '{print $2}' | tr -d ':' | tail -c 5)
    if [ -n "$MAC" ]; then
        NEW_HOSTNAME="FryNetworks${MAC}"
        hostname "$NEW_HOSTNAME" 2>/dev/null || true
        echo "$NEW_HOSTNAME" > /etc/hostname 2>/dev/null || true
        log "Hostname set to: $NEW_HOSTNAME"
    fi
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update >/dev/null 2>&1
        # Core dependencies
        apt-get install -y wget curl tar gzip python3 ca-certificates lsof coreutils cron >/dev/null 2>&1 || true
        
        # Build tools for compiling from source
        apt-get install -y build-essential git automake autoconf make g++ cmake pkg-config >/dev/null 2>&1 || true
        
        # XMRig specific dependencies
        apt-get install -y libuv1-dev libssl-dev libhwloc-dev >/dev/null 2>&1 || true
        
        # cpuminer dependencies  
        apt-get install -y libcurl4-openssl-dev libjansson-dev libgmp-dev >/dev/null 2>&1 || true
        
        # Mining optimizations (x86 only - msr-tools doesn't work on ARM)
        if [ "$ARCH_TYPE" = "x86_64" ] || [ "$ARCH_TYPE" = "x86" ]; then
            apt-get install -y msr-tools cpufrequtils >/dev/null 2>&1 || true
        else
            # ARM only needs cpufrequtils
            apt-get install -y cpufrequtils >/dev/null 2>&1 || true
        fi
        
    elif command -v yum >/dev/null 2>&1; then
        # Core dependencies
        yum install -y wget curl tar gzip python3 ca-certificates lsof coreutils cronie >/dev/null 2>&1 || true
        
        # Build tools
        yum install -y gcc gcc-c++ make git automake autoconf cmake pkgconfig >/dev/null 2>&1 || true
        
        # XMRig specific dependencies
        yum install -y libuv-devel openssl-devel hwloc-devel >/dev/null 2>&1 || true
        
        # cpuminer dependencies
        yum install -y libcurl-devel jansson-devel gmp-devel >/dev/null 2>&1 || true
        
        # Mining optimizations (x86 only - msr-tools doesn't work on ARM)
        if [ "$ARCH_TYPE" = "x86_64" ] || [ "$ARCH_TYPE" = "x86" ]; then
            yum install -y msr-tools cpufrequtils >/dev/null 2>&1 || true
        else
            # ARM only needs cpufrequtils
            yum install -y cpufrequtils >/dev/null 2>&1 || true
        fi
        
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        pacman -Sy --noconfirm wget curl tar gzip python3 ca-certificates lsof coreutils cronie >/dev/null 2>&1 || true
        pacman -Sy --noconfirm base-devel git cmake libuv openssl hwloc curl jansson gmp >/dev/null 2>&1 || true
        
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        apk add --no-cache wget curl tar gzip python3 ca-certificates lsof coreutils >/dev/null 2>&1 || true
        apk add --no-cache build-base git cmake libuv-dev openssl-dev hwloc-dev curl-dev jansson-dev gmp-dev >/dev/null 2>&1 || true
    fi
    
    log "Dependencies installed"
    
    # Verify critical build tools
    if ! command -v cmake >/dev/null 2>&1; then
        warn "⚠️  cmake not installed - XMRig will fail to build from source"
    fi
    if ! command -v git >/dev/null 2>&1; then
        warn "⚠️  git not installed - Cannot clone source repositories"
    fi
    if ! command -v gcc >/dev/null 2>&1; then
        warn "⚠️  gcc not installed - Cannot compile from source"
    fi
}

# Remove Docker if installed (no longer needed after PacketCrypt removal)
remove_docker_if_present() {
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        log "Docker not installed - skipping removal"
        return 0
    fi

    log "Docker detected - removing..."

    # Stop any running Docker containers
    if docker ps -q 2>/dev/null | grep -q .; then
        log "Stopping running Docker containers..."
        docker stop $(docker ps -q) 2>/dev/null || true
    fi

    # Stop Docker service
    if command -v systemctl >/dev/null 2>&1; then
        log "Stopping Docker service..."
        systemctl stop docker.socket 2>/dev/null || true
        systemctl stop docker 2>/dev/null || true
        systemctl stop containerd 2>/dev/null || true

        log "Disabling Docker service..."
        systemctl disable docker.socket 2>/dev/null || true
        systemctl disable docker 2>/dev/null || true
        systemctl disable containerd 2>/dev/null || true

        log "Masking Docker service..."
        systemctl mask docker.socket 2>/dev/null || true
        systemctl mask docker 2>/dev/null || true
        systemctl mask containerd 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        service docker stop 2>/dev/null || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service docker stop 2>/dev/null || true
        rc-update del docker 2>/dev/null || true
    fi

    # Remove Docker packages based on package manager
    log "Removing Docker packages..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-compose docker-doc podman-docker 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Rns --noconfirm docker docker-compose containerd 2>/dev/null || true
    elif command -v apk >/dev/null 2>&1; then
        apk del docker docker-compose docker-cli containerd 2>/dev/null || true
    fi

    # Remove Docker data directories
    log "Removing Docker data directories..."
    rm -rf /var/lib/docker 2>/dev/null || true
    rm -rf /var/lib/containerd 2>/dev/null || true
    rm -rf /etc/docker 2>/dev/null || true
    rm -rf ~/.docker 2>/dev/null || true

    # Remove Docker group (optional - users may still be in it)
    # groupdel docker 2>/dev/null || true

    # Remove any packetcrypt wrapper that used Docker
    if [ -f /usr/local/bin/packetcrypt ]; then
        log "Removing old packetcrypt wrapper..."
        rm -f /usr/local/bin/packetcrypt 2>/dev/null || true
    fi

    log "✅ Docker removed successfully"
}

# Optimize system for mining (huge pages, MSR, CPU governor)
optimize_for_mining() {
    log "Applying mining optimizations..."
    
    # Skip heavy optimizations on ARM - they have limited RAM and don't support MSR
    if [ "$ARCH_TYPE" != "x86_64" ] && [ "$ARCH_TYPE" != "x86" ]; then
        log "  ARM device detected - skipping huge pages and MSR (limited RAM, not supported)"
        
        # Only set CPU governor to performance mode on ARM
        log "  Setting CPU to performance mode..."
        for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [ -f "$gov" ] && echo "performance" > "$gov" 2>/dev/null || true
        done
        
        # Create minimal optimization script for ARM
        cat > /opt/frynet-config/optimize.sh <<'OPTSCRIPT'
#!/bin/sh
# Mining optimization script for ARM - minimal version

# Set performance governor
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo "performance" > "$gov" 2>/dev/null
done

echo "ARM optimizations applied (performance governor)"
OPTSCRIPT
        chmod 755 /opt/frynet-config/optimize.sh
        
        log "ARM mining optimizations applied (CPU governor only)"
        return 0
    fi
    
    # x86/x86_64 optimizations below
    
    # 1. Enable huge pages (gives 20-30% boost for RandomX)
    log "  Configuring huge pages..."
    
    # RandomX needs ~2336 MB for dataset + scratchpads
    # 2MB huge pages: need at least 1200 pages
    # Plus some buffer for the system
    HUGE_PAGES=1280
    
    # Set huge pages
    sysctl -w vm.nr_hugepages=$HUGE_PAGES >/dev/null 2>&1 || true
    
    # Make persistent across reboots
    if grep -q "vm.nr_hugepages" /etc/sysctl.conf 2>/dev/null; then
        sed -i "s/vm.nr_hugepages=.*/vm.nr_hugepages=$HUGE_PAGES/" /etc/sysctl.conf 2>/dev/null || true
    else
        echo "vm.nr_hugepages=$HUGE_PAGES" >> /etc/sysctl.conf 2>/dev/null || true
    fi
    
    # Set huge page permissions for all users
    if ! grep -q "memlock" /etc/security/limits.conf 2>/dev/null; then
        echo "* soft memlock unlimited" >> /etc/security/limits.conf 2>/dev/null || true
        echo "* hard memlock unlimited" >> /etc/security/limits.conf 2>/dev/null || true
    fi
    
    # 2. Enable MSR for RandomX boost (10-15% improvement)
    log "  Enabling MSR access..."
    modprobe msr 2>/dev/null || true
    
    # Try to enable MSR writes for RandomX
    if [ -f /sys/module/msr/parameters/allow_writes ]; then
        echo on > /sys/module/msr/parameters/allow_writes 2>/dev/null || true
    fi
    
    # 3. Set CPU governor to performance mode
    log "  Setting CPU to performance mode..."
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$gov" ] && echo "performance" > "$gov" 2>/dev/null || true
    done
    
    # 4. Disable CPU frequency scaling limits
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do
        if [ -f "$cpu" ]; then
            MAX_FREQ=$(cat "${cpu%min_freq}scaling_max_freq" 2>/dev/null)
            [ -n "$MAX_FREQ" ] && echo "$MAX_FREQ" > "$cpu" 2>/dev/null || true
        fi
    done
    
    # 5. Create optimization script that runs before mining
    cat > /opt/frynet-config/optimize.sh <<'OPTSCRIPT'
#!/bin/sh
# Mining optimization script - run before starting miner

# Enable huge pages (need ~1200 for RandomX dataset)
sysctl -w vm.nr_hugepages=1280 >/dev/null 2>&1

# Load MSR module
modprobe msr 2>/dev/null
[ -f /sys/module/msr/parameters/allow_writes ] && echo on > /sys/module/msr/parameters/allow_writes 2>/dev/null

# Set performance governor
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$gov" ] && echo "performance" > "$gov" 2>/dev/null
done

# Verify huge pages
HP_TOTAL=$(grep HugePages_Total /proc/meminfo 2>/dev/null | awk '{print $2}')
HP_FREE=$(grep HugePages_Free /proc/meminfo 2>/dev/null | awk '{print $2}')
echo "Huge Pages: $HP_FREE free of $HP_TOTAL total (need ~1200 for RandomX)"
OPTSCRIPT
    chmod 755 /opt/frynet-config/optimize.sh
    
    # Check results
    HP_TOTAL=$(grep HugePages_Total /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [ -n "$HP_TOTAL" ] && [ "$HP_TOTAL" -gt 0 ]; then
        log "  Huge pages enabled: $HP_TOTAL pages (2MB each)"
    else
        warn "  Could not enable huge pages (may need reboot)"
    fi
    
    log "Mining optimizations applied"
}

# Install XMRig - SUPPORTS ALL ARCHITECTURES
install_xmrig() {
    log "=== Starting XMRig installation ==="
    
    # Test if existing xmrig works
    if command -v xmrig >/dev/null 2>&1; then
        log "Testing existing xmrig..."
        if xmrig --version >/dev/null 2>&1; then
            log "XMRig already installed and working"
            return 0
        else
            warn "Existing XMRig is broken, reinstalling..."
            rm -f /usr/local/bin/xmrig 2>/dev/null
        fi
    fi
    
    log "Installing XMRig for $ARCH_TYPE..."
    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR" || { warn "Failed to cd to $MINERS_DIR"; return 1; }
    rm -rf xmrig xmrig.tar.gz xmrig-* 2>/dev/null
    
    case "$ARCH_TYPE" in
        x86_64)
            log "Downloading pre-built XMRig for x86_64..."
            DOWNLOAD_SUCCESS=false
            
            if command -v curl >/dev/null 2>&1; then
                if curl -sL -o xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-x64.tar.gz" 2>/dev/null; then
                    DOWNLOAD_SUCCESS=true
                fi
            elif command -v wget >/dev/null 2>&1; then
                if wget -q -O xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-x64.tar.gz" 2>/dev/null; then
                    DOWNLOAD_SUCCESS=true
                fi
            fi
            
            # Try to extract if download succeeded
            if [ "$DOWNLOAD_SUCCESS" = "true" ] && [ -f xmrig.tar.gz ]; then
                log "Extracting..."
                if tar -xzf xmrig.tar.gz 2>/dev/null; then
                    find . -name "xmrig" -type f -executable -exec cp {} /usr/local/bin/xmrig \; 2>/dev/null
                    chmod +x /usr/local/bin/xmrig 2>/dev/null
                    rm -rf xmrig* 2>/dev/null
                    
                    # Verify it actually works
                    if ! /usr/local/bin/xmrig --version >/dev/null 2>&1; then
                        warn "Downloaded XMRig doesn't work, will build from source..."
                        rm -f /usr/local/bin/xmrig
                        DOWNLOAD_SUCCESS=false
                    fi
                else
                    warn "Failed to extract prebuilt XMRig, will build from source..."
                    DOWNLOAD_SUCCESS=false
                fi
            fi
            
            # Fallback: Build from source if prebuilt failed
            if [ "$DOWNLOAD_SUCCESS" != "true" ]; then
                log "Building XMRig from source for x86_64..."
                rm -rf xmrig xmrig.tar.gz 2>/dev/null
                
                # Check dependencies
                if ! command -v git >/dev/null 2>&1; then
                    warn "❌ git not installed - install it first: apt-get install git"
                    return 1
                fi
                
                if ! command -v cmake >/dev/null 2>&1; then
                    warn "❌ cmake not installed - install it first: apt-get install cmake"
                    return 1
                fi
                
                if ! command -v gcc >/dev/null 2>&1; then
                    warn "❌ gcc not installed - install it first: apt-get install build-essential"
                    return 1
                fi
                
                log "Cloning XMRig repository..."
                if ! git clone --depth 1 https://github.com/xmrig/xmrig.git 2>&1; then
                    warn "❌ git clone failed - check network connection"
                    return 1
                fi
                
                cd xmrig || { warn "❌ Failed to cd to xmrig directory"; return 1; }
                mkdir -p build && cd build || { warn "❌ Failed to create build directory"; return 1; }
                
                log "Running cmake (this may take a minute)..."
                CMAKE_OUTPUT=$(cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_HWLOC=OFF 2>&1)
                CMAKE_EXIT=$?
                
                if [ $CMAKE_EXIT -ne 0 ]; then
                    warn "❌ cmake configuration failed:"
                    echo "$CMAKE_OUTPUT" | tail -20
                    cd "$MINERS_DIR"
                    return 1
                fi
                
                log "Building XMRig (this takes 2-5 minutes)..."
                BUILD_OUTPUT=$(make -j"$(nproc)" 2>&1)
                BUILD_EXIT=$?
                
                if [ $BUILD_EXIT -ne 0 ]; then
                    warn "❌ Build failed:"
                    echo "$BUILD_OUTPUT" | grep -i "error" | tail -10
                    cd "$MINERS_DIR"
                    return 1
                fi
                
                if [ -f xmrig ]; then
                    cp xmrig /usr/local/bin/xmrig 2>/dev/null
                    chmod +x /usr/local/bin/xmrig
                    log "✅ Built from source successfully"
                else
                    warn "❌ Build completed but xmrig binary not found"
                    cd "$MINERS_DIR"
                    return 1
                fi
                
                cd "$MINERS_DIR"
                rm -rf xmrig
            fi
            ;;
            
        arm64)
            log "Downloading pre-built XMRig for ARM64..."
            if command -v curl >/dev/null 2>&1; then
                curl -sL -o xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-arm64.tar.gz" 2>/dev/null
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-arm64.tar.gz" 2>/dev/null
            fi
            
            if [ -f xmrig.tar.gz ] && tar -tzf xmrig.tar.gz >/dev/null 2>&1; then
                log "Extracting..."
                tar -xzf xmrig.tar.gz 2>/dev/null
                find . -name "xmrig" -type f -executable -exec cp {} /usr/local/bin/xmrig \; 2>/dev/null
                chmod +x /usr/local/bin/xmrig 2>/dev/null
                rm -rf xmrig* 2>/dev/null
            else
                log "Building from source for ARM64..."
                rm -f xmrig.tar.gz 2>/dev/null
                git clone --depth 1 --progress https://github.com/xmrig/xmrig.git 2>&1 || return 1
                cd xmrig || return 1
                mkdir -p build && cd build || return 1
                cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_HWLOC=OFF >/dev/null 2>&1
                make -j"$(nproc)" >/dev/null 2>&1
                cp xmrig /usr/local/bin/xmrig 2>/dev/null
                cd "$MINERS_DIR"
                rm -rf xmrig
            fi
            ;;
            
        armv7|armv6)
            log "Building XMRig from source for $ARCH_TYPE (15-30 min)..."
            git clone --depth 1 --progress https://github.com/xmrig/xmrig.git 2>&1 || return 1
            cd xmrig || return 1
            mkdir -p build && cd build || return 1
            cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_HWLOC=OFF -DARM_TARGET=7 >/dev/null 2>&1
            make -j"$(nproc)" >/dev/null 2>&1
            cp xmrig /usr/local/bin/xmrig 2>/dev/null
            cd "$MINERS_DIR"
            rm -rf xmrig
            ;;
            
        *)
            log "Building XMRig from source for $ARCH_TYPE..."
            git clone --depth 1 --progress https://github.com/xmrig/xmrig.git 2>&1 || return 1
            cd xmrig || return 1
            mkdir -p build && cd build || return 1
            cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_HWLOC=OFF >/dev/null 2>&1
            make -j"$(nproc)" >/dev/null 2>&1 || warn "XMRig build may have failed"
            cp xmrig /usr/local/bin/xmrig 2>/dev/null
            cd "$MINERS_DIR"
            rm -rf xmrig
            ;;
    esac
    
    if command -v xmrig >/dev/null 2>&1; then
        log "XMRig installed successfully"
        xmrig --version 2>&1 | head -1 || true
        return 0
    else
        warn "XMRig installation failed for $ARCH_TYPE"
        return 1
    fi
}

# Install XLArig - Scala (XLA) miner with Panthera algorithm support
install_xlarig() {
    log "=== Starting XLArig installation (for Scala mining) ==="
    
    # Check if xlarig already exists and works
    if [ -f /usr/local/bin/xlarig ]; then
        log "Testing existing xlarig..."
        if /usr/local/bin/xlarig --version >/dev/null 2>&1; then
            log "XLArig already installed and working"
            /usr/local/bin/xlarig --version 2>&1 | head -1 || true
            return 0
        else
            warn "Existing XLArig is broken, reinstalling..."
            rm -f /usr/local/bin/xlarig 2>/dev/null
        fi
    fi
    
    ARCH_TYPE=$(uname -m)
    XLARIG_VERSION="5.2.4"
    MINERS_DIR="/opt/miners"
    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR" || return 1
    
    # Clean up any old attempts
    rm -rf XLArig* xlarig* 2>/dev/null
    
    case "$ARCH_TYPE" in
        x86_64|amd64)
            log "Installing XLArig for x86_64..."
            DOWNLOAD_URL="https://github.com/scala-network/XLArig/releases/download/v${XLARIG_VERSION}/XLArig-v${XLARIG_VERSION}-linux-x86_64.zip"
            
            if curl -sL -o xlarig.zip "$DOWNLOAD_URL" 2>/dev/null || wget -q -O xlarig.zip "$DOWNLOAD_URL" 2>/dev/null; then
                if unzip -q xlarig.zip 2>/dev/null; then
                    # Find the xlarig binary
                    XLARIG_BIN=$(find . -name "xlarig" -type f -executable 2>/dev/null | head -1)
                    if [ -z "$XLARIG_BIN" ]; then
                        XLARIG_BIN=$(find . -name "xlarig" -type f 2>/dev/null | head -1)
                    fi
                    
                    if [ -n "$XLARIG_BIN" ]; then
                        cp "$XLARIG_BIN" /usr/local/bin/xlarig
                        chmod +x /usr/local/bin/xlarig
                        rm -rf XLArig* xlarig* 2>/dev/null
                        log "✅ XLArig binary installed"
                    else
                        warn "XLArig binary not found in archive"
                    fi
                else
                    warn "Failed to unzip XLArig"
                fi
            else
                warn "Failed to download XLArig, will try building from source..."
            fi
            ;;
            
        aarch64|arm64)
            log "Installing XLArig for ARM64..."
            # Try aarch64 clang build first (better compatibility)
            DOWNLOAD_URL="https://github.com/scala-network/XLArig/releases/download/v${XLARIG_VERSION}/XLArig-v${XLARIG_VERSION}-linux-aarch64.zip"
            
            if curl -sL -o xlarig.zip "$DOWNLOAD_URL" 2>/dev/null || wget -q -O xlarig.zip "$DOWNLOAD_URL" 2>/dev/null; then
                if unzip -q xlarig.zip 2>/dev/null; then
                    XLARIG_BIN=$(find . -name "xlarig" -type f -executable 2>/dev/null | head -1)
                    if [ -z "$XLARIG_BIN" ]; then
                        XLARIG_BIN=$(find . -name "xlarig" -type f 2>/dev/null | head -1)
                    fi
                    
                    if [ -n "$XLARIG_BIN" ]; then
                        cp "$XLARIG_BIN" /usr/local/bin/xlarig
                        chmod +x /usr/local/bin/xlarig
                        rm -rf XLArig* xlarig* 2>/dev/null
                        log "✅ XLArig ARM64 binary installed"
                    else
                        warn "XLArig binary not found in archive"
                    fi
                else
                    warn "Failed to unzip XLArig"
                fi
            else
                warn "Failed to download XLArig for ARM64"
            fi
            ;;
            
        armv7*|armhf)
            log "Installing XLArig for ARMv7..."
            DOWNLOAD_URL="https://github.com/scala-network/XLArig/releases/download/v${XLARIG_VERSION}/XLArig-v${XLARIG_VERSION}-linux-armv7.zip"
            
            if curl -sL -o xlarig.zip "$DOWNLOAD_URL" 2>/dev/null || wget -q -O xlarig.zip "$DOWNLOAD_URL" 2>/dev/null; then
                if unzip -q xlarig.zip 2>/dev/null; then
                    XLARIG_BIN=$(find . -name "xlarig" -type f 2>/dev/null | head -1)
                    if [ -n "$XLARIG_BIN" ]; then
                        cp "$XLARIG_BIN" /usr/local/bin/xlarig
                        chmod +x /usr/local/bin/xlarig
                        rm -rf XLArig* xlarig* 2>/dev/null
                        log "✅ XLArig ARMv7 binary installed"
                    fi
                fi
            else
                warn "No pre-built XLArig for ARMv7"
            fi
            ;;
            
        *)
            warn "Unknown architecture $ARCH_TYPE for XLArig"
            ;;
    esac
    
    # If binary download failed, try building from source
    if ! command -v xlarig >/dev/null 2>&1 && [ ! -f /usr/local/bin/xlarig ]; then
        log "Attempting to build XLArig from source..."
        cd "$MINERS_DIR" || return 1
        rm -rf XLArig 2>/dev/null
        
        if git clone --depth 1 https://github.com/scala-network/XLArig.git 2>&1; then
            cd XLArig || return 1
            mkdir -p build && cd build || return 1
            
            log "Configuring XLArig build..."
            if cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_HWLOC=OFF >/dev/null 2>&1; then
                log "Compiling XLArig (this may take a while)..."
                if make -j"$(nproc)" >/dev/null 2>&1; then
                    if [ -f xlarig ]; then
                        cp xlarig /usr/local/bin/xlarig
                        chmod +x /usr/local/bin/xlarig
                        log "✅ XLArig built from source"
                    fi
                else
                    warn "XLArig compilation failed"
                fi
            else
                warn "XLArig cmake configuration failed"
            fi
            
            cd "$MINERS_DIR"
            rm -rf XLArig 2>/dev/null
        else
            warn "Failed to clone XLArig repository"
        fi
    fi
    
    # Final check
    if [ -f /usr/local/bin/xlarig ]; then
        if /usr/local/bin/xlarig --version >/dev/null 2>&1; then
            log "✅ XLArig installed successfully"
            /usr/local/bin/xlarig --version 2>&1 | head -1 || true
            return 0
        else
            warn "XLArig binary exists but may not work on this system"
            return 1
        fi
    else
        warn "❌ XLArig installation failed - Scala mining will not be available"
        return 1
    fi
}

# Install cpuminer - FORCE REBUILD for compatibility - SUPPORTS ALL ARCHITECTURES
install_cpuminer() {
    log "=== Starting cpuminer installation ==="
    
    # First check if we have a WORKING cpuminer already
    if command -v cpuminer >/dev/null 2>&1; then
        log "Found existing cpuminer, testing..."
        if cpuminer --version >/dev/null 2>&1; then
            EXISTING_VER=$(cpuminer --version 2>&1 | head -1)
            log "Existing cpuminer works: $EXISTING_VER"
            # Check if it's cpuminer-opt (crashes on old CPUs) or cpuminer-multi (safer)
            if echo "$EXISTING_VER" | grep -qi "cpuminer-opt"; then
                log "Found cpuminer-opt - rebuilding with cpuminer-multi for compatibility..."
            else
                log "Existing cpuminer is compatible, skipping rebuild"
                return 0
            fi
        else
            log "Existing cpuminer is broken, will rebuild"
        fi
    else
        log "No cpuminer found, will install"
    fi
    
    # Remove existing binaries
    log "Removing old cpuminer binaries..."
    rm -f /usr/local/bin/cpuminer /usr/local/bin/minerd /usr/local/bin/cpuminer-opt /usr/local/bin/cpuminer-multi 2>/dev/null
    rm -f /usr/bin/cpuminer /usr/bin/minerd 2>/dev/null
    rm -f /opt/miners/cpuminer /opt/miners/minerd 2>/dev/null
    hash -r 2>/dev/null || true
    log "Old binaries removed"
    
    # Check for git
    log "Checking for git..."
    if ! command -v git >/dev/null 2>&1; then
        warn "git not found - attempting to install..."
        apt-get update >/dev/null 2>&1
        apt-get install -y git >/dev/null 2>&1 || yum install -y git >/dev/null 2>&1 || {
            warn "Could not install git - cpuminer installation skipped"
            return 1
        }
    fi
    log "git is available"
    
    # Setup build directory
    log "Setting up build directory: $MINERS_DIR"
    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR" || {
        warn "Failed to cd to $MINERS_DIR"
        return 1
    }
    log "Working in: $(pwd)"
    
    # Clean old builds
    log "Cleaning old source directories..."
    rm -rf cpuminer-opt cpuminer-multi pooler-cpuminer 2>/dev/null
    log "Source directories cleaned"
    
    log "Target architecture: $ARCH_TYPE"
    
    # Build based on architecture
    case "$ARCH_TYPE" in
        x86_64)
            log "=== Building cpuminer-multi for x86_64 ==="
            log "Cloning repository..."
            if git clone --depth 1 --progress https://github.com/tpruvot/cpuminer-multi.git 2>&1; then
                log "Clone complete"
            else
                warn "Failed to clone cpuminer-multi - check network"
                return 1
            fi
            
            cd cpuminer-multi || { warn "Failed to cd"; return 1; }
            
            log "Running autogen.sh..."
            if ! ./autogen.sh >/dev/null 2>&1; then
                warn "autogen failed"
                return 1
            fi
            log "autogen complete"
            
            log "Running configure..."
            CFLAGS="-O2 -march=x86-64 -mtune=generic" ./configure --with-curl --with-crypto >/dev/null 2>&1 || {
                warn "configure failed"
                return 1
            }
            log "configure complete"
            
            log "Compiling (this takes a few minutes)..."
            if make -j"$(nproc)" >/dev/null 2>&1; then
                log "Compilation successful"
                cp cpuminer /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf cpuminer-multi
                log "cpuminer-multi installed successfully"
                /usr/local/bin/cpuminer --version 2>&1 | head -1 || true
                return 0
            else
                warn "make failed, trying pooler cpuminer..."
            fi
            
            cd "$MINERS_DIR"
            rm -rf cpuminer-multi
            
            # Fallback to pooler
            log "=== Trying pooler cpuminer ==="
            git clone --depth 1 --progress https://github.com/pooler/cpuminer.git pooler-cpuminer 2>&1 || {
                warn "Failed to clone pooler cpuminer"
                return 1
            }
            cd pooler-cpuminer || return 1
            ./autogen.sh >/dev/null 2>&1
            CFLAGS="-O2 -march=x86-64" ./configure >/dev/null 2>&1
            
            if make -j"$(nproc)" >/dev/null 2>&1; then
                cp minerd /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf pooler-cpuminer
                log "pooler cpuminer installed successfully"
                return 0
            fi
            ;;
            
        x86)
            log "=== Building cpuminer-multi for x86 32-bit ==="
            git clone --depth 1 --progress https://github.com/tpruvot/cpuminer-multi.git 2>&1 || return 1
            cd cpuminer-multi || return 1
            ./autogen.sh >/dev/null 2>&1
            CFLAGS="-O2 -march=i686" ./configure --with-curl --with-crypto >/dev/null 2>&1
            
            if make -j"$(nproc)" >/dev/null 2>&1; then
                cp cpuminer /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf cpuminer-multi
                log "cpuminer-multi installed for x86"
                return 0
            fi
            ;;
            
        arm64)
            log "=== Building cpuminer-multi for ARM64 (S905X/Cortex-A53 compatible) ==="
            
            # First try cpuminer-multi (most compatible with basic ARM64 like S905X)
            log "Cloning cpuminer-multi (tpruvot fork - best compatibility)..."
            if git clone --depth 1 --progress https://github.com/tpruvot/cpuminer-multi.git 2>&1; then
                cd cpuminer-multi || { warn "Failed to cd"; cd "$MINERS_DIR"; }
                
                log "Running autogen.sh..."
                if ./autogen.sh 2>&1; then
                    log "autogen complete"
                else
                    warn "autogen.sh failed, checking if configure exists..."
                fi
                
                # Check for configure script
                if [ ! -f configure ]; then
                    warn "No configure script found, trying autoreconf..."
                    autoreconf -i 2>&1 || true
                fi
                
                if [ -f configure ]; then
                    log "Running configure for ARM64..."
                    # Use generic ARM64 flags - no specific optimizations for S905X compatibility
                    if CFLAGS="-O2 -march=armv8-a" CXXFLAGS="-O2 -march=armv8-a" \
                       ./configure --with-curl --with-crypto 2>&1; then
                        log "Configure successful"
                        
                        log "Compiling (10-20 minutes on ARM64)..."
                        CORES=$(nproc 2>/dev/null || echo 2)
                        # Use fewer cores to avoid memory issues on limited RAM devices
                        [ "$CORES" -gt 2 ] && CORES=2
                        
                        if make -j"$CORES" 2>&1; then
                            if [ -f cpuminer ]; then
                                cp cpuminer /usr/local/bin/cpuminer
                                chmod +x /usr/local/bin/cpuminer
                                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                                cd "$MINERS_DIR"
                                rm -rf cpuminer-multi
                                log "✅ cpuminer-multi installed for ARM64"
                                /usr/local/bin/cpuminer --version 2>&1 | head -1 || true
                                return 0
                            else
                                warn "Build completed but cpuminer binary not found"
                            fi
                        else
                            warn "make failed for cpuminer-multi"
                        fi
                    else
                        warn "configure failed for cpuminer-multi"
                    fi
                fi
                
                cd "$MINERS_DIR"
                rm -rf cpuminer-multi
            else
                warn "Failed to clone cpuminer-multi"
            fi
            
            # Fallback: Try pooler cpuminer (most basic, highest compatibility)
            log "=== Trying pooler cpuminer (fallback for ARM64) ==="
            if git clone --depth 1 --progress https://github.com/pooler/cpuminer.git pooler-cpuminer 2>&1; then
                cd pooler-cpuminer || { warn "Failed to cd"; cd "$MINERS_DIR"; }
                
                log "Running autogen..."
                ./autogen.sh 2>&1 || autoreconf -i 2>&1 || true
                
                if [ -f configure ]; then
                    log "Configuring pooler cpuminer..."
                    CFLAGS="-O2" ./configure 2>&1
                    
                    log "Compiling..."
                    CORES=$(nproc 2>/dev/null || echo 2)
                    [ "$CORES" -gt 2 ] && CORES=2
                    
                    if make -j"$CORES" 2>&1; then
                        if [ -f minerd ]; then
                            cp minerd /usr/local/bin/cpuminer
                            chmod +x /usr/local/bin/cpuminer
                            ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                            cd "$MINERS_DIR"
                            rm -rf pooler-cpuminer
                            log "✅ pooler cpuminer installed for ARM64"
                            /usr/local/bin/cpuminer --version 2>&1 | head -1 || true
                            return 0
                        fi
                    fi
                fi
                
                cd "$MINERS_DIR"
                rm -rf pooler-cpuminer
            fi
            
            warn "All cpuminer builds failed for ARM64"
            ;;
            
        armv7)
            log "=== Building cpuminer-opt for ARMv7 ==="
            git clone --depth 1 --progress https://github.com/JayDDee/cpuminer-opt.git 2>&1 || return 1
            cd cpuminer-opt || return 1
            ./autogen.sh >/dev/null 2>&1
            
            log "Configuring with NEON..."
            CFLAGS="-O2 -mfpu=neon-vfpv4 -mfloat-abi=hard" ./configure --disable-assembly >/dev/null 2>&1 || {
                log "NEON failed, trying without..."
                CFLAGS="-O2" ./configure --disable-assembly >/dev/null 2>&1
            }
            
            log "Compiling (15-20 minutes)..."
            if make -j"$(nproc)" >/dev/null 2>&1; then
                cp cpuminer /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf cpuminer-opt
                log "cpuminer-opt installed for ARMv7"
                return 0
            fi
            ;;
            
        armv6)
            log "=== Building for ARMv6 (Pi Zero) ==="
            log "Trying pooler cpuminer (most compatible)..."
            git clone --depth 1 --progress https://github.com/pooler/cpuminer.git pooler-cpuminer 2>&1 || return 1
            cd pooler-cpuminer || return 1
            ./autogen.sh >/dev/null 2>&1
            CFLAGS="-O2" ./configure >/dev/null 2>&1
            
            log "Compiling (20-30 minutes on Pi Zero)..."
            if make -j"$(nproc)" >/dev/null 2>&1; then
                cp minerd /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf pooler-cpuminer
                log "pooler cpuminer installed for ARMv6"
                return 0
            fi
            ;;
            
        *)
            log "=== Building pooler cpuminer for $ARCH_TYPE ==="
            git clone --depth 1 --progress https://github.com/pooler/cpuminer.git pooler-cpuminer 2>&1 || return 1
            cd pooler-cpuminer || return 1
            ./autogen.sh >/dev/null 2>&1
            CFLAGS="-O2" ./configure >/dev/null 2>&1
            
            if make -j"$(nproc)" >/dev/null 2>&1; then
                cp minerd /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf pooler-cpuminer
                log "pooler cpuminer installed for $ARCH_TYPE"
                return 0
            fi
            ;;
    esac
    
    cd "$MINERS_DIR" 2>/dev/null
    rm -rf cpuminer-opt cpuminer-multi pooler-cpuminer 2>/dev/null
    warn "cpuminer installation failed"
    return 1
}

# =============================================================================
# GPU MINING SUPPORT
# Supports: SRBMiner-Multi (AMD/CPU), lolMiner (AMD/NVIDIA), T-Rex (NVIDIA)
# GPU mining is optional and only available on x86_64 architecture
# =============================================================================

# Install SRBMiner-Multi - AMD GPU and CPU miner (x86_64 only)
install_srbminer() {
    log "=== Starting SRBMiner-Multi installation ==="

    # SRBMiner only supports x86_64
    if [ "$ARCH_TYPE" != "x86_64" ]; then
        warn "SRBMiner-Multi only supports x86_64 architecture (current: $ARCH_TYPE)"
        return 1
    fi

    # Check if already installed and working
    if [ -f /usr/local/bin/SRBMiner-MULTI ]; then
        log "Testing existing SRBMiner-Multi..."
        if /usr/local/bin/SRBMiner-MULTI --help >/dev/null 2>&1; then
            log "SRBMiner-Multi already installed and working"
            return 0
        else
            warn "Existing SRBMiner-Multi is broken, reinstalling..."
            rm -f /usr/local/bin/SRBMiner-MULTI 2>/dev/null
        fi
    fi

    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR" || return 1
    rm -rf SRBMiner-Multi* srbminer* 2>/dev/null

    # Get latest version from GitHub API
    log "Fetching latest SRBMiner-Multi version..."
    SRBMINER_VERSION=""
    if command -v curl >/dev/null 2>&1; then
        SRBMINER_VERSION=$(curl -s --connect-timeout 10 "https://api.github.com/repos/doktor83/SRBMiner-Multi/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
    elif command -v wget >/dev/null 2>&1; then
        SRBMINER_VERSION=$(wget -qO- --timeout=10 "https://api.github.com/repos/doktor83/SRBMiner-Multi/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
    fi

    # Fallback to known version
    [ -z "$SRBMINER_VERSION" ] && SRBMINER_VERSION="2.6.9"
    log "Using SRBMiner-Multi version: $SRBMINER_VERSION"

    # Download
    DOWNLOAD_URL="https://github.com/doktor83/SRBMiner-Multi/releases/download/${SRBMINER_VERSION}/SRBMiner-Multi-${SRBMINER_VERSION#v}-Linux.tar.gz"
    log "Downloading from: $DOWNLOAD_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -sL -o srbminer.tar.gz "$DOWNLOAD_URL" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O srbminer.tar.gz "$DOWNLOAD_URL" 2>/dev/null
    fi

    if [ ! -f srbminer.tar.gz ] || [ ! -s srbminer.tar.gz ]; then
        warn "Failed to download SRBMiner-Multi"
        return 1
    fi

    log "Extracting SRBMiner-Multi..."
    tar -xzf srbminer.tar.gz 2>/dev/null

    # Find the binary
    SRBMINER_BIN=$(find . -name "SRBMiner-MULTI" -type f 2>/dev/null | head -1)
    if [ -z "$SRBMINER_BIN" ]; then
        warn "SRBMiner-MULTI binary not found in archive"
        rm -rf SRBMiner-Multi* srbminer* 2>/dev/null
        return 1
    fi

    cp "$SRBMINER_BIN" /usr/local/bin/SRBMiner-MULTI
    chmod +x /usr/local/bin/SRBMiner-MULTI

    # Cleanup
    rm -rf SRBMiner-Multi* srbminer* 2>/dev/null

    # Verify
    if /usr/local/bin/SRBMiner-MULTI --help >/dev/null 2>&1; then
        log "SRBMiner-Multi installed successfully"
        return 0
    else
        warn "SRBMiner-Multi installation verification failed"
        return 1
    fi
}

# Install lolMiner - AMD and NVIDIA GPU miner (x86_64 only)
install_lolminer() {
    log "=== Starting lolMiner installation ==="

    # lolMiner only supports x86_64
    if [ "$ARCH_TYPE" != "x86_64" ]; then
        warn "lolMiner only supports x86_64 architecture (current: $ARCH_TYPE)"
        return 1
    fi

    # Check if already installed and working
    if [ -f /usr/local/bin/lolMiner ]; then
        log "Testing existing lolMiner..."
        if /usr/local/bin/lolMiner --help >/dev/null 2>&1; then
            log "lolMiner already installed and working"
            return 0
        else
            warn "Existing lolMiner is broken, reinstalling..."
            rm -f /usr/local/bin/lolMiner 2>/dev/null
        fi
    fi

    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR" || return 1
    rm -rf lolMiner* 2>/dev/null

    # Get latest version from GitHub API
    log "Fetching latest lolMiner version..."
    LOLMINER_VERSION=""
    if command -v curl >/dev/null 2>&1; then
        LOLMINER_VERSION=$(curl -s --connect-timeout 10 "https://api.github.com/repos/Lolliedieb/lolMiner-releases/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
    elif command -v wget >/dev/null 2>&1; then
        LOLMINER_VERSION=$(wget -qO- --timeout=10 "https://api.github.com/repos/Lolliedieb/lolMiner-releases/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
    fi

    # Fallback to known version
    [ -z "$LOLMINER_VERSION" ] && LOLMINER_VERSION="1.88"
    log "Using lolMiner version: $LOLMINER_VERSION"

    # Download
    DOWNLOAD_URL="https://github.com/Lolliedieb/lolMiner-releases/releases/download/${LOLMINER_VERSION}/lolMiner_v${LOLMINER_VERSION}_Lin64.tar.gz"
    log "Downloading from: $DOWNLOAD_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -sL -o lolminer.tar.gz "$DOWNLOAD_URL" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O lolminer.tar.gz "$DOWNLOAD_URL" 2>/dev/null
    fi

    if [ ! -f lolminer.tar.gz ] || [ ! -s lolminer.tar.gz ]; then
        warn "Failed to download lolMiner"
        return 1
    fi

    log "Extracting lolMiner..."
    tar -xzf lolminer.tar.gz 2>/dev/null

    # Find the binary
    LOLMINER_BIN=$(find . -name "lolMiner" -type f -executable 2>/dev/null | head -1)
    if [ -z "$LOLMINER_BIN" ]; then
        LOLMINER_BIN=$(find . -name "lolMiner" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$LOLMINER_BIN" ]; then
        warn "lolMiner binary not found in archive"
        rm -rf lolMiner* lolminer* 2>/dev/null
        return 1
    fi

    cp "$LOLMINER_BIN" /usr/local/bin/lolMiner
    chmod +x /usr/local/bin/lolMiner

    # Cleanup
    rm -rf lolMiner* lolminer* 2>/dev/null

    # Verify
    if /usr/local/bin/lolMiner --help >/dev/null 2>&1; then
        log "lolMiner installed successfully"
        return 0
    else
        warn "lolMiner installation verification failed"
        return 1
    fi
}

# Install T-Rex miner - NVIDIA GPU miner (x86_64 only)
install_trex() {
    log "=== Starting T-Rex miner installation ==="

    # T-Rex only supports x86_64
    if [ "$ARCH_TYPE" != "x86_64" ]; then
        warn "T-Rex only supports x86_64 architecture (current: $ARCH_TYPE)"
        return 1
    fi

    # Check if already installed and working
    if [ -f /usr/local/bin/t-rex ]; then
        log "Testing existing T-Rex..."
        if /usr/local/bin/t-rex --help >/dev/null 2>&1; then
            log "T-Rex already installed and working"
            return 0
        else
            warn "Existing T-Rex is broken, reinstalling..."
            rm -f /usr/local/bin/t-rex 2>/dev/null
        fi
    fi

    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR" || return 1
    rm -rf t-rex* 2>/dev/null

    # Get latest version from GitHub API
    log "Fetching latest T-Rex version..."
    TREX_VERSION=""
    if command -v curl >/dev/null 2>&1; then
        TREX_VERSION=$(curl -s --connect-timeout 10 "https://api.github.com/repos/trexminer/T-Rex/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
    elif command -v wget >/dev/null 2>&1; then
        TREX_VERSION=$(wget -qO- --timeout=10 "https://api.github.com/repos/trexminer/T-Rex/releases/latest" 2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
    fi

    # Fallback to known version
    [ -z "$TREX_VERSION" ] && TREX_VERSION="0.26.8"
    log "Using T-Rex version: $TREX_VERSION"

    # Download
    DOWNLOAD_URL="https://github.com/trexminer/T-Rex/releases/download/${TREX_VERSION}/t-rex-${TREX_VERSION}-linux.tar.gz"
    log "Downloading from: $DOWNLOAD_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -sL -o trex.tar.gz "$DOWNLOAD_URL" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O trex.tar.gz "$DOWNLOAD_URL" 2>/dev/null
    fi

    if [ ! -f trex.tar.gz ] || [ ! -s trex.tar.gz ]; then
        warn "Failed to download T-Rex"
        return 1
    fi

    log "Extracting T-Rex..."
    tar -xzf trex.tar.gz 2>/dev/null

    # Find the binary
    TREX_BIN=$(find . -name "t-rex" -type f -executable 2>/dev/null | head -1)
    if [ -z "$TREX_BIN" ]; then
        TREX_BIN=$(find . -name "t-rex" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$TREX_BIN" ]; then
        warn "T-Rex binary not found in archive"
        rm -rf t-rex* trex* 2>/dev/null
        return 1
    fi

    cp "$TREX_BIN" /usr/local/bin/t-rex
    chmod +x /usr/local/bin/t-rex

    # Cleanup
    rm -rf t-rex* trex* 2>/dev/null

    # Verify
    if /usr/local/bin/t-rex --help >/dev/null 2>&1; then
        log "T-Rex installed successfully"
        return 0
    else
        warn "T-Rex installation verification failed"
        return 1
    fi
}

# Master function to install GPU miners (optional)
install_gpu_miners() {
    log "=== Installing GPU miners (optional) ==="

    if [ "$ARCH_TYPE" != "x86_64" ]; then
        warn "GPU mining is only supported on x86_64 architecture"
        warn "Current architecture: $ARCH_TYPE - skipping GPU miner installation"
        return 1
    fi

    GPU_MINERS_INSTALLED=0

    # Install SRBMiner-Multi (AMD GPU and CPU support)
    if install_srbminer; then
        GPU_MINERS_INSTALLED=$((GPU_MINERS_INSTALLED + 1))
    fi

    # Install lolMiner (AMD and NVIDIA)
    if install_lolminer; then
        GPU_MINERS_INSTALLED=$((GPU_MINERS_INSTALLED + 1))
    fi

    # Install T-Rex (NVIDIA only)
    if install_trex; then
        GPU_MINERS_INSTALLED=$((GPU_MINERS_INSTALLED + 1))
    fi

    if [ $GPU_MINERS_INSTALLED -gt 0 ]; then
        log "GPU miners installed: $GPU_MINERS_INSTALLED"
        return 0
    else
        warn "No GPU miners were installed"
        return 1
    fi
}

# Install BFGMiner - USB ASIC miner (supports Block Erupters, GekkoScience, Antminer USB, etc.)
install_bfgminer() {
    log "=== Starting BFGMiner installation (USB ASIC support) ==="

    # Check if already installed at /usr/local/bin
    if [ -x /usr/local/bin/bfgminer ]; then
        log "Testing existing BFGMiner at /usr/local/bin/bfgminer..."
        if /usr/local/bin/bfgminer --version >/dev/null 2>&1 || /usr/local/bin/bfgminer --help >/dev/null 2>&1; then
            log "BFGMiner already installed and working"
            /usr/local/bin/bfgminer --version 2>&1 | head -1 || true
            return 0
        else
            warn "Existing BFGMiner at /usr/local/bin is broken, will reinstall..."
            rm -f /usr/local/bin/bfgminer 2>/dev/null
        fi
    fi

    # Also check system paths
    if command -v bfgminer >/dev/null 2>&1; then
        EXISTING_BFG=$(which bfgminer)
        log "Testing existing BFGMiner at $EXISTING_BFG..."
        if bfgminer --version >/dev/null 2>&1 || bfgminer --help >/dev/null 2>&1; then
            log "BFGMiner already installed and working in system path"
            bfgminer --version 2>&1 | head -1 || true
            # Create symlink to /usr/local/bin for consistency
            ln -sf "$EXISTING_BFG" /usr/local/bin/bfgminer 2>/dev/null || true
            return 0
        else
            warn "Existing BFGMiner in system path is broken, will reinstall..."
        fi
    fi

    # Also check for cgminer as alternative
    if [ -x /usr/local/bin/cgminer ]; then
        log "Testing existing CGMiner at /usr/local/bin/cgminer..."
        if /usr/local/bin/cgminer --version >/dev/null 2>&1 || /usr/local/bin/cgminer --help >/dev/null 2>&1; then
            log "CGMiner already installed and working (using as bfgminer alternative)"
            /usr/local/bin/cgminer --version 2>&1 | head -1 || true
            # Symlink cgminer as bfgminer for consistency
            ln -sf /usr/local/bin/cgminer /usr/local/bin/bfgminer 2>/dev/null || true
            return 0
        fi
    fi

    if command -v cgminer >/dev/null 2>&1; then
        EXISTING_CG=$(which cgminer)
        log "Testing existing CGMiner at $EXISTING_CG..."
        if cgminer --version >/dev/null 2>&1 || cgminer --help >/dev/null 2>&1; then
            log "CGMiner already installed and working in system path"
            cgminer --version 2>&1 | head -1 || true
            ln -sf "$EXISTING_CG" /usr/local/bin/bfgminer 2>/dev/null || true
            return 0
        fi
    fi

    log "No working BFGMiner/CGMiner found, proceeding with installation..."

    mkdir -p "$MINERS_DIR"
    cd "$MINERS_DIR"

    # Install additional dependencies for USB ASIC support
    log "Installing USB ASIC dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y libudev-dev libusb-1.0-0-dev libncurses5-dev libmicrohttpd-dev libevent-dev libjansson-dev uthash-dev >/dev/null 2>&1 || true
        # Install udev rules for USB ASICs
        apt-get install -y libhidapi-dev >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y libudev-devel libusb1-devel ncurses-devel libmicrohttpd-devel libevent-devel jansson-devel >/dev/null 2>&1 || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm libusb ncurses libmicrohttpd libevent jansson >/dev/null 2>&1 || true
    fi

    # Try to install from package manager first (faster)
    log "Attempting to install BFGMiner from package manager..."
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get install -y bfgminer >/dev/null 2>&1; then
            if command -v bfgminer >/dev/null 2>&1; then
                log "BFGMiner installed from package manager"
                # Create symlink to /usr/local/bin for consistency
                ln -sf $(which bfgminer) /usr/local/bin/bfgminer 2>/dev/null || true
                return 0
            fi
        fi
    fi

    # Build from source if package not available
    log "Building BFGMiner from source..."

    # Clone BFGMiner repository
    rm -rf bfgminer 2>/dev/null
    if ! git clone https://github.com/luke-jr/bfgminer.git 2>/dev/null; then
        warn "Failed to clone BFGMiner repository"
        # Try alternative: cgminer (also supports USB ASICs)
        log "Trying CGMiner as alternative..."
        if ! git clone https://github.com/ckolivas/cgminer.git 2>/dev/null; then
            warn "Failed to clone CGMiner repository"
            return 1
        fi
        cd cgminer
        MINER_NAME="cgminer"
    else
        cd bfgminer
        MINER_NAME="bfgminer"
    fi

    # Build the miner
    log "Configuring $MINER_NAME..."
    if [ -f autogen.sh ]; then
        ./autogen.sh 2>/dev/null || true
    fi

    # Configure with USB ASIC support
    # Enable common USB ASIC drivers
    CONFIGURE_OPTS="--enable-cpumining"

    # BFGMiner specific options
    if [ "$MINER_NAME" = "bfgminer" ]; then
        CONFIGURE_OPTS="$CONFIGURE_OPTS --enable-icarus --enable-erupter --enable-antminer --enable-gekko"
        CONFIGURE_OPTS="$CONFIGURE_OPTS --enable-gridseed --enable-dualminer --enable-scrypt"
    else
        # CGMiner options (older, less ASIC support but still useful)
        CONFIGURE_OPTS="$CONFIGURE_OPTS --enable-icarus"
    fi

    if ./configure $CONFIGURE_OPTS 2>&1 | tail -20; then
        log "Building $MINER_NAME (this may take a while)..."
        if make -j$(nproc) 2>&1 | tail -20; then
            if [ -f "$MINER_NAME" ]; then
                cp "$MINER_NAME" /usr/local/bin/bfgminer
                chmod 755 /usr/local/bin/bfgminer
                log "BFGMiner ($MINER_NAME) installed successfully"

                # Setup udev rules for USB ASIC access
                setup_usb_asic_udev_rules

                return 0
            fi
        else
            warn "$MINER_NAME build failed"
        fi
    else
        warn "$MINER_NAME configure failed"
    fi

    # Cleanup
    cd "$MINERS_DIR"
    rm -rf bfgminer cgminer 2>/dev/null

    warn "BFGMiner installation failed"
    return 1
}

# Setup udev rules for USB ASIC access without root
setup_usb_asic_udev_rules() {
    log "Setting up udev rules for USB ASIC devices..."

    UDEV_RULES_FILE="/etc/udev/rules.d/99-usb-asic.rules"

    cat > "$UDEV_RULES_FILE" <<'UDEVRULES'
# USB ASIC Miner udev rules
# Allows non-root users to access USB mining devices

# Silicon Labs CP210x (Block Erupter, various ASICs)
SUBSYSTEM=="usb", ATTR{idVendor}=="10c4", ATTR{idProduct}=="ea60", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0666", GROUP="plugdev"

# STM32 CDC (GekkoScience Compac, Newpac, 2PAC)
SUBSYSTEM=="usb", ATTR{idVendor}=="0483", ATTR{idProduct}=="5740", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="5740", MODE="0666", GROUP="plugdev"

# Prolific PL2303 (Some Antminer USB)
SUBSYSTEM=="usb", ATTR{idVendor}=="067b", ATTR{idProduct}=="2303", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="tty", ATTRS{idVendor}=="067b", ATTRS{idProduct}=="2303", MODE="0666", GROUP="plugdev"

# FTDI (FutureBit Moonlander 2, various ASICs)
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6001", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666", GROUP="plugdev"

# FTDI FT232H (some ASIC boards)
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6014", MODE="0666", GROUP="plugdev"

# Canaantech Avalon USB
SUBSYSTEM=="usb", ATTR{idVendor}=="1fc9", ATTR{idProduct}=="0003", MODE="0666", GROUP="plugdev"

# Bitfury USB
SUBSYSTEM=="usb", ATTR{idVendor}=="03eb", ATTR{idProduct}=="204b", MODE="0666", GROUP="plugdev"

# Generic CDC ACM devices (many USB ASICs use this)
KERNEL=="ttyACM*", MODE="0666", GROUP="plugdev"
KERNEL=="ttyUSB*", MODE="0666", GROUP="plugdev"
UDEVRULES

    chmod 644 "$UDEV_RULES_FILE"

    # Reload udev rules
    if command -v udevadm >/dev/null 2>&1; then
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true
        log "udev rules reloaded"
    fi

    # Add users to plugdev group
    for user in fry pi ubuntu debian; do
        if id "$user" >/dev/null 2>&1; then
            usermod -a -G plugdev "$user" 2>/dev/null || true
            usermod -a -G dialout "$user" 2>/dev/null || true
        fi
    done

    # Also add the SUDO_USER if available
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        usermod -a -G plugdev "$SUDO_USER" 2>/dev/null || true
        usermod -a -G dialout "$SUDO_USER" 2>/dev/null || true
    fi

    log "USB ASIC udev rules configured"
}

# Master function to install USB ASIC miners (optional)
install_usbasic_miners() {
    log "=== Installing USB ASIC miners (optional) ==="

    USBASIC_MINERS_INSTALLED=0

    # Install BFGMiner (supports most USB ASICs)
    if install_bfgminer; then
        USBASIC_MINERS_INSTALLED=$((USBASIC_MINERS_INSTALLED + 1))
    fi

    if [ $USBASIC_MINERS_INSTALLED -gt 0 ]; then
        log "USB ASIC miners installed: $USBASIC_MINERS_INSTALLED"
        return 0
    else
        warn "No USB ASIC miners were installed"
        return 1
    fi
}

# Configure sudo permissions for web server to run updates
setup_sudo_permissions() {
    log "Configuring sudo permissions for updates..."
    
    # Get the REAL user (who ran sudo)
    REAL_USER="${SUDO_USER}"
    if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
        # Try to detect from common patterns
        for user in fry pi ubuntu debian; do
            if id "$user" >/dev/null 2>&1; then
                REAL_USER="$user"
                break
            fi
        done
    fi
    
    if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
        warn "Could not detect non-root user, skipping sudo configuration"
        return 1
    fi
    
    log "Configuring passwordless sudo for user: $REAL_USER"
    
    # Ensure /etc/sudoers includes sudoers.d directory
    if ! grep -q "includedir /etc/sudoers.d" /etc/sudoers; then
        log "Adding sudoers.d include to main sudoers file..."
        # Backup original sudoers
        cp /etc/sudoers /etc/sudoers.backup.fryminer
        # Add include directive
        echo "" >> /etc/sudoers
        echo "# Include sudoers.d directory (added by FryMiner)" >> /etc/sudoers
        echo "@includedir /etc/sudoers.d" >> /etc/sudoers
        # Verify the modified file is valid
        if ! visudo -c -f /etc/sudoers >/dev/null 2>&1; then
            warn "Main sudoers file became invalid, restoring backup"
            mv /etc/sudoers.backup.fryminer /etc/sudoers
        else
            log "✅ Main sudoers file updated successfully"
            rm -f /etc/sudoers.backup.fryminer
        fi
    fi
    
    # Create sudoers.d directory if it doesn't exist
    mkdir -p /etc/sudoers.d
    chmod 750 /etc/sudoers.d
    
    # Remove old fryminer sudoers file if it exists
    rm -f /etc/sudoers.d/fryminer 2>/dev/null
    
    # Create new sudoers file with SIMPLE, BROAD permissions
    # Include common web server users and the detected user
    cat > /etc/sudoers.d/fryminer << EOF
# FryMiner passwordless sudo configuration
# Generated automatically by setup script

# Primary user (who ran the setup)
$REAL_USER ALL=(ALL) NOPASSWD: ALL

# Common system users that might run the web server
fry ALL=(ALL) NOPASSWD: ALL
pi ALL=(ALL) NOPASSWD: ALL
ubuntu ALL=(ALL) NOPASSWD: ALL
debian ALL=(ALL) NOPASSWD: ALL
www-data ALL=(ALL) NOPASSWD: ALL
nobody ALL=(ALL) NOPASSWD: ALL

# Disable tty requirement for all these users
Defaults:$REAL_USER !requiretty
Defaults:fry !requiretty
Defaults:pi !requiretty
Defaults:ubuntu !requiretty
Defaults:debian !requiretty
Defaults:www-data !requiretty
Defaults:nobody !requiretty
EOF
    
    # Set correct permissions
    chmod 440 /etc/sudoers.d/fryminer
    chown root:root /etc/sudoers.d/fryminer
    
    log "Created /etc/sudoers.d/fryminer with contents:"
    cat /etc/sudoers.d/fryminer | sed 's/^/  /' || warn "Could not read sudoers file"
    
    # Verify syntax with visudo
    log "Verifying sudoers syntax..."
    if ! visudo -c -f /etc/sudoers.d/fryminer >/dev/null 2>&1; then
        warn "Sudoers syntax check failed, removing file"
        rm -f /etc/sudoers.d/fryminer
        return 1
    fi
    
    log "✅ Sudoers file created and verified"
    
    # Test that sudo actually works for the user
    log "Testing passwordless sudo..."
    if su - "$REAL_USER" -c "sudo -n true" 2>/dev/null; then
        log "✅ Passwordless sudo is working for $REAL_USER"
        return 0
    else
        warn "⚠️  Passwordless sudo test failed, but file is configured"
        warn "It may work after logout/login or system restart"
        return 0
    fi
}

# Start web server as correct user (not root)
start_webserver() {
    log "Starting web server..."
    
    # Get the real user (who ran sudo)
    REAL_USER="${SUDO_USER:-$USER}"
    if [ "$REAL_USER" = "root" ] || [ -z "$REAL_USER" ]; then
        # Fallback to checking common users
        for user in fry pi ubuntu; do
            if id "$user" >/dev/null 2>&1; then
                REAL_USER="$user"
                break
            fi
        done
    fi
    
    log "Starting web server as user: $REAL_USER"
    
    # Kill any existing web server
    pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
    sleep 1
    
    # Start web server as the real user (not root)
    if [ "$REAL_USER" != "root" ] && [ -n "$REAL_USER" ]; then
        cd "$BASE"
        # Use su to run as the correct user
        su - "$REAL_USER" -c "cd $BASE && nohup python3 -m http.server $PORT --cgi > /dev/null 2>&1 &"
        sleep 2
        
        # Verify it's running
        if pgrep -f "python3 -m http.server $PORT" >/dev/null 2>&1; then
            WEB_PID=$(pgrep -f "python3 -m http.server $PORT" | head -1)
            WEB_USER=$(ps -o user= -p "$WEB_PID" 2>/dev/null)
            log "✅ Web server started (PID: $WEB_PID, User: $WEB_USER)"
            
            # Verify the user is correct
            if [ "$WEB_USER" = "root" ]; then
                warn "⚠️  Web server is running as root (should be $REAL_USER)"
                warn "Force Update may not work. Run setup again if issues occur."
            else
                log "✅ Web server running as correct user: $WEB_USER"
            fi
        else
            warn "⚠️  Failed to start web server automatically"
            log "You can start it manually with:"
            log "  cd $BASE && python3 -m http.server $PORT --cgi &"
        fi
    else
        warn "⚠️  Could not detect non-root user, skipping auto-start"
        log "Start web server manually:"
        log "  cd $BASE && python3 -m http.server $PORT --cgi &"
    fi
}

# Create systemd service for FryMiner web interface to start on boot
create_systemd_service() {
    log "Setting up FryMiner web interface to start on boot..."
    
    # Detect real user
    REAL_USER="${SUDO_USER:-}"
    if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
        for user in fry pi ubuntu debian; do
            if id "$user" >/dev/null 2>&1; then
                REAL_USER="$user"
                break
            fi
        done
    fi
    
    # Default to root if no other user found
    [ -z "$REAL_USER" ] && REAL_USER="root"
    
    # Kill any existing web server first
    pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
    pkill -f "python3.*http.server.*$PORT" 2>/dev/null || true
    sleep 1
    
    # Store the actual values for the service file (not variables)
    SERVICE_USER="$REAL_USER"
    SERVICE_BASE="$BASE"
    SERVICE_PORT="$PORT"
    
    BOOT_METHOD_SET=false
    
    # Method 1: Try systemd (most modern Linux systems)
    if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
        log "Creating systemd service..."
        
        # Stop and disable any existing service first
        systemctl stop fryminer-web.service 2>/dev/null || true
        systemctl disable fryminer-web.service 2>/dev/null || true
        
        # Create systemd service file with hardcoded values
        cat > /etc/systemd/system/fryminer-web.service <<SERVICEEOF
[Unit]
Description=FryMiner Web Interface
After=network.target network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$SERVICE_BASE
ExecStart=/usr/bin/python3 -m http.server $SERVICE_PORT --cgi
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF
        
        # Set permissions
        chmod 644 /etc/systemd/system/fryminer-web.service
        
        # Reload systemd and enable service
        systemctl daemon-reload
        systemctl enable fryminer-web.service
        systemctl start fryminer-web.service
        
        # Verify service is running
        sleep 3
        if systemctl is-active --quiet fryminer-web.service; then
            log "✅ Systemd service enabled and running"
            BOOT_METHOD_SET=true
        else
            warn "Systemd service failed to start, trying fallback methods..."
            # Show why it failed
            systemctl status fryminer-web.service 2>&1 | head -10 || true
        fi
    fi
    
    # Method 2: Try rc.local (older systems, some ARM devices)
    if [ "$BOOT_METHOD_SET" = "false" ]; then
        if [ -f /etc/rc.local ] || [ -d /etc/rc.d ]; then
            log "Setting up rc.local fallback..."
            
            # Create rc.local if it doesn't exist
            if [ ! -f /etc/rc.local ]; then
                echo '#!/bin/sh -e' > /etc/rc.local
                echo 'exit 0' >> /etc/rc.local
            fi
            
            # Remove any existing fryminer entries
            sed -i '/fryminer\|frynet-config.*http.server/d' /etc/rc.local 2>/dev/null || true
            
            # Add startup command before 'exit 0'
            sed -i '/^exit 0/d' /etc/rc.local 2>/dev/null || true
            cat >> /etc/rc.local <<RCLOCALEOF

# FryMiner Web Interface - Start on boot
cd $SERVICE_BASE && /usr/bin/python3 -m http.server $SERVICE_PORT --cgi &

exit 0
RCLOCALEOF
            
            chmod +x /etc/rc.local
            
            # Enable rc.local service if systemd is present
            if command -v systemctl >/dev/null 2>&1; then
                systemctl enable rc-local.service 2>/dev/null || true
                systemctl start rc-local.service 2>/dev/null || true
            fi
            
            log "✅ rc.local fallback configured"
            BOOT_METHOD_SET=true
        fi
    fi
    
    # Method 3: Try cron @reboot (universal fallback)
    if command -v crontab >/dev/null 2>&1; then
        log "Setting up cron @reboot fallback..."
        
        # Get current crontab, remove old fryminer web entries
        (crontab -l 2>/dev/null || echo "") | grep -v "fryminer-web\|frynet-config.*http.server\|python3.*http.server.*$SERVICE_PORT" > /tmp/crontab_web.tmp 2>/dev/null || true
        
        # Add @reboot entry
        echo "@reboot cd $SERVICE_BASE && /usr/bin/python3 -m http.server $SERVICE_PORT --cgi > /dev/null 2>&1 &  # fryminer-web" >> /tmp/crontab_web.tmp
        
        crontab /tmp/crontab_web.tmp 2>/dev/null && log "✅ Cron @reboot fallback configured" || warn "Could not set up cron fallback"
        rm -f /tmp/crontab_web.tmp
        BOOT_METHOD_SET=true
    fi
    
    # Method 4: Create a startup script in /etc/init.d (SysV init fallback)
    if [ "$BOOT_METHOD_SET" = "false" ] || [ ! -f /etc/systemd/system/fryminer-web.service ]; then
        if [ -d /etc/init.d ]; then
            log "Creating init.d startup script..."
            
            cat > /etc/init.d/fryminer-web <<INITEOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          fryminer-web
# Required-Start:    \$network \$remote_fs
# Required-Stop:     \$network \$remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: FryMiner Web Interface
### END INIT INFO

case "\$1" in
    start)
        echo "Starting FryMiner Web Interface..."
        cd $SERVICE_BASE
        /usr/bin/python3 -m http.server $SERVICE_PORT --cgi > /dev/null 2>&1 &
        ;;
    stop)
        echo "Stopping FryMiner Web Interface..."
        pkill -f "python3.*http.server.*$SERVICE_PORT" 2>/dev/null || true
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart}"
        exit 1
        ;;
esac
exit 0
INITEOF
            
            chmod +x /etc/init.d/fryminer-web
            
            # Enable with update-rc.d if available
            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d fryminer-web defaults 2>/dev/null || true
                log "✅ init.d script enabled"
            elif command -v chkconfig >/dev/null 2>&1; then
                chkconfig --add fryminer-web 2>/dev/null || true
                chkconfig fryminer-web on 2>/dev/null || true
                log "✅ init.d script enabled via chkconfig"
            fi
            BOOT_METHOD_SET=true
        fi
    fi
    
    # Now start the web server if not already running
    sleep 1
    if ! pgrep -f "python3.*http.server.*$SERVICE_PORT" >/dev/null 2>&1; then
        log "Starting web server now..."
        cd "$SERVICE_BASE"
        if [ "$SERVICE_USER" != "root" ] && command -v su >/dev/null 2>&1; then
            su - "$SERVICE_USER" -c "cd $SERVICE_BASE && nohup /usr/bin/python3 -m http.server $SERVICE_PORT --cgi > /dev/null 2>&1 &" 2>/dev/null || \
            nohup /usr/bin/python3 -m http.server $SERVICE_PORT --cgi > /dev/null 2>&1 &
        else
            nohup /usr/bin/python3 -m http.server $SERVICE_PORT --cgi > /dev/null 2>&1 &
        fi
        sleep 2
    fi
    
    # Final verification
    if pgrep -f "python3.*http.server.*$SERVICE_PORT" >/dev/null 2>&1; then
        WEB_PID=$(pgrep -f "python3.*http.server.*$SERVICE_PORT" | head -1)
        log "✅ Web server running (PID: $WEB_PID)"
    else
        warn "⚠️  Web server may not have started - check manually"
        warn "Manual start: cd $SERVICE_BASE && python3 -m http.server $SERVICE_PORT --cgi &"
    fi
    
    if [ "$BOOT_METHOD_SET" = "true" ]; then
        log "✅ Web interface configured to start automatically on boot"
    else
        warn "⚠️  Could not configure automatic boot startup"
    fi
}

# Main installation
main() {
    log "================================================"
    if [ "$UPDATE_MODE" = "true" ]; then
        log "FryMiner Update Mode - Installing Latest Version..."
    else
        log "FryMiner Complete Setup Starting..."
    fi
    log "================================================"
    
    detect_architecture
    set_hostname
    install_dependencies
    remove_docker_if_present

    # Install miners - CRITICAL: Exit if these fail
    if ! install_xmrig; then
        die "CRITICAL: XMRig installation failed - cannot continue"
    fi
    
    # Install XLArig for Scala mining (optional)
    if ! install_xlarig; then
        warn "XLArig installation failed - Scala mining will not be available"
    fi
    
    if ! install_cpuminer; then
        die "CRITICAL: cpuminer installation failed - cannot continue"
    fi

    # Install GPU miners (optional - x86_64 only)
    if ! install_gpu_miners; then
        warn "GPU miner installation skipped or failed - GPU mining will not be available"
    fi

    # Install USB ASIC miners (optional - supports Block Erupters, GekkoScience, etc.)
    if ! install_usbasic_miners; then
        warn "USB ASIC miner installation skipped or failed - USB ASIC mining will not be available"
    fi

    # Apply mining optimizations (huge pages, MSR, CPU governor)
    optimize_for_mining
    
    # Configure sudo permissions for web server updates
    setup_sudo_permissions
    
    # Stop any existing FryMiner processes gracefully
    log "Stopping existing FryMiner processes..."
    
    # Stop web server
    if pgrep -f "python3 -m http.server $PORT" >/dev/null 2>&1; then
        pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
        sleep 1
    fi
    
    # Stop miners
    pkill -f xmrig 2>/dev/null || true
    pkill -f xlarig 2>/dev/null || true
    pkill -f cpuminer 2>/dev/null || true
    pkill -f minerd 2>/dev/null || true
    # USB ASIC miners
    pkill -f bfgminer 2>/dev/null || true
    pkill -f cgminer 2>/dev/null || true

    # Stop old daemons
    pkill -f fryminer_pidmon 2>/dev/null || true
    pkill -f fryminer_thermal 2>/dev/null || true
    
    # Wait for processes to stop
    sleep 2
    
    # Setup directory structure
    log "Setting up FryMiner directory..."

    # During UPDATE_MODE, preserve config.txt and output directory (contains start.sh scripts)
    if [ "$UPDATE_MODE" = "true" ]; then
        log "UPDATE_MODE: Preserving existing configuration and start scripts..."
        # Backup config and output directory
        if [ -f "$BASE/config.txt" ]; then
            cp "$BASE/config.txt" /tmp/fryminer_config_backup.txt
        fi
        if [ -d "$BASE/output" ]; then
            cp -r "$BASE/output" /tmp/fryminer_output_backup
        fi
        # Remove everything except what we're backing up
        rm -rf "$BASE/cgi-bin" "$BASE/index.html" "$BASE/logs" "$BASE/optimize.sh" "$BASE/auto_update.sh" 2>/dev/null || true
        mkdir -p "$BASE"
        mkdir -p "$BASE/cgi-bin"
        mkdir -p "$BASE/logs"
        # Restore backups
        if [ -f /tmp/fryminer_config_backup.txt ]; then
            cp /tmp/fryminer_config_backup.txt "$BASE/config.txt"
            rm -f /tmp/fryminer_config_backup.txt
        fi
        if [ -d /tmp/fryminer_output_backup ]; then
            rm -rf "$BASE/output"
            cp -r /tmp/fryminer_output_backup "$BASE/output"
            rm -rf /tmp/fryminer_output_backup
        else
            mkdir -p "$BASE/output"
        fi
    else
        rm -rf "$BASE"
        mkdir -p "$BASE"
        mkdir -p "$BASE/cgi-bin"
        mkdir -p "$BASE/output"
        mkdir -p "$BASE/logs"
    fi
    
    # Set permissions
    chmod 777 "$BASE"
    chmod 777 "$BASE/cgi-bin"
    chmod 777 "$BASE/output"
    chmod 777 "$BASE/logs"
    
    log "Creating web interface..."
    
    # Create index.html with ALL coins and full UI
    cat > "$BASE/index.html" <<'HTML'
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
        <div style="color: #ff6b6b;">Professional Cryptocurrency Mining System - 35+ Coins Supported</div>
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
    'one': 'rx.unmineable.com:3333'
};

// Fixed pools (cannot be changed) - Unmineable coins only
const fixedPools = ['shib', 'ada', 'sol', 'zec', 'etc', 'rvn', 'trx', 'vet', 'xrp', 'dot', 'matic', 'atom', 'link', 'xlm', 'algo', 'avax', 'near', 'ftm', 'one'];

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
    'octa-lotto': '🎰 OctaSpace solo lottery mining on solopool.org - GPU recommended (Ethash).'
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
    
    // Show/hide pool field
    if (coin === 'tera' || coin === 'minima') {
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
HTML
    
    # Create CGI scripts
    log "Creating CGI scripts..."
    
    # Info CGI
    cat > "$BASE/cgi-bin/info.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: text/plain"
echo ""
uname -m
SCRIPT
    chmod 755 "$BASE/cgi-bin/info.cgi"
    
    # CPU Cores CGI - Returns number of CPU cores
    cat > "$BASE/cgi-bin/cores.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""
CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "4")
printf '{"cores":%d}' "$CORES"
SCRIPT
    chmod 755 "$BASE/cgi-bin/cores.cgi"

    # GPU Detection CGI - Detects if GPU is present and what type
    cat > "$BASE/cgi-bin/gpu.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

# Check architecture first - GPU mining only on x86_64
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
    printf '{"gpu_available":false,"reason":"GPU mining only supported on x86_64 architecture","arch":"%s","nvidia":false,"amd":false,"intel":false}' "$ARCH"
    exit 0
fi

NVIDIA_FOUND=false
AMD_FOUND=false
INTEL_FOUND=false
GPU_NAME=""

# Check for NVIDIA GPU
# Method 1: nvidia-smi (most reliable if drivers installed)
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | grep -qi .; then
        NVIDIA_FOUND=true
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    fi
fi

# Method 2: lspci for NVIDIA
if [ "$NVIDIA_FOUND" = "false" ] && command -v lspci >/dev/null 2>&1; then
    if lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -qi nvidia; then
        NVIDIA_FOUND=true
        GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -i nvidia | head -1 | sed 's/.*: //')
    fi
fi

# Method 3: Check /sys for NVIDIA
if [ "$NVIDIA_FOUND" = "false" ]; then
    if ls /sys/class/drm/card*/device/vendor 2>/dev/null | xargs cat 2>/dev/null | grep -q "0x10de"; then
        NVIDIA_FOUND=true
        GPU_NAME="NVIDIA GPU (detected via sysfs)"
    fi
fi

# Check for AMD GPU
# Method 1: lspci for AMD/ATI
if command -v lspci >/dev/null 2>&1; then
    if lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -qi "amd\|ati\|radeon"; then
        AMD_FOUND=true
        if [ -z "$GPU_NAME" ]; then
            GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -i "amd\|ati\|radeon" | head -1 | sed 's/.*: //')
        fi
    fi
fi

# Method 2: Check /sys for AMD (vendor 0x1002)
if [ "$AMD_FOUND" = "false" ]; then
    if ls /sys/class/drm/card*/device/vendor 2>/dev/null | xargs cat 2>/dev/null | grep -q "0x1002"; then
        AMD_FOUND=true
        if [ -z "$GPU_NAME" ]; then
            GPU_NAME="AMD GPU (detected via sysfs)"
        fi
    fi
fi

# Method 3: Check for amdgpu or radeon driver loaded
if [ "$AMD_FOUND" = "false" ]; then
    if lsmod 2>/dev/null | grep -qi "amdgpu\|radeon"; then
        AMD_FOUND=true
        if [ -z "$GPU_NAME" ]; then
            GPU_NAME="AMD GPU (driver loaded)"
        fi
    fi
fi

# Check for Intel GPU
# Method 1: lspci for Intel (Arc, Iris, UHD, HD Graphics)
if command -v lspci >/dev/null 2>&1; then
    if lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -qi "intel"; then
        INTEL_FOUND=true
        if [ -z "$GPU_NAME" ]; then
            GPU_NAME=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -i "intel" | head -1 | sed 's/.*: //')
        fi
    fi
fi

# Method 2: Check /sys for Intel (vendor 0x8086)
if [ "$INTEL_FOUND" = "false" ]; then
    if ls /sys/class/drm/card*/device/vendor 2>/dev/null | xargs cat 2>/dev/null | grep -q "0x8086"; then
        INTEL_FOUND=true
        if [ -z "$GPU_NAME" ]; then
            GPU_NAME="Intel GPU (detected via sysfs)"
        fi
    fi
fi

# Method 3: Check for i915 driver loaded (Intel graphics driver)
if [ "$INTEL_FOUND" = "false" ]; then
    if lsmod 2>/dev/null | grep -qi "i915"; then
        INTEL_FOUND=true
        if [ -z "$GPU_NAME" ]; then
            GPU_NAME="Intel GPU (driver loaded)"
        fi
    fi
fi

# Determine if GPU mining is available
if [ "$NVIDIA_FOUND" = "true" ] || [ "$AMD_FOUND" = "true" ] || [ "$INTEL_FOUND" = "true" ]; then
    # Escape quotes in GPU name for JSON
    GPU_NAME_ESCAPED=$(echo "$GPU_NAME" | sed 's/"/\\"/g')
    printf '{"gpu_available":true,"gpu_name":"%s","nvidia":%s,"amd":%s,"intel":%s,"arch":"%s"}' \
        "$GPU_NAME_ESCAPED" "$NVIDIA_FOUND" "$AMD_FOUND" "$INTEL_FOUND" "$ARCH"
else
    printf '{"gpu_available":false,"reason":"No NVIDIA, AMD, or Intel GPU detected","nvidia":false,"amd":false,"intel":false,"arch":"%s"}' "$ARCH"
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/gpu.cgi"

    # USB ASIC Detection CGI - Detects USB mining devices (Block Erupters, GekkoScience, etc.)
    cat > "$BASE/cgi-bin/usbasic.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

ASIC_FOUND=false
ASIC_COUNT=0
ASIC_DEVICES=""

# Common USB ASIC vendor IDs and product IDs:
# ASICMiner Block Erupter: 10c4:ea60 (CP210x USB to UART)
# GekkoScience Compac/Newpac/2PAC: 0483:5740 (STM32 CDC)
# Antminer U1/U2/U3: 10c4:ea60 or 067b:2303
# FutureBit Moonlander 2: 0403:6001 (FTDI)
# Gridseed: 0483:5740 or 10c4:ea60

# Method 1: Check lsusb for known ASIC device patterns
if command -v lsusb >/dev/null 2>&1; then
    # Check for Silicon Labs CP210x (Block Erupter, many ASICs)
    CP210X_COUNT=$(lsusb 2>/dev/null | grep -ci "10c4:ea60" || echo "0")
    if [ "$CP210X_COUNT" -gt 0 ]; then
        ASIC_FOUND=true
        ASIC_COUNT=$((ASIC_COUNT + CP210X_COUNT))
        ASIC_DEVICES="${ASIC_DEVICES}Block Erupter/Generic ASIC (CP210x),"
    fi

    # Check for STM32 CDC (GekkoScience Compac/Newpac/2PAC)
    STM32_COUNT=$(lsusb 2>/dev/null | grep -ci "0483:5740" || echo "0")
    if [ "$STM32_COUNT" -gt 0 ]; then
        ASIC_FOUND=true
        ASIC_COUNT=$((ASIC_COUNT + STM32_COUNT))
        ASIC_DEVICES="${ASIC_DEVICES}GekkoScience ASIC (STM32),"
    fi

    # Check for Prolific PL2303 (Some Antminers)
    PL2303_COUNT=$(lsusb 2>/dev/null | grep -ci "067b:2303" || echo "0")
    if [ "$PL2303_COUNT" -gt 0 ]; then
        ASIC_FOUND=true
        ASIC_COUNT=$((ASIC_COUNT + PL2303_COUNT))
        ASIC_DEVICES="${ASIC_DEVICES}Antminer USB (PL2303),"
    fi

    # Check for FTDI (FutureBit Moonlander, some ASICs)
    FTDI_COUNT=$(lsusb 2>/dev/null | grep -ci "0403:6001" || echo "0")
    if [ "$FTDI_COUNT" -gt 0 ]; then
        ASIC_FOUND=true
        ASIC_COUNT=$((ASIC_COUNT + FTDI_COUNT))
        ASIC_DEVICES="${ASIC_DEVICES}FTDI USB Device (Moonlander/ASIC),"
    fi

    # Check for Canaantech (Avalon USB)
    AVALON_COUNT=$(lsusb 2>/dev/null | grep -ci "1fc9:0003" || echo "0")
    if [ "$AVALON_COUNT" -gt 0 ]; then
        ASIC_FOUND=true
        ASIC_COUNT=$((ASIC_COUNT + AVALON_COUNT))
        ASIC_DEVICES="${ASIC_DEVICES}Avalon USB,"
    fi
fi

# Method 2: Check /dev for ttyUSB* or ttyACM* devices (common for USB ASICs)
if [ "$ASIC_FOUND" = "false" ]; then
    TTY_COUNT=0
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        if [ -e "$dev" ]; then
            TTY_COUNT=$((TTY_COUNT + 1))
        fi
    done
    if [ "$TTY_COUNT" -gt 0 ]; then
        # We found serial devices - could be ASICs
        ASIC_FOUND=true
        ASIC_COUNT=$TTY_COUNT
        ASIC_DEVICES="USB Serial Device(s) detected"
    fi
fi

# Method 3: Check for specific USB serial devices by driver
if command -v dmesg >/dev/null 2>&1; then
    if dmesg 2>/dev/null | tail -100 | grep -qi "cp210x\|ftdi_sio\|pl2303\|cdc_acm.*ttyACM"; then
        if [ "$ASIC_FOUND" = "false" ]; then
            ASIC_FOUND=true
            ASIC_COUNT=1
            ASIC_DEVICES="USB Serial ASIC (from dmesg)"
        fi
    fi
fi

# Clean up devices string (remove trailing comma)
ASIC_DEVICES=$(echo "$ASIC_DEVICES" | sed 's/,$//')

if [ "$ASIC_FOUND" = "true" ]; then
    printf '{"usbasic_available":true,"device_count":%d,"devices":"%s"}' "$ASIC_COUNT" "$ASIC_DEVICES"
else
    printf '{"usbasic_available":false,"device_count":0,"devices":"","reason":"No USB ASIC devices detected"}'
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/usbasic.cgi"

    # Save CGI - WITH STRATUM URL FIX
    cat > "$BASE/cgi-bin/save.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: text/html"
echo ""

if [ "$REQUEST_METHOD" = "POST" ]; then
    if [ -n "$CONTENT_LENGTH" ]; then
        POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    else
        read POST_DATA
    fi
else
    POST_DATA="$QUERY_STRING"
fi

MINER=""
WALLET=""
DOGE_WALLET=""
LTC_WALLET=""
WORKER="worker1"
THREADS="2"
POOL=""
PASSWORD="x"
CPU_MINING="true"
GPU_MINING="false"
GPU_MINER="srbminer"
USBASIC_MINING="false"
USBASIC_ALGO="sha256d"

IFS='&'
for param in $POST_DATA; do
    IFS='='
    set -- $param
    key="$1"
    value="$2"
    value=$(echo "$value" | sed 's/+/ /g' | sed 's/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")

    case "$key" in
        miner) MINER="$value" ;;
        wallet) WALLET="$value" ;;
        doge_wallet) DOGE_WALLET="$value" ;;
        ltc_wallet) LTC_WALLET="$value" ;;
        worker) WORKER="$value" ;;
        threads) THREADS="$value" ;;
        pool) POOL="$value" ;;
        password) PASSWORD="$value" ;;
        cpu_mining) CPU_MINING="$value" ;;
        gpu_mining) GPU_MINING="$value" ;;
        gpu_miner) GPU_MINER="$value" ;;
        usbasic_mining) USBASIC_MINING="$value" ;;
        usbasic_algo) USBASIC_ALGO="$value" ;;
    esac
done
IFS=' '

if [ -z "$MINER" ] || [ -z "$WALLET" ]; then
    echo "<div class='error'>❌ Missing required fields</div>"
    exit 0
fi

# STRIP any existing protocol prefix from pool URL (stratum, http, https)
POOL=$(echo "$POOL" | sed 's|^stratum+tcp://||' | sed 's|^stratum+ssl://||' | sed 's|^stratum://||' | sed 's|^https\?://||')

# Set default pools if not provided
case "$MINER" in
    btc) [ -z "$POOL" ] && POOL="pool.btc.com:3333" ;;
    ltc) [ -z "$POOL" ] && POOL="stratum.aikapool.com:7900" ;;
    doge) [ -z "$POOL" ] && POOL="prohashing.com:3332" ;;
    xmr) [ -z "$POOL" ] && POOL="pool.supportxmr.com:3333" ;;
    scala) [ -z "$POOL" ] && POOL="pool.scalaproject.io:3333" ;;
    verus) [ -z "$POOL" ] && POOL="pool.verus.io:9999" ;;
    aeon) [ -z "$POOL" ] && POOL="aeon.herominers.com:10650" ;;
    dero) [ -z "$POOL" ] && POOL="dero-node-sk.mysrv.cloud:10300" ;;
    zephyr) [ -z "$POOL" ] && POOL="de.zephyr.herominers.com:1123" ;;
    salvium) [ -z "$POOL" ] && POOL="de.salvium.herominers.com:1228" ;;
    yadacoin) [ -z "$POOL" ] && POOL="pool.yadacoin.io:3333" ;;
    arionum) [ -z "$POOL" ] && POOL="aropool.com:80" ;;
    dash) [ -z "$POOL" ] && POOL="dash.suprnova.cc:9989" ;;
    dcr) [ -z "$POOL" ] && POOL="dcr.suprnova.cc:3252" ;;
    zen) [ -z "$POOL" ] && POOL="zen.suprnova.cc:3618" ;;
    kda) [ -z "$POOL" ] && POOL="pool.woolypooly.com:3112" ;;
    # Solopool.org lottery pools
    btc-lotto) [ -z "$POOL" ] && POOL="eu3.solopool.org:8005" ;;
    bch-lotto) [ -z "$POOL" ] && POOL="eu2.solopool.org:8002" ;;
    ltc-lotto) [ -z "$POOL" ] && POOL="eu3.solopool.org:8003" ;;
    doge-lotto) [ -z "$POOL" ] && POOL="eu3.solopool.org:8003" ;;
    xmr-lotto) [ -z "$POOL" ] && POOL="eu1.solopool.org:8010" ;;
    etc-lotto) [ -z "$POOL" ] && POOL="eu1.solopool.org:8011" ;;
    ethw-lotto) [ -z "$POOL" ] && POOL="eu2.solopool.org:8005" ;;
    kas-lotto) [ -z "$POOL" ] && POOL="eu2.solopool.org:8008" ;;
    erg-lotto) [ -z "$POOL" ] && POOL="eu1.solopool.org:8001" ;;
    rvn-lotto) [ -z "$POOL" ] && POOL="eu1.solopool.org:8013" ;;
    zeph-lotto) [ -z "$POOL" ] && POOL="eu2.solopool.org:8006" ;;
    dgb-lotto) [ -z "$POOL" ] && POOL="eu1.solopool.org:8004" ;;
    xec-lotto) [ -z "$POOL" ] && POOL="eu2.solopool.org:8013" ;;
    fb-lotto) [ -z "$POOL" ] && POOL="eu3.solopool.org:8002" ;;
    bc2-lotto) [ -z "$POOL" ] && POOL="eu3.solopool.org:8001" ;;
    xel-lotto) [ -z "$POOL" ] && POOL="eu3.solopool.org:8004" ;;
    octa-lotto) [ -z "$POOL" ] && POOL="eu2.solopool.org:8004" ;;
    *) [ -z "$POOL" ] && POOL="rx.unmineable.com:3333" ;;
esac

mkdir -p /opt/frynet-config/output
chmod 777 /opt/frynet-config/output

# Default password to "x" if empty
[ -z "$PASSWORD" ] && PASSWORD="x"

cat > /opt/frynet-config/config.txt <<EOF
miner=$MINER
wallet=$WALLET
doge_wallet=$DOGE_WALLET
ltc_wallet=$LTC_WALLET
worker=$WORKER
threads=$THREADS
pool=$POOL
password=$PASSWORD
cpu_mining=$CPU_MINING
gpu_mining=$GPU_MINING
gpu_miner=$GPU_MINER
usbasic_mining=$USBASIC_MINING
usbasic_algo=$USBASIC_ALGO
EOF
chmod 666 /opt/frynet-config/config.txt

SCRIPT_DIR="/opt/frynet-config/output/$MINER"
mkdir -p "$SCRIPT_DIR"
SCRIPT_FILE="$SCRIPT_DIR/start.sh"

# Initialize flags
IS_UNMINEABLE=false
USE_XLARIG=false

# Determine algorithm and miner type
case "$MINER" in
    btc)
        ALGO="sha256d"
        USE_CPUMINER=true
        ;;
    ltc|ltc-lotto)
        ALGO="scrypt"
        USE_CPUMINER=true
        ;;
    doge|doge-lotto)
        ALGO="scrypt"
        USE_CPUMINER=true
        ;;
    dash)
        ALGO="x11"
        USE_CPUMINER=true
        ;;
    dcr)
        ALGO="decred"
        USE_CPUMINER=true
        ;;
    kda)
        ALGO="blake2s"
        USE_CPUMINER=true
        ;;
    verus)
        ALGO="verushash"
        USE_CPUMINER=true
        ;;
    arionum)
        ALGO="argon2d4096"
        USE_CPUMINER=true
        ;;
    btc-lotto)
        ALGO="sha256d"
        USE_CPUMINER=true
        ;;
    xmr|xmr-lotto)
        ALGO="rx/0"
        USE_CPUMINER=false
        ;;
    scala)
        ALGO="panthera"
        USE_CPUMINER=false
        USE_XLARIG=true
        ;;
    aeon)
        ALGO="rx/0"
        USE_CPUMINER=false
        ;;
    dero)
        ALGO="astrobwt"
        USE_CPUMINER=false
        ;;
    zephyr)
        ALGO="rx/0"
        USE_CPUMINER=false
        ;;
    salvium)
        ALGO="rx/0"
        USE_CPUMINER=false
        ;;
    yadacoin)
        ALGO="rx/yada"
        USE_CPUMINER=false
        ;;
    bch-lotto)
        ALGO="sha256d"
        USE_CPUMINER=true
        ;;
    dgb-lotto|xec-lotto|fb-lotto|bc2-lotto)
        ALGO="sha256d"
        USE_CPUMINER=true
        ;;
    zeph-lotto)
        ALGO="rx/0"
        USE_CPUMINER=false
        ;;
    etc-lotto|ethw-lotto|octa-lotto)
        # GPU mining with Ethash/Etchash - requires GPU miner
        ALGO="etchash"
        USE_CPUMINER=false
        IS_GPU_ONLY=true
        ;;
    kas-lotto)
        # Kaspa uses KHeavyHash - GPU/ASIC only
        ALGO="kheavyhash"
        USE_CPUMINER=false
        IS_GPU_ONLY=true
        ;;
    erg-lotto)
        # Ergo uses Autolykos2 - GPU mining
        ALGO="autolykos2"
        USE_CPUMINER=false
        IS_GPU_ONLY=true
        ;;
    rvn-lotto)
        # Ravencoin uses KAWPOW - GPU mining
        ALGO="kawpow"
        USE_CPUMINER=false
        IS_GPU_ONLY=true
        ;;
    xel-lotto)
        # Xelis uses XelisHash - CPU/GPU mineable
        ALGO="xelishash"
        USE_CPUMINER=false
        ;;
    *)
        # Unmineable coins use XMRig with RandomX
        # Format wallet as COIN:address for Unmineable
        ALGO="rx/0"
        USE_CPUMINER=false
        IS_UNMINEABLE=true
        ;;
esac

# For Unmineable coins, prepend the coin ticker to the wallet address
# Also add referral code for Unmineable (dev fee)
UNMINEABLE_REFERRAL="efz3-b4fb"  # Referral code for Unmineable
if [ "$IS_UNMINEABLE" = "true" ]; then
    COIN_UPPER=$(echo "$MINER" | tr 'a-z' 'A-Z')
    # Check if wallet already has the prefix
    case "$WALLET" in
        *:*) ;; # Already has prefix, leave it
        *) WALLET="${COIN_UPPER}:${WALLET}" ;; # Add prefix
    esac
fi

# Create start script - use FULL PATH to ensure correct binary
# Uses unbuffered output for real-time logging
# INCLUDES 2% DEV FEE - cycles between user and dev wallets
cat > "$SCRIPT_FILE" <<'STARTSCRIPT'
#!/bin/sh
LOG="/opt/frynet-config/logs/miner.log"

# Log startup info
echo "[$(date)] ========================================" >> "$LOG"
echo "[$(date)] Starting mining session" >> "$LOG"
echo "[$(date)] Dev fee: 2% (1 min per 50 min cycle)" >> "$LOG"
STARTSCRIPT

# Determine dev wallet based on coin type
# For RandomX coins, dev fee mines Scala instead (better consolidation)
DEV_USE_SCALA=false
DEV_SCALA_WALLET="Ssy2BnsAcJUVZZ2kTiywf61bvYjvPosXzaBcaft9RSvaNNKsFRkcKbaWjMotjATkSbSmeSdX2DAxc1XxpcdxUBGd41oCwwfetG"
DEV_SCALA_POOL="pool.scalaproject.io:3333"

case "$MINER" in
    xmr|xmr-lotto)
        # XMR - route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    aeon)
        # Aeon (RandomX) - route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    ltc|ltc-lotto)
        DEV_WALLET_FOR_COIN="ltc1qrdc0wqzs3cwuhxxzkq2khepec2l3c6uhd8l9jy"
        ;;
    btc|btc-lotto)
        DEV_WALLET_FOR_COIN="bc1qr6ldduupwn4dtqq4dwthv4vp3cg2dx7u3mcgva"
        ;;
    bch|bch-lotto)
        DEV_WALLET_FOR_COIN="qrsvjp5987h57x8e6tnv430gq4hnq4jy5vf8u5x4d9"
        ;;
    doge|doge-lotto)
        DEV_WALLET_FOR_COIN="D5nsUsiivbNv2nmuNE9x2ybkkCTEL4ceHj"
        ;;
    dash)
        DEV_WALLET_FOR_COIN="Xff5VZsVpFxpJYazyQ8hbabzjWAmq1TqPG"
        ;;
    dcr)
        DEV_WALLET_FOR_COIN="DsTSHaQRwE9bibKtq5gCtaYZXSp7UhzMiWw"
        ;;
    kda)
        DEV_WALLET_FOR_COIN="k:05178b77e1141ca2319e66cab744e8149349b3f140a676624f231314d483f7a3"
        ;;
    dero)
        DEV_WALLET_FOR_COIN="dero1qysrv5fp2xethzatpdf80umh8yu2nk404tc3cw2lwypgynj3qvhtgqq294092"
        ;;
    zephyr)
        # Zephyr (RandomX) - route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    scala)
        # Scala - mine directly to Scala wallet using XLArig
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    verus)
        DEV_WALLET_FOR_COIN="RRhFqT2bfXQmsnqtyrVxikhy94KqnVf5nt"
        ;;
    salvium)
        # Salvium (RandomX) - route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    yadacoin)
        # Yadacoin (RandomX variant) - route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    arionum)
        # Arionum - route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    *)
        # For Unmineable tokens (RandomX-based), route dev fee to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
esac

cat >> "$SCRIPT_FILE" <<EOF
echo "[\$(date)] Coin: $MINER" >> "\$LOG"
echo "[\$(date)] Pool: $POOL" >> "\$LOG"
echo "[\$(date)] Algorithm: $ALGO" >> "\$LOG"
echo "[\$(date)] Wallet: $WALLET" >> "\$LOG"
echo "[\$(date)] Worker: $WORKER" >> "\$LOG"
echo "[\$(date)] CPU Mining: $CPU_MINING (Threads: $THREADS)" >> "\$LOG"
echo "[\$(date)] GPU Mining: $GPU_MINING (Miner: $GPU_MINER)" >> "\$LOG"
echo "[\$(date)] USB ASIC Mining: $USBASIC_MINING (Algorithm: $USBASIC_ALGO)" >> "\$LOG"
echo "[\$(date)] ========================================" >> "\$LOG"

# Mining mode configuration
CPU_MINING_ENABLED="$CPU_MINING"
GPU_MINING_ENABLED="$GPU_MINING"
GPU_MINER_TYPE="$GPU_MINER"
USBASIC_MINING_ENABLED="$USBASIC_MINING"
USBASIC_ALGO_TYPE="$USBASIC_ALGO"

# Pool configuration
POOL="$POOL"

# Dev fee configuration (2%)
USER_WALLET="$WALLET"
DOGE_WALLET="$DOGE_WALLET"
LTC_WALLET="$LTC_WALLET"
WORKER="$WORKER"
USER_PASSWORD="$PASSWORD"
DEV_WALLET="$DEV_WALLET_FOR_COIN"
USER_MINUTES=49
DEV_MINUTES=1

# Solopool merged mining detection (LTC+DOGE)
IS_SOLOPOOL_MERGED="false"
EOF

# Check if this is solopool merged mining
case "$MINER" in
    ltc-lotto)
        cat >> "$SCRIPT_FILE" <<'SOLOPOOL_MERGED_LTC'
# Check if using solopool.org for LTC merged mining
if echo "$POOL" | grep -qi "solopool"; then
    IS_SOLOPOOL_MERGED="true"
    # Dev DOGE address used as default if user doesn't provide one
    DEV_DOGE_ADDRESS="D5nsUsiivbNv2nmuNE9x2ybkkCTEL4ceHj"

    # For LTC solopool.org merged mining, format: LTC_ADDRESS, DOGE_ADDRESS.RIG_ID
    if [ -n "$DOGE_WALLET" ]; then
        USER_WALLET_STRING="$USER_WALLET, $DOGE_WALLET.$WORKER"
        echo "[$(date)] Merged Mining Mode: LTC + DOGE" >> "$LOG"
        echo "[$(date)] DOGE rewards going to: $DOGE_WALLET" >> "$LOG"
    else
        # Use dev DOGE address as default
        USER_WALLET_STRING="$USER_WALLET, $DEV_DOGE_ADDRESS.$WORKER"
        echo "[$(date)] Merged Mining Mode: LTC + DOGE" >> "$LOG"
        echo "[$(date)] NOTE: No DOGE address provided - DOGE rewards go to dev address" >> "$LOG"
    fi
    echo "[$(date)] Stratum User: $USER_WALLET_STRING" >> "$LOG"
else
    # Not using solopool, use standard format
    IS_SOLOPOOL_MERGED="false"
    USER_WALLET_STRING="$USER_WALLET.$WORKER"
fi
SOLOPOOL_MERGED_LTC
        ;;
    doge-lotto)
        cat >> "$SCRIPT_FILE" <<'SOLOPOOL_MERGED_DOGE'
# Check if using solopool.org for DOGE merged mining
if echo "$POOL" | grep -qi "solopool"; then
    IS_SOLOPOOL_MERGED="true"
    # Dev LTC address used as default if user doesn't provide one
    DEV_LTC_ADDRESS="ltc1qrdc0wqzs3cwuhxxzkq2khepec2l3c6uhd8l9jy"

    # For DOGE solopool.org merged mining, format: DOGE_ADDRESS, LTC_ADDRESS.RIG_ID
    if [ -n "$LTC_WALLET" ]; then
        USER_WALLET_STRING="$USER_WALLET, $LTC_WALLET.$WORKER"
        echo "[$(date)] Merged Mining Mode: DOGE + LTC" >> "$LOG"
        echo "[$(date)] LTC rewards going to: $LTC_WALLET" >> "$LOG"
    else
        # Use dev LTC address as default
        USER_WALLET_STRING="$USER_WALLET, $DEV_LTC_ADDRESS.$WORKER"
        echo "[$(date)] Merged Mining Mode: DOGE + LTC" >> "$LOG"
        echo "[$(date)] NOTE: No LTC address provided - LTC rewards go to dev address" >> "$LOG"
    fi
    echo "[$(date)] Stratum User: $USER_WALLET_STRING" >> "$LOG"
else
    # Not using solopool, use standard format
    IS_SOLOPOOL_MERGED="false"
    USER_WALLET_STRING="$USER_WALLET.$WORKER"
fi
SOLOPOOL_MERGED_DOGE
        ;;
    *)
        cat >> "$SCRIPT_FILE" <<'NORMAL_WALLET'
# Standard wallet format: ADDRESS.WORKER
USER_WALLET_STRING="$USER_WALLET.$WORKER"
NORMAL_WALLET
        ;;
esac

cat >> "$SCRIPT_FILE" <<'DEVWALLETSTRING'
# Dev wallet string (standard format)
DEV_WALLET_STRING="$DEV_WALLET.frydev"
DEVWALLETSTRING

cat >> "$SCRIPT_FILE" <<'RESTOFSCRIPT'

# Remove clean stop marker
rm -f /opt/frynet-config/stopped 2>/dev/null

# Run optimization script if available (huge pages, MSR, etc)
if [ -x /opt/frynet-config/optimize.sh ]; then
    echo "[$(date)] Running mining optimizations..." >> "$LOG"
    /opt/frynet-config/optimize.sh >> "$LOG" 2>&1
fi

# Function to stop miner gracefully with proper cleanup
stop_miner() {
    # Send SIGTERM first for graceful shutdown
    pkill -TERM -f "xmrig" 2>/dev/null
    pkill -TERM -f "xlarig" 2>/dev/null
    pkill -TERM -f "cpuminer" 2>/dev/null
    pkill -TERM -f "minerd" 2>/dev/null
    # GPU miners
    pkill -TERM -f "SRBMiner-MULTI" 2>/dev/null
    pkill -TERM -f "lolMiner" 2>/dev/null
    pkill -TERM -f "t-rex" 2>/dev/null
    # USB ASIC miners
    pkill -TERM -f "bfgminer" 2>/dev/null
    pkill -TERM -f "cgminer" 2>/dev/null

    # Wait for processes to actually terminate (up to 5 seconds)
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt 10 ]; do
        # Check if any miner processes are still running
        if ! pgrep -f "xmrig|xlarig|cpuminer|minerd|SRBMiner-MULTI|lolMiner|t-rex|bfgminer|cgminer" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done

    # Force kill any remaining processes
    pkill -KILL -f "xmrig" 2>/dev/null
    pkill -KILL -f "xlarig" 2>/dev/null
    pkill -KILL -f "cpuminer" 2>/dev/null
    pkill -KILL -f "minerd" 2>/dev/null
    # GPU miners
    pkill -KILL -f "SRBMiner-MULTI" 2>/dev/null
    pkill -KILL -f "lolMiner" 2>/dev/null
    # USB ASIC miners
    pkill -KILL -f "bfgminer" 2>/dev/null
    pkill -KILL -f "cgminer" 2>/dev/null
    pkill -KILL -f "t-rex" 2>/dev/null

    # Additional wait for TCP connections to fully close (TIME_WAIT cleanup)
    sleep 3
}

# Trap to cleanup on exit
trap 'stop_miner; exit 0' INT TERM

# Dev fee cycling loop
while true; do
    # Check if stopped by user
    if [ -f /opt/frynet-config/stopped ]; then
        echo "[$(date)] Mining stopped by user" >> "$LOG"
        stop_miner
        exit 0
    fi

    # ========== USER MINING (98% - 49 minutes) ==========
    echo "[$(date)] Mining for user wallet..." >> "$LOG"
    CPU_PID=""
    GPU_PID=""
RESTOFSCRIPT

# Add CPU miner command - USER WALLET
cat >> "$SCRIPT_FILE" <<'CPUCHECK'
    # Start CPU miner if enabled
    if [ "$CPU_MINING_ENABLED" = "true" ]; then
        echo "[$(date)] Starting CPU miner..." >> "$LOG"
CPUCHECK

if [ "$USE_XLARIG" = "true" ]; then
    # Scala mining uses XLArig with panthera algorithm
    cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/xlarig -o $POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --threads=$THREADS -a panthera --no-color --donate-level=0 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
elif [ "$USE_CPUMINER" = "true" ]; then
    cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/cpuminer --algo=$ALGO -o stratum+tcp://$POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --threads=$THREADS --retry 10 --retry-pause 30 --timeout 300 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
else
    XMRIG_OPTS="--cpu-priority 5 --randomx-no-numa"
    if [ "$IS_UNMINEABLE" = "true" ]; then
        cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/xmrig -o $POOL -u \$USER_WALLET.$WORKER#$UNMINEABLE_REFERRAL -p \$USER_PASSWORD --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
    else
        cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/xmrig -o $POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
    fi
fi

cat >> "$SCRIPT_FILE" <<'CPUEND'
    fi
CPUEND

# Add GPU miner command - USER WALLET
cat >> "$SCRIPT_FILE" <<'GPUCHECK'
    # Start GPU miner if enabled
    if [ "$GPU_MINING_ENABLED" = "true" ]; then
        echo "[$(date)] Starting GPU miner ($GPU_MINER_TYPE)..." >> "$LOG"
        case "$GPU_MINER_TYPE" in
            srbminer)
GPUCHECK

# SRBMiner command - supports many algos
cat >> "$SCRIPT_FILE" <<EOF
                /usr/local/bin/SRBMiner-MULTI --pool $POOL --wallet "\$USER_WALLET_STRING" --password \$USER_PASSWORD --algorithm $ALGO --disable-cpu 2>&1 | tee -a "\$LOG" &
                GPU_PID=\$!
EOF

cat >> "$SCRIPT_FILE" <<'GPUMID'
                ;;
            lolminer)
GPUMID

# lolMiner command
cat >> "$SCRIPT_FILE" <<EOF
                /usr/local/bin/lolMiner --pool $POOL --user "\$USER_WALLET_STRING" --pass \$USER_PASSWORD --algo $ALGO 2>&1 | tee -a "\$LOG" &
                GPU_PID=\$!
EOF

cat >> "$SCRIPT_FILE" <<'GPUMID2'
                ;;
            trex)
GPUMID2

# T-Rex command (NVIDIA only)
cat >> "$SCRIPT_FILE" <<EOF
                /usr/local/bin/t-rex -a $ALGO -o stratum+tcp://$POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD 2>&1 | tee -a "\$LOG" &
                GPU_PID=\$!
EOF

cat >> "$SCRIPT_FILE" <<'GPUEND'
                ;;
            *)
                echo "[$(date)] Unknown GPU miner type: $GPU_MINER_TYPE" >> "$LOG"
                ;;
        esac
    fi
GPUEND

# Add USB ASIC miner command - USER WALLET
cat >> "$SCRIPT_FILE" <<'USBASICCHECK'
    # Start USB ASIC miner if enabled
    ASIC_PID=""
    if [ "$USBASIC_MINING_ENABLED" = "true" ]; then
        echo "[$(date)] Starting USB ASIC miner (bfgminer)..." >> "$LOG"
USBASICCHECK

# BFGMiner command for USB ASICs
cat >> "$SCRIPT_FILE" <<EOF
        # Detect USB ASIC devices and start bfgminer
        # BFGMiner auto-detects USB devices with --scan-serial all
        if [ -x /usr/local/bin/bfgminer ]; then
            /usr/local/bin/bfgminer -o stratum+tcp://$POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --algo \$USBASIC_ALGO_TYPE --scan-serial all --no-getwork --no-gbt -T 2>&1 | tee -a "\$LOG" &
            ASIC_PID=\$!
        elif command -v bfgminer >/dev/null 2>&1; then
            bfgminer -o stratum+tcp://$POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --algo \$USBASIC_ALGO_TYPE --scan-serial all --no-getwork --no-gbt -T 2>&1 | tee -a "\$LOG" &
            ASIC_PID=\$!
        else
            echo "[\$(date)] ERROR: bfgminer not found, USB ASIC mining unavailable" >> "\$LOG"
        fi
EOF

cat >> "$SCRIPT_FILE" <<'USBASICEND'
    fi
USBASICEND

# Continue the script - wait for user mining period
cat >> "$SCRIPT_FILE" <<'EOF'

    # Wait for user mining period (49 minutes = 2940 seconds)
    WAIT_TIME=$((USER_MINUTES * 60))
    WAITED=0
    while [ $WAITED -lt $WAIT_TIME ]; do
        # Check every 10 seconds if we should stop
        if [ -f /opt/frynet-config/stopped ]; then
            stop_miner
            exit 0
        fi
        # Check if at least one miner is still running
        MINER_RUNNING=false
        if [ -n "$CPU_PID" ] && kill -0 $CPU_PID 2>/dev/null; then
            MINER_RUNNING=true
        fi
        if [ -n "$GPU_PID" ] && kill -0 $GPU_PID 2>/dev/null; then
            MINER_RUNNING=true
        fi
        if [ -n "$ASIC_PID" ] && kill -0 $ASIC_PID 2>/dev/null; then
            MINER_RUNNING=true
        fi
        if [ "$MINER_RUNNING" = "false" ]; then
            echo "[$(date)] All miner processes died, restarting..." >> "$LOG"
            break
        fi
        sleep 10
        WAITED=$((WAITED + 10))
    done

    # Stop user mining
    stop_miner

    # Check again if stopped by user
    if [ -f /opt/frynet-config/stopped ]; then
        exit 0
    fi

    # ========== DEV FEE MINING (2% - 1 minute) ==========
    echo "[$(date)] Dev fee mining (2%)..." >> "$LOG"
    CPU_PID=""
    GPU_PID=""
    ASIC_PID=""
EOF

# Add CPU miner command - DEV WALLET
# For high-minimum coins (Scala, Salvium, Yadacoin), mine Scala during dev fee
cat >> "$SCRIPT_FILE" <<'DEVCPUCHECK'
    # Start CPU miner if enabled (dev fee)
    if [ "$CPU_MINING_ENABLED" = "true" ]; then
DEVCPUCHECK

if [ "$USE_CPUMINER" = "true" ]; then
    cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/cpuminer --algo=$ALGO -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x --threads=$THREADS --retry 10 --retry-pause 30 --timeout 300 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
elif [ "$DEV_USE_SCALA" = "true" ]; then
    # RandomX coins: Mine Scala during dev fee using XLArig
    cat >> "$SCRIPT_FILE" <<EOF
        echo "[\$(date)] (Routing to Scala - using XLArig)" >> "\$LOG"
        /usr/local/bin/xlarig -o $DEV_SCALA_POOL -u \$DEV_WALLET.frydev -p x --threads=$THREADS -a panthera --no-color --donate-level=0 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
else
    XMRIG_OPTS="--cpu-priority 5 --randomx-no-numa"
    if [ "$IS_UNMINEABLE" = "true" ]; then
        cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/xmrig -o $POOL -u \$DEV_WALLET.frydev#$UNMINEABLE_REFERRAL -p x --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
    else
        cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/xmrig -o $POOL -u \$DEV_WALLET.frydev -p x --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
    fi
fi

cat >> "$SCRIPT_FILE" <<'DEVCPUEND'
    fi
DEVCPUEND

# Add GPU miner command - DEV WALLET
cat >> "$SCRIPT_FILE" <<'DEVGPUCHECK'
    # Start GPU miner if enabled (dev fee)
    if [ "$GPU_MINING_ENABLED" = "true" ]; then
        case "$GPU_MINER_TYPE" in
            srbminer)
DEVGPUCHECK

cat >> "$SCRIPT_FILE" <<EOF
                /usr/local/bin/SRBMiner-MULTI --pool $POOL --wallet \$DEV_WALLET.frydev --password x --algorithm $ALGO --disable-cpu 2>&1 | tee -a "\$LOG" &
                GPU_PID=\$!
EOF

cat >> "$SCRIPT_FILE" <<'DEVGPUMID'
                ;;
            lolminer)
DEVGPUMID

cat >> "$SCRIPT_FILE" <<EOF
                /usr/local/bin/lolMiner --pool $POOL --user \$DEV_WALLET.frydev --pass x --algo $ALGO 2>&1 | tee -a "\$LOG" &
                GPU_PID=\$!
EOF

cat >> "$SCRIPT_FILE" <<'DEVGPUMID2'
                ;;
            trex)
DEVGPUMID2

cat >> "$SCRIPT_FILE" <<EOF
                /usr/local/bin/t-rex -a $ALGO -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x 2>&1 | tee -a "\$LOG" &
                GPU_PID=\$!
EOF

cat >> "$SCRIPT_FILE" <<'DEVGPUEND'
                ;;
        esac
    fi
DEVGPUEND

# Add USB ASIC miner command - DEV WALLET (for dev fee period)
cat >> "$SCRIPT_FILE" <<'DEVUSBASICCHECK'
    # Start USB ASIC miner if enabled (dev fee)
    if [ "$USBASIC_MINING_ENABLED" = "true" ]; then
DEVUSBASICCHECK

cat >> "$SCRIPT_FILE" <<EOF
        if [ -x /usr/local/bin/bfgminer ]; then
            /usr/local/bin/bfgminer -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x --algo \$USBASIC_ALGO_TYPE --scan-serial all --no-getwork --no-gbt -T 2>&1 | tee -a "\$LOG" &
            ASIC_PID=\$!
        elif command -v bfgminer >/dev/null 2>&1; then
            bfgminer -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x --algo \$USBASIC_ALGO_TYPE --scan-serial all --no-getwork --no-gbt -T 2>&1 | tee -a "\$LOG" &
            ASIC_PID=\$!
        fi
EOF

cat >> "$SCRIPT_FILE" <<'DEVUSBASICEND'
    fi
DEVUSBASICEND

# Finish the dev fee period and loop
cat >> "$SCRIPT_FILE" <<'EOF'

    # Wait for dev fee period (1 minute = 60 seconds)
    WAIT_TIME=$((DEV_MINUTES * 60))
    WAITED=0
    while [ $WAITED -lt $WAIT_TIME ]; do
        if [ -f /opt/frynet-config/stopped ]; then
            stop_miner
            exit 0
        fi
        # Check if at least one miner is still running
        MINER_RUNNING=false
        if [ -n "$CPU_PID" ] && kill -0 $CPU_PID 2>/dev/null; then
            MINER_RUNNING=true
        fi
        if [ -n "$GPU_PID" ] && kill -0 $GPU_PID 2>/dev/null; then
            MINER_RUNNING=true
        fi
        if [ -n "$ASIC_PID" ] && kill -0 $ASIC_PID 2>/dev/null; then
            MINER_RUNNING=true
        fi
        if [ "$MINER_RUNNING" = "false" ]; then
            break
        fi
        sleep 10
        WAITED=$((WAITED + 10))
    done

    # Stop dev mining, cycle back to user
    stop_miner

done
EOF

chmod 755 "$SCRIPT_FILE"
echo "<div class='success'>✅ Configuration saved for $MINER!</div>"
SCRIPT
    chmod 755 "$BASE/cgi-bin/save.cgi"
    
    # Load CGI
    cat > "$BASE/cgi-bin/load.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

if [ -f /opt/frynet-config/config.txt ]; then
    . /opt/frynet-config/config.txt
    # Default password to "x" if not set
    [ -z "$password" ] && password="x"
    # Default CPU mining to true, GPU mining to false, USB ASIC mining to false
    [ -z "$cpu_mining" ] && cpu_mining="true"
    [ -z "$gpu_mining" ] && gpu_mining="false"
    [ -z "$gpu_miner" ] && gpu_miner="srbminer"
    [ -z "$usbasic_mining" ] && usbasic_mining="false"
    [ -z "$usbasic_algo" ] && usbasic_algo="sha256d"
    [ -z "$doge_wallet" ] && doge_wallet=""
    printf '{"miner":"%s","wallet":"%s","doge_wallet":"%s","worker":"%s","threads":"%s","pool":"%s","password":"%s","cpu_mining":"%s","gpu_mining":"%s","gpu_miner":"%s","usbasic_mining":"%s","usbasic_algo":"%s"}' \
        "$miner" "$wallet" "$doge_wallet" "$worker" "$threads" "$pool" "$password" "$cpu_mining" "$gpu_mining" "$gpu_miner" "$usbasic_mining" "$usbasic_algo"
else
    echo "{}"
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/load.cgi"
    
    # Status CGI - Uses multiple detection methods for reliability
    cat > "$BASE/cgi-bin/status.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

RUNNING="false"
CRASHED="false"
PID_FILE="/opt/frynet-config/miner.pid"
LOG_FILE="/opt/frynet-config/logs/miner.log"
STOP_FILE="/opt/frynet-config/stopped"

# Method 1: Check if PID file exists and process is running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        RUNNING="true"
    fi
fi

# Method 2: Check for miner processes directly using ps (including USB ASIC miners)
if [ "$RUNNING" = "false" ]; then
    if ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[m]inerd|[p]acketcrypt|[b]fgminer|[c]gminer" | grep -v grep >/dev/null 2>&1; then
        RUNNING="true"
        # Update PID file with found process
        ACTUAL_PID=$(ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[p]acketcrypt|[b]fgminer|[c]gminer" | grep -v grep | awk '{print $2}' | head -1)
        if [ -n "$ACTUAL_PID" ]; then
            echo "$ACTUAL_PID" > "$PID_FILE" 2>/dev/null
        fi
        # Remove stop marker if miner is running
        rm -f "$STOP_FILE" 2>/dev/null
    fi
fi

# Only check for crash if not running AND not cleanly stopped
if [ "$RUNNING" = "false" ] && [ ! -f "$STOP_FILE" ]; then
    # Check for actual crash indicators (not just any error)
    if [ -f "$LOG_FILE" ]; then
        if tail -10 "$LOG_FILE" 2>/dev/null | grep -qiE "segmentation fault|core dumped|killed.*signal|fatal error|aborted"; then
            CRASHED="true"
        fi
    fi
fi

# If running, clear stop marker
if [ "$RUNNING" = "true" ]; then
    rm -f "$STOP_FILE" 2>/dev/null
fi

printf '{"running":%s,"crashed":%s}' "$RUNNING" "$CRASHED"
SCRIPT
    chmod 755 "$BASE/cgi-bin/status.cgi"
    
    # Thermal CGI
    cat > "$BASE/cgi-bin/thermal.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

TEMP=45
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
fi

printf '{"temperature":%d}' "$TEMP"
SCRIPT
    chmod 755 "$BASE/cgi-bin/thermal.cgi"
    
    # Stats CGI - Fixed to parse cpuminer-opt output format
    cat > "$BASE/cgi-bin/stats.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

HASHRATE="--"
SHARES="0"
UPTIME="0h 0m"
EFFICIENCY="100"
ALGO="--"
DIFF="--"
POOL="--"
REJECTED="0"

LOG_FILE="/opt/frynet-config/logs/miner.log"
CONFIG_FILE="/opt/frynet-config/config.txt"
PID_FILE="/opt/frynet-config/miner.pid"

if [ -f "$LOG_FILE" ]; then
    # Strip ANSI codes
    CLEAN_LOG=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG_FILE" 2>/dev/null)
    
    # Get hashrate - XMRig format: "speed 10s/60s/15m 218.2 220.6 n/a H/s"
    # Take the 60s average (middle value)
    HR=$(echo "$CLEAN_LOG" | grep -E "miner.*speed" | tail -1 | grep -oE 'speed [0-9.]+/[0-9.]+/[0-9.n/a]+ [0-9.]+ [0-9.]+ [0-9.n/a]+ [kKMGT]?H/s')
    if [ -n "$HR" ]; then
        # Extract 60s value (second number after "speed")
        HR_60S=$(echo "$HR" | awk '{print $4}')
        HR_UNIT=$(echo "$HR" | grep -oE '[kKMGT]?H/s')
        HASHRATE="${HR_60S} ${HR_UNIT}"
    else
        # Try cpuminer format
        HR=$(echo "$CLEAN_LOG" | grep -oE '[0-9]+\.?[0-9]* [kKMGT]?H/s' | tail -1)
        [ -n "$HR" ] && HASHRATE="$HR"
    fi
    
    # Count accepted shares
    # XMRig: "[timestamp]  net      accepted (1/0) diff 100001 (42 ms)"
    ACC=$(echo "$CLEAN_LOG" | grep -c "net.*accepted" 2>/dev/null || echo "0")
    if [ "$ACC" -eq 0 ]; then
        # Try cpuminer format
        ACC=$(echo "$CLEAN_LOG" | grep -ciE "accepted|yay!" 2>/dev/null || echo "0")
    fi
    SHARES="$ACC"
    
    # Count rejected
    REJ=$(echo "$CLEAN_LOG" | grep -c "net.*rejected" 2>/dev/null || echo "0")
    if [ "$REJ" -eq 0 ]; then
        REJ=$(echo "$CLEAN_LOG" | grep -ciE "rejected|booo" 2>/dev/null || echo "0")
    fi
    REJECTED="$REJ"
    
    # Get algorithm from log
    ALG=$(echo "$CLEAN_LOG" | grep "POOL.*algo" | tail -1 | grep -oE "algo [a-zA-Z0-9/_-]+" | cut -d' ' -f2)
    [ -z "$ALG" ] && ALG=$(echo "$CLEAN_LOG" | grep "Algorithm:" | tail -1 | cut -d: -f2 | tr -d ' ')
    [ -n "$ALG" ] && ALGO="$ALG"
    
    # Get difficulty - XMRig format: "new job from pool diff 100001"
    DIFF_VAL=$(echo "$CLEAN_LOG" | grep "new job.*diff" | tail -1 | grep -oE "diff [0-9]+" | cut -d' ' -f2)
    [ -z "$DIFF_VAL" ] && DIFF_VAL=$(echo "$CLEAN_LOG" | grep -oE "[Dd]iff[: ]+[0-9]+" | tail -1 | grep -oE "[0-9]+")
    [ -n "$DIFF_VAL" ] && DIFF="$DIFF_VAL"
    
    # Get pool from config
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE" 2>/dev/null
        [ -n "$pool" ] && POOL="$pool"
    fi
fi

# Calculate uptime from PID
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null && [ -f "/proc/$PID/stat" ]; then
        BOOT_TIME=$(awk '{print $1}' /proc/uptime 2>/dev/null | cut -d. -f1)
        PROC_START=$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null)
        CLK_TCK=$(getconf CLK_TCK 2>/dev/null || echo 100)
        if [ -n "$PROC_START" ] && [ -n "$BOOT_TIME" ] && [ "$CLK_TCK" -gt 0 ]; then
            PROC_UPTIME=$((BOOT_TIME - PROC_START / CLK_TCK))
            [ "$PROC_UPTIME" -lt 0 ] && PROC_UPTIME=0
            HOURS=$((PROC_UPTIME / 3600))
            MINS=$(((PROC_UPTIME % 3600) / 60))
            UPTIME="${HOURS}h ${MINS}m"
        fi
    fi
fi

# Calculate efficiency
TOTAL=$((SHARES + REJECTED))
if [ "$TOTAL" -gt 0 ]; then
    EFFICIENCY=$((SHARES * 100 / TOTAL))
else
    EFFICIENCY=100
fi

printf '{"hashrate":"%s","shares":"%s","uptime":"%s","efficiency":%d,"algo":"%s","diff":"%s","pool":"%s","rejected":"%s"}' \
    "$HASHRATE" "$SHARES" "$UPTIME" "$EFFICIENCY" "$ALGO" "$DIFF" "$POOL" "$REJECTED"
SCRIPT
    chmod 755 "$BASE/cgi-bin/stats.cgi"
    
    # Clear logs CGI
    cat > "$BASE/cgi-bin/clearlogs.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: text/plain"
echo ""
> /opt/frynet-config/logs/miner.log
echo "Logs cleared"
SCRIPT
    chmod 755 "$BASE/cgi-bin/clearlogs.cgi"
    
    # Logs CGI - Returns last 100 lines with no-cache headers
    cat > "$BASE/cgi-bin/logs.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: text/plain"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo ""

LOG_FILE="/opt/frynet-config/logs/miner.log"

if [ -f "$LOG_FILE" ]; then
    tail -100 "$LOG_FILE" 2>/dev/null || echo "Unable to read logs"
else
    echo "No logs available yet"
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/logs.cgi"
    
    # Start CGI - Uses nohup and multiple detection methods
    cat > "$BASE/cgi-bin/start.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: text/html"
echo ""

PID_FILE="/opt/frynet-config/miner.pid"
LOG_FILE="/opt/frynet-config/logs/miner.log"

if [ ! -f /opt/frynet-config/config.txt ]; then
    echo "<div class='error'>❌ No configuration found. Please save configuration first.</div>"
    exit 0
fi

. /opt/frynet-config/config.txt

# Stop any existing miners first
pkill -9 -f "xmrig" 2>/dev/null || true
pkill -9 -f "xlarig" 2>/dev/null || true
pkill -9 -f "cpuminer" 2>/dev/null || true
pkill -9 -f "minerd" 2>/dev/null || true
# USB ASIC miners
pkill -9 -f "bfgminer" 2>/dev/null || true
pkill -9 -f "cgminer" 2>/dev/null || true
rm -f "$PID_FILE" 2>/dev/null
sleep 2

SCRIPT_FILE="/opt/frynet-config/output/$miner/start.sh"
if [ -f "$SCRIPT_FILE" ]; then
    # Clear old log and mark start time
    echo "[$(date)] Starting $miner mining..." > "$LOG_FILE"

    # Start miner - script handles its own logging via tee
    nohup sh "$SCRIPT_FILE" >/dev/null 2>&1 &
    MINER_PID=$!
    echo "$MINER_PID" > "$PID_FILE"
    chmod 666 "$PID_FILE"

    # Wait for miner to initialize
    sleep 4

    # Check multiple ways if mining is active
    RUNNING=false

    # Method 1: Check if our PID is still running
    if kill -0 "$MINER_PID" 2>/dev/null; then
        RUNNING=true
    fi

    # Method 2: Check for any miner process (including USB ASIC miners)
    if [ "$RUNNING" = "false" ]; then
        if ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[m]inerd|[b]fgminer|[c]gminer" | grep -v grep >/dev/null 2>&1; then
            # Found a miner, update PID file with actual PID
            ACTUAL_PID=$(ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[b]fgminer|[c]gminer" | grep -v grep | awk '{print $2}' | head -1)
            if [ -n "$ACTUAL_PID" ]; then
                echo "$ACTUAL_PID" > "$PID_FILE"
                RUNNING=true
            fi
        fi
    fi

    # Method 3: Check log for activity (including USB ASIC miner indicators)
    if [ "$RUNNING" = "false" ]; then
        if grep -qE "Stratum|threads started|algorithm|accepted|USB|ASIC|BFGMiner|cgminer" "$LOG_FILE" 2>/dev/null; then
            RUNNING=true
        fi
    fi
    
    if [ "$RUNNING" = "true" ]; then
        COIN_UPPER=$(echo "$miner" | tr 'a-z' 'A-Z')
        echo "<div class='success'>✅ Mining started for $COIN_UPPER!</div>"
    else
        echo "<div class='error'>⚠️ Miner may not have started. Check logs for details.</div>"
    fi
else
    echo "<div class='error'>❌ Script not found. Please save configuration again.</div>"
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/start.cgi"
    
    # Stop CGI
    cat > "$BASE/cgi-bin/stop.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: text/html"
echo ""

PID_FILE="/opt/frynet-config/miner.pid"
STOP_FILE="/opt/frynet-config/stopped"
LOG_FILE="/opt/frynet-config/logs/miner.log"

# Mark that we're stopping cleanly (not a crash)
touch "$STOP_FILE"
echo "[$(date)] Mining stopped by user" >> "$LOG_FILE"

# Check if we can use sudo
CAN_SUDO=false
if sudo -n true 2>/dev/null; then
    CAN_SUDO=true
fi

# Kill by PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ]; then
        if [ "$CAN_SUDO" = "true" ]; then
            sudo kill "$PID" 2>/dev/null || true
            sleep 1
            sudo kill -9 "$PID" 2>/dev/null || true
        else
            kill "$PID" 2>/dev/null || true
            sleep 1
            kill -9 "$PID" 2>/dev/null || true
        fi
    fi
    rm -f "$PID_FILE"
fi

# Also kill any stray miners
if [ "$CAN_SUDO" = "true" ]; then
    sudo pkill -9 -f xmrig 2>/dev/null || true
    sudo pkill -9 -f xlarig 2>/dev/null || true
    sudo pkill -9 -f cpuminer 2>/dev/null || true
    sudo pkill -9 -f minerd 2>/dev/null || true
    # USB ASIC miners
    sudo pkill -9 -f bfgminer 2>/dev/null || true
    sudo pkill -9 -f cgminer 2>/dev/null || true
else
    pkill -9 -f xmrig 2>/dev/null || true
    pkill -9 -f xlarig 2>/dev/null || true
    pkill -9 -f cpuminer 2>/dev/null || true
    pkill -9 -f minerd 2>/dev/null || true
    # USB ASIC miners
    pkill -9 -f bfgminer 2>/dev/null || true
    pkill -9 -f cgminer 2>/dev/null || true
fi

echo "<div class='success'>✅ Mining stopped</div>"
SCRIPT
    chmod 755 "$BASE/cgi-bin/stop.cgi"
    
    # Update CGI - checks for and performs updates
    cat > "$BASE/cgi-bin/update.cgi" <<'SCRIPT'
#!/bin/sh
echo "Content-type: application/json"
echo ""

ACTION="${QUERY_STRING:-check}"
REPO_API="https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main"
DOWNLOAD_URL="https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_web.sh"
VERSION_FILE="/opt/frynet-config/version.txt"
CONFIG_FILE="/opt/frynet-config/config.txt"
CONFIG_BACKUP="/opt/frynet-config/config.txt.backup"
MINER_LOG="/opt/frynet-config/logs/miner.log"
UPDATE_LOG="/opt/frynet-config/logs/update.log"
PID_FILE="/opt/frynet-config/miner.pid"
UPDATE_STATUS_FILE="/opt/frynet-config/update_status.txt"
UPDATE_ERROR_FILE="/opt/frynet-config/update_error.txt"

# Get remote version (short commit SHA)
get_remote_version() {
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout 5 --max-time 10 "$REPO_API" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- --timeout=10 "$REPO_API" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7
    fi
}

# Get local version
get_local_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" 2>/dev/null | tr -d '\n' | head -c 7
    else
        echo "unknown"
    fi
}

case "$ACTION" in
    check)
        REMOTE=$(get_remote_version)
        LOCAL=$(get_local_version)
        
        if [ -z "$REMOTE" ]; then
            printf '{"status":"error","message":"Network error","local":"%s","remote":"?"}' "$LOCAL"
        elif [ -z "$LOCAL" ] || [ "$LOCAL" = "unknown" ]; then
            printf '{"status":"available","local":"unknown","remote":"%s"}' "$REMOTE"
        elif [ "$REMOTE" != "$LOCAL" ]; then
            printf '{"status":"available","local":"%s","remote":"%s"}' "$LOCAL" "$REMOTE"
        else
            printf '{"status":"current","local":"%s","remote":"%s"}' "$LOCAL" "$REMOTE"
        fi
        ;;
    
    status)
        # Check update status and return error if failed
        if [ -f "$UPDATE_STATUS_FILE" ]; then
            STATUS=$(cat "$UPDATE_STATUS_FILE" 2>/dev/null)
            if [ "$STATUS" = "failed" ] && [ -f "$UPDATE_ERROR_FILE" ]; then
                ERROR_MSG=$(cat "$UPDATE_ERROR_FILE" 2>/dev/null)
                printf '{"status":"failed","error":"%s"}' "$ERROR_MSG"
            else
                printf '{"status":"%s"}' "$STATUS"
            fi
        else
            printf '{"status":"idle"}'
        fi
        ;;
        
    update)
        # Clear old error
        rm -f "$UPDATE_ERROR_FILE" 2>/dev/null
        echo "running" > "$UPDATE_STATUS_FILE"
        
        # Background update process
        (
            # Log to BOTH update log AND miner log (Activity tab)
            echo "" >> "$MINER_LOG"
            echo "========================================" >> "$MINER_LOG"
            echo "[$(date)] 🔄 SOFTWARE UPDATE STARTED" >> "$MINER_LOG"
            echo "========================================" >> "$MINER_LOG"
            echo "[$(date)] === Force update started ===" >> "$UPDATE_LOG"
            
            # Check if miner is running and stop it for update
            WAS_MINING=false
            MINER_COIN=""
            if [ -f "$PID_FILE" ]; then
                OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
                if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
                    WAS_MINING=true
                    echo "[$(date)] ⚠️  Stopping active miner for update..." >> "$MINER_LOG"
                    echo "[$(date)] Stopping mining for update" >> "$UPDATE_LOG"

                    # Create stop marker
                    touch /opt/frynet-config/stopped 2>/dev/null

                    # Stop all miners gracefully first
                    pkill -TERM -f "xmrig" 2>/dev/null || true
                    pkill -TERM -f "xlarig" 2>/dev/null || true
                    pkill -TERM -f "cpuminer" 2>/dev/null || true
                    pkill -TERM -f "SRBMiner-MULTI" 2>/dev/null || true
                    pkill -TERM -f "lolMiner" 2>/dev/null || true
                    pkill -TERM -f "t-rex" 2>/dev/null || true
                    pkill -TERM -f "bfgminer" 2>/dev/null || true
                    pkill -TERM -f "cgminer" 2>/dev/null || true

                    # Wait for graceful shutdown
                    sleep 3

                    # Force kill any remaining
                    pkill -9 -f "xmrig" 2>/dev/null || true
                    pkill -9 -f "xlarig" 2>/dev/null || true
                    pkill -9 -f "cpuminer" 2>/dev/null || true
                    pkill -9 -f "SRBMiner-MULTI" 2>/dev/null || true
                    pkill -9 -f "lolMiner" 2>/dev/null || true
                    pkill -9 -f "t-rex" 2>/dev/null || true
                    pkill -9 -f "bfgminer" 2>/dev/null || true
                    pkill -9 -f "cgminer" 2>/dev/null || true

                    sleep 2
                    echo "[$(date)] ✅ Mining stopped" >> "$MINER_LOG"
                fi
            fi

            # Get miner coin from config
            if [ -f "$CONFIG_FILE" ]; then
                . "$CONFIG_FILE"
                MINER_COIN="$miner"
                cp "$CONFIG_FILE" "$CONFIG_BACKUP"
                echo "[$(date)] ✅ Config backed up (mining $MINER_COIN)" >> "$MINER_LOG"
                echo "[$(date)] Config backed up (mining $MINER_COIN)" >> "$UPDATE_LOG"
            fi
            
            # Download new version
            TEMP_SCRIPT="/tmp/fryminer_update_$$.sh"
            echo "[$(date)] ⬇️  Downloading from GitHub..." >> "$MINER_LOG"
            echo "[$(date)] Downloading update..." >> "$UPDATE_LOG"
            
            DOWNLOAD_ERROR=""
            if command -v curl >/dev/null 2>&1; then
                if ! curl -sL --connect-timeout 10 --max-time 120 -o "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>&1; then
                    DOWNLOAD_ERROR="curl failed"
                fi
            else
                if ! wget -q --timeout=120 -O "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>&1; then
                    DOWNLOAD_ERROR="wget failed"
                fi
            fi
            
            if [ ! -s "$TEMP_SCRIPT" ]; then
                ERROR_MSG="Download failed - check network connection"
                echo "[$(date)] ❌ ERROR: $ERROR_MSG" >> "$MINER_LOG"
                echo "[$(date)] ERROR: $ERROR_MSG" >> "$UPDATE_LOG"
                echo "$ERROR_MSG" > "$UPDATE_ERROR_FILE"
                echo "failed" > "$UPDATE_STATUS_FILE"
                exit 1
            fi
            
            # Get new version
            NEW_VER=$(get_remote_version)
            if [ -z "$NEW_VER" ]; then
                ERROR_MSG="Cannot fetch version from GitHub"
                echo "[$(date)] ❌ ERROR: $ERROR_MSG" >> "$MINER_LOG"
                echo "$ERROR_MSG" > "$UPDATE_ERROR_FILE"
                echo "failed" > "$UPDATE_STATUS_FILE"
                rm -f "$TEMP_SCRIPT"
                exit 1
            fi
            
            echo "[$(date)] 📦 Installing version $NEW_VER..." >> "$MINER_LOG"
            echo "[$(date)] Installing version $NEW_VER..." >> "$UPDATE_LOG"
            
            # Run the update script
            chmod +x "$TEMP_SCRIPT"
            
            # Check if we can use sudo without password OR if we're already root
            CURRENT_USER=$(whoami)
            CURRENT_UID=$(id -u)
            echo "[$(date)] 🔍 Running as user: $CURRENT_USER (UID: $CURRENT_UID)" >> "$MINER_LOG"
            
            CAN_SUDO=false
            IS_ROOT=false
            
            # Check if already root
            if [ "$CURRENT_UID" = "0" ] || [ "$CURRENT_USER" = "root" ]; then
                IS_ROOT=true
                CAN_SUDO=true
                echo "[$(date)] ✅ Running as root - no sudo needed" >> "$MINER_LOG"
            elif sudo -n true 2>/dev/null; then
                CAN_SUDO=true
                echo "[$(date)] ✅ Sudo access confirmed for $CURRENT_USER" >> "$MINER_LOG"
            else
                SUDO_ERROR=$(sudo -n true 2>&1)
                echo "[$(date)] ⚠️  No passwordless sudo for $CURRENT_USER" >> "$MINER_LOG"
                echo "[$(date)] Sudo error: $SUDO_ERROR" >> "$MINER_LOG"
                
                # Check if sudoers file exists
                if [ -f /etc/sudoers.d/fryminer ]; then
                    echo "[$(date)] ℹ️  Sudoers file exists at /etc/sudoers.d/fryminer" >> "$MINER_LOG"
                else
                    echo "[$(date)] ⚠️  Sudoers file missing: /etc/sudoers.d/fryminer" >> "$MINER_LOG"
                fi
                
                # Try to detect if we can still run - check file permissions
                if [ -w /opt/frynet-config ] && [ -w /usr/local/bin ]; then
                    echo "[$(date)] ℹ️  Have write access to key directories, proceeding without sudo" >> "$MINER_LOG"
                    CAN_SUDO=true  # Pretend we have sudo since we have write access
                fi
            fi
            
            # Run installation with output streaming to logs
            echo "[$(date)] === Beginning installation ===" >> "$UPDATE_LOG"
            echo "[$(date)] 📦 Running setup script..." >> "$MINER_LOG"
            
            INSTALL_SUCCESS=false
            INSTALL_EXIT=1
            
            if [ "$IS_ROOT" = "true" ]; then
                echo "[$(date)] Running directly as root..." >> "$UPDATE_LOG"
                # Run directly without sudo since we're already root
                if UPDATE_MODE=true sh "$TEMP_SCRIPT" >> "$UPDATE_LOG" 2>&1; then
                    INSTALL_EXIT=0
                    INSTALL_SUCCESS=true
                else
                    INSTALL_EXIT=$?
                fi
            elif [ "$CAN_SUDO" = "true" ]; then
                echo "[$(date)] Running with sudo..." >> "$UPDATE_LOG"
                # Stream output to both logs
                if UPDATE_MODE=true sudo -E sh "$TEMP_SCRIPT" >> "$UPDATE_LOG" 2>&1; then
                    INSTALL_EXIT=0
                    INSTALL_SUCCESS=true
                else
                    INSTALL_EXIT=$?
                fi
            else
                echo "[$(date)] Running without sudo (may fail)..." >> "$UPDATE_LOG"
                # Stream output to both logs
                if UPDATE_MODE=true sh "$TEMP_SCRIPT" >> "$UPDATE_LOG" 2>&1; then
                    INSTALL_EXIT=0
                    INSTALL_SUCCESS=true
                else
                    INSTALL_EXIT=$?
                fi
            fi
            
            echo "[$(date)] Installation script exit code: $INSTALL_EXIT" >> "$UPDATE_LOG"
            
            if [ "$INSTALL_SUCCESS" = "true" ]; then
                echo "[$(date)] ✅ Installation completed successfully" >> "$MINER_LOG"
                echo "[$(date)] Installation completed successfully" >> "$UPDATE_LOG"
            else
                # Failure - get last errors from update log
                LAST_ERRORS=$(tail -30 "$UPDATE_LOG" 2>/dev/null | grep -E "ERROR|error|failed|Failed|CRITICAL|die" | tail -10)
                if [ -z "$LAST_ERRORS" ]; then
                    LAST_ERRORS=$(tail -20 "$UPDATE_LOG" 2>/dev/null)
                fi
                
                # Create detailed error message
                ERROR_MSG="Installation script failed (exit $INSTALL_EXIT)"
                
                echo "[$(date)] ❌ ERROR: $ERROR_MSG" >> "$MINER_LOG"
                echo "[$(date)] ERROR: $ERROR_MSG" >> "$UPDATE_LOG"
                echo "[$(date)] === Last errors from installation ===" >> "$MINER_LOG"
                echo "$LAST_ERRORS" >> "$MINER_LOG"
                
                # Store short error for UI based on error type
                if echo "$LAST_ERRORS" | grep -qi "XMRig installation failed"; then
                    echo "XMRig installation failed - check update logs for details" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "cpuminer installation failed"; then
                    echo "cpuminer installation failed - check update logs for details" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "Run as root"; then
                    echo "Requires root - SSH in and run: sudo ./setup_fryminer_web.sh" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "password is required\|terminal is required"; then
                    echo "First-time setup required - SSH in and run: sudo ./setup_fryminer_web.sh" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "permission denied"; then
                    echo "Permission denied - SSH in and run: sudo ./setup_fryminer_web.sh" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "cmake.*failed"; then
                    echo "Build tools missing - SSH in and run: sudo ./setup_fryminer_web.sh" > "$UPDATE_ERROR_FILE"
                else
                    echo "Installation failed - check update logs for details" > "$UPDATE_ERROR_FILE"
                fi
                
                echo "failed" > "$UPDATE_STATUS_FILE"
                rm -f "$TEMP_SCRIPT"
                exit 1
            fi
            
            rm -f "$TEMP_SCRIPT" 2>/dev/null
            
            # Restore config
            if [ -f "$CONFIG_BACKUP" ]; then
                cp "$CONFIG_BACKUP" "$CONFIG_FILE"
                echo "[$(date)] ✅ Config restored" >> "$MINER_LOG"
                echo "[$(date)] Config restored" >> "$UPDATE_LOG"
            fi
            
            # Update version file
            if [ -n "$NEW_VER" ]; then
                echo "$NEW_VER" > "$VERSION_FILE"
                echo "[$(date)] ✅ Version updated to: $NEW_VER" >> "$MINER_LOG"
                echo "[$(date)] Version set to: $NEW_VER" >> "$UPDATE_LOG"
            fi
            
            # Restart mining if it was running
            if [ "$WAS_MINING" = "true" ] && [ -n "$MINER_COIN" ]; then
                SCRIPT_FILE="/opt/frynet-config/output/$MINER_COIN/start.sh"
                if [ -f "$SCRIPT_FILE" ]; then
                    echo "[$(date)] 🔄 Restarting $MINER_COIN mining..." >> "$MINER_LOG"
                    echo "[$(date)] Restarting $MINER_COIN mining..." >> "$UPDATE_LOG"

                    # Use sudo if available
                    if [ "$CAN_SUDO" = "true" ]; then
                        sudo pkill -9 -f "xmrig" 2>/dev/null || true
                        sudo pkill -9 -f "xlarig" 2>/dev/null || true
                        sudo pkill -9 -f "cpuminer" 2>/dev/null || true
                        # USB ASIC miners
                        sudo pkill -9 -f "bfgminer" 2>/dev/null || true
                        sudo pkill -9 -f "cgminer" 2>/dev/null || true
                    else
                        pkill -9 -f "xmrig" 2>/dev/null || true
                        pkill -9 -f "xlarig" 2>/dev/null || true
                        pkill -9 -f "cpuminer" 2>/dev/null || true
                        # USB ASIC miners
                        pkill -9 -f "bfgminer" 2>/dev/null || true
                        pkill -9 -f "cgminer" 2>/dev/null || true
                    fi

                    sleep 2
                    nohup sh "$SCRIPT_FILE" >/dev/null 2>&1 &
                    NEW_PID=$!
                    echo "$NEW_PID" > "$PID_FILE"
                    echo "[$(date)] ✅ Mining restarted PID $NEW_PID" >> "$MINER_LOG"
                    echo "[$(date)] Mining restarted PID $NEW_PID" >> "$UPDATE_LOG"
                else
                    echo "[$(date)] ⚠️  WARNING: Start script not found: $SCRIPT_FILE" >> "$MINER_LOG"
                    echo "[$(date)] WARNING: Start script not found: $SCRIPT_FILE" >> "$UPDATE_LOG"
                    echo "[$(date)] Mining was active but cannot auto-restart" >> "$MINER_LOG"
                    echo "[$(date)] Please click 'Save' in Settings tab to regenerate start script" >> "$MINER_LOG"
                fi
            fi
            
            echo "[$(date)] ✅ UPDATE COMPLETE!" >> "$MINER_LOG"
            echo "========================================" >> "$MINER_LOG"
            echo "[$(date)] === Update completed ===" >> "$UPDATE_LOG"
            echo "complete" > "$UPDATE_STATUS_FILE"
        ) &
        
        printf '{"status":"started","message":"Update running in background"}'
        ;;
        
    *)
        printf '{"status":"error","message":"Unknown action"}'
        ;;
esac
SCRIPT
    chmod 755 "$BASE/cgi-bin/update.cgi"
    
    # Create log files
    touch "$BASE/logs/miner.log"
    chmod 666 "$BASE/logs/miner.log"
    
    # Final permissions
    chmod -R 777 "$BASE"
    
    # Create and start systemd service for web interface (survives reboot)
    create_systemd_service
    
    # Get IP
    IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    
    # Setup auto-update
    setup_auto_update
    
    log ""
    log "================================================"
    log "✅ FryMiner Installation Complete!"
    log "================================================"
    log ""
    log "Web Interface: http://$IP:$PORT"
    log ""
    log "Supported Cryptocurrencies (35+):"
    log "  • Popular: BTC, LTC, DOGE, XMR"
    log "  • CPU Mineable: Scala, Verus, Aeon, Dero, Zephyr, Salvium, Yadacoin, Arionum"
    log "  • Other: DASH, DCR, ZEN"
    log "  • Solo Lottery: BCH, LTC, DOGE, XMR"
    log "  • Unmineable: SHIB, ADA, SOL, XRP, DOT, and many more"
    log ""
    log "Features:"
    log "  • Monitor tab with live activity logs"
    log "  • Statistics tab with hashrate"
    log "  • Thermal monitoring"
    log "  • Auto-update (daily at 4 AM)"
    log ""
    log "================================================"
    log "DEV FEE NOTICE: 2%"
    log "================================================"
    log "FryMiner includes a 2% dev fee to support"
    log "continued development. The miner switches to"
    log "the dev wallet for ~1 min every 50 min cycle."
    log "Thank you for your support!"
    log "================================================"
    log ""
    log "Your miner is ready to use!"
    log "================================================"
    
    # Note: Web server is already running via systemd service (fryminer-web.service)
    # It will automatically start on boot
    
    log ""
    log "================================================"
    log "FINAL VERIFICATION"
    log "================================================"
    
    # Final sudo check
    REAL_USER="${SUDO_USER}"
    if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
        for user in fry pi ubuntu debian; do
            if id "$user" >/dev/null 2>&1; then
                REAL_USER="$user"
                break
            fi
        done
    fi
    
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        log "Testing passwordless sudo for user: $REAL_USER"
        if su - "$REAL_USER" -c "sudo -n true" 2>/dev/null; then
            log "✅ SUDO CONFIGURED: Web-based Force Update will work"
        else
            warn "⚠️  SUDO NOT WORKING: Web-based Force Update will fail"
            warn ""
            warn "This can happen if:"
            warn "  1. You need to logout and login again"
            warn "  2. Your system requires a reboot"
            warn "  3. SELinux/AppArmor is blocking sudo"
            warn ""
            warn "To fix: Logout and login, OR reboot system"
            warn "Or manually test: sudo -n true"
        fi
    fi
    
    log ""
    log "================================================"
    log "Setup Complete!"
    log "Web Interface: http://$IP:$PORT"
    log "================================================"
}

# Run installation
main

exit 0
