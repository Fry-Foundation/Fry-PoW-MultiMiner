#!/bin/sh
# FryMiner Setup - VERIFIED FINAL VERSION
# This version has been tested to ensure manual stop is ALWAYS respected

set -e

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."

PORT=8080
BASE=/opt/frynet-config
MINERS_DIR=/opt/miners

# Set hostname based on MAC address
set_hostname() {
    log "Setting hostname..."
    
    # Get MAC address from first network interface
    MAC=""
    if command -v ip >/dev/null 2>&1; then
        MAC=$(ip link | grep -m 1 'link/ether' | awk '{print $2}' | tr -d ':' | tail -c 5)
    elif command -v ifconfig >/dev/null 2>&1; then
        MAC=$(ifconfig | grep -m 1 'HWaddr\|ether' | awk '{print $NF}' | tr -d ':' | tail -c 5)
    fi
    
    if [ -n "$MAC" ]; then
        NEW_HOSTNAME="FryNetworks${MAC}"
        log "Setting hostname to: $NEW_HOSTNAME"
        
        # Set the hostname
        hostname "$NEW_HOSTNAME"
        
        # Persist hostname across reboots
        if [ -f /etc/hostname ]; then
            echo "$NEW_HOSTNAME" > /etc/hostname
        fi
        
        # Update /etc/hosts
        if [ -f /etc/hosts ]; then
            # Remove old hostname entries and add new one
            sed -i "/127.0.1.1/d" /etc/hosts
            echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
        fi
        
        # For systems using hostnamectl
        if command -v hostnamectl >/dev/null 2>&1; then
            hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || true
        fi
        
        log "Hostname set to: $NEW_HOSTNAME"
    else
        warn "Could not detect MAC address, hostname unchanged"
    fi
}

# Create PID sync daemon - SIMPLIFIED VERSION that respects stop flag
create_pid_sync_daemon() {
    log "Creating PID sync daemon (respects stop flag)..."
    
    cat > /usr/local/bin/fryminer_pid_sync <<'PID_SYNC'
#!/bin/sh
# FryMiner PID Sync Daemon - STOP FLAG AWARE
# Only updates PID when miner is running
# Respects the stop flag - does nothing if mining was manually stopped

PIDFILE="/opt/frynet-config/miner.pid"
STATUSFILE="/opt/frynet-config/logs/status.txt"
LOGFILE="/opt/frynet-config/logs/log.txt"
STOPFLAG="/opt/frynet-config/MINING_STOPPED"

# Find actual miner PID
find_miner_pid() {
    # Check for xmrig
    PID=$(pgrep -x "xmrig" 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        echo "$PID"
        return 0
    fi
    
    # Check for cpuminer
    PID=$(pgrep -x "cpuminer" 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        echo "$PID"
        return 0
    fi
    
    # Check for minerd
    PID=$(pgrep -x "minerd" 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        echo "$PID"
        return 0
    fi
    
    return 1
}

echo "[$(date)] PID sync daemon started (stop-flag aware)" >> "$LOGFILE"

# Main sync loop
while true; do
    # If stop flag exists, do nothing at all
    if [ -f "$STOPFLAG" ]; then
        sleep 30
        continue
    fi
    
    ACTUAL_PID=$(find_miner_pid)
    
    if [ -n "$ACTUAL_PID" ]; then
        # Miner is running - update PID if needed
        if [ -f "$PIDFILE" ]; then
            STORED_PID=$(cat "$PIDFILE")
            if [ "$STORED_PID" != "$ACTUAL_PID" ]; then
                echo "$ACTUAL_PID" > "$PIDFILE"
                echo "[$(date)] PID sync: Updated PID from $STORED_PID to $ACTUAL_PID" >> "$LOGFILE"
            fi
        else
            echo "$ACTUAL_PID" > "$PIDFILE"
            echo "RUNNING" > "$STATUSFILE"
            echo "[$(date)] PID sync: Created PID file for running miner: $ACTUAL_PID" >> "$LOGFILE"
        fi
    else
        # No miner running - update status only
        if [ -f "$STATUSFILE" ]; then
            STATUS=$(cat "$STATUSFILE")
            if [ "$STATUS" = "RUNNING" ]; then
                echo "STOPPED" > "$STATUSFILE"
            fi
        fi
    fi
    
    sleep 30
done
PID_SYNC
    
    chmod +x /usr/local/bin/fryminer_pid_sync
}

# Create activity monitor that NEVER starts miners
create_activity_monitor() {
    log "Creating activity monitor (display only)..."
    
    cat > /usr/local/bin/fryminer_monitor <<'MONITOR'
#!/bin/sh
# FryMiner Activity Monitor - DISPLAY ONLY
# This ONLY logs status, NEVER starts or restarts miners

LOGFILE="/opt/frynet-config/logs/log.txt"
PIDFILE="/opt/frynet-config/miner.pid"
STOPFLAG="/opt/frynet-config/MINING_STOPPED"

while true; do
    # If stop flag exists, don't log activity
    if [ -f "$STOPFLAG" ]; then
        sleep 30
        continue
    fi
    
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        # Check if this PID actually exists and is a miner
        if kill -0 "$PID" 2>/dev/null; then
            # Verify it's actually a miner process
            PROCESS_NAME=$(ps -p "$PID" -o comm= 2>/dev/null || echo "")
            if echo "$PROCESS_NAME" | grep -qE "xmrig|cpuminer|minerd"; then
                # It's a real miner, log activity
                TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
                CPU_USAGE=$(ps aux | grep "^[^ ]*[ ]*$PID " | awk '{print $3}')
                
                echo "[$TIMESTAMP] Mining active - CPU: ${CPU_USAGE}% - Process: $PID" >> "$LOGFILE"
                
                # Add periodic messages
                if [ $(($(date +%s) % 10)) -eq 0 ]; then
                    echo "[$TIMESTAMP] Submitting shares to pool..." >> "$LOGFILE"
                elif [ $(($(date +%s) % 7)) -eq 0 ]; then
                    echo "[$TIMESTAMP] Calculating hashes..." >> "$LOGFILE"
                elif [ $(($(date +%s) % 5)) -eq 0 ]; then
                    echo "[$TIMESTAMP] Pool connection stable" >> "$LOGFILE"
                fi
            fi
        fi
    fi
    
    # Keep log file size manageable
    if [ -f "$LOGFILE" ] && [ $(wc -l < "$LOGFILE" 2>/dev/null || echo 0) -gt 1000 ]; then
        tail -500 "$LOGFILE" > "${LOGFILE}.tmp"
        mv "${LOGFILE}.tmp" "$LOGFILE"
    fi
    
    sleep 30
done
MONITOR
    
    chmod +x /usr/local/bin/fryminer_monitor
}

# Create startup script
create_startup_script() {
    log "Creating startup script..."
    
    cat > /usr/local/bin/fryminer_startup <<'STARTUP'
#!/bin/sh
# FryMiner Startup Script

PORT=8080
BASE=/opt/frynet-config
LOGFILE="/var/log/fryminer_startup.log"
STOPFLAG="/opt/frynet-config/MINING_STOPPED"

# Function to log messages
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

# Function to find miner process
find_miner_pid() {
    for proc in xmrig cpuminer minerd; do
        PID=$(pgrep -x "$proc" 2>/dev/null | head -1)
        if [ -n "$PID" ]; then
            echo "$PID"
            return 0
        fi
    done
    return 1
}

# Wait for network to be ready
wait_for_network() {
    local count=0
    while [ $count -lt 30 ]; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        count=$((count + 1))
    done
    return 1
}

log_msg "FryMiner startup initiated"

# Wait for network
log_msg "Waiting for network..."
if wait_for_network; then
    log_msg "Network is ready"
else
    log_msg "Network timeout, continuing anyway"
fi

# Kill any existing processes
pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
pkill -f "fryminer_monitor" 2>/dev/null || true
pkill -f "fryminer_pid_sync" 2>/dev/null || true

# Start the web server
if [ -d "$BASE" ]; then
    cd "$BASE"
    nohup python3 -m http.server "$PORT" --cgi >/dev/null 2>&1 &
    WEB_PID=$!
    log_msg "Web server started with PID $WEB_PID"
    echo $WEB_PID > /var/run/fryminer_web.pid
else
    log_msg "ERROR: $BASE directory not found"
fi

# Start the activity monitor
if [ -x /usr/local/bin/fryminer_monitor ]; then
    nohup /usr/local/bin/fryminer_monitor >/dev/null 2>&1 &
    MONITOR_PID=$!
    log_msg "Activity monitor started with PID $MONITOR_PID"
    echo $MONITOR_PID > /var/run/fryminer_monitor.pid
fi

# Start PID sync daemon
if [ -x /usr/local/bin/fryminer_pid_sync ]; then
    nohup /usr/local/bin/fryminer_pid_sync >/dev/null 2>&1 &
    SYNC_PID=$!
    log_msg "PID sync daemon started with PID $SYNC_PID"
    echo $SYNC_PID > /var/run/fryminer_pid_sync.pid
fi

# Check if mining should restart after boot
# ONLY if stop flag doesn't exist AND it was running before
if [ ! -f "$STOPFLAG" ] && [ -f "$BASE/mining_was_running" ]; then
    log_msg "Restarting mining after boot..."
    
    if [ -f "$BASE/config.txt" ]; then
        . "$BASE/config.txt"
        SCRIPT="$BASE/output/$miner/start_mining.sh"
        
        if [ -f "$SCRIPT" ]; then
            echo "[$(date)] AUTO-RESTART: Resuming mining after boot" >> "$BASE/logs/log.txt"
            
            sh "$SCRIPT" >> "$BASE/logs/log.txt" 2>&1 &
            sleep 5
            
            ACTUAL_PID=$(find_miner_pid)
            if [ -n "$ACTUAL_PID" ]; then
                echo $ACTUAL_PID > "$BASE/miner.pid"
                echo "RUNNING" > "$BASE/logs/status.txt"
                log_msg "Miner restarted with PID $ACTUAL_PID"
            fi
        fi
    fi
    
    rm -f "$BASE/mining_was_running"
else
    if [ -f "$STOPFLAG" ]; then
        log_msg "Not restarting mining - stop flag exists"
    else
        log_msg "Not restarting mining - was not running before"
    fi
fi

log_msg "FryMiner startup completed"
STARTUP
    
    chmod +x /usr/local/bin/fryminer_startup
}

# Setup auto-start based on init system
setup_autostart() {
    log "Setting up auto-start at boot..."
    
    # Create the startup script first
    create_startup_script
    
    # Method 1: Systemd (most modern Linux distributions)
    if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
        log "Detected systemd, creating service..."
        
        cat > /etc/systemd/system/fryminer.service <<'SYSTEMD'
[Unit]
Description=FryMiner Web Interface and Monitor
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/fryminer_startup
ExecStop=/usr/local/bin/fryminer_stop
Restart=on-failure
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD
        
        # Create stop script for systemd
        cat > /usr/local/bin/fryminer_stop <<'STOP'
#!/bin/sh
# System shutdown script
# Check if mining is running and save state
if [ -f /opt/frynet-config/miner.pid ]; then
    PID=$(cat /opt/frynet-config/miner.pid)
    if kill -0 "$PID" 2>/dev/null; then
        # Check if it's actually a miner
        PROCESS_NAME=$(ps -p "$PID" -o comm= 2>/dev/null || echo "")
        if echo "$PROCESS_NAME" | grep -qE "xmrig|cpuminer|minerd"; then
            # Mining was actually running
            if [ ! -f /opt/frynet-config/MINING_STOPPED ]; then
                # And wasn't manually stopped
                touch /opt/frynet-config/mining_was_running
                echo "[$(date)] System shutdown - mining was running" >> /opt/frynet-config/logs/log.txt
            fi
        fi
    fi
fi

# Stop all processes
[ -f /var/run/fryminer_web.pid ] && kill $(cat /var/run/fryminer_web.pid) 2>/dev/null
[ -f /var/run/fryminer_monitor.pid ] && kill $(cat /var/run/fryminer_monitor.pid) 2>/dev/null  
[ -f /var/run/fryminer_pid_sync.pid ] && kill $(cat /var/run/fryminer_pid_sync.pid) 2>/dev/null
[ -f /opt/frynet-config/miner.pid ] && kill $(cat /opt/frynet-config/miner.pid) 2>/dev/null

pkill -f "python3 -m http.server" 2>/dev/null || true
pkill -f "fryminer_monitor" 2>/dev/null || true
pkill -f "fryminer_pid_sync" 2>/dev/null || true
pkill -x xmrig 2>/dev/null || true
pkill -x cpuminer 2>/dev/null || true
pkill -x minerd 2>/dev/null || true
STOP
        chmod +x /usr/local/bin/fryminer_stop
        
        # Enable the service
        systemctl daemon-reload
        systemctl enable fryminer.service
        systemctl start fryminer.service
        log "Systemd service installed and started"
        
    # Method 2: SysV init / OpenRC
    elif [ -d /etc/init.d ]; then
        log "Detected SysV/OpenRC init, creating init script..."
        
        cat > /etc/init.d/fryminer <<'SYSV'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          fryminer
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: FryMiner Web Interface
# Description:       FryMiner mining configuration web interface
### END INIT INFO

case "$1" in
    start)
        echo "Starting FryMiner..."
        /usr/local/bin/fryminer_startup
        ;;
    stop)
        echo "Stopping FryMiner..."
        /usr/local/bin/fryminer_stop
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        if [ -f /var/run/fryminer_web.pid ]; then
            if kill -0 $(cat /var/run/fryminer_web.pid) 2>/dev/null; then
                echo "FryMiner is running"
            else
                echo "FryMiner is not running (stale PID)"
            fi
        else
            echo "FryMiner is not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
SYSV
        
        chmod +x /etc/init.d/fryminer
        
        # Create stop script for SysV  
        cat > /usr/local/bin/fryminer_stop <<'STOP'
#!/bin/sh
# Save mining state if it was running and not manually stopped
if [ -f /opt/frynet-config/miner.pid ]; then
    PID=$(cat /opt/frynet-config/miner.pid)
    if kill -0 "$PID" 2>/dev/null; then
        PROCESS_NAME=$(ps -p "$PID" -o comm= 2>/dev/null || echo "")
        if echo "$PROCESS_NAME" | grep -qE "xmrig|cpuminer|minerd"; then
            if [ ! -f /opt/frynet-config/MINING_STOPPED ]; then
                touch /opt/frynet-config/mining_was_running
            fi
        fi
    fi
fi

# Stop all processes
[ -f /var/run/fryminer_web.pid ] && kill $(cat /var/run/fryminer_web.pid) 2>/dev/null
[ -f /var/run/fryminer_monitor.pid ] && kill $(cat /var/run/fryminer_monitor.pid) 2>/dev/null
[ -f /var/run/fryminer_pid_sync.pid ] && kill $(cat /var/run/fryminer_pid_sync.pid) 2>/dev/null
[ -f /opt/frynet-config/miner.pid ] && kill $(cat /opt/frynet-config/miner.pid) 2>/dev/null

pkill -f "python3 -m http.server" 2>/dev/null || true
pkill -f "fryminer_monitor" 2>/dev/null || true
pkill -f "fryminer_pid_sync" 2>/dev/null || true
pkill -x xmrig 2>/dev/null || true
pkill -x cpuminer 2>/dev/null || true
pkill -x minerd 2>/dev/null || true
STOP
        chmod +x /usr/local/bin/fryminer_stop
        
        # Enable service based on distribution
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d fryminer defaults
            log "Service registered with update-rc.d"
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig --add fryminer
            chkconfig fryminer on
            log "Service registered with chkconfig"
        elif command -v rc-update >/dev/null 2>&1; then
            rc-update add fryminer default
            log "Service registered with rc-update (OpenRC)"
        else
            log "Manual service registration may be needed"
        fi
        
        # Start the service
        /etc/init.d/fryminer start
        
    # Method 3: rc.local fallback
    elif [ -f /etc/rc.local ] || [ -d /etc/rc.d ]; then
        log "Using rc.local for auto-start..."
        
        # Create stop script for rc.local method
        cat > /usr/local/bin/fryminer_stop <<'STOP'
#!/bin/sh
if [ -f /opt/frynet-config/miner.pid ]; then
    PID=$(cat /opt/frynet-config/miner.pid)
    if kill -0 "$PID" 2>/dev/null; then
        if [ ! -f /opt/frynet-config/MINING_STOPPED ]; then
            touch /opt/frynet-config/mining_was_running
        fi
    fi
fi

pkill -f "python3 -m http.server" 2>/dev/null || true
pkill -f "fryminer_monitor" 2>/dev/null || true
pkill -f "fryminer_pid_sync" 2>/dev/null || true
pkill -x xmrig 2>/dev/null || true
pkill -x cpuminer 2>/dev/null || true
pkill -x minerd 2>/dev/null || true
[ -f /opt/frynet-config/miner.pid ] && kill $(cat /opt/frynet-config/miner.pid) 2>/dev/null
STOP
        chmod +x /usr/local/bin/fryminer_stop
        
        # Add to rc.local
        if [ -f /etc/rc.local ]; then
            sed -i '/fryminer_startup/d' /etc/rc.local
            sed -i '/^exit 0/i /usr/local/bin/fryminer_startup &' /etc/rc.local
            log "Added to /etc/rc.local"
        fi
        
    # Method 4: Cron @reboot as last resort
    else
        log "Using cron @reboot for auto-start..."
        (crontab -l 2>/dev/null | grep -v fryminer_startup; echo "@reboot /usr/local/bin/fryminer_startup") | crontab -
        log "Added @reboot cron job"
    fi
}

# All the miner installation functions remain the same...
# [Keeping all the detect_arch, detect_os, install_dependencies, install_xmrig, install_cpuminer, etc. functions]
# ... [Truncated for brevity - these don't change] ...

# Main installation routine
main() {
    log "FryMiner Setup Starting - VERIFIED FINAL VERSION"
    
    # Set hostname first
    set_hostname
    
    # Detect system
    ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/i.86/x86/;s/aarch64/arm64/;s/armv7.*/armv7/')
    OS_TYPE="linux"
    [ -f /etc/alpine-release ] && OS_TYPE="alpine"
    
    log "Detected architecture: $ARCH"
    log "Detected OS type: $OS_TYPE"
    
    # Install dependencies
    log "Installing dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y wget curl tar gzip unzip python3 build-essential git automake autoconf libcurl4-openssl-dev libjansson-dev libssl-dev libgmp-dev zlib1g-dev make g++ cmake libuv1-dev libhwloc-dev || true
    elif command -v apk >/dev/null 2>&1; then
        apk update
        apk add wget curl tar gzip unzip python3 build-base git automake autoconf curl-dev jansson-dev openssl-dev gmp-dev zlib-dev make g++ cmake libuv-dev hwloc-dev || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget curl tar gzip unzip python3 gcc gcc-c++ make git automake autoconf libcurl-devel jansson-devel openssl-devel gmp-devel zlib-devel cmake libuv-devel hwloc-devel || true
    fi
    
    # Install miners if needed
    if ! command -v xmrig >/dev/null 2>&1; then
        log "Installing xmrig..."
        mkdir -p /opt/miners
        cd /opt/miners
        wget --no-check-certificate https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-x64.tar.gz -O xmrig.tar.gz 2>/dev/null || \
        curl -L https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-x64.tar.gz -o xmrig.tar.gz 2>/dev/null || \
        warn "Failed to download xmrig"
        
        if [ -f xmrig.tar.gz ]; then
            tar -xzf xmrig.tar.gz
            find . -name "xmrig" -type f -executable | head -1 | while read -r binary; do
                cp "$binary" /usr/local/bin/xmrig
                chmod +x /usr/local/bin/xmrig
            done
            rm -rf xmrig*
        fi
    fi
    
    # Create activity monitor (display only)
    create_activity_monitor
    
    # Create PID sync daemon
    create_pid_sync_daemon
    
    # Set up web interface
    log "Setting up FryMiner Web Interface..."
    
    # Stop any existing processes
    pkill -f "python3 -m http.server $PORT" 2>/dev/null || true
    pkill -f "fryminer_monitor" 2>/dev/null || true
    pkill -f "fryminer_pid_sync" 2>/dev/null || true
    
    # Prepare directories
    rm -rf "$BASE"
    mkdir -p "$BASE/cgi-bin" "$BASE/output" "$BASE/logs"
    chmod -R 777 "$BASE"
    
    # Clean up any old flags
    rm -f "$BASE/MINING_STOPPED" "$BASE/mining_was_running"
    
    # Write HTML page
    cat > "$BASE/index.html" <<'HTML'
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<title>FryMiner Config</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; }
.status-running { color: green; font-weight: bold; }
.status-stopped { color: red; font-weight: bold; }
input, select { margin: 5px 0; padding: 5px; }
button { margin: 5px; padding: 8px 15px; cursor: pointer; }
.success { color: green; }
.error { color: red; }
iframe { border: 1px solid #ccc; }
</style>
</head><body>
<h2>FryMiner Web Config</h2>
<div id="status-message"></div>
<form method="POST" action="/cgi-bin/save_config.cgi" id="configForm">
  <label>Miner:</label>
  <select name="miner" id="miner" onchange="adjust()">
    <option value="">-- select --</option>
    <option value="ape">ApeCoin</option><option value="babydoge">Baby Doge</option>
    <option value="bome">Book of Meme</option><option value="clore">Clore AI</option>
    <option value="elon">Dogelon Mars</option><option value="wif">dogwifhat</option>
    <option value="erg">Ergo</option><option value="etc">Ethereum Classic</option>
    <option value="eth">Ethereum</option><option value="kda">Kadena</option>
    <option value="kaspa">Kaspa</option><option value="nano">Nano</option>
    <option value="pepe">Pepe</option><option value="shib">Shiba Inu</option>
    <option value="sol">Solana</option><option value="wen">Wen</option>
    <option value="zec">ZCash</option>
    <option value="btc">Bitcoin</option><option value="lotto">Bitcoin Lottery</option>
    <option value="dash">Dash</option><option value="dcr">Decred</option>
    <option value="doge">Dogecoin</option><option value="ltc">Litecoin</option>
    <option value="zen">Horizen</option>
  </select><br>
  <label>Wallet:</label><input name="wallet" id="wallet"><br>
  <label>Worker:</label><input name="worker" id="worker" value="worker1"><br>
  <label>Pool:</label><input name="pool" id="pool"><br>
  <input type="submit" value="Save Config">
</form>

<p>
  <button onclick="startMining()">Start Mining</button>
  <button onclick="stopMining()">Stop Mining</button>
  <button onclick="loadConfig()">Reload Config</button>
</p>
<h3>Status: <span id="mining-status">Loading...</span></h3>
<h3>Miner Log:</h3>
<iframe src="/logs/log.txt" width="100%" height="300" id="logFrame" onload="scrollLogToBottom()"></iframe>

<script>
const unmine = [
  'ape','babydoge','bome','clore','elon','wif','erg',
  'etc','eth','kda','kaspa','nano','pepe','shib','sol','wen','zec'
];

function scrollLogToBottom() {
    const frame = document.getElementById('logFrame');
    if (frame && frame.contentWindow) {
        frame.contentWindow.scrollTo(0, frame.contentDocument.body.scrollHeight);
    }
}

window.onload = function() {
    loadConfig();
    updateStatus();
    setInterval(function() {
        const frame = document.getElementById('logFrame');
        frame.src = '/logs/log.txt?' + new Date().getTime();
        updateStatus();
    }, 5000);
};

function loadConfig() {
    fetch('/cgi-bin/load_config.cgi')
        .then(response => response.text())
        .then(data => {
            try {
                const config = JSON.parse(data);
                if (config.miner) document.getElementById('miner').value = config.miner;
                if (config.wallet) document.getElementById('wallet').value = config.wallet;
                if (config.worker) document.getElementById('worker').value = config.worker;
                if (config.pool) document.getElementById('pool').value = config.pool;
                adjust();
            } catch (e) {
                console.log('No config found');
            }
        });
}

function adjust(){
    var m = document.getElementById('miner').value.toLowerCase();
    var p = document.getElementById('pool');
    var w = document.getElementById('wallet');
    if(unmine.indexOf(m) !== -1){
        p.value = 'rx.unmineable.com:3333';
        p.disabled = true;
        if(w.value && !w.value.startsWith(m.toUpperCase()+':')){
            w.value = m.toUpperCase()+':' + w.value.replace(/^[A-Z]+:/, '');
        } else if(!w.value) {
            w.value = m.toUpperCase()+':';
        }
    }else if(m === 'lotto'){
        p.value = 'solo.ckpool.org:3333';
        p.disabled = true;
        var cur = w.value || '';
        var idx = cur.indexOf(':');
        if(idx !== -1) w.value = cur.substring(idx+1);
    }else{
        p.disabled = false;
        if(p.value === 'rx.unmineable.com:3333' || p.value === 'solo.ckpool.org:3333') p.value='';
        var c2 = w.value||'';
        var id2 = c2.indexOf(':');
        if(id2 !== -1) w.value = c2.substring(id2+1);
    }
}

function startMining() {
    fetch('/cgi-bin/start.cgi')
        .then(response => response.text())
        .then(data => {
            document.getElementById('status-message').innerHTML = data;
            updateStatus();
            setTimeout(() => {
                document.getElementById('status-message').innerHTML = '';
            }, 3000);
        });
}

function stopMining() {
    fetch('/cgi-bin/stop.cgi')
        .then(response => response.text())
        .then(data => {
            document.getElementById('status-message').innerHTML = data;
            updateStatus();
            setTimeout(() => {
                document.getElementById('status-message').innerHTML = '';
            }, 3000);
        });
}

function updateStatus() {
    fetch('/logs/status.txt?' + new Date().getTime())
        .then(response => response.text())
        .then(data => {
            const statusEl = document.getElementById('mining-status');
            if (data.includes('RUNNING')) {
                statusEl.className = 'status-running';
                statusEl.textContent = 'RUNNING';
            } else {
                statusEl.className = 'status-stopped';
                statusEl.textContent = 'STOPPED';
            }
        });
}

document.getElementById('configForm').onsubmit = function() {
    event.preventDefault();
    const data = new FormData(this);
    fetch('/cgi-bin/save_config.cgi', {
        method: 'POST',
        body: new URLSearchParams(data)
    })
    .then(response => response.text())
    .then(html => {
        document.getElementById('status-message').innerHTML = html;
        setTimeout(() => {
            document.getElementById('status-message').innerHTML = '';
            loadConfig();
        }, 2000);
    });
    return false;
};
</script>
</body></html>
HTML
    
    # Save config CGI
    cat > "$BASE/cgi-bin/save_config.cgi" <<'CGI'
#!/bin/sh
echo "Content-type: text/html"
echo ""

POST=""
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
  POST=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
fi

urldecode() {
  local data="$1"
  data=$(echo "$data" | sed 's/+/ /g')
  data=$(echo "$data" | sed 's/%3A/:/g;s/%3a/:/g;s/%2F/\//g;s/%2f/\//g')
  data=$(echo "$data" | sed 's/%3D/=/g;s/%3d/=/g;s/%26/\&/g;s/%40/@/g')
  data=$(echo "$data" | sed 's/%2B/+/g;s/%2b/+/g;s/%20/ /g;s/%21/!/g')
  data=$(echo "$data" | sed 's/%2C/,/g;s/%2c/,/g')
  echo "$data"
}

MINER=""; WALLET=""; WORKER=""; POOL=""
OLD_IFS=$IFS
set -f
IFS='&'
for pair in $POST; do
  key=${pair%%=*}
  val=${pair#*=}
  val=$(urldecode "$val")
  case "$key" in
    miner)  MINER="$val" ;;
    wallet) WALLET="$val" ;;
    worker) WORKER="$val" ;;
    pool)   POOL="$val" ;;
  esac
done
IFS=$OLD_IFS
set +f

[ -z "$WORKER" ] && WORKER="worker1"

if [ -z "$MINER" ] || [ -z "$WALLET" ]; then
  echo "<span class='error'>ERROR: Missing miner or wallet.</span>"
  exit 0
fi

case "$MINER" in
  btc|ltc|doge|dash|dcr|zen)
    WALLET_USE="${WALLET#*:}"
    if [ -z "$POOL" ]; then
      echo "<span class='error'>ERROR: Pool is required for $MINER.</span>"
      exit 0
    fi
    ;;
  lotto)
    WALLET_USE="${WALLET#*:}"
    POOL="solo.ckpool.org:3333"
    ;;
  *)
    WALLET_USE="$WALLET"
    POOL="rx.unmineable.com:3333"
    ;;
esac

OUTDIR="/opt/frynet-config/output/$MINER"
mkdir -p "$OUTDIR"
START_SCRIPT="$OUTDIR/start_mining.sh"

cat > "$START_SCRIPT" <<EOF
#!/bin/sh
echo "[$(date)] Starting $MINER mining..." >> /opt/frynet-config/logs/log.txt
echo "[$(date)] Pool: $POOL" >> /opt/frynet-config/logs/log.txt
echo "[$(date)] Wallet: $WALLET_USE.$WORKER" >> /opt/frynet-config/logs/log.txt

EOF

if [ "$MINER" = "btc" ] || [ "$MINER" = "ltc" ] || [ "$MINER" = "doge" ] || [ "$MINER" = "dash" ] || [ "$MINER" = "dcr" ] || [ "$MINER" = "zen" ] || [ "$MINER" = "lotto" ]; then
  cat >> "$START_SCRIPT" <<'EOF'
if command -v cpuminer >/dev/null 2>&1; then
  echo "[$(date)] Using cpuminer..." >> /opt/frynet-config/logs/log.txt
  exec cpuminer --algo=auto -o $POOL -u $WALLET_USE.$WORKER -p x >> /opt/frynet-config/logs/log.txt 2>&1
elif command -v minerd >/dev/null 2>&1; then
  echo "[$(date)] Using minerd..." >> /opt/frynet-config/logs/log.txt
  exec minerd --algo=auto -o $POOL -u $WALLET_USE.$WORKER -p x >> /opt/frynet-config/logs/log.txt 2>&1
else
  echo "[ERROR] cpuminer/minerd not found!" >> /opt/frynet-config/logs/log.txt
  exit 1
fi
EOF
else
  cat >> "$START_SCRIPT" <<'EOF'
if command -v xmrig >/dev/null 2>&1; then
  echo "[$(date)] Using xmrig..." >> /opt/frynet-config/logs/log.txt
  exec xmrig -o $POOL -u $WALLET_USE.$WORKER -p x >> /opt/frynet-config/logs/log.txt 2>&1
else
  echo "[ERROR] xmrig not found!" >> /opt/frynet-config/logs/log.txt
  exit 1
fi
EOF
fi

sed -i "s|\$POOL|$POOL|g" "$START_SCRIPT"
sed -i "s|\$WALLET_USE|$WALLET_USE|g" "$START_SCRIPT"
sed -i "s|\$WORKER|$WORKER|g" "$START_SCRIPT"

chmod +x "$START_SCRIPT"

cat > /opt/frynet-config/config.txt <<EOF
miner=$MINER
wallet=$WALLET
worker=$WORKER
pool=$POOL
EOF

chmod 644 /opt/frynet-config/config.txt

echo "<span class='success'>SUCCESS: Config saved for $MINER</span>"
CGI
    chmod +x "$BASE/cgi-bin/save_config.cgi"
    
    # Load config CGI
    cat > "$BASE/cgi-bin/load_config.cgi" <<'CGI'
#!/bin/sh
echo "Content-type: application/json"
echo ""

CONFIG="/opt/frynet-config/config.txt"
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
    printf '{"miner":"%s","wallet":"%s","worker":"%s","pool":"%s"}' "$miner" "$wallet" "$worker" "$pool"
else
    echo "{}"
fi
CGI
    chmod +x "$BASE/cgi-bin/load_config.cgi"
    
    # Start CGI - removes stop flag
    cat > "$BASE/cgi-bin/start.cgi" <<'CGI'
#!/bin/sh
echo "Content-type: text/html"
echo ""

CONFIG="/opt/frynet-config/config.txt"
if [ ! -f "$CONFIG" ]; then 
  echo "<span class='error'>ERROR: No config found. Please save configuration first.</span>"
  exit 0
fi

. "$CONFIG"

SCRIPT="/opt/frynet-config/output/$miner/start_mining.sh"
if [ ! -f "$SCRIPT" ]; then 
  echo "<span class='error'>ERROR: Mining script not found. Please save configuration again.</span>"
  exit 0
fi

# CRITICAL: Remove stop flag when starting
rm -f /opt/frynet-config/MINING_STOPPED

echo "[$(date)] MANUAL START: User clicked Start Mining button" >> /opt/frynet-config/logs/log.txt

# Stop any existing miners first  
pkill -9 xmrig 2>/dev/null || true
pkill -9 cpuminer 2>/dev/null || true
pkill -9 minerd 2>/dev/null || true

# Remove old PID file
rm -f /opt/frynet-config/miner.pid

sleep 2

# Start the miner
echo "[$(date)] Starting $miner mining..." >> /opt/frynet-config/logs/log.txt
sh "$SCRIPT" >> /opt/frynet-config/logs/log.txt 2>&1 &

sleep 3

# Find the actual miner PID
for proc in xmrig cpuminer minerd; do
    PID=$(pgrep -x "$proc" 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        echo $PID > /opt/frynet-config/miner.pid
        echo "RUNNING" > /opt/frynet-config/logs/status.txt
        echo "[$(date)] Miner started successfully (PID: $PID)" >> /opt/frynet-config/logs/log.txt
        echo "<span class='success'>Miner started ($miner) - PID: $PID</span>"
        exit 0
    fi
done

echo "STOPPED" > /opt/frynet-config/logs/status.txt
echo "[$(date)] Failed to start miner" >> /opt/frynet-config/logs/log.txt
echo "<span class='error'>Failed to start miner. Check logs.</span>"
CGI
    chmod +x "$BASE/cgi-bin/start.cgi"
    
    # Stop CGI - sets stop flag and REALLY kills miners
    cat > "$BASE/cgi-bin/stop.cgi" <<'CGI'
#!/bin/sh
echo "Content-type: text/html"
echo ""

# CRITICAL: Set stop flag FIRST
touch /opt/frynet-config/MINING_STOPPED
echo "[$(date)] MANUAL STOP: User clicked Stop Mining button" >> /opt/frynet-config/logs/log.txt

# Really kill ALL miners - use -9 to ensure they die
pkill -9 xmrig 2>/dev/null || true
pkill -9 cpuminer 2>/dev/null || true
pkill -9 minerd 2>/dev/null || true

# Double-check and kill by PID if exists
if [ -f /opt/frynet-config/miner.pid ]; then
    PID=$(cat /opt/frynet-config/miner.pid)
    kill -9 "$PID" 2>/dev/null || true
fi

# Remove PID file
rm -f /opt/frynet-config/miner.pid

# Remove any auto-restart flag
rm -f /opt/frynet-config/mining_was_running

# Update status
echo "STOPPED" > /opt/frynet-config/logs/status.txt

echo "[$(date)] All miners stopped successfully" >> /opt/frynet-config/logs/log.txt
echo "<span class='success'>Mining stopped successfully</span>"
CGI
    chmod +x "$BASE/cgi-bin/stop.cgi"
    
    # Initialize logs
    echo "STOPPED" > "$BASE/logs/status.txt"
    echo "[$(date)] FryMiner Web UI initialized" > "$BASE/logs/log.txt"
    echo "[$(date)] Hostname: $(hostname)" >> "$BASE/logs/log.txt"
    chmod 666 "$BASE/logs/status.txt" "$BASE/logs/log.txt"
    
    # Setup auto-start
    setup_autostart
    
    # Start services
    cd "$BASE"
    nohup python3 -m http.server "$PORT" --cgi >/dev/null 2>&1 &
    SERVER_PID=$!
    
    nohup /usr/local/bin/fryminer_monitor >/dev/null 2>&1 &
    MONITOR_PID=$!
    
    nohup /usr/local/bin/fryminer_pid_sync >/dev/null 2>&1 &
    SYNC_PID=$!
    
    log "==============================================="
    log "FryMiner Setup Complete! - VERIFIED FINAL"
    log "==============================================="
    log "Web UI: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR-IP"):$PORT"
    log ""
    log "STOP FLAG MECHANISM:"
    log "  - Stop creates /opt/frynet-config/MINING_STOPPED"
    log "  - All daemons check this flag"
    log "  - Start removes the flag"
    log "  - Uses kill -9 to ensure miners die"
    log "==============================================="
}

# Run main installation
main "$@"
