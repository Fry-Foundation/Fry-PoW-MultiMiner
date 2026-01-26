#!/bin/bash
# FryMiner Setup - macOS (Apple Silicon & Intel)
# Multi-cryptocurrency CPU miner with web interface
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
DEV_WALLET_SCALA="Ssy2BnsAcJUVZZ2kTiywf61bvYjvPosXzaBcaft9RSvaNNKsFRkcKbaWjMotjATkSbSmeSdX2DAxc1XxpcdxUBGd41oCwwfetG"

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

        # Add brew to PATH for Apple Silicon
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
    brew install jansson gmp pkg-config >/dev/null 2>&1 || true

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

    # Build from source for macOS (best compatibility)
    log "Building XMRig from source..."

    cd /tmp
    rm -rf xmrig-build
    git clone https://github.com/xmrig/xmrig.git xmrig-build 2>/dev/null
    cd xmrig-build

    mkdir build && cd build
    cmake .. -DWITH_HWLOC=ON -DWITH_TLS=ON
    make -j$(sysctl -n hw.ncpu)

    if [[ -f "xmrig" ]]; then
        cp xmrig "$XMRIG_PATH"
        chmod +x "$XMRIG_PATH"
        log "XMRig installed successfully"
    else
        warn "XMRig build failed - will try prebuilt binary"

        # Fallback to prebuilt for x86_64
        if [[ "$ARCH_TYPE" == "x86_64" ]]; then
            cd /tmp
            curl -sL "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-macos-x64.tar.gz" -o xmrig.tar.gz
            tar xzf xmrig.tar.gz
            cp xmrig-*/xmrig "$XMRIG_PATH"
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

    ./autogen.sh
    ./configure --with-curl --with-crypto
    make -j$(sysctl -n hw.ncpu)

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

# Setup auto-update using launchd (macOS scheduler)
setup_auto_update() {
    log "Setting up automatic daily updates..."

    UPDATE_SCRIPT="$BASE/auto_update.sh"
    PLIST_FILE="$HOME/Library/LaunchAgents/org.frynetworks.fryminer.update.plist"

    # Create update script
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

# Check if miner was running and stop it
WAS_MINING=false
if [[ -f "$PID_FILE" ]]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        WAS_MINING=true
        log_msg "Stopping mining for update..."

        # Stop miners gracefully
        pkill -TERM -f "xmrig" 2>/dev/null || true
        pkill -TERM -f "xlarig" 2>/dev/null || true
        pkill -TERM -f "cpuminer" 2>/dev/null || true
        sleep 3
        pkill -9 -f "xmrig" 2>/dev/null || true
        pkill -9 -f "xlarig" 2>/dev/null || true
        pkill -9 -f "cpuminer" 2>/dev/null || true
        sleep 2
        log_msg "Mining stopped"
    fi
fi

# Backup config
if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    log_msg "Config backed up"
fi

# Download and run update
TEMP_SCRIPT="/tmp/fryminer_update_$$.sh"
curl -sL -o "$TEMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null

if [[ ! -s "$TEMP_SCRIPT" ]]; then
    log_msg "ERROR: Failed to download update"
    rm -f "$TEMP_SCRIPT"
    exit 1
fi

log_msg "Downloaded update, installing..."
chmod +x "$TEMP_SCRIPT"
bash "$TEMP_SCRIPT" >> "$LOG_FILE" 2>&1

# Restore config
if [[ -f "${CONFIG_FILE}.backup" ]]; then
    cp "${CONFIG_FILE}.backup" "$CONFIG_FILE"
    log_msg "Config restored"
fi

# Update version
echo "$REMOTE_VER" > "$VERSION_FILE"
log_msg "Version updated to $REMOTE_VER"

# Restart mining if it was running
if [[ "$WAS_MINING" == "true" ]] && [[ -f "$CONFIG_FILE" ]]; then
    log_msg "Restarting mining..."
    source "$CONFIG_FILE"
    SCRIPT_FILE="$HOME/.fryminer/output/$miner/start.sh"

    if [[ -f "$SCRIPT_FILE" ]]; then
        nohup bash "$SCRIPT_FILE" >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        log_msg "Mining restarted"
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

    # Load the launch agent
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE" 2>/dev/null || true

    log "Auto-update configured (runs daily at 4 AM)"
}

# Create web interface
create_web_interface() {
    log "Creating web interface..."

    # Create index.html (simplified version for macOS)
    cat > "$BASE/index.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>FryMiner - macOS</title>
<style>
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: linear-gradient(135deg, #1a1a1a 0%, #2d2d2d 100%);
    color: #fff;
    margin: 0;
    padding: 20px;
}
.container {
    max-width: 900px;
    margin: 0 auto;
    background: #0a0a0a;
    border-radius: 20px;
    padding: 30px;
    border: 1px solid #333;
}
h1 {
    text-align: center;
    color: #dc143c;
    font-size: 2em;
}
.form-group { margin-bottom: 20px; }
.form-group label { display: block; margin-bottom: 8px; color: #dc143c; }
.form-group input, .form-group select {
    width: 100%;
    padding: 12px;
    border: 2px solid #333;
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
    margin: 5px;
    font-size: 1em;
}
button:hover { transform: translateY(-2px); }
.status-card {
    background: #1a1a1a;
    padding: 20px;
    margin: 20px 0;
    border-radius: 10px;
    border: 1px solid #333;
}
.log-viewer {
    background: #000;
    color: #0f0;
    padding: 15px;
    height: 200px;
    overflow-y: auto;
    font-family: monospace;
    font-size: 12px;
    white-space: pre-wrap;
    border-radius: 8px;
}
.info { background: #1a3d1a; padding: 10px; border-radius: 5px; margin: 10px 0; }
</style>
</head>
<body>
<div class="container">
    <h1>FryMiner for macOS</h1>
    <p style="text-align: center; color: #888;">Multi-Coin CPU Mining Control Panel</p>

    <div class="info">
        <strong>Dev Fee:</strong> 2% (mines to dev wallet ~1 min every 50 min cycle)
    </div>

    <form id="configForm">
        <div class="form-group">
            <label>Cryptocurrency:</label>
            <select id="miner" name="miner" required>
                <option value="">-- Select --</option>
                <optgroup label="CPU Mineable">
                    <option value="xmr">Monero (XMR) - RandomX</option>
                    <option value="scala">Scala (XLA) - Panthera</option>
                    <option value="zephyr">Zephyr (ZEPH) - RandomX</option>
                    <option value="verus">Verus (VRSC) - VerusHash</option>
                </optgroup>
                <optgroup label="Solo Lottery Mining">
                    <option value="xmr-lotto">Monero Lottery (XMR)</option>
                    <option value="zeph-lotto">Zephyr Lottery (ZEPH)</option>
                </optgroup>
            </select>
        </div>

        <div class="form-group">
            <label>Wallet Address:</label>
            <input type="text" id="wallet" name="wallet" required placeholder="Your wallet address">
        </div>

        <div class="form-group">
            <label>Worker Name:</label>
            <input type="text" id="worker" name="worker" value="macworker">
        </div>

        <div class="form-group">
            <label>CPU Threads:</label>
            <input type="number" id="threads" name="threads" min="1" value="4">
        </div>

        <div class="form-group">
            <label>Pool (leave empty for default):</label>
            <input type="text" id="pool" name="pool" placeholder="pool.example.com:3333">
        </div>

        <div style="text-align: center;">
            <button type="submit">Save & Start</button>
            <button type="button" onclick="stopMining()">Stop Mining</button>
        </div>
    </form>

    <div class="status-card">
        <h3>Status: <span id="statusText">Checking...</span></h3>
    </div>

    <div class="status-card">
        <h3>Log Output</h3>
        <div class="log-viewer" id="logViewer">Loading...</div>
        <button onclick="refreshLogs()" style="margin-top: 10px;">Refresh Logs</button>
    </div>
</div>

<script>
const defaultPools = {
    'xmr': 'pool.supportxmr.com:3333',
    'scala': 'pool.scalaproject.io:3333',
    'zephyr': 'de.zephyr.herominers.com:1123',
    'verus': 'pool.verus.io:9999',
    'xmr-lotto': 'xmr.solopool.org:3333',
    'zeph-lotto': 'zeph.solopool.org:8008'
};

document.getElementById('miner').addEventListener('change', function() {
    const pool = defaultPools[this.value] || '';
    document.getElementById('pool').placeholder = pool || 'pool.example.com:3333';
});

document.getElementById('configForm').addEventListener('submit', function(e) {
    e.preventDefault();
    const data = new FormData(this);
    fetch('/cgi-bin/save.cgi', {
        method: 'POST',
        body: new URLSearchParams(data)
    })
    .then(r => r.text())
    .then(result => {
        alert('Configuration saved! Mining started.');
        setTimeout(checkStatus, 2000);
    });
});

function stopMining() {
    fetch('/cgi-bin/stop.cgi')
        .then(r => r.text())
        .then(() => {
            alert('Mining stopped');
            checkStatus();
        });
}

function refreshLogs() {
    fetch('/cgi-bin/logs.cgi')
        .then(r => r.text())
        .then(logs => {
            document.getElementById('logViewer').textContent = logs || 'No logs';
        })
        .catch(() => {
            document.getElementById('logViewer').textContent = 'Error loading logs';
        });
}

function checkStatus() {
    fetch('/cgi-bin/status.cgi')
        .then(r => r.json())
        .then(data => {
            const el = document.getElementById('statusText');
            el.textContent = data.running ? 'Mining Active' : 'Stopped';
            el.style.color = data.running ? '#4caf50' : '#f44336';
        })
        .catch(() => {});
}

refreshLogs();
checkStatus();
setInterval(checkStatus, 5000);
setInterval(refreshLogs, 10000);
</script>
</body>
</html>
HTML

    # Create CGI scripts
    create_cgi_scripts

    log "Web interface created"
}

# Create CGI scripts
create_cgi_scripts() {
    # Status CGI
    cat > "$BASE/cgi-bin/status.cgi" << 'SCRIPT'
#!/bin/bash
echo "Content-type: application/json"
echo ""
RUNNING=false
if pgrep -f "xmrig|xlarig|cpuminer" >/dev/null 2>&1; then
    RUNNING=true
fi
printf '{"running":%s}' "$RUNNING"
SCRIPT
    chmod +x "$BASE/cgi-bin/status.cgi"

    # Logs CGI
    cat > "$BASE/cgi-bin/logs.cgi" << SCRIPT
#!/bin/bash
echo "Content-type: text/plain"
echo ""
LOG_FILE="$BASE/logs/miner.log"
if [[ -f "\$LOG_FILE" ]]; then
    tail -100 "\$LOG_FILE"
else
    echo "No logs available"
fi
SCRIPT
    chmod +x "$BASE/cgi-bin/logs.cgi"

    # Stop CGI
    cat > "$BASE/cgi-bin/stop.cgi" << SCRIPT
#!/bin/bash
echo "Content-type: text/plain"
echo ""
touch "$BASE/stopped"
pkill -TERM -f "xmrig" 2>/dev/null || true
pkill -TERM -f "xlarig" 2>/dev/null || true
pkill -TERM -f "cpuminer" 2>/dev/null || true
sleep 2
pkill -9 -f "xmrig" 2>/dev/null || true
pkill -9 -f "xlarig" 2>/dev/null || true
pkill -9 -f "cpuminer" 2>/dev/null || true
echo "Mining stopped"
SCRIPT
    chmod +x "$BASE/cgi-bin/stop.cgi"

    # Save CGI
    cat > "$BASE/cgi-bin/save.cgi" << 'SCRIPT'
#!/bin/bash
echo "Content-type: text/html"
echo ""

# Read POST data
read POST_DATA

# Parse parameters
MINER=$(echo "$POST_DATA" | grep -oP 'miner=\K[^&]*' | sed 's/+/ /g;s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")
WALLET=$(echo "$POST_DATA" | grep -oP 'wallet=\K[^&]*' | sed 's/+/ /g;s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")
WORKER=$(echo "$POST_DATA" | grep -oP 'worker=\K[^&]*' | sed 's/+/ /g;s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")
THREADS=$(echo "$POST_DATA" | grep -oP 'threads=\K[^&]*' | sed 's/+/ /g')
POOL=$(echo "$POST_DATA" | grep -oP 'pool=\K[^&]*' | sed 's/+/ /g;s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")

BASE="$HOME/.fryminer"
MINERS_DIR="$BASE/miners"

# Set default pools
case "$MINER" in
    xmr) [[ -z "$POOL" ]] && POOL="pool.supportxmr.com:3333" ;;
    scala) [[ -z "$POOL" ]] && POOL="pool.scalaproject.io:3333" ;;
    zephyr) [[ -z "$POOL" ]] && POOL="de.zephyr.herominers.com:1123" ;;
    verus) [[ -z "$POOL" ]] && POOL="pool.verus.io:9999" ;;
    xmr-lotto) [[ -z "$POOL" ]] && POOL="xmr.solopool.org:3333" ;;
    zeph-lotto) [[ -z "$POOL" ]] && POOL="zeph.solopool.org:8008" ;;
esac

# Save config
cat > "$BASE/config.txt" << EOF
miner=$MINER
wallet=$WALLET
worker=$WORKER
threads=$THREADS
pool=$POOL
EOF

# Determine algorithm
case "$MINER" in
    xmr|xmr-lotto|zephyr|zeph-lotto) ALGO="rx/0"; USE_XMRIG=true ;;
    scala) ALGO="panthera"; USE_XMRIG=false ;;
    verus) ALGO="verushash"; USE_XMRIG=false ;;
esac

# Create start script
SCRIPT_DIR="$BASE/output/$MINER"
mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_DIR/start.sh" << STARTEOF
#!/bin/bash
LOG="$BASE/logs/miner.log"
rm -f "$BASE/stopped"
echo "[\$(date)] Starting $MINER mining..." >> "\$LOG"
while true; do
    [[ -f "$BASE/stopped" ]] && exit 0

    # User mining (49 min)
    echo "[\$(date)] Mining for user wallet..." >> "\$LOG"
STARTEOF

if [[ "$USE_XMRIG" == "true" ]]; then
    cat >> "$SCRIPT_DIR/start.sh" << XMRIGEOF
    "$MINERS_DIR/xmrig" -o "$POOL" -u "$WALLET.$WORKER" -p x --threads=$THREADS -a $ALGO --no-color --donate-level=0 2>&1 | tee -a "\$LOG" &
    MINER_PID=\$!
XMRIGEOF
else
    cat >> "$SCRIPT_DIR/start.sh" << CPUEOF
    "$MINERS_DIR/cpuminer" --algo=$ALGO -o stratum+tcp://$POOL -u "$WALLET.$WORKER" -p x --threads=$THREADS 2>&1 | tee -a "\$LOG" &
    MINER_PID=\$!
CPUEOF
fi

cat >> "$SCRIPT_DIR/start.sh" << ENDEOF
    echo \$MINER_PID > "$BASE/miner.pid"

    # Wait 49 minutes
    for i in \$(seq 1 294); do
        [[ -f "$BASE/stopped" ]] && kill \$MINER_PID 2>/dev/null; exit 0
        sleep 10
    done
    kill \$MINER_PID 2>/dev/null
    sleep 2

    # Dev mining (1 min)
    echo "[\$(date)] Dev fee mining (2%)..." >> "\$LOG"
ENDEOF

# Dev wallet selection
DEV_WALLET="$DEV_WALLET_SCALA"
DEV_POOL="pool.scalaproject.io:3333"

cat >> "$SCRIPT_DIR/start.sh" << DEVEOF
    "$MINERS_DIR/xmrig" -o "$DEV_POOL" -u "$DEV_WALLET.frydev" -p x --threads=$THREADS -a panthera --no-color --donate-level=0 2>&1 | tee -a "\$LOG" &
    DEV_PID=\$!
    for i in \$(seq 1 6); do
        [[ -f "$BASE/stopped" ]] && kill \$DEV_PID 2>/dev/null; exit 0
        sleep 10
    done
    kill \$DEV_PID 2>/dev/null
    sleep 2
done
DEVEOF

chmod +x "$SCRIPT_DIR/start.sh"

# Stop any existing mining
pkill -9 -f "xmrig" 2>/dev/null || true
pkill -9 -f "cpuminer" 2>/dev/null || true
sleep 2

# Start mining
nohup bash "$SCRIPT_DIR/start.sh" >/dev/null 2>&1 &

echo "<div style='color:#4caf50'>Configuration saved! Mining started.</div>"
SCRIPT
    chmod +x "$BASE/cgi-bin/save.cgi"
}

# Start web server
start_webserver() {
    log "Starting web server on port $PORT..."

    # Create Python web server script
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

    # Start web server in background
    cd "$BASE"
    nohup python3 "$BASE/webserver.py" > "$BASE/logs/webserver.log" 2>&1 &

    log "Web server started at http://localhost:$PORT"
}

# Main
main() {
    echo ""
    echo "========================================"
    echo " FryMiner Setup - macOS Edition"
    echo " Multi-Coin CPU Miner"
    echo "========================================"
    echo ""

    detect_architecture
    check_homebrew
    setup_directories
    install_dependencies
    install_xmrig
    install_cpuminer
    setup_auto_update
    create_web_interface
    start_webserver

    echo ""
    log "FryMiner setup complete!"
    echo ""
    echo "Open http://localhost:$PORT in your browser"
    echo ""
    echo "Files installed to: $BASE"
    echo ""
}

main "$@"
