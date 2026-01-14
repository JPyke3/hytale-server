# Hytale Server Docker

A Docker-based Hytale dedicated server with ARM64 support and Lazytainer integration for automatic idle shutdown.

## Features

- **ARM64 Native**: Runs natively on Apple Silicon and ARM servers
- **Lazytainer Integration**: Automatically stops when idle, restarts on connection
- **Java 25**: Uses official Adoptium Temurin JRE
- **Persistent Data**: Universe, logs, mods, and config survive container rebuilds
- **AOT Cache**: Faster startup using ahead-of-time compilation when available

## Requirements

- Docker with Compose v2
- 4GB+ RAM (8GB recommended)
- Hytale game license for authentication
- UDP port 5520 open/forwarded

## Quick Start

### 1. Download Game Files

Use the official Hytale Downloader CLI:

```bash
# Download the downloader
curl -sL https://downloader.hytale.com/hytale-downloader.zip -o hytale-downloader.zip
unzip hytale-downloader.zip

# Run it (requires browser authentication)
# On Linux:
./hytale-downloader-linux-amd64

# On macOS (via Docker):
docker run -it --rm --platform linux/amd64 -v "$(pwd):/data" -w /data debian:bookworm-slim \
  bash -c 'chmod +x hytale-downloader-linux-amd64 && ./hytale-downloader-linux-amd64'

# Extract to game directory
unzip *.zip -d game/
```

### 2. Generate machine-id (macOS)

```bash
ioreg -rd1 -c IOPlatformExpertDevice | grep IOPlatformUUID | \
  awk -F'"' '{print $4}' | tr -d '-' | tr '[:upper:]' '[:lower:]' > machine-id
```

Or on Linux, just use `/etc/machine-id`.

### 3. Start the Server

```bash
docker compose build
docker compose up -d
```

### 4. Authenticate

```bash
docker attach hytale-server
# In console: /auth login device
# Follow the URL to authenticate
# Detach: Ctrl+P Ctrl+Q
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JVM_OPTS` | `-Xms2G -Xmx6G -XX:+UseG1GC` | JVM memory and GC settings |

### Lazytainer Settings

| Setting | Value | Description |
|---------|-------|-------------|
| `inactiveTimeout` | 300 | Seconds before stopping (5 min) |
| `sleepMethod` | stop | Fully stops container to free RAM |
| `minPacketThreshold` | 30 | Packets needed to wake server |

## Network

- **Port**: 5520/UDP (QUIC protocol)
- **Firewall**: Must allow UDP, not TCP
- **Connect**: `your-server-ip:5520`

## File Structure

```
Hytale-Server/
├── Dockerfile
├── docker-compose.yml
├── game/               # Game files (Server/, Assets.zip)
├── universe/           # World saves
├── logs/               # Server logs
├── mods/               # Installed mods
├── config/             # Configuration files
└── machine-id          # Device ID for auth persistence
```

## Updating

```bash
# Download new game files
./hytale-downloader-linux-amd64
unzip -o *.zip -d game/

# Rebuild and restart
docker compose build --no-cache
docker compose up -d
```

## Based On

- [Official Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
- [Lazytainer](https://github.com/vmorganp/Lazytainer)

## License

The Dockerfile and configuration are MIT licensed. Hytale game files are subject to Hypixel Studios' terms of service.
