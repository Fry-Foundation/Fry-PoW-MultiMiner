#!/bin/bash
# FryMiner Setup - macOS (Apple Silicon & Intel)
# Multi-cryptocurrency CPU miner with web interface
# Synced with setup_fryminer_web.sh (source of truth)
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

# Check for macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is for macOS only. Please use setup_fryminer_web.sh for Linux."
    exit 1
fi

# =============================================================================
# DEV FEE CONFIGURATION (2%)
# =============================================================================
DEV_FEE_PERCENT=2
DEV_FEE_CYCLE_MINUTES=50
DEV_FEE_USER_MINUTES=49
DEV_FEE_DEV_MINUTES=1

# Dev wallet addresses
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
DEV_WALLET_UNMINEABLE="$DEV_WALLET_SCALA"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

PORT=8080
BASE="$HOME/.fryminer"
MINERS_DIR="$BASE/miners"

# Detect architecture - Apple Silicon or Intel
detect_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        arm64)
            ARCH_TYPE="arm64"
            log "Detected architecture: Apple Silicon (arm64)"
            ;;
        x86_64)
            ARCH_TYPE="x86_64"
            log "Detected architecture: Intel (x86_64)"
            ;;
        *)
            ARCH_TYPE="unknown"
            warn "Unknown architecture: $ARCH"
            ;;
    esac
}

# Check for Homebrew
check_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ "$ARCH_TYPE" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    log "Homebrew is available"
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies via Homebrew..."
    brew install wget curl python3 cmake git automake autoconf libuv openssl hwloc >/dev/null 2>&1 || true
    brew install jansson gmp pkg-config unzip >/dev/null 2>&1 || true
    log "Dependencies installed"
}

# Setup directories
setup_directories() {
    log "Creating directory structure..."
    mkdir -p "$BASE"
    mkdir -p "$MINERS_DIR"
    mkdir -p "$BASE/logs"
    mkdir -p "$BASE/output"
    mkdir -p "$BASE/cgi-bin"
    mkdir -p "$BASE/scripts"
    log "Directories created at $BASE"
}

# Install XMRig for macOS
install_xmrig() {
    log "=== Installing XMRig for macOS ==="

    XMRIG_PATH="$MINERS_DIR/xmrig"

    if [[ -f "$XMRIG_PATH" ]]; then
        if "$XMRIG_PATH" --version 2>&1 | grep -q "XMRig"; then
            log "XMRig already installed"
            return 0
        fi
    fi

    log "Building XMRig from source..."
    cd /tmp
    rm -rf xmrig-build
    git clone --depth 1 https://github.com/xmrig/xmrig.git xmrig-build 2>/dev/null
    cd xmrig-build
    mkdir build && cd build
    cmake .. -DWITH_HWLOC=ON -DWITH_TLS=ON 2>/dev/null
    make -j$(sysctl -n hw.ncpu) 2>/dev/null

    if [[ -f "xmrig" ]]; then
        cp xmrig "$XMRIG_PATH"
        chmod +x "$XMRIG_PATH"
        log "XMRig installed successfully"
    else
        warn "XMRig build failed - will try prebuilt binary"
        if [[ "$ARCH_TYPE" == "x86_64" ]]; then
            cd /tmp
            curl -sL "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-macos-x64.tar.gz" -o xmrig.tar.gz
            tar xzf xmrig.tar.gz
            find . -name "xmrig" -type f -exec cp {} "$XMRIG_PATH" \;
            chmod +x "$XMRIG_PATH"
        fi
    fi

    cd /tmp
    rm -rf xmrig-build xmrig.tar.gz xmrig-*
}

# Install cpuminer-multi for macOS
install_cpuminer() {
    log "=== Installing cpuminer-multi for macOS ==="

    CPUMINER_PATH="$MINERS_DIR/cpuminer"

    if [[ -f "$CPUMINER_PATH" ]]; then
        if "$CPUMINER_PATH" --version 2>&1 | grep -q "cpuminer"; then
            log "cpuminer already installed"
            return 0
        fi
    fi

    log "Building cpuminer-multi from source..."
    cd /tmp
    rm -rf cpuminer-build
    git clone https://github.com/tpruvot/cpuminer-multi.git cpuminer-build 2>/dev/null
    cd cpuminer-build
    ./autogen.sh 2>/dev/null
    ./configure --with-curl --with-crypto 2>/dev/null
    make -j$(sysctl -n hw.ncpu) 2>/dev/null

    if [[ -f "cpuminer" ]]; then
        cp cpuminer "$CPUMINER_PATH"
        chmod +x "$CPUMINER_PATH"
        log "cpuminer installed successfully"
    else
        warn "cpuminer build failed"
    fi

    cd /tmp
    rm -rf cpuminer-build
}

# Install XLArig for Scala mining on macOS
install_xlarig() {
    log "=== Installing XLArig (Scala miner) for macOS ==="

    XLARIG_PATH="$MINERS_DIR/xlarig"

    if [[ -f "$XLARIG_PATH" ]]; then
        if "$XLARIG_PATH" --version 2>&1 | grep -qi "xlarig\|xla"; then
            log "XLArig already installed"
            return 0
        fi
    fi

    log "Building XLArig from source..."
    cd /tmp
    rm -rf xlarig-build
    git clone https://github.com/scala-network/XLArig.git xlarig-build 2>/dev/null
    cd xlarig-build
    mkdir build && cd build
    cmake .. -DWITH_HWLOC=ON -DWITH_TLS=ON 2>/dev/null
    make -j$(sysctl -n hw.ncpu) 2>/dev/null

    if [[ -f "xlarig" ]]; then
        cp xlarig "$XLARIG_PATH"
        chmod +x "$XLARIG_PATH"
        log "XLArig installed successfully"
    else
        warn "XLArig build failed - Scala mining will use XMRig fallback"
    fi

    cd /tmp
    rm -rf xlarig-build
}

# Install ccminer for Verus mining on macOS
install_verus_miner() {
    log "=== Installing ccminer-verus (Verus miner) for macOS ==="

    CCMINER_PATH="$MINERS_DIR/ccminer-verus"

    if [[ -f "$CCMINER_PATH" ]]; then
        if "$CCMINER_PATH" --version 2>&1 | grep -qi "ccminer"; then
            log "ccminer-verus already installed"
            return 0
        fi
    fi

    log "Building ccminer-verus from source..."
    cd /tmp
    rm -rf ccminer-build
    git clone https://github.com/monkins1010/ccminer.git ccminer-build 2>/dev/null
    cd ccminer-build
    chmod +x autogen.sh build.sh 2>/dev/null
    ./autogen.sh 2>/dev/null
    ./configure 2>/dev/null
    make -j$(sysctl -n hw.ncpu) 2>/dev/null

    if [[ -f "ccminer" ]]; then
        cp ccminer "$CCMINER_PATH"
        chmod +x "$CCMINER_PATH"
        log "ccminer-verus installed successfully"
    else
        warn "ccminer-verus build failed - Verus mining may not be available"
    fi

    cd /tmp
    rm -rf ccminer-build
}

# Install ORE miner (ore-cli) - Solana PoW token
install_ore_cli() {
    log "=== Installing ORE miner (ore-cli) ==="

    if command -v ore >/dev/null 2>&1; then
        log "ore-cli already installed: $(ore --version 2>/dev/null || echo 'unknown version')"
        return 0
    fi

    # Install Rust if not present
    if ! command -v cargo >/dev/null 2>&1; then
        log "Installing Rust toolchain..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>&1
        source "$HOME/.cargo/env" 2>/dev/null || true
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    if ! command -v cargo >/dev/null 2>&1; then
        warn "Rust/Cargo installation failed - ORE mining not available"
        return 1
    fi

    # Install Solana CLI
    if ! command -v solana >/dev/null 2>&1; then
        log "Installing Solana CLI..."
        sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)" 2>&1 || true
        export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
    fi

    # Install ore-cli
    log "Building ore-cli (this may take several minutes)..."
    cargo install ore-cli 2>&1 || {
        warn "ore-cli cargo install failed, trying from GitHub..."
        cargo install --git https://github.com/regolith-labs/ore-cli.git 2>&1 || {
            warn "ore-cli installation failed"
            return 1
        }
    }

    # Symlink to miners dir
    CARGO_BIN="$HOME/.cargo/bin/ore"
    if [[ -x "$CARGO_BIN" ]]; then
        ln -sf "$CARGO_BIN" "$MINERS_DIR/ore" 2>/dev/null
        log "ore-cli installed successfully"
        return 0
    fi

    warn "ore-cli binary not found after installation"
    return 1
}

# Install Oranges (ORA) miner - Algorand-based
install_ora_miner() {
    log "=== Installing Oranges (ORA) miner ==="

    mkdir -p "$BASE/scripts"

    # Install Algorand goal CLI if possible
    if ! command -v goal >/dev/null 2>&1; then
        log "Attempting to install Algorand node tools..."
        brew install algorand 2>/dev/null || true
    fi

    # Create ORA mining script
    cat > "$BASE/scripts/ora_miner.sh" << 'ORAMINER'
#!/bin/bash
# ORA (Oranges) Miner - Submits "juice" application call transactions to the ORA smart contract
# on the Algorand blockchain. Every 5 blocks, the miner with highest transaction fees wins 1.05 ORA.

WALLET="$1"
NODE_URL="${2:-http://localhost:4001}"
API_TOKEN="${3:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
THREADS="${4:-1}"
LOG="${5:-$HOME/.fryminer/logs/miner.log}"

ORA_APP_ID=1284326447

ROUND=0

echo "[$(date)] Starting ORA (Oranges) miner" >> "$LOG"
echo "[$(date)] Wallet: $WALLET | Node: $NODE_URL" >> "$LOG"

while true; do
    if [[ -f "$HOME/.fryminer/stopped" ]]; then
        echo "[$(date)] ORA miner stopped by user" >> "$LOG"
        exit 0
    fi

    if command -v goal >/dev/null 2>&1; then
        CURRENT_ROUND=$(goal node status 2>/dev/null | grep "Last committed block" | awk '{print $NF}')
        if [[ -n "$CURRENT_ROUND" ]]; then
            ROUND=$((ROUND + 1))
            goal app call --app-id $ORA_APP_ID --from "$WALLET" \
                --app-arg "str:juice" \
                --fee 2000 \
                --out /tmp/ora_tx_$$.tx 2>/dev/null
            
            if [[ -f "/tmp/ora_tx_$$.tx" ]]; then
                goal clerk rawsend --filename /tmp/ora_tx_$$.tx 2>/dev/null
                rm -f /tmp/ora_tx_$$.tx
            fi
        fi

        echo "[$(date)] ORA miner: $ROUND rounds submitted at block $CURRENT_ROUND" >> "$LOG"
    fi

    sleep 4.5
done
ORAMINER
    chmod +x "$BASE/scripts/ora_miner.sh"

    if command -v goal >/dev/null 2>&1; then
        log "ORA miner installed successfully (with goal CLI)"
    else
        log "ORA miner installed (API-only mode - no local goal CLI)"
    fi
    return 0
}

# Install SRBMiner-Multi for GPU mining on macOS
install_srbminer() {
    log "=== Installing SRBMiner-Multi (GPU miner) ==="

    SRBMINER_PATH="$MINERS_DIR/SRBMiner-MULTI"
    if [[ -f "$SRBMINER_PATH" ]]; then
        log "SRBMiner-Multi already installed"
        return 0
    fi

    # SRBMiner-Multi has macOS builds
    SRBMINER_VER="2.7.9"
    cd /tmp
    rm -rf srbminer* SRBMiner* 2>/dev/null

    if [[ "$ARCH_TYPE" == "x86_64" ]]; then
        curl -sL -o srbminer.tar.gz "https://github.com/doktor83/SRBMiner-Multi/releases/download/${SRBMINER_VER}/SRBMiner-Multi-${SRBMINER_VER}-macOS.tar.gz" 2>/dev/null
    else
        warn "SRBMiner-Multi may not have ARM64 macOS builds"
        return 1
    fi

    if [[ -f srbminer.tar.gz ]]; then
        tar xzf srbminer.tar.gz 2>/dev/null
        SRBIN=$(find . -name "SRBMiner-MULTI" -type f 2>/dev/null | head -1)
        if [[ -n "$SRBIN" ]]; then
            cp "$SRBIN" "$SRBMINER_PATH"
            chmod +x "$SRBMINER_PATH"
            log "SRBMiner-Multi installed successfully"
        else
            warn "SRBMiner-Multi binary not found in archive"
        fi
    fi

    rm -rf srbminer* SRBMiner* 2>/dev/null
}

# Install BFGMiner for USB ASIC mining on macOS
install_bfgminer() {
    log "=== Installing BFGMiner (USB ASIC miner) ==="

    if command -v bfgminer >/dev/null 2>&1; then
        log "BFGMiner already installed"
        return 0
    fi

    log "Installing BFGMiner via Homebrew..."
    brew install bfgminer 2>/dev/null || {
        log "Building BFGMiner from source..."
        cd /tmp
        rm -rf bfgminer-build 2>/dev/null
        git clone https://github.com/luke-jr/bfgminer.git bfgminer-build 2>/dev/null
        cd bfgminer-build
        ./autogen.sh 2>/dev/null
        ./configure --enable-scrypt 2>/dev/null
        make -j$(sysctl -n hw.ncpu) 2>/dev/null
        if [[ -f "bfgminer" ]]; then
            cp bfgminer "$MINERS_DIR/bfgminer"
            chmod +x "$MINERS_DIR/bfgminer"
            log "BFGMiner installed successfully"
        else
            warn "BFGMiner build failed"
        fi
        cd /tmp
        rm -rf bfgminer-build
    }
}

# Setup auto-update using launchd (macOS scheduler)
setup_auto_update() {
    log "Setting up automatic daily updates..."

    UPDATE_SCRIPT="$BASE/auto_update.sh"
    PLIST_FILE="$HOME/Library/LaunchAgents/org.frynetworks.fryminer.update.plist"

    cat > "$UPDATE_SCRIPT" << 'AUTOUPDATE'
#!/bin/bash
# FryMiner Automatic Update Script for macOS

REPO_API="https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main"
DOWNLOAD_URL="https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_macos.sh"
VERSION_FILE="$HOME/.fryminer/version.txt"
CONFIG_FILE="$HOME/.fryminer/config.txt"
LOG_FILE="$HOME/.fryminer/logs/update.log"
PID_FILE="$HOME/.fryminer/miner.pid"

log_msg() {
    echo "[$(date)] $1" >> "$LOG_FILE"
}

get_remote_version() {
    curl -s "$REPO_API" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7
}

get_local_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE" 2>/dev/null
    else
        echo "none"
    fi
}

log_msg "=== Auto-update check started ==="

# Clean up orphaned temp files
find /tmp -maxdepth 1 -name "fryminer_update_*.sh" -mmin +60 -delete 2>/dev/null || true

REMOTE_VER=$(get_remote_version)
LOCAL_VER=$(get_local_version)

log_msg "Local version: $LOCAL_VER"
log_msg "Remote version: $REMOTE_VER"

if [[ -z "$REMOTE_VER" ]]; then
    log_msg "ERROR: Could not fetch remote version"
    exit 1
fi

if [[ "$REMOTE_VER" == "$LOCAL_VER" ]]; then
    log_msg "Already up to date"
    exit 0
fi

log_msg "Update available! Starting update process..."

WAS_MINING=false
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        WAS_MINING=true
        log_msg "Stopping mining for update..."
        touch "$HOME/.fryminer/stopped" 2>/dev/null
        pkill -TERM -f "xmrig" 2>/dev/null || true
        pkill -TERM -f "xlarig" 2>/dev/null || true
        pkill -TERM -f "cpuminer" 2>/dev/null || true
        pkill -TERM -f "ccminer" 2>/dev/null || true
        pkill -TERM -f "SRBMiner" 2>/dev/null || true
        pkill -TERM -f "bfgminer" 2>/dev/null || true
        sleep 3
        pkill -9 -f "xmrig" 2>/dev/null || true
        pkill -9 -f "xlarig" 2>/dev/null || true
        pkill -9 -f "cpuminer" 2>/dev/null || true
        pkill -9 -f "ccminer" 2>/dev/null || true
        pkill -9 -f "SRBMiner" 2>/dev/null || true
        pkill -9 -f "bfgminer" 2>/dev/null || true
        sleep 2
        log_msg "Mining stopped"
    fi
fi

if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    log_msg "Config backed up"
fi

TEMP_SCRIPT="/tmp/fryminer_update_$$.sh"
curl -sL -o "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null

if [[ ! -s "$TEMP_SCRIPT" ]]; then
    log_msg "ERROR: Failed to download update"
    rm -f "$TEMP_SCRIPT"
    # Restart mining if it was running (even on download failure)
    if [[ "$WAS_MINING" == "true" ]] && [[ -f "$CONFIG_FILE" ]]; then
        log_msg "Restarting mining after failed download..."
        rm -f "$HOME/.fryminer/stopped" 2>/dev/null
        source "$CONFIG_FILE"
        SCRIPT_FILE="$HOME/.fryminer/output/$miner/start.sh"
        if [[ -f "$SCRIPT_FILE" ]]; then
            nohup bash "$SCRIPT_FILE" >/dev/null 2>&1 &
            echo $! > "$PID_FILE"
            log_msg "Mining restarted"
        fi
    fi
    exit 1
fi

log_msg "Downloaded update, installing..."
chmod +x "$TEMP_SCRIPT"
bash "$TEMP_SCRIPT" >> "$LOG_FILE" 2>&1
UPDATE_STATUS=$?

if [[ -f "${CONFIG_FILE}.backup" ]]; then
    cp "${CONFIG_FILE}.backup" "$CONFIG_FILE"
    log_msg "Config restored"
fi

if [[ $UPDATE_STATUS -eq 0 ]]; then
    echo "$REMOTE_VER" > "$VERSION_FILE"
    log_msg "Version updated to $REMOTE_VER"
fi

# Restart mining if it was running (regardless of update success/failure)
if [[ "$WAS_MINING" == "true" ]] && [[ -f "$CONFIG_FILE" ]]; then
    log_msg "Restarting mining..."
    rm -f "$HOME/.fryminer/stopped" 2>/dev/null
    source "$CONFIG_FILE"
    SCRIPT_FILE="$HOME/.fryminer/output/$miner/start.sh"
    if [[ -f "$SCRIPT_FILE" ]]; then
        pkill -9 -f "xmrig" 2>/dev/null || true
        pkill -9 -f "xlarig" 2>/dev/null || true
        pkill -9 -f "cpuminer" 2>/dev/null || true
        pkill -9 -f "ccminer" 2>/dev/null || true
        sleep 2
        nohup bash "$SCRIPT_FILE" >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        log_msg "Mining restarted"
    else
        log_msg "WARNING: Start script not found at $SCRIPT_FILE"
        MINER_LOG="$HOME/.fryminer/logs/miner.log"
        echo "[$(date)] WARNING: Auto-update completed but start script missing" >> "$MINER_LOG"
        echo "[$(date)] Please click 'Save' in web interface to regenerate" >> "$MINER_LOG"
    fi
fi

log_msg "=== Update completed ==="
rm -f "$TEMP_SCRIPT"
AUTOUPDATE
    chmod +x "$UPDATE_SCRIPT"

    # Create launchd plist for daily updates
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.frynetworks.fryminer.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$UPDATE_SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>4</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$BASE/logs/update_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$BASE/logs/update_stderr.log</string>
</dict>
</plist>
PLIST

    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE" 2>/dev/null || true

    log "Auto-update configured (runs daily at 4 AM)"
}

# Create web interface
create_web_interface() {
    log "Creating web interface..."

    # Create index.html - copied from source of truth (setup_fryminer_web.sh)
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
HTML

    # Create CGI scripts - adapted from source of truth for macOS
    log "Creating CGI scripts..."

    # Info CGI
    cat > "$BASE/cgi-bin/info.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
uname -m
SCRIPT
    chmod 755 "$BASE/cgi-bin/info.cgi"

    # CPU Cores CGI - macOS uses sysctl
    cat > "$BASE/cgi-bin/cores.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: application/json"
echo ""
CORES=$(sysctl -n hw.ncpu 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo "4")
printf '{"cores":%d}' "$CORES"
SCRIPT
    chmod 755 "$BASE/cgi-bin/cores.cgi"

    # GPU Detection CGI - macOS uses system_profiler
    cat > "$BASE/cgi-bin/gpu.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: application/json"
echo ""

GPU_NAME=""
GPU_AVAILABLE=false
NVIDIA_FOUND=false
AMD_FOUND=false
INTEL_FOUND=false

# macOS GPU detection via system_profiler
GPU_INFO=$(system_profiler SPDisplaysDataType 2>/dev/null)

if echo "$GPU_INFO" | grep -qi "nvidia"; then
    NVIDIA_FOUND=true
    GPU_AVAILABLE=true
    GPU_NAME=$(echo "$GPU_INFO" | grep "Chipset Model" | head -1 | sed 's/.*: //')
fi

if echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
    AMD_FOUND=true
    GPU_AVAILABLE=true
    [ -z "$GPU_NAME" ] && GPU_NAME=$(echo "$GPU_INFO" | grep "Chipset Model" | head -1 | sed 's/.*: //')
fi

if echo "$GPU_INFO" | grep -qi "intel"; then
    INTEL_FOUND=true
    GPU_AVAILABLE=true
    [ -z "$GPU_NAME" ] && GPU_NAME=$(echo "$GPU_INFO" | grep "Chipset Model" | head -1 | sed 's/.*: //')
fi

# Apple Silicon has integrated GPU
if echo "$GPU_INFO" | grep -qi "apple"; then
    GPU_AVAILABLE=true
    GPU_NAME=$(echo "$GPU_INFO" | grep "Chipset Model" | head -1 | sed 's/.*: //')
fi

if [ "$GPU_AVAILABLE" = "true" ]; then
    GPU_NAME_ESCAPED=$(echo "$GPU_NAME" | sed 's/"/\\"/g')
    printf '{"gpu_available":true,"gpu_name":"%s","nvidia":%s,"amd":%s,"intel":%s}' \
        "$GPU_NAME_ESCAPED" "$NVIDIA_FOUND" "$AMD_FOUND" "$INTEL_FOUND"
else
    printf '{"gpu_available":false,"reason":"No discrete GPU detected","nvidia":false,"amd":false,"intel":false}'
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/gpu.cgi"

    # USB ASIC Detection CGI - macOS uses system_profiler SPUSBDataType
    cat > "$BASE/cgi-bin/usbasic.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: application/json"
echo ""

ASIC_FOUND=false
ASIC_COUNT=0
ASIC_DEVICES=""

USB_INFO=$(system_profiler SPUSBDataType 2>/dev/null)

# Check for common USB ASIC patterns
if echo "$USB_INFO" | grep -qi "CP2102\|CP210x\|Silicon Labs"; then
    ASIC_FOUND=true
    ASIC_COUNT=$((ASIC_COUNT + 1))
    ASIC_DEVICES="${ASIC_DEVICES}Block Erupter/Generic ASIC (CP210x),"
fi

if echo "$USB_INFO" | grep -qi "GekkoScience\|STM32\|0483:5740"; then
    ASIC_FOUND=true
    ASIC_COUNT=$((ASIC_COUNT + 1))
    ASIC_DEVICES="${ASIC_DEVICES}GekkoScience ASIC,"
fi

if echo "$USB_INFO" | grep -qi "FTDI\|FT232\|FutureBit"; then
    ASIC_FOUND=true
    ASIC_COUNT=$((ASIC_COUNT + 1))
    ASIC_DEVICES="${ASIC_DEVICES}FTDI USB Device (Moonlander/ASIC),"
fi

ASIC_DEVICES=$(echo "$ASIC_DEVICES" | sed 's/,$//')

if [ "$ASIC_FOUND" = "true" ]; then
    printf '{"usbasic_available":true,"device_count":%d,"devices":"%s"}' "$ASIC_COUNT" "$ASIC_DEVICES"
else
    printf '{"usbasic_available":false,"device_count":0,"devices":"","reason":"No USB ASIC devices detected"}'
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/usbasic.cgi"

    # Thermal CGI - macOS temperature
    cat > "$BASE/cgi-bin/thermal.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: application/json"
echo ""
TEMP=45
# Try osx-cpu-temp if available
if command -v osx-cpu-temp >/dev/null 2>&1; then
    TEMP=$(osx-cpu-temp 2>/dev/null | grep -oE '[0-9]+' | head -1)
fi
printf '{"temperature":%d}' "${TEMP:-45}"
SCRIPT
    chmod 755 "$BASE/cgi-bin/thermal.cgi"

    # Clear logs CGI
    cat > "$BASE/cgi-bin/clearlogs.cgi" <<SCRIPT
#!/bin/bash
echo "Content-type: text/plain"
echo ""
> "$BASE/logs/miner.log"
echo "Logs cleared"
SCRIPT
    chmod 755 "$BASE/cgi-bin/clearlogs.cgi"

    # Save CGI - WITH STRATUM URL FIX
    cat > "$BASE/cgi-bin/save.cgi" <<'SCRIPT'
#!/bin/bash
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
ORE_KEYPAIR=""
ORE_RPC=""
ORE_PRIORITY_FEE="100000"
ORA_NODE_URL=""
ORA_API_TOKEN=""

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
        ore_keypair) ORE_KEYPAIR="$value" ;;
        ore_rpc) ORE_RPC="$value" ;;
        ore_priority_fee) ORE_PRIORITY_FEE="$value" ;;
        ora_node_url) ORA_NODE_URL="$value" ;;
        ora_api_token) ORA_API_TOKEN="$value" ;;
    esac
done
IFS=' '

# ORE uses keypair path as wallet, ORA uses wallet address normally
if [ "$MINER" = "ore" ] && [ -z "$WALLET" ]; then
    WALLET="${ORE_KEYPAIR:-~/.config/solana/id.json}"
fi

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
    ore) [ -z "$POOL" ] && POOL="${ORE_RPC:-https://api.mainnet-beta.solana.com}" ;;
    ora) [ -z "$POOL" ] && POOL="${ORA_NODE_URL:-http://localhost:4001}" ;;
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

mkdir -p $HOME/.fryminer/output
chmod 777 $HOME/.fryminer/output

# Default password to "x" if empty
[ -z "$PASSWORD" ] && PASSWORD="x"

cat > $HOME/.fryminer/config.txt <<EOF
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
ore_keypair=$ORE_KEYPAIR
ore_rpc=$ORE_RPC
ore_priority_fee=$ORE_PRIORITY_FEE
ora_node_url=$ORA_NODE_URL
ora_api_token=$ORA_API_TOKEN
EOF
chmod 666 $HOME/.fryminer/config.txt

SCRIPT_DIR="$HOME/.fryminer/output/$MINER"
mkdir -p "$SCRIPT_DIR"
SCRIPT_FILE="$SCRIPT_DIR/start.sh"

# Initialize flags
IS_UNMINEABLE=false
USE_XLARIG=false
USE_VERUS_MINER=false
USE_ORE_MINER=false
USE_ORA_MINER=false

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
        USE_CPUMINER=false
        USE_VERUS_MINER=true
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
    ore)
        # ORE - Solana PoW using DrillX (Argon2 + Blake3)
        ALGO="drillx"
        USE_CPUMINER=false
        USE_ORE_MINER=true
        ;;
    ora)
        # Oranges (ORA) - Algorand transaction-based mining
        ALGO="algorand-tx"
        USE_CPUMINER=false
        USE_ORA_MINER=true
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
#!/bin/bash
LOG="$HOME/.fryminer/logs/miner.log"

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
    ore)
        # ORE (Solana) - no traditional pool dev fee, route to Scala
        DEV_WALLET_FOR_COIN="$DEV_SCALA_WALLET"
        DEV_USE_SCALA=true
        ;;
    ora)
        # ORA (Algorand) - no traditional pool dev fee, route to Scala
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
rm -f $HOME/.fryminer/stopped 2>/dev/null

# Run optimization script if available (huge pages, MSR, etc)
if [ -x $HOME/.fryminer/optimize.sh ]; then
    echo "[$(date)] Running mining optimizations..." >> "$LOG"
    $HOME/.fryminer/optimize.sh >> "$LOG" 2>&1
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
    # Verus miners
    pkill -TERM -f "ccminer-verus" 2>/dev/null
    pkill -TERM -f "ccminer.*verus" 2>/dev/null
    pkill -TERM -f "hellminer" 2>/dev/null
    pkill -TERM -f "nheqminer" 2>/dev/null

    # Wait for processes to actually terminate (up to 5 seconds)
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt 10 ]; do
        # Check if any miner processes are still running
        if ! pgrep -f "xmrig|xlarig|cpuminer|minerd|SRBMiner-MULTI|lolMiner|t-rex|bfgminer|cgminer|ccminer|hellminer|nheqminer" >/dev/null 2>&1; then
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
    # Verus miners
    pkill -KILL -f "ccminer-verus" 2>/dev/null
    pkill -KILL -f "ccminer.*verus" 2>/dev/null
    pkill -KILL -f "hellminer" 2>/dev/null
    pkill -KILL -f "nheqminer" 2>/dev/null

    # Additional wait for TCP connections to fully close (TIME_WAIT cleanup)
    sleep 3
}

# Trap to cleanup on exit
trap 'stop_miner; exit 0' INT TERM

# Dev fee cycling loop
while true; do
    # Check if stopped by user
    if [ -f $HOME/.fryminer/stopped ]; then
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

if [ "$USE_ORE_MINER" = "true" ]; then
    # ORE mining uses ore-cli with Solana RPC
    ORE_KEYPAIR_PATH="${ORE_KEYPAIR:-~/.config/solana/id.json}"
    ORE_RPC_URL="${ORE_RPC:-$POOL}"
    ORE_FEE="${ORE_PRIORITY_FEE:-100000}"
    cat >> "$SCRIPT_FILE" <<EOF
        # Source cargo/solana PATH
        [ -f "\$HOME/.cargo/env" ] && . "\$HOME/.cargo/env"
        export PATH="\$HOME/.local/share/solana/install/active_release/bin:\$HOME/.cargo/bin:\$PATH"
        ORE_BIN=""
        for OPATH in $HOME/.fryminer/miners/ore "\$HOME/.cargo/bin/ore" /root/.cargo/bin/ore; do
            if [ -x "\$OPATH" ]; then
                ORE_BIN="\$OPATH"
                break
            fi
        done
        if [ -z "\$ORE_BIN" ] && command -v ore >/dev/null 2>&1; then
            ORE_BIN=\$(command -v ore)
        fi
        if [ -n "\$ORE_BIN" ]; then
            echo "[\$(date)] Using ore-cli: \$ORE_BIN" >> "\$LOG"
            \$ORE_BIN --rpc $ORE_RPC_URL --keypair $ORE_KEYPAIR_PATH --priority-fee $ORE_FEE mine --cores $THREADS 2>&1 | tee -a "\$LOG" &
            CPU_PID=\$!
        else
            echo "[\$(date)] ERROR: ore-cli not found! Run setup_fryminer_web.sh to reinstall." >> "\$LOG"
        fi
EOF
elif [ "$USE_ORA_MINER" = "true" ]; then
    # ORA mining uses custom Algorand transaction mining script
    ORA_NODE="${ORA_NODE_URL:-$POOL}"
    ORA_TOKEN="${ORA_API_TOKEN:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    cat >> "$SCRIPT_FILE" <<EOF
        if [ -x $HOME/.fryminer/scripts/ora_miner.sh ]; then
            echo "[\$(date)] Starting ORA (Oranges) miner via Algorand tx mining" >> "\$LOG"
            $HOME/.fryminer/scripts/ora_miner.sh "\$USER_WALLET" "$ORA_NODE" "$ORA_TOKEN" "$THREADS" "\$LOG" &
            CPU_PID=\$!
        else
            echo "[\$(date)] ERROR: ORA miner script not found at $HOME/.fryminer/scripts/ora_miner.sh" >> "\$LOG"
            echo "[\$(date)] Run setup_fryminer_web.sh to reinstall." >> "\$LOG"
        fi
EOF
elif [ "$USE_XLARIG" = "true" ]; then
    # Scala mining uses XLArig with panthera algorithm
    cat >> "$SCRIPT_FILE" <<EOF
        $HOME/.fryminer/miners/xlarig -o $POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --threads=$THREADS -a panthera --no-color --donate-level=0 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
elif [ "$USE_VERUS_MINER" = "true" ]; then
    # Verus mining uses ccminer from monkins1010/ccminer (ARM or Verus2.2 branch)
    cat >> "$SCRIPT_FILE" <<'VERUS_DETECT'
        # Detect and use appropriate Verus miner
        VERUS_MINER=""
        VERUS_MINER_TYPE=""
        
        # Search for ccminer-verus in multiple locations
        for VPATH in /usr/local/bin/ccminer-verus /usr/bin/ccminer-verus $HOME/.fryminer/miners/ccminer-verus; do
            if [ -x "$VPATH" ]; then
                VERUS_MINER="$VPATH"
                VERUS_MINER_TYPE="ccminer"
                break
            fi
        done
        
        # Check home directory installations
        if [ -z "$VERUS_MINER" ]; then
            for VHOME in "$HOME/ccminer/ccminer" /root/ccminer/ccminer /home/*/ccminer/ccminer; do
                if [ -x "$VHOME" ]; then
                    VERUS_MINER="$VHOME"
                    VERUS_MINER_TYPE="ccminer"
                    break
                fi
            done
        fi
        
        # Fallback to nheqminer-verus
        if [ -z "$VERUS_MINER" ]; then
            for VPATH in /usr/local/bin/nheqminer-verus /usr/bin/nheqminer-verus $HOME/.fryminer/miners/nheqminer-verus; do
                if [ -x "$VPATH" ]; then
                    VERUS_MINER="$VPATH"
                    VERUS_MINER_TYPE="nheqminer"
                    break
                fi
            done
        fi
        
        if [ -z "$VERUS_MINER" ]; then
            echo "[$(date)] ERROR: No Verus miner found!" >> "$LOG"
            echo "[$(date)] Searched: /usr/local/bin/ccminer-verus, ~/ccminer/ccminer, $HOME/.fryminer/miners/ccminer-verus" >> "$LOG"
            echo "[$(date)] Run: sudo sh setup_fryminer_web.sh  to reinstall" >> "$LOG"
            echo "[$(date)] Or manually install ccminer-verus to /usr/local/bin/" >> "$LOG"
            exit 1
        fi
        
        echo "[$(date)] Using Verus miner: $VERUS_MINER ($VERUS_MINER_TYPE)" >> "$LOG"
VERUS_DETECT

    cat >> "$SCRIPT_FILE" <<EOF
        # Launch Verus miner based on type
        case "\$VERUS_MINER_TYPE" in
            ccminer)
                # ccminer format: -a verus -o stratum+tcp://pool:port -u wallet -p x -t threads
                "\$VERUS_MINER" -a verus -o stratum+tcp://$POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD -t $THREADS 2>&1 | tee -a "\$LOG" &
                CPU_PID=\$!
                ;;
            nheqminer)
                # nheqminer-verus format: -v (verushash) -l pool:port -u wallet -p x -t threads
                "\$VERUS_MINER" -v -l $POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD -t $THREADS 2>&1 | tee -a "\$LOG" &
                CPU_PID=\$!
                ;;
            *)
                echo "[$(date)] Unknown Verus miner type: \$VERUS_MINER_TYPE" >> "\$LOG"
                ;;
        esac
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
        $HOME/.fryminer/miners/xmrig -o $POOL -u \$USER_WALLET.$WORKER#$UNMINEABLE_REFERRAL -p \$USER_PASSWORD --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
    else
        cat >> "$SCRIPT_FILE" <<EOF
        $HOME/.fryminer/miners/xmrig -o $POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
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
        if [ -x $HOME/.fryminer/miners/bfgminer ]; then
            $HOME/.fryminer/miners/bfgminer -o stratum+tcp://$POOL -u "\$USER_WALLET_STRING" -p \$USER_PASSWORD --algo \$USBASIC_ALGO_TYPE --scan-serial all --no-getwork --no-gbt -T 2>&1 | tee -a "\$LOG" &
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
        if [ -f $HOME/.fryminer/stopped ]; then
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
    if [ -f $HOME/.fryminer/stopped ]; then
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

if [ "$USE_VERUS_MINER" = "true" ]; then
    # Verus dev fee mining uses ccminer from monkins1010/ccminer
    cat >> "$SCRIPT_FILE" <<'DEVVERUS_DETECT'
        # Detect Verus miner for dev fee
        VERUS_MINER=""
        VERUS_MINER_TYPE=""
        
        # Search for ccminer-verus in multiple locations
        for VPATH in /usr/local/bin/ccminer-verus /usr/bin/ccminer-verus $HOME/.fryminer/miners/ccminer-verus; do
            if [ -x "$VPATH" ]; then
                VERUS_MINER="$VPATH"
                VERUS_MINER_TYPE="ccminer"
                break
            fi
        done
        
        # Check home directory installations
        if [ -z "$VERUS_MINER" ]; then
            for VHOME in "$HOME/ccminer/ccminer" /root/ccminer/ccminer /home/*/ccminer/ccminer; do
                if [ -x "$VHOME" ]; then
                    VERUS_MINER="$VHOME"
                    VERUS_MINER_TYPE="ccminer"
                    break
                fi
            done
        fi
        
        # Fallback to nheqminer-verus
        if [ -z "$VERUS_MINER" ]; then
            for VPATH in /usr/local/bin/nheqminer-verus /usr/bin/nheqminer-verus $HOME/.fryminer/miners/nheqminer-verus; do
                if [ -x "$VPATH" ]; then
                    VERUS_MINER="$VPATH"
                    VERUS_MINER_TYPE="nheqminer"
                    break
                fi
            done
        fi
DEVVERUS_DETECT

    cat >> "$SCRIPT_FILE" <<EOF
        if [ -n "\$VERUS_MINER" ]; then
            case "\$VERUS_MINER_TYPE" in
                ccminer)
                    "\$VERUS_MINER" -a verus -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x -t $THREADS 2>&1 | tee -a "\$LOG" &
                    CPU_PID=\$!
                    ;;
                nheqminer)
                    "\$VERUS_MINER" -v -l $POOL -u \$DEV_WALLET.frydev -p x -t $THREADS 2>&1 | tee -a "\$LOG" &
                    CPU_PID=\$!
                    ;;
            esac
        fi
EOF
elif [ "$USE_CPUMINER" = "true" ]; then
    cat >> "$SCRIPT_FILE" <<EOF
        /usr/local/bin/cpuminer --algo=$ALGO -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x --threads=$THREADS --retry 10 --retry-pause 30 --timeout 300 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
elif [ "$DEV_USE_SCALA" = "true" ]; then
    # RandomX coins: Mine Scala during dev fee using XLArig
    cat >> "$SCRIPT_FILE" <<EOF
        echo "[\$(date)] (Routing to Scala - using XLArig)" >> "\$LOG"
        $HOME/.fryminer/miners/xlarig -o $DEV_SCALA_POOL -u \$DEV_WALLET.frydev -p x --threads=$THREADS -a panthera --no-color --donate-level=0 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
else
    XMRIG_OPTS="--cpu-priority 5 --randomx-no-numa"
    if [ "$IS_UNMINEABLE" = "true" ]; then
        cat >> "$SCRIPT_FILE" <<EOF
        $HOME/.fryminer/miners/xmrig -o $POOL -u \$DEV_WALLET.frydev#$UNMINEABLE_REFERRAL -p x --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
        CPU_PID=\$!
EOF
    else
        cat >> "$SCRIPT_FILE" <<EOF
        $HOME/.fryminer/miners/xmrig -o $POOL -u \$DEV_WALLET.frydev -p x --threads=$THREADS -a $ALGO --no-color --donate-level=0 $XMRIG_OPTS 2>&1 | tee -a "\$LOG" &
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
        if [ -x $HOME/.fryminer/miners/bfgminer ]; then
            $HOME/.fryminer/miners/bfgminer -o stratum+tcp://$POOL -u \$DEV_WALLET.frydev -p x --algo \$USBASIC_ALGO_TYPE --scan-serial all --no-getwork --no-gbt -T 2>&1 | tee -a "\$LOG" &
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
        if [ -f $HOME/.fryminer/stopped ]; then
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
#!/bin/bash
echo "Content-type: application/json"
echo ""

if [ -f $HOME/.fryminer/config.txt ]; then
    . $HOME/.fryminer/config.txt
    # Default password to "x" if not set
    [ -z "$password" ] && password="x"
    # Default CPU mining to true, GPU mining to false, USB ASIC mining to false
    [ -z "$cpu_mining" ] && cpu_mining="true"
    [ -z "$gpu_mining" ] && gpu_mining="false"
    [ -z "$gpu_miner" ] && gpu_miner="srbminer"
    [ -z "$usbasic_mining" ] && usbasic_mining="false"
    [ -z "$usbasic_algo" ] && usbasic_algo="sha256d"
    [ -z "$doge_wallet" ] && doge_wallet=""
    [ -z "$ore_keypair" ] && ore_keypair=""
    [ -z "$ore_rpc" ] && ore_rpc=""
    [ -z "$ore_priority_fee" ] && ore_priority_fee=""
    [ -z "$ora_node_url" ] && ora_node_url=""
    [ -z "$ora_api_token" ] && ora_api_token=""
    printf '{"miner":"%s","wallet":"%s","doge_wallet":"%s","worker":"%s","threads":"%s","pool":"%s","password":"%s","cpu_mining":"%s","gpu_mining":"%s","gpu_miner":"%s","usbasic_mining":"%s","usbasic_algo":"%s","ore_keypair":"%s","ore_rpc":"%s","ore_priority_fee":"%s","ora_node_url":"%s","ora_api_token":"%s"}' \
        "$miner" "$wallet" "$doge_wallet" "$worker" "$threads" "$pool" "$password" "$cpu_mining" "$gpu_mining" "$gpu_miner" "$usbasic_mining" "$usbasic_algo" "$ore_keypair" "$ore_rpc" "$ore_priority_fee" "$ora_node_url" "$ora_api_token"
else
    echo "{}"
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/load.cgi"
    
    # Status CGI - Uses multiple detection methods for reliability
    cat > "$BASE/cgi-bin/status.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: application/json"
echo ""

RUNNING="false"
CRASHED="false"
PID_FILE="$HOME/.fryminer/miner.pid"
LOG_FILE="$HOME/.fryminer/logs/miner.log"
STOP_FILE="$HOME/.fryminer/stopped"

# Method 1: Check if PID file exists and process is running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        RUNNING="true"
    fi
fi

# Method 2: Check for miner processes directly using ps (including USB ASIC miners)
if [ "$RUNNING" = "false" ]; then
    if ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[x]larig|[m]inerd|[p]acketcrypt|[b]fgminer|[c]gminer|[c]cminer|[h]ellminer|[n]heqminer|[S]RBMiner|[l]olMiner|[t]-rex" | grep -v grep >/dev/null 2>&1; then
        RUNNING="true"
        # Update PID file with found process
        ACTUAL_PID=$(ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[x]larig|[b]fgminer|[c]gminer|[c]cminer|[h]ellminer|[n]heqminer|[S]RBMiner|[l]olMiner|[t]-rex" | grep -v grep | awk '{print $2}' | head -1)
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
#!/bin/bash
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
#!/bin/bash
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

LOG_FILE="$HOME/.fryminer/logs/miner.log"
CONFIG_FILE="$HOME/.fryminer/config.txt"
PID_FILE="$HOME/.fryminer/miner.pid"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    # Strip ANSI codes for clean parsing
    CLEAN_LOG=$(sed 's/\x1b\[[0-9;]*m//g; s/\[0m//g; s/\[1;[0-9]*m//g; s/\[0;[0-9]*m//g; s/\[[0-9]*;[0-9]*m//g; s/\[[0-9]*m//g' "$LOG_FILE" 2>/dev/null)
    
    # ========== HASHRATE ==========
    # Method 1: XMRig format - "speed 10s/60s/15m 218.2 220.6 n/a H/s"
    HR=$(echo "$CLEAN_LOG" | grep -E "speed [0-9]" | tail -1 | grep -oE '[0-9]+\.[0-9]+ [kKMGT]?H/s' | head -1)
    
    if [ -z "$HR" ]; then
        # Method 2: XLArig format - "CPU T0: Verus Hashing. (null), 364.98 kH/s"
        # Get all recent per-thread hashrates and sum them
        LAST_BATCH_TIME=$(echo "$CLEAN_LOG" | grep -E "CPU T[0-9]+:.*[kKMGT]?H/s" | tail -1 | grep -oE '^\[[0-9 :-]+\]' | head -1)
        if [ -n "$LAST_BATCH_TIME" ]; then
            # Sum all threads from the most recent timestamp batch
            HR_SUM=$(echo "$CLEAN_LOG" | grep -E "CPU T[0-9]+:.*[kKMGT]?H/s" | grep "$LAST_BATCH_TIME" | grep -oE '[0-9]+\.[0-9]+ [kKMGT]?H/s' | awk '{
                val = $1
                unit = $2
                if (unit ~ /^kH/) val = val
                else if (unit ~ /^MH/) val = val * 1000
                else if (unit ~ /^GH/) val = val * 1000000
                else if (unit ~ /^H/) val = val / 1000
                total += val
            } END {
                if (total >= 1000000) printf "%.2f GH/s", total / 1000000
                else if (total >= 1000) printf "%.2f MH/s", total / 1000
                else if (total >= 1) printf "%.2f kH/s", total
                else printf "%.2f H/s", total * 1000
            }')
            # If we only got one thread or summing failed, use last single value
            if [ -n "$HR_SUM" ] && [ "$HR_SUM" != "0.00 H/s" ]; then
                HR="$HR_SUM"
            else
                HR=$(echo "$CLEAN_LOG" | grep -E "CPU T[0-9]+:.*[kKMGT]?H/s" | tail -1 | grep -oE '[0-9]+\.[0-9]+ [kKMGT]?H/s')
            fi
        else
            # Single line fallback
            HR=$(echo "$CLEAN_LOG" | grep -E "CPU T[0-9]+:.*[kKMGT]?H/s" | tail -1 | grep -oE '[0-9]+\.[0-9]+ [kKMGT]?H/s')
        fi
    fi
    
    if [ -z "$HR" ]; then
        # Method 3: cpuminer format - various "123.45 kH/s" patterns
        HR=$(echo "$CLEAN_LOG" | grep -oE '[0-9]+\.?[0-9]* [kKMGT]?H/s' | tail -1)
    fi
    
    [ -n "$HR" ] && HASHRATE="$HR"
    
    # ========== SHARES ==========
    # Method 1: XLArig/XMRig format - "accepted: 66208/66506 (diff ..."
    # The first number is accepted, second is total submitted
    ACC_LINE=$(echo "$CLEAN_LOG" | grep "accepted:" | tail -1)
    if [ -n "$ACC_LINE" ]; then
        ACC=$(echo "$ACC_LINE" | grep -oE 'accepted: [0-9]+' | grep -oE '[0-9]+')
        [ -n "$ACC" ] && SHARES="$ACC"
    fi
    
    if [ "$SHARES" = "0" ]; then
        # Method 2: Count individual accepted lines (XMRig "net accepted" style)
        ACC=$(echo "$CLEAN_LOG" | grep -c "net.*accepted" 2>/dev/null || echo "0")
        [ "$ACC" -gt 0 ] && SHARES="$ACC"
    fi
    
    if [ "$SHARES" = "0" ]; then
        # Method 3: cpuminer "accepted" or "yay!" lines
        ACC=$(echo "$CLEAN_LOG" | grep -ciE "accepted|yay!" 2>/dev/null || echo "0")
        [ "$ACC" -gt 0 ] && SHARES="$ACC"
    fi
    
    # ========== REJECTED ==========
    # Method 1: XLArig format - get total from "accepted: X/Y" where rejected = Y - X
    if [ -n "$ACC_LINE" ]; then
        TOTAL_SUBMITTED=$(echo "$ACC_LINE" | grep -oE 'accepted: [0-9]+/[0-9]+' | grep -oE '/[0-9]+' | tr -d '/')
        if [ -n "$TOTAL_SUBMITTED" ] && [ -n "$ACC" ] && [ "$TOTAL_SUBMITTED" -gt 0 ]; then
            REJECTED=$((TOTAL_SUBMITTED - ACC))
            [ "$REJECTED" -lt 0 ] && REJECTED=0
        fi
    fi
    
    if [ "$REJECTED" = "0" ]; then
        # Method 2: Count reject lines
        REJ=$(echo "$CLEAN_LOG" | grep -ciE "reject|booo" 2>/dev/null || echo "0")
        REJECTED="$REJ"
    fi
    
    # ========== ALGORITHM ==========
    # Method 1: From log "Algorithm: xxx"
    ALG=$(echo "$CLEAN_LOG" | grep "Algorithm:" | tail -1 | sed 's/.*Algorithm: *//' | awk '{print $1}')
    
    if [ -z "$ALG" ] || [ "$ALG" = "--" ]; then
        # Method 2: XMRig "POOL.*algo" format
        ALG=$(echo "$CLEAN_LOG" | grep "algo" | tail -1 | grep -oE "algo [a-zA-Z0-9/_-]+" | cut -d' ' -f2)
    fi
    
    if [ -z "$ALG" ] || [ "$ALG" = "--" ]; then
        # Method 3: Detect from log content
        if echo "$CLEAN_LOG" | grep -q "Verus Hashing\|panthera"; then
            ALG="panthera"
        elif echo "$CLEAN_LOG" | grep -q "RandomX\|rx/0"; then
            ALG="rx/0"
        fi
    fi
    
    [ -n "$ALG" ] && ALGO="$ALG"
    
    # ========== DIFFICULTY ==========
    # Method 1: XLArig format - "Stratum difficulty set to 88239.98"
    DIFF_VAL=$(echo "$CLEAN_LOG" | grep -i "difficulty set to" | tail -1 | grep -oE '[0-9]+\.?[0-9]*$')
    
    if [ -z "$DIFF_VAL" ]; then
        # Method 2: XMRig format - "new job from pool diff 100001"
        DIFF_VAL=$(echo "$CLEAN_LOG" | grep "diff" | tail -1 | grep -oE "diff [0-9]+" | tail -1 | cut -d' ' -f2)
    fi
    
    if [ -z "$DIFF_VAL" ]; then
        # Method 3: From accepted share lines - "accepted: X/Y (diff 12345"
        DIFF_VAL=$(echo "$CLEAN_LOG" | grep "accepted.*diff" | tail -1 | grep -oE 'diff [0-9]+' | tail -1 | cut -d' ' -f2)
    fi
    
    [ -n "$DIFF_VAL" ] && DIFF="$DIFF_VAL"
    
    # ========== POOL ==========
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE" 2>/dev/null
        [ -n "$pool" ] && POOL="$pool"
    fi
    
    # Fallback: try to get pool from log
    if [ "$POOL" = "--" ]; then
        POOL_VAL=$(echo "$CLEAN_LOG" | grep -i "Pool:" | tail -1 | sed 's/.*Pool: *//' | awk '{print $1}')
        [ -n "$POOL_VAL" ] && POOL="$POOL_VAL"
    fi
fi

# Calculate uptime from PID or from log timestamps
UPTIME_CALCULATED=false
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
            UPTIME_CALCULATED=true
        fi
    fi
fi

# Fallback: estimate uptime from first and last log timestamps
if [ "$UPTIME_CALCULATED" = "false" ] && [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    FIRST_TS=$(grep -oE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$LOG_FILE" 2>/dev/null | head -1 | tr -d '[]')
    LAST_TS=$(grep -oE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$LOG_FILE" 2>/dev/null | tail -1 | tr -d '[]')
    if [ -n "$FIRST_TS" ] && [ -n "$LAST_TS" ]; then
        FIRST_EPOCH=$(date -d "$FIRST_TS" +%s 2>/dev/null || echo 0)
        LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
        if [ "$FIRST_EPOCH" -gt 0 ] && [ "$LAST_EPOCH" -gt 0 ]; then
            ELAPSED=$((LAST_EPOCH - FIRST_EPOCH))
            [ "$ELAPSED" -lt 0 ] && ELAPSED=0
            HOURS=$((ELAPSED / 3600))
            MINS=$(((ELAPSED % 3600) / 60))
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
    # Clear logs CGI
    cat > "$BASE/cgi-bin/clearlogs.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: text/plain"
echo ""
> $HOME/.fryminer/logs/miner.log
echo "Logs cleared"
SCRIPT
    chmod 755 "$BASE/cgi-bin/clearlogs.cgi"
    
    # Logs CGI - Returns last 100 lines with no-cache headers
    cat > "$BASE/cgi-bin/logs.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: text/plain"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo ""

LOG_FILE="$HOME/.fryminer/logs/miner.log"

if [ -f "$LOG_FILE" ]; then
    tail -100 "$LOG_FILE" 2>/dev/null || echo "Unable to read logs"
else
    echo "No logs available yet"
fi
SCRIPT
    chmod 755 "$BASE/cgi-bin/logs.cgi"
    
    # Start CGI - Uses nohup and multiple detection methods
    cat > "$BASE/cgi-bin/start.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: text/html"
echo ""

PID_FILE="$HOME/.fryminer/miner.pid"
LOG_FILE="$HOME/.fryminer/logs/miner.log"

if [ ! -f $HOME/.fryminer/config.txt ]; then
    echo "<div class='error'>❌ No configuration found. Please save configuration first.</div>"
    exit 0
fi

. $HOME/.fryminer/config.txt

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

SCRIPT_FILE="$HOME/.fryminer/output/$miner/start.sh"
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
        if ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[x]larig|[m]inerd|[b]fgminer|[c]gminer|[c]cminer|[h]ellminer|[n]heqminer|[S]RBMiner|[l]olMiner|[t]-rex" | grep -v grep >/dev/null 2>&1; then
            # Found a miner, update PID file with actual PID
            ACTUAL_PID=$(ps aux 2>/dev/null | grep -E "[c]puminer|[x]mrig|[x]larig|[b]fgminer|[c]gminer|[c]cminer|[h]ellminer|[n]heqminer|[S]RBMiner|[l]olMiner|[t]-rex" | grep -v grep | awk '{print $2}' | head -1)
            if [ -n "$ACTUAL_PID" ]; then
                echo "$ACTUAL_PID" > "$PID_FILE"
                RUNNING=true
            fi
        fi
    fi

    # Method 3: Check log for activity (including USB ASIC miner indicators)
    if [ "$RUNNING" = "false" ]; then
        if grep -qE "Stratum|threads started|algorithm|accepted|USB|ASIC|BFGMiner|cgminer|Verus Hashing|panthera|XLArig|ccminer" "$LOG_FILE" 2>/dev/null; then
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
#!/bin/bash
echo "Content-type: text/html"
echo ""

PID_FILE="$HOME/.fryminer/miner.pid"
STOP_FILE="$HOME/.fryminer/stopped"
LOG_FILE="$HOME/.fryminer/logs/miner.log"

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
    cat > "$BASE/cgi-bin/stop.cgi" <<'SCRIPT'
#!/bin/bash
echo "Content-type: text/html"
echo ""

PID_FILE="$HOME/.fryminer/miner.pid"
STOP_FILE="$HOME/.fryminer/stopped"
LOG_FILE="$HOME/.fryminer/logs/miner.log"

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
#!/bin/bash
echo "Content-type: application/json"
echo ""

ACTION="${QUERY_STRING:-check}"
REPO_API="https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main"
DOWNLOAD_URL="https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_macos.sh"
VERSION_FILE="$HOME/.fryminer/version.txt"
CONFIG_FILE="$HOME/.fryminer/config.txt"
CONFIG_BACKUP="$HOME/.fryminer/config.txt.backup"
MINER_LOG="$HOME/.fryminer/logs/miner.log"
UPDATE_LOG="$HOME/.fryminer/logs/update.log"
PID_FILE="$HOME/.fryminer/miner.pid"
UPDATE_STATUS_FILE="$HOME/.fryminer/update_status.txt"
UPDATE_ERROR_FILE="$HOME/.fryminer/update_error.txt"

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
                    touch $HOME/.fryminer/stopped 2>/dev/null

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
                if [ -w $HOME/.fryminer ] && [ -w /usr/local/bin ]; then
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
                    echo "Requires root - SSH in and run: sudo ./setup_fryminer_macos.sh" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "password is required\|terminal is required"; then
                    echo "First-time setup required - SSH in and run: sudo ./setup_fryminer_macos.sh" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "permission denied"; then
                    echo "Permission denied - SSH in and run: sudo ./setup_fryminer_macos.sh" > "$UPDATE_ERROR_FILE"
                elif echo "$LAST_ERRORS" | grep -qi "cmake.*failed"; then
                    echo "Build tools missing - SSH in and run: sudo ./setup_fryminer_macos.sh" > "$UPDATE_ERROR_FILE"
                else
                    echo "Installation failed - check update logs for details" > "$UPDATE_ERROR_FILE"
                fi
                
                echo "failed" > "$UPDATE_STATUS_FILE"
                
                # CRITICAL: Restart mining even if update failed!
                # The update killed the miner, so we must restart it regardless
                if [ "$WAS_MINING" = "true" ] && [ -n "$MINER_COIN" ]; then
                    SCRIPT_FILE="$HOME/.fryminer/output/$MINER_COIN/start.sh"
                    if [ -f "$SCRIPT_FILE" ]; then
                        echo "[$(date)] 🔄 Update failed but miner was running - restarting $MINER_COIN mining..." >> "$MINER_LOG"
                        echo "[$(date)] Restarting mining after failed update..." >> "$UPDATE_LOG"
                        
                        rm -f $HOME/.fryminer/stopped 2>/dev/null
                        
                        if [ "$CAN_SUDO" = "true" ]; then
                            sudo pkill -9 -f "xmrig" 2>/dev/null || true
                            sudo pkill -9 -f "xlarig" 2>/dev/null || true
                            sudo pkill -9 -f "cpuminer" 2>/dev/null || true
                            sudo pkill -9 -f "ccminer" 2>/dev/null || true
                            sudo pkill -9 -f "nheqminer" 2>/dev/null || true
                            sudo pkill -9 -f "bfgminer" 2>/dev/null || true
                            sudo pkill -9 -f "cgminer" 2>/dev/null || true
                        else
                            pkill -9 -f "xmrig" 2>/dev/null || true
                            pkill -9 -f "xlarig" 2>/dev/null || true
                            pkill -9 -f "cpuminer" 2>/dev/null || true
                            pkill -9 -f "ccminer" 2>/dev/null || true
                            pkill -9 -f "nheqminer" 2>/dev/null || true
                            pkill -9 -f "bfgminer" 2>/dev/null || true
                            pkill -9 -f "cgminer" 2>/dev/null || true
                        fi
                        
                        sleep 2
                        nohup sh "$SCRIPT_FILE" >/dev/null 2>&1 &
                        RESTART_PID=$!
                        echo "$RESTART_PID" > "$PID_FILE"
                        echo "[$(date)] ✅ Mining restarted PID $RESTART_PID (using previous version)" >> "$MINER_LOG"
                        echo "[$(date)] Mining restarted PID $RESTART_PID (previous version)" >> "$UPDATE_LOG"
                    else
                        echo "[$(date)] ⚠️  Cannot restart mining - start script missing: $SCRIPT_FILE" >> "$MINER_LOG"
                        echo "[$(date)] Please click 'Save' in Settings to regenerate and restart" >> "$MINER_LOG"
                    fi
                fi
                
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
                SCRIPT_FILE="$HOME/.fryminer/output/$MINER_COIN/start.sh"
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

    log "Web interface created"
}

# Start web server
start_webserver() {
    log "Starting web server on port $PORT..."

    cat > "$BASE/webserver.py" << PYSERVER
import http.server
import socketserver
import os
import subprocess
import json

PORT = $PORT
BASE_DIR = "$BASE"
os.chdir(BASE_DIR)

class Handler(http.server.CGIHTTPRequestHandler):
    cgi_directories = ['/cgi-bin']

    def do_GET(self):
        if self.path == '/':
            self.path = '/index.html'
        super().do_GET()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"FryMiner running at http://localhost:{PORT}")
    httpd.serve_forever()
PYSERVER

    # Kill any existing webserver
    pkill -f "python3.*webserver.py" 2>/dev/null || true
    sleep 1

    cd "$BASE"
    nohup python3 "$BASE/webserver.py" > "$BASE/logs/webserver.log" 2>&1 &

    log "Web server started at http://localhost:$PORT"
}

# Main
main() {
    echo ""
    echo "========================================"
    echo " FryMiner Setup - macOS Edition"
    echo " Multi-Coin CPU Miner (37+ Coins)"
    echo "========================================"
    echo ""

    detect_architecture
    check_homebrew
    setup_directories
    install_dependencies

    # Install CPU miners
    install_xmrig
    install_xlarig
    install_cpuminer
    install_verus_miner

    # Install ORE miner (Solana PoW)
    ORE_OK=false
    if install_ore_cli; then
        ORE_OK=true
    else
        warn "ORE miner installation failed - ORE mining will not be available"
    fi

    # Install ORA miner (Oranges/Algorand)
    ORA_OK=false
    if install_ora_miner; then
        ORA_OK=true
    else
        warn "ORA miner installation failed - Oranges mining will not be available"
    fi

    # Install GPU miner
    install_srbminer

    # Install USB ASIC miner
    install_bfgminer

    # Setup auto-update
    setup_auto_update

    # Create web interface
    create_web_interface

    # Start web server
    start_webserver

    # Save initial version
    if [[ ! -f "$BASE/version.txt" ]]; then
        CURRENT_VER=$(curl -s --connect-timeout 5 "https://api.github.com/repos/Fry-Foundation/Fry-PoW-MultiMiner/commits/main" 2>/dev/null | grep -m1 '"sha"' | cut -d'"' -f4 | head -c 7)
        if [[ -n "$CURRENT_VER" ]]; then
            echo "$CURRENT_VER" > "$BASE/version.txt"
        else
            echo "initial" > "$BASE/version.txt"
        fi
    fi

    echo ""
    log "================================================"
    log "FryMiner Installation Complete!"
    log "================================================"
    echo ""
    log "Web Interface: http://localhost:$PORT"
    echo ""
    log "Installation Summary:"
    [[ -f "$MINERS_DIR/xmrig" ]] && log "  ✅ XMRig" || log "  ❌ XMRig"
    [[ -f "$MINERS_DIR/xlarig" ]] && log "  ✅ XLArig (Scala)" || log "  ❌ XLArig"
    [[ -f "$MINERS_DIR/cpuminer" ]] && log "  ✅ cpuminer-multi" || log "  ❌ cpuminer"
    [[ -f "$MINERS_DIR/ccminer-verus" ]] && log "  ✅ ccminer-verus" || log "  ❌ ccminer-verus"
    [ "$ORE_OK" = "true" ] && log "  ✅ ore-cli (ORE/Solana)" || log "  ❌ ore-cli"
    [ "$ORA_OK" = "true" ] && log "  ✅ ORA miner (Oranges)" || log "  ❌ ORA miner"
    echo ""
    log "Files installed to: $BASE"
    echo ""
    log "================================================"
    log "DEV FEE NOTICE: 2%"
    log "================================================"
    log "FryMiner includes a 2% dev fee to support"
    log "continued development. The miner switches to"
    log "the dev wallet for ~1 min every 50 min cycle."
    log "Thank you for your support!"
    log "================================================"
    echo ""
}

main "$@"
