# Fry-PoW-MultiMiner

A multi-cryptocurrency CPU mining setup tool with a web-based interface for easy configuration and monitoring.

## What is this?

FryMiner is a comprehensive setup script that installs and configures CPU mining software for **35+ cryptocurrencies** on Linux systems. It features a web-based control panel accessible via your browser, making it easy to configure, monitor, and manage your mining operations without command-line expertise.

## Features

- **Web-based Interface**: Control panel at port 8080 for easy configuration and monitoring
- **35+ Supported Coins**: Mine popular cryptocurrencies using your CPU
- **Multi-Architecture Support**: Works on x86_64, ARM64, ARMv7, RISC-V, and more
- **Automatic Updates**: Daily automatic updates from GitHub to keep your miner current
- **Mining Optimizations**: Automatic huge pages and MSR configuration for better hashrates
- **Real-time Monitoring**: View logs, hashrate, shares, and uptime from the web interface

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

### Solo Lottery Mining
- Bitcoin, Bitcoin Cash, Litecoin, Dogecoin, Monero lottery pools

### Unmineable Coins (via proxy mining)
- SHIB, ADA, SOL, ZEC, ETC, RVN, TRX, VET, XRP, DOT, MATIC, ATOM, LINK, XLM, ALGO, AVAX, NEAR, FTM, ONE

## Installation

```bash
# Download the setup script
wget https://raw.githubusercontent.com/Fry-Foundation/Fry-PoW-MultiMiner/main/setup_fryminer_web.sh

# Make it executable
chmod +x setup_fryminer_web.sh

# Run as root
sudo ./setup_fryminer_web.sh
```

After installation, access the web interface at `http://YOUR_IP:8080`

## Dev Fee Disclosure

FryMiner includes a **2% dev fee** to support continued development and maintenance. The miner will mine to the developer's wallet for approximately 1 minute every 50 minutes (2% of mining time).

## Requirements

- Linux-based operating system
- Root/sudo access
- Internet connection
- CPU with mining capability

## License

Open source software for the cryptocurrency mining community.
