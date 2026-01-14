# Hytale Server Docker

[![Build and Push Docker Image](https://github.com/JPyke3/hytale-server/actions/workflows/docker-build.yml/badge.svg)](https://github.com/JPyke3/hytale-server/actions/workflows/docker-build.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/jpyke3/hytale-server)](https://hub.docker.com/r/jpyke3/hytale-server)

A Docker-based Hytale dedicated server with ARM64/AMD64 support and Lazytainer integration for automatic idle shutdown.

## Features

- **Auto-Updates**: Automatically downloads new game versions on container startup (works on ARM64 via QEMU emulation)
- **Multi-Architecture**: Native ARM64 and AMD64 support (Apple Silicon, Raspberry Pi, AWS Graviton, x86 servers)
- **Lazytainer Integration**: Automatically stops when idle, restarts on connection (saves RAM)
- **Java 25**: Uses official Adoptium Temurin JRE
- **Non-root**: Runs as unprivileged user for security
- **AOT Cache**: Faster startup when HytaleServer.aot is provided

## Quick Start

### 1. Pull the Image

```bash
docker pull jpyke3/hytale-server:latest
```

### 2. Authenticate with Hytale (one-time setup)

Game files require authentication. Run the downloader once to save credentials:

```bash
mkdir -p data

# Download the Hytale Downloader
curl -sL https://downloader.hytale.com/hytale-downloader.zip -o data/downloader.zip
unzip data/downloader.zip -d data/

# Run the downloader to authenticate (follow the browser prompt)
# On Linux:
chmod +x data/hytale-downloader-linux-amd64
./data/hytale-downloader-linux-amd64

# On macOS (via Docker, since no native binary):
docker run -it --rm --platform linux/amd64 -v "$(pwd)/data:/data" -w /data debian:bookworm-slim \
  bash -c 'apt-get update && apt-get install -y ca-certificates && chmod +x hytale-downloader-linux-amd64 && ./hytale-downloader-linux-amd64'
```

This creates `data/.hytale-downloader-credentials.json` - the container will use this to auto-download game files.

### 3. Create docker-compose.yml

```yaml
services:
  lazytainer:
    image: ghcr.io/vmorganp/lazytainer:latest
    ports:
      - "5520:5520/udp"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "lazytainer.group.hytale.ports=5520"
      - "lazytainer.group.hytale.sleepMethod=stop"
      - "lazytainer.group.hytale.inactiveTimeout=300"
    restart: unless-stopped
    network_mode: bridge

  hytale:
    image: jpyke3/hytale-server:latest
    container_name: hytale-server
    restart: unless-stopped
    labels:
      - "lazytainer.group=hytale"
    network_mode: service:lazytainer
    depends_on:
      - lazytainer
    environment:
      - JVM_OPTS=-Xms2G -Xmx6G -XX:+UseG1GC
      - AUTO_UPDATE=true
    volumes:
      # Credentials for auto-download
      - ./data/.hytale-downloader-credentials.json:/server/.hytale-downloader-credentials.json:ro
      # Game files (auto-downloaded on first start)
      - ./game:/server/game
      # Persistent data
      - ./universe:/server/universe
      - ./logs:/server/logs
      - ./mods:/server/mods
    stdin_open: true
    tty: true
```

### 4. Start the Server

```bash
docker compose up -d
```

### 5. Authenticate

```bash
docker attach hytale-server
# In console:
/auth login device
# Follow the URL to authenticate
# Then persist credentials:
/auth persistence Encrypted
# Detach: Ctrl+P Ctrl+Q
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JVM_OPTS` | `-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200` | JVM memory and GC settings |
| `AUTO_UPDATE` | `true` | Check for game updates on startup |

### Lazytainer Settings

| Setting | Value | Description |
|---------|-------|-------------|
| `inactiveTimeout` | 300 | Seconds before stopping (5 min) |
| `sleepMethod` | stop | Fully stops container to free RAM |
| `minPacketThreshold` | 30 | Packets needed to wake server |

### Volume Mounts

| Container Path | Description |
|----------------|-------------|
| `/server/game` | Auto-downloaded game files (recommended) |
| `/server/.hytale-downloader-credentials.json` | Credentials for auto-updates |
| `/server/universe` | World saves |
| `/server/logs` | Server logs |
| `/server/mods` | Installed mods |
| `/server/config` | Server configuration |

**Legacy mounts** (if `AUTO_UPDATE=false`):

| Container Path | Description |
|----------------|-------------|
| `/server/HytaleServer.jar` | Server executable |
| `/server/Assets.zip` | Game assets |
| `/server/HytaleServer.aot` | AOT cache for faster startup |

## Network

- **Port**: 5520/UDP (QUIC protocol)
- **Firewall**: Must allow UDP, not TCP
- **Connect**: `your-server-ip:5520`

## Local Build (Alternative)

If you prefer to build locally with game files baked in (personal use only):

```bash
# Clone the repo
git clone https://github.com/JPyke3/hytale-server.git
cd hytale-server

# Download game files to ./game/
# ... (see step 2 above)

# Build and run
docker compose -f docker-compose.local.yml up -d
```

## Auto-Updates

The container automatically checks for and downloads new Hytale game versions on startup.

### How It Works

On every container start:
1. Checks the Hytale servers for the latest available version
2. Compares with the currently installed version (stored in `game/.current-version`)
3. Downloads and extracts new files if an update is available (~1.4GB)
4. Keeps one backup of the previous version
5. Starts the game server

### ARM64 Support

Auto-updates work on ARM64 (Apple Silicon, Raspberry Pi, AWS Graviton) via QEMU emulation. The container includes `qemu-user-static` which runs the x86-64 Hytale downloader binary transparently. No additional configuration needed.

### Disable Auto-Updates

To manage game files manually:

```yaml
environment:
  - AUTO_UPDATE=false
```

Then mount game files directly (legacy mode):
```yaml
volumes:
  - ./game/Server/HytaleServer.jar:/server/HytaleServer.jar:ro
  - ./game/Server/HytaleServer.aot:/server/HytaleServer.aot:ro
  - ./game/Assets.zip:/server/Assets.zip:ro
```

## Manual Updates (Legacy)

If auto-updates are disabled, update manually:

```bash
# Pull latest image
docker compose pull

# Download new game files
./hytale-downloader-linux-amd64
unzip -o *.zip -d game/

# Restart
docker compose up -d
```

## Requirements

- Docker with Compose v2
- 4GB+ RAM (8GB recommended)
- Hytale game license for authentication
- UDP port 5520 open/forwarded

## Based On

- [Official Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
- [Lazytainer](https://github.com/vmorganp/Lazytainer)

## License

The Dockerfile and configuration are MIT licensed. Hytale game files are subject to Hypixel Studios' terms of service and cannot be redistributed.
