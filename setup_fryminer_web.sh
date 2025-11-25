#!/bin/sh
# FryMiner Setup - COMPLETE RESTORED VERSION
# Fixed stratum URL doubling, all 35+ coins restored
# Monitor and Statistics tabs included

# DO NOT USE set -e - it causes silent failures
# set -e

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."

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

# Check if miner was running
WAS_MINING=false
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        WAS_MINING=true
        log_msg "Miner is running, will restart after update"
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
        
        # Source config and find start script
        . "$CONFIG_FILE"
        SCRIPT_FILE="/opt/frynet-config/output/$miner/start.sh"
        
        if [ -f "$SCRIPT_FILE" ]; then
            # Kill any existing miners
            pkill -9 -f "xmrig" 2>/dev/null || true
            pkill -9 -f "cpuminer" 2>/dev/null || true
            sleep 2
            
            # Start miner - script handles its own logging
            nohup sh "$SCRIPT_FILE" >/dev/null 2>&1 &
            NEW_PID=$!
            echo "$NEW_PID" > "$PID_FILE"
            log_msg "Mining restarted with PID $NEW_PID"
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
        apt-get install -y wget curl tar gzip python3 build-essential git \
            automake autoconf libcurl4-openssl-dev libjansson-dev libssl-dev \
            libgmp-dev make g++ cmake ca-certificates lsof coreutils cron \
            msr-tools cpufrequtils >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget curl tar gzip python3 gcc gcc-c++ make git \
            automake autoconf libcurl-devel jansson-devel openssl-devel \
            gmp-devel cmake ca-certificates lsof coreutils cronie \
            msr-tools cpufrequtils >/dev/null 2>&1 || true
    fi
    log "Dependencies installed"
}

# Optimize system for mining (huge pages, MSR, CPU governor)
optimize_for_mining() {
    log "Applying mining optimizations..."
    
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
            if command -v curl >/dev/null 2>&1; then
                curl -sL -o xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-x64.tar.gz"
            elif command -v wget >/dev/null 2>&1; then
                wget -q -O xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-x64.tar.gz"
            else
                warn "Neither curl nor wget available"
                return 1
            fi
            
            if [ -f xmrig.tar.gz ]; then
                log "Extracting..."
                tar -xzf xmrig.tar.gz 2>/dev/null
                find . -name "xmrig" -type f -executable -exec cp {} /usr/local/bin/xmrig \; 2>/dev/null
                chmod +x /usr/local/bin/xmrig 2>/dev/null
                rm -rf xmrig* 2>/dev/null
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
            log "=== Building cpuminer-opt for ARM64 ==="
            log "Cloning cpuminer-opt..."
            git clone --depth 1 --progress https://github.com/JayDDee/cpuminer-opt.git 2>&1 || {
                warn "Failed to clone"
                return 1
            }
            cd cpuminer-opt || return 1
            
            log "Running autogen..."
            ./autogen.sh >/dev/null 2>&1
            
            log "Configuring..."
            CFLAGS="-O2" ./configure --disable-assembly >/dev/null 2>&1
            
            log "Compiling (10-15 minutes on ARM)..."
            if make -j"$(nproc)" >/dev/null 2>&1; then
                cp cpuminer /usr/local/bin/cpuminer
                chmod +x /usr/local/bin/cpuminer
                ln -sf /usr/local/bin/cpuminer /usr/local/bin/minerd
                cd "$MINERS_DIR"
                rm -rf cpuminer-opt
                log "cpuminer-opt installed for ARM64"
                /usr/local/bin/cpuminer --version 2>&1 | head -1 || true
                return 0
            fi
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

# Main installation
main() {
    log "================================================"
    log "FryMiner Complete Setup Starting..."
    log "================================================"
    
    detect_architecture
    set_hostname
    install_dependencies
    
    # Install miners
    install_xmrig
    install_cpuminer
    
    # Apply mining optimizations (huge pages, MSR, CPU governor)
    optimize_for_mining
    
    # Stop any existing FryMiner processes gracefully
    log "Stopping existing FryMiner processes..."
    
    # Stop web server
    if pgrep -f "python3 -m http.server $PORT" >/dev/null 2>&1; then
        pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
        sleep 1
    fi
    
    # Stop miners
    pkill -f xmrig 2>/dev/null || true
    pkill -f cpuminer 2>/dev/null || true
    pkill -f minerd 2>/dev/null || true
    
    # Stop old daemons
    pkill -f fryminer_pidmon 2>/dev/null || true
    pkill -f fryminer_thermal 2>/dev/null || true
    
    # Wait for processes to stop
    sleep 2
    
    # Setup directory structure
    log "Setting up FryMiner directory..."
    rm -rf "$BASE"
    mkdir -p "$BASE"
    mkdir -p "$BASE/cgi-bin"
    mkdir -p "$BASE/output"
    mkdir -p "$BASE/logs"
    
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
                            <option value="yadacoin">Yadacoin (YDA) - RandomX</option>
                            <option value="arionum">Arionum (ARO) - Argon2</option>
                        </optgroup>
                        <optgroup label="Other Minable">
                            <option value="dash">Dash (DASH) - X11</option>
                            <option value="dcr">Decred (DCR) - Blake</option>
                            <option value="kda">Kadena (KDA) - Blake2s</option>
                        </optgroup>
                        <optgroup label="Solo Lottery Mining">
                            <option value="btc-lotto">Bitcoin Lottery (BTC)</option>
                            <option value="bch-lotto">Bitcoin Cash Lottery (BCH)</option>
                            <option value="ltc-lotto">Litecoin Lottery (LTC)</option>
                            <option value="doge-lotto">Dogecoin Lottery (DOGE)</option>
                            <option value="xmr-lotto">Monero Lottery (XMR)</option>
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
                
                <div class="form-group">
                    <label>Worker Name:</label>
                    <input type="text" id="worker" name="worker" value="worker1">
                </div>
                
                <div class="form-group">
                    <label>CPU Threads:</label>
                    <input type="number" id="threads" name="threads" min="1" max="128" value="2">
                </div>
                
                <div class="form-group" id="poolGroup">
                    <label>Mining Pool:</label>
                    <input type="text" id="pool" name="pool" placeholder="pool.example.com:3333">
                    <small style="color: #888;">Enter without stratum+tcp:// prefix (will be added automatically)</small>
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
                <h3>Activity Log</h3>
                <div class="log-viewer" id="logViewer">Loading...</div>
            </div>
            
            <button onclick="refreshLogs()">🔄 Refresh Logs</button>
            <button onclick="clearLogs()">🗑️ Clear Logs</button>
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
                <p style="font-size: 0.9em; color: #888;">Dev fee: 1% for XMRig coins, Unmineable referral for Unmineable coins</p>
            </div>
        </div>
    </div>
</div>

<script>
// Default pools for each coin
const defaultPools = {
    'btc': 'pool.btc.com:3333',
    'ltc': 'litecoin.nerdpool.xyz:5320',
    'doge': 'prohashing.com:3332',
    'xmr': 'pool.supportxmr.com:3333',
    'scala': 'scala.herominers.com:10131',
    'verus': 'pool.verus.io:9999',
    'aeon': 'aeon.herominers.com:10650',
    'dero': 'dero-node-sk.mysrv.cloud:10300',
    'yadacoin': 'pool.yadacoin.io:3333',
    'arionum': 'aropool.com:80',
    'dash': 'dash.suprnova.cc:9989',
    'dcr': 'dcr.suprnova.cc:3252',
    'kda': 'pool.woolypooly.com:3112',
    'bch-lotto': 'solo.ckpool.org:3333',
    'btc-lotto': 'solo.ckpool.org:3333',
    'ltc-lotto': 'litesolo.org:3333',
    'doge-lotto': 'litesolo.org:3334',
    'xmr-lotto': 'xmr.solopool.org:3333',
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

// Fixed pools (cannot be changed)
const fixedPools = ['btc-lotto', 'bch-lotto', 'ltc-lotto', 'doge-lotto', 'xmr-lotto', 'shib', 'ada', 'sol', 'zec', 'etc', 'rvn', 'trx', 'vet', 'xrp', 'dot', 'matic', 'atom', 'link', 'xlm', 'algo', 'avax', 'near', 'ftm', 'one'];

// Coin info messages
const coinInfo = {
    'tera': '⚠️ TERA requires running a full node. Visit teraexplorer.org for setup instructions.',
    'minima': '⚠️ Minima is mobile-only. Download the Minima app from your app store.',
    'bch-lotto': '🎰 Solo lottery mining - very low odds but winner takes full block reward!',
    'ltc-lotto': '🎰 Solo lottery mining - very low odds but winner takes full block reward!',
    'doge-lotto': '🎰 Solo lottery mining - merged with LTC, very low odds!',
    'xmr-lotto': '🎰 Solo lottery mining - very low odds but winner takes full block reward!'
};

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
    
    // Show/hide pool field
    if (coin === 'tera' || coin === 'minima') {
        poolGroup.style.display = 'none';
    } else {
        poolGroup.style.display = 'block';
        
        // Set pool value intelligently
        if (defaultPools[coin] && !isLoadingConfig) {
            // Fixed pools (Unmineable, lottery) ALWAYS update
            if (fixedPools.includes(coin)) {
                poolInput.value = defaultPools[coin];
            }
            // Non-fixed pools only update if field is empty (preserve custom values)
            else if (!poolInput.value) {
                poolInput.value = defaultPools[coin];
            }
        }
        
        poolInput.disabled = fixedPools.includes(coin);
    }
    
    // Show coin info if available
    if (coinInfo[coin]) {
        infoBox.innerHTML = coinInfo[coin];
        infoBox.style.display = 'block';
    } else {
        infoBox.style.display = 'none';
    }
});

document.getElementById('configForm').addEventListener('submit', function(e) {
    e.preventDefault();
    
    // Validate threads
    const threadsInput = document.getElementById('threads');
    const maxThreads = parseInt(threadsInput.max) || 32;
    const threads = parseInt(threadsInput.value) || 1;
    if (threads > maxThreads) {
        document.getElementById('message').innerHTML = '<div class="error">❌ Cannot use more than ' + maxThreads + ' threads on this system</div>';
        return;
    }
    if (threads < 1) {
        threadsInput.value = 1;
    }
    
    const formData = new FormData(this);
    const params = new URLSearchParams();
    for (const [key, value] of formData) params.append(key, value);
    
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
    fetch('/logs/miner.log')
        .then(r => r.text())
        .then(logs => {
            const viewer = document.getElementById('logViewer');
            viewer.textContent = logs.split('\n').slice(-100).join('\n');
            viewer.scrollTop = viewer.scrollHeight;
        })
        .catch(() => {
            document.getElementById('logViewer').textContent = 'No logs available';
        });
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
                document.getElementById('updateResult').innerHTML = '<div class="error">❌ Update failed. Check logs.</div>';
            } else if (data.status === 'running') {
                // Still running, keep polling
                document.getElementById('updateResult').innerHTML = '<div class="info-box">⏳ Update in progress... Please wait.</div>';
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
setInterval(checkStatus, 5000);
setInterval(refreshLogs, 10000);

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
WORKER="worker1"
THREADS="2"
POOL=""

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
        worker) WORKER="$value" ;;
        threads) THREADS="$value" ;;
        pool) POOL="$value" ;;
    esac
done
IFS=' '

if [ -z "$MINER" ] || [ -z "$WALLET" ]; then
    echo "<div class='error'>❌ Missing required fields</div>"
    exit 0
fi

# STRIP any existing stratum protocol prefix from pool URL
POOL=$(echo "$POOL" | sed 's|^stratum+tcp://||' | sed 's|^stratum+ssl://||' | sed 's|^stratum://||')

# Set default pools if not provided
case "$MINER" in
    btc) [ -z "$POOL" ] && POOL="pool.btc.com:3333" ;;
    ltc) [ -z "$POOL" ] && POOL="litecoin.nerdpool.xyz:5320" ;;
    doge) [ -z "$POOL" ] && POOL="prohashing.com:3332" ;;
    xmr) [ -z "$POOL" ] && POOL="pool.supportxmr.com:3333" ;;
    scala) [ -z "$POOL" ] && POOL="scala.herominers.com:10131" ;;
    verus) [ -z "$POOL" ] && POOL="pool.verus.io:9999" ;;
    aeon) [ -z "$POOL" ] && POOL="aeon.herominers.com:10650" ;;
    dero) [ -z "$POOL" ] && POOL="dero-node-sk.mysrv.cloud:10300" ;;
    yadacoin) [ -z "$POOL" ] && POOL="pool.yadacoin.io:3333" ;;
    arionum) [ -z "$POOL" ] && POOL="aropool.com:80" ;;
    dash) [ -z "$POOL" ] && POOL="dash.suprnova.cc:9989" ;;
    dcr) [ -z "$POOL" ] && POOL="dcr.suprnova.cc:3252" ;;
    zen) [ -z "$POOL" ] && POOL="zen.suprnova.cc:3618" ;;
    kda) [ -z "$POOL" ] && POOL="pool.woolypooly.com:3112" ;;
    bch-lotto) POOL="solo.ckpool.org:3333" ;;
    btc-lotto) POOL="solo.ckpool.org:3333" ;;
    ltc-lotto) POOL="litesolo.org:3333" ;;
    doge-lotto) POOL="litesolo.org:3334" ;;
    xmr-lotto) POOL="xmr.solopool.org:3333" ;;
    *) [ -z "$POOL" ] && POOL="rx.unmineable.com:3333" ;;
esac

mkdir -p /opt/frynet-config/output
chmod 777 /opt/frynet-config/output

cat > /opt/frynet-config/config.txt <<EOF
miner=$MINER
wallet=$WALLET
worker=$WORKER
threads=$THREADS
pool=$POOL
EOF
chmod 666 /opt/frynet-config/config.txt

SCRIPT_DIR="/opt/frynet-config/output/$MINER"
mkdir -p "$SCRIPT_DIR"
SCRIPT_FILE="$SCRIPT_DIR/start.sh"

# Initialize flags
IS_UNMINEABLE=false

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
        ;;
    aeon)
        ALGO="rx/0"
        USE_CPUMINER=false
        ;;
    dero)
        ALGO="astrobwt"
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
cat > "$SCRIPT_FILE" <<'STARTSCRIPT'
#!/bin/sh
LOG="/opt/frynet-config/logs/miner.log"

# Log startup info
echo "[$(date)] ========================================" >> "$LOG"
echo "[$(date)] Starting mining session" >> "$LOG"
STARTSCRIPT

cat >> "$SCRIPT_FILE" <<EOF
echo "[\$(date)] Coin: $MINER" >> "\$LOG"
echo "[\$(date)] Pool: $POOL" >> "\$LOG"
echo "[\$(date)] Algorithm: $ALGO" >> "\$LOG"
echo "[\$(date)] Wallet: $WALLET" >> "\$LOG"
echo "[\$(date)] Worker: $WORKER" >> "\$LOG"
echo "[\$(date)] Threads: $THREADS" >> "\$LOG"
echo "[\$(date)] ========================================" >> "\$LOG"

# Remove clean stop marker
rm -f /opt/frynet-config/stopped 2>/dev/null

# Run optimization script if available (huge pages, MSR, etc)
if [ -x /opt/frynet-config/optimize.sh ]; then
    echo "[\$(date)] Running mining optimizations..." >> "\$LOG"
    /opt/frynet-config/optimize.sh >> "\$LOG" 2>&1
fi

# Start heartbeat logger in background
(
    sleep 30
    while true; do
        if pgrep -f "cpuminer\|xmrig" >/dev/null 2>&1; then
            echo "[\$(date)] ♥ Mining active" >> "\$LOG"
        else
            break
        fi
        sleep 60
    done
) &

EOF

# Add miner command with proper output handling
if [ "$USE_CPUMINER" = "true" ]; then
    # cpuminer - use stdbuf for unbuffered output
    cat >> "$SCRIPT_FILE" <<EOF
# Run cpuminer with unbuffered output
exec /usr/local/bin/cpuminer --algo=$ALGO -o stratum+tcp://$POOL -u $WALLET.$WORKER -p x --threads=$THREADS 2>&1 | tee -a "\$LOG"
EOF
else
    # xmrig - optimized flags for better hashrate
    # --cpu-priority 5: Highest priority
    # --randomx-no-numa: Better for single socket systems
    # Note: 1GB pages removed - requires boot-time kernel config
    XMRIG_OPTS="--cpu-priority 5 --randomx-no-numa"
    
    if [ "$IS_UNMINEABLE" = "true" ]; then
        # For Unmineable, add referral code to worker name
        cat >> "$SCRIPT_FILE" <<EOF
# Run xmrig for Unmineable with referral code and optimizations
exec /usr/local/bin/xmrig -o $POOL -u $WALLET.$WORKER#$UNMINEABLE_REFERRAL -p x --threads=$THREADS -a $ALGO --no-color --donate-level=1 $XMRIG_OPTS 2>&1 | tee -a "\$LOG"
EOF
    else
        cat >> "$SCRIPT_FILE" <<EOF
# Run xmrig with 1% dev donation and optimizations
exec /usr/local/bin/xmrig -o $POOL -u $WALLET.$WORKER -p x --threads=$THREADS -a $ALGO --no-color --donate-level=1 $XMRIG_OPTS 2>&1 | tee -a "\$LOG"
EOF
    fi
fi

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
    printf '{"miner":"%s","wallet":"%s","worker":"%s","threads":"%s","pool":"%s"}' \
        "$miner" "$wallet" "$worker" "$threads" "$pool"
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

# Method 2: Check for miner processes directly using ps
if [ "$RUNNING" = "false" ]; then
    if ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[m]inerd" | grep -v grep >/dev/null 2>&1; then
        RUNNING="true"
        # Update PID file with found process
        ACTUAL_PID=$(ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig" | grep -v grep | awk '{print $2}' | head -1)
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
pkill -9 -f "cpuminer" 2>/dev/null || true
pkill -9 -f "minerd" 2>/dev/null || true
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
    
    # Method 2: Check for any miner process
    if [ "$RUNNING" = "false" ]; then
        if ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[m]inerd" | grep -v grep >/dev/null 2>&1; then
            # Found a miner, update PID file with actual PID
            ACTUAL_PID=$(ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig" | grep -v grep | awk '{print $2}' | head -1)
            if [ -n "$ACTUAL_PID" ]; then
                echo "$ACTUAL_PID" > "$PID_FILE"
                RUNNING=true
            fi
        fi
    fi
    
    # Method 3: Check log for activity
    if [ "$RUNNING" = "false" ]; then
        if grep -qE "Stratum|threads started|algorithm|accepted" "$LOG_FILE" 2>/dev/null; then
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

# Kill by PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ]; then
        kill "$PID" 2>/dev/null || true
        sleep 1
        kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Also kill any stray miners and heartbeat processes
pkill -f xmrig 2>/dev/null || true
pkill -f cpuminer 2>/dev/null || true
pkill -f minerd 2>/dev/null || true

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
LOG_FILE="/opt/frynet-config/logs/update.log"
PID_FILE="/opt/frynet-config/miner.pid"
UPDATE_STATUS_FILE="/opt/frynet-config/update_status.txt"

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
        # Check update status
        if [ -f "$UPDATE_STATUS_FILE" ]; then
            STATUS=$(cat "$UPDATE_STATUS_FILE" 2>/dev/null)
            printf '{"status":"%s"}' "$STATUS"
        else
            printf '{"status":"idle"}'
        fi
        ;;
        
    update)
        # Run update in background
        echo "running" > "$UPDATE_STATUS_FILE"
        
        # Background update process
        (
            echo "[$(date)] === Force update started ===" >> "$LOG_FILE"
            
            # Check if miner is running
            WAS_MINING=false
            MINER_COIN=""
            if [ -f "$PID_FILE" ]; then
                OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
                if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
                    WAS_MINING=true
                fi
            fi
            
            # Get miner coin from config
            if [ -f "$CONFIG_FILE" ]; then
                . "$CONFIG_FILE"
                MINER_COIN="$miner"
                cp "$CONFIG_FILE" "$CONFIG_BACKUP"
                echo "[$(date)] Config backed up (mining $MINER_COIN)" >> "$LOG_FILE"
            fi
            
            # Download new version
            TEMP_SCRIPT="/tmp/fryminer_update_$$.sh"
            echo "[$(date)] Downloading update..." >> "$LOG_FILE"
            
            if command -v curl >/dev/null 2>&1; then
                curl -sL --connect-timeout 10 --max-time 120 -o "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null
            else
                wget -q --timeout=120 -O "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null
            fi
            
            if [ ! -s "$TEMP_SCRIPT" ]; then
                echo "[$(date)] ERROR: Download failed" >> "$LOG_FILE"
                echo "failed" > "$UPDATE_STATUS_FILE"
                exit 1
            fi
            
            # Get new version
            NEW_VER=$(get_remote_version)
            echo "[$(date)] Installing version $NEW_VER..." >> "$LOG_FILE"
            
            # Run the update script
            chmod +x "$TEMP_SCRIPT"
            sh "$TEMP_SCRIPT" >> "$LOG_FILE" 2>&1
            UPDATE_RESULT=$?
            
            rm -f "$TEMP_SCRIPT" 2>/dev/null
            
            if [ $UPDATE_RESULT -eq 0 ]; then
                # Restore config
                if [ -f "$CONFIG_BACKUP" ]; then
                    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
                    echo "[$(date)] Config restored" >> "$LOG_FILE"
                fi
                
                # Update version file
                if [ -n "$NEW_VER" ]; then
                    echo "$NEW_VER" > "$VERSION_FILE"
                    echo "[$(date)] Version set to: $NEW_VER" >> "$LOG_FILE"
                fi
                
                # Restart mining if it was running
                if [ "$WAS_MINING" = "true" ] && [ -n "$MINER_COIN" ]; then
                    SCRIPT_FILE="/opt/frynet-config/output/$MINER_COIN/start.sh"
                    if [ -f "$SCRIPT_FILE" ]; then
                        echo "[$(date)] Restarting $MINER_COIN mining..." >> "$LOG_FILE"
                        pkill -9 -f "xmrig" 2>/dev/null || true
                        pkill -9 -f "cpuminer" 2>/dev/null || true
                        sleep 2
                        nohup sh "$SCRIPT_FILE" >/dev/null 2>&1 &
                        NEW_PID=$!
                        echo "$NEW_PID" > "$PID_FILE"
                        echo "[$(date)] Mining restarted PID $NEW_PID" >> "$LOG_FILE"
                    fi
                fi
                
                echo "[$(date)] === Update completed ===" >> "$LOG_FILE"
                echo "complete" > "$UPDATE_STATUS_FILE"
            else
                echo "[$(date)] ERROR: Update failed" >> "$LOG_FILE"
                echo "failed" > "$UPDATE_STATUS_FILE"
            fi
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
    
    # Start web server
    log "Starting web server..."
    cd "$BASE"
    nohup python3 -m http.server $PORT --cgi > /dev/null 2>&1 &
    SERVER_PID=$!
    
    sleep 2
    
    # Verify server started
    if kill -0 $SERVER_PID 2>/dev/null; then
        log "Web server started successfully (PID: $SERVER_PID)"
    else
        warn "Web server may not have started properly"
    fi
    
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
    log "  • CPU Mineable: Scala, Verus, Aeon, Dero, Yadacoin, Arionum"
    log "  • Other: DASH, DCR, ZEN"
    log "  • Solo Lottery: BCH, LTC, DOGE, XMR"
    log "  • Unmineable: SHIB, ADA, SOL, XRP, DOT, and many more"
    log ""
    log "Features:"
    log "  • Monitor tab with live activity logs"
    log "  • Statistics tab with hashrate"
    log "  • Thermal monitoring"
    log "  • Auto-update (daily at 4 AM)"
    log "  • 1% dev fee (XMRig coins only)"
    log ""
    log "Your miner is ready to use!"
    log "================================================"
}

# Run installation
main

exit 0
