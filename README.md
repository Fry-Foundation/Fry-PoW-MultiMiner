# Fry-PoW-MultiMiner

A multi-cryptocurrency CPU mining setup tool with a web-based interface for easy configuration and monitoring.

## What is this?

FryMiner is a comprehensive setup script that installs and configures CPU mining software for **35+ cryptocurrencies** on Linux, macOS, and Windows. It features a web-based control panel accessible via your browser, making it easy to configure, monitor, and manage your mining operations without command-line expertise.

## Features

- **Web-based Interface**: Control panel at port 8080 for easy configuration and monitoring
- **35+ Supported Coins**: Mine popular cryptocurrencies using your CPU
- **Cross-Platform**: Supports Linux, macOS (Apple Silicon & Intel), and Windows
- **Multi-Architecture Support**: Works on x86_64, ARM64, ARMv7, ARMv6, RISC-V, MIPS, PowerPC, and more
- **Multiple Mining Software**: XMRig, XLArig (Scala), cpuminer-multi, ccminer-verus (Verus)
- **GPU Mining Support** (Linux): SRBMiner-MULTI, lolMiner, T-Rex for GPU-mineable coins
- **USB ASIC Support** (Linux): BFGMiner for Block Erupters, GekkoScience devices
- **Solo Lottery Mining**: 17 coins via solopool.org with merged mining support (LTC+DOGE)
- **Unmineable Proxy Mining**: Mine 19 non-CPU-mineable tokens (SHIB, ADA, SOL, etc.) via RandomX
- **Automatic Updates**: Daily automatic updates from GitHub (cron on Linux, launchd on macOS, Task Scheduler on Windows)
- **Mining Optimizations**: Automatic huge pages, MSR configuration, and CPU governor tuning (Linux)
- **Real-time Monitoring**: View logs, hashrate, shares, and uptime from the web interface
- **Version Tracking**: Automatic version management for seamless updates

## Supported Cryptocurrencies

### Popular Coins
- Bitcoin (BTC) - SHA256d
- Litecoin (LTC) - Scrypt
- Dogecoin (DOGE) - Scrypt
- Monero (XMR) - RandomX

### CPU Mineable
- Scala (XLA) - Panthera
- Verus (VRSC) - VerusHash
- Aeon (AEON) - K12
- Dero (DERO) - AstroBWT
- Zephyr (ZEPH) - RandomX
- Salvium (SAL) - RandomX
- Yadacoin (YDA) - RandomX
- Arionum (ARO) - Argon2

### Other Mineable
- Dash (DASH) - X11
- Decred (DCR) - Blake
- Kadena (KDA) - Blake2s
- Bitcoin Cash (BCH) - SHA256d

### Solo Lottery Mining (solopool.org)
- Bitcoin (BTC), Bitcoin Cash (BCH), Litecoin (LTC), Dogecoin (DOGE)
- Monero (XMR), Zephyr (ZEPH)
- Ethereum Classic (ETC), EthereumPoW (ETHW), Kaspa (KAS)
- Ergo (ERG), Ravencoin (RVN), DigiByte (DGB)
- eCash (XEC), Fractal Bitcoin (FB), Bitcoin II (BC2)
- Xelis (XEL), OctaSpace (OCTA)

### Unmineable Coins (via proxy mining)
- SHIB, ADA, SOL, ZEC, ETC, RVN, TRX, VET, XRP, DOT, MATIC, ATOM, LINK, XLM, ALGO, AVAX, NEAR, FTM, ONE

## Installation

### Linux

```bash
# Download the setup script
wget https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_web.sh

# Make it executable
chmod +x setup_fryminer_web.sh

# Run as root
sudo ./setup_fryminer_web.sh
```

After installation, access the web interface at `http://YOUR_IP:8080`

### macOS (Apple Silicon & Intel)

```bash
# Download the macOS setup script
curl -O https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_macos.sh

# Make it executable
chmod +x setup_fryminer_macos.sh

# Run (will install Homebrew if needed)
./setup_fryminer_macos.sh
```

After installation, access the web interface at `http://localhost:8080`

### Windows (PowerShell)

```powershell
# Download the setup script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_web.ps1" -OutFile "setup_fryminer_web.ps1"

# Run as Administrator
powershell -ExecutionPolicy Bypass -File setup_fryminer_web.ps1
```

After installation, access the web interface at `http://localhost:8080`

## Mining Software Installed

| Software | Purpose | Platforms |
|----------|---------|-----------|
| XMRig | RandomX, AstroBWT mining | Linux, macOS, Windows |
| XLArig | Scala (Panthera) mining | Linux, macOS, Windows |
| cpuminer-multi | SHA256d, Scrypt, X11, Blake mining | Linux, macOS, Windows |
| ccminer-verus | Verus (VerusHash) mining | Linux, macOS, Windows |
| SRBMiner-MULTI | GPU mining (multiple algorithms) | Linux |
| lolMiner | GPU mining (Ethash, Etchash) | Linux |
| T-Rex | GPU mining (KAWPOW, Ethash) | Linux |
| BFGMiner | USB ASIC mining | Linux |

## Dev Fee Disclosure

FryMiner includes a **2% dev fee** to support continued development and maintenance. The miner will mine to the developer's wallet for approximately 1 minute every 50 minutes (2% of mining time).

For RandomX-based coins (XMR, Zephyr, Salvium, Yadacoin, Aeon, Unmineable), the dev fee is routed through Scala mining for better consolidation.

## Requirements

### Linux
- Root/sudo access
- Internet connection
- CPU with mining capability
- Python 3 (for web server)

### macOS
- macOS with Apple Silicon (arm64) or Intel (x86_64)
- Homebrew (installed automatically if missing)
- Internet connection

### Windows
- Windows 10/11
- Administrator privileges
- Python 3 (for web server)
- PowerShell 5.1+

## License

Open source software for the cryptocurrency mining community.
