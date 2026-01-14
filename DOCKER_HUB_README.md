# Hytale Server Docker

A Docker image for running Hytale dedicated servers with **automatic game updates**. Supports **AMD64** and **ARM64** (Apple Silicon, Raspberry Pi, AWS Graviton).

## Features

- **Auto-Updates** - Automatically downloads new game versions on startup
- **ARM64 Native** - Full ARM64 support with QEMU emulation for the downloader
- **Java 25** - Adoptium Temurin JRE
- **Non-root** - Runs as unprivileged user for security
- **Lazytainer Ready** - Works with Lazytainer for auto-idle

## Quick Start (with Auto-Updates)

```bash
# 1. Create project directory
mkdir hytale-server && cd hytale-server
mkdir -p data game

# 2. Download and run the Hytale Downloader once to authenticate
curl -sL https://downloader.hytale.com/hytale-downloader.zip -o data/downloader.zip
unzip data/downloader.zip -d data/
chmod +x data/hytale-downloader-linux-amd64
./data/hytale-downloader-linux-amd64  # Follow browser auth prompt

# 3. Create docker-compose.yml (see below)

# 4. Start the server (auto-downloads game files)
docker compose up -d

# 5. Authenticate the server
docker attach hytale-server
# Run: /auth login device
# Run: /auth persistence Encrypted
# Detach: Ctrl+P Ctrl+Q
```

## docker-compose.yml

```yaml
services:
  hytale:
    image: jpyke3/hytale-server:latest
    container_name: hytale-server
    restart: unless-stopped
    ports:
      - "5520:5520/udp"
    environment:
      - JVM_OPTS=-Xms2G -Xmx6G -XX:+UseG1GC
      - AUTO_UPDATE=true
    volumes:
      # Credentials for auto-download
      - ./data/.hytale-downloader-credentials.json:/server/.hytale-downloader-credentials.json:ro
      # Game files (auto-downloaded)
      - ./game:/server/game
      # Persistent data
      - ./universe:/server/universe
      - ./logs:/server/logs
    stdin_open: true
    tty: true
```

## How Auto-Updates Work

On every container start:
1. Checks Hytale servers for the latest version
2. Compares with installed version (`game/.current-version`)
3. Downloads new files if update available (~1.4GB)
4. Keeps one backup of previous version
5. Starts the game server

**ARM64**: Uses QEMU to run the x86-64 downloader - no additional config needed.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JVM_OPTS` | `-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200` | JVM memory settings |
| `AUTO_UPDATE` | `true` | Check for game updates on startup |

## Volume Mounts

| Path | Description |
|------|-------------|
| `/server/.hytale-downloader-credentials.json` | Credentials for auto-updates |
| `/server/game` | Game files (auto-downloaded) |
| `/server/universe` | World saves |
| `/server/logs` | Server logs |
| `/server/mods` | Installed mods |

## Network

- **Port**: 5520/UDP (QUIC protocol)
- **Connect**: `your-server-ip:5520`

## Why Credentials Required?

Hytale game files require authentication to download and cannot be redistributed. You authenticate once with your Hytale account, and the container uses saved credentials to auto-download updates.

## Links

- [Full Documentation](https://github.com/JPyke3/hytale-server)
- [Issues](https://github.com/JPyke3/hytale-server/issues)
- [Official Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
