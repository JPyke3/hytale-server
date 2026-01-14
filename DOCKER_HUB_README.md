# Hytale Server Docker

[![Build and Push Docker Image](https://github.com/JPyke3/hytale-server/actions/workflows/docker-build.yml/badge.svg)](https://github.com/JPyke3/hytale-server/actions/workflows/docker-build.yml)

A Docker image for running Hytale dedicated servers with **automatic game updates** and **automatic authentication**. Supports **AMD64** and **ARM64** (Apple Silicon, Raspberry Pi, AWS Graviton).

## Features

- **Auto-Updates**: Automatically downloads new game versions on container startup
- **Automatic Authentication**: OAuth tokens refresh automatically on startup - no manual login needed after initial setup
- **Multi-Architecture**: Native ARM64 and AMD64 support (Apple Silicon, Raspberry Pi, AWS Graviton, x86 servers)
- **Lazytainer Ready**: Works with Lazytainer for automatic idle shutdown
- **Java 25**: Uses official Adoptium Temurin JRE
- **Non-root**: Runs as unprivileged user for security
- **AOT Cache**: Faster startup when HytaleServer.aot is provided

## Quick Start

### 1. Create Directory Structure

```bash
mkdir -p data universe logs mods game .cache
```

### 2. Get Downloader Credentials (for auto-updates)

Game files require authentication. Run the downloader once to save credentials:

```bash
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

This creates `data/.hytale-downloader-credentials.json` for game file downloads.

### 3. Get Server Authentication (for player connections)

> **Why is this needed?**
>
> Hytale servers must authenticate with Hytale's session service to validate players connecting to your server. Without authentication, players see "Server authentication unavailable" when trying to join.
>
> The `get-server-token.sh` script performs a one-time OAuth login to get a refresh token (valid 30 days, auto-renews). This enables the container to automatically re-authenticate on every restart - no manual `/auth login` needed!

```bash
# Download and run the setup script
curl -sL https://raw.githubusercontent.com/JPyke3/hytale-server/main/get-server-token.sh -o get-server-token.sh
chmod +x get-server-token.sh
./get-server-token.sh
```

Follow the browser prompt to authenticate. This creates `data/.hytale-server-credentials.json`.

### 4. Create docker-compose.yml

```yaml
services:
  hytale:
    image: jpyke3/hytale-server:latest
    container_name: hytale-server
    restart: unless-stopped
    ports:
      - "5520:5520/udp"
    environment:
      - JVM_OPTS=-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200
      - AUTO_UPDATE=true
    volumes:
      # Credentials
      - ./data/.hytale-downloader-credentials.json:/server/.hytale-downloader-credentials.json:ro
      - ./data/.hytale-server-credentials.json:/server/.hytale-server-credentials.json
      # Server configuration (persisted)
      - ./data/config.json:/server/config.json
      - ./data/permissions.json:/server/permissions.json
      - ./data/bans.json:/server/bans.json
      - ./data/whitelist.json:/server/whitelist.json
      # Game files and data
      - ./game:/server/game
      - ./universe:/server/universe
      - ./logs:/server/logs
      - ./mods:/server/mods
      - ./.cache:/server/.cache
    stdin_open: true
    tty: true
    mem_limit: 8g
    mem_reservation: 2g
```

### 5. Create Initial Config Files

```bash
# Create empty config files (server will populate them)
echo '{}' > data/config.json
echo '{"users":{},"groups":{"Default":[],"OP":["*"]}}' > data/permissions.json
echo '[]' > data/bans.json
echo '[]' > data/whitelist.json
```

### 6. Start the Server

```bash
docker compose up -d
```

That's it! The server will:
1. Download game files automatically (first start takes a few minutes)
2. Authenticate using your stored credentials
3. Start accepting player connections

## Authentication

### Two Credential Files

This server uses two separate credential files:

| File | Purpose | Created By |
|------|---------|------------|
| `.hytale-downloader-credentials.json` | Download game files (auto-updates) | Hytale Downloader |
| `.hytale-server-credentials.json` | Authenticate server for player connections | `get-server-token.sh` |

### How Automatic Authentication Works

On every container startup:
1. Entrypoint reads the stored OAuth refresh token
2. Exchanges it for a new access token via Hytale OAuth
3. Creates a game session via the Session Service API
4. Passes session/identity tokens to the server
5. Server accepts player connections

The refresh token is valid for 30 days and auto-renews on each use.

### Manual Authentication (Alternative)

If you prefer not to use `get-server-token.sh`, you can authenticate manually after each container restart:

```bash
docker attach hytale-server
# In console:
/auth login device
# Follow the URL to authenticate
# Detach: Ctrl+P Ctrl+Q
```

Note: This must be done every time the container restarts.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JVM_OPTS` | `-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200` | JVM memory and GC settings |
| `AUTO_UPDATE` | `true` | Check for game updates on startup |

### Volume Mounts

| Host Path | Container Path | Description |
|-----------|----------------|-------------|
| `./data/.hytale-server-credentials.json` | `/server/.hytale-server-credentials.json` | OAuth refresh token for auto-auth |
| `./data/.hytale-downloader-credentials.json` | `/server/.hytale-downloader-credentials.json:ro` | Game download credentials |
| `./data/config.json` | `/server/config.json` | Server configuration |
| `./data/permissions.json` | `/server/permissions.json` | Player permissions (OP, groups) |
| `./data/bans.json` | `/server/bans.json` | Banned players |
| `./data/whitelist.json` | `/server/whitelist.json` | Whitelisted players |
| `./game` | `/server/game` | Game files (auto-downloaded) |
| `./universe` | `/server/universe` | World saves, player data |
| `./logs` | `/server/logs` | Server logs |
| `./mods` | `/server/mods` | Installed mods |
| `./.cache` | `/server/.cache` | Optimized files cache |

## Network

- **Port**: 5520/UDP (QUIC protocol)
- **Firewall**: Must allow UDP, not TCP
- **Connect**: `your-server-ip:5520`

## Troubleshooting

### "Server authentication unavailable" / Players can't connect

The server isn't authenticated. Run `get-server-token.sh` on the host, then restart the container.

Or authenticate manually:
```bash
docker attach hytale-server
/auth login device
# Complete browser auth, then Ctrl+P Ctrl+Q to detach
```

### Lost OP status / Permissions reset

Ensure `permissions.json` is mounted as a volume. Check that `./data/permissions.json` exists on the host.

To restore OP:
```bash
# Edit permissions.json, change your user's group to "OP"
docker compose restart hytale
```

### "Connection Aborted by Peer (0)"

Server authentication failed. Check logs for auth errors:
```bash
docker logs hytale-server | grep -i auth
```

### Refresh token expired (after 30 days of inactivity)

Re-run `get-server-token.sh` to get a new token:
```bash
./get-server-token.sh
docker compose restart hytale
```

## Auto-Updates

The container automatically checks for and downloads new Hytale game versions on startup.

### How It Works

On every container start:
1. Checks the Hytale servers for the latest available version
2. Compares with the currently installed version (stored in `game/.current-version`)
3. Downloads and extracts new files if an update is available (~3.5GB)
4. Keeps one backup of the previous version
5. Starts the game server

### ARM64 Support

Auto-updates work on ARM64 (Apple Silicon, Raspberry Pi, AWS Graviton) via QEMU emulation. The container includes `qemu-user-static` which runs the x86-64 Hytale downloader binary transparently.

### Disable Auto-Updates

```yaml
environment:
  - AUTO_UPDATE=false
```

## With Lazytainer (Auto-Idle)

For automatic idle shutdown, use with [Lazytainer](https://github.com/vmorganp/Lazytainer):

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
      - "lazytainer.group.hytale.minPacketThreshold=2"
      - "lazytainer.group.hytale.pollRate=5"
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
      - JVM_OPTS=-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200
      - AUTO_UPDATE=true
    volumes:
      # Credentials
      - ./data/.hytale-downloader-credentials.json:/server/.hytale-downloader-credentials.json:ro
      - ./data/.hytale-server-credentials.json:/server/.hytale-server-credentials.json
      # Server configuration (persisted)
      - ./data/config.json:/server/config.json
      - ./data/permissions.json:/server/permissions.json
      - ./data/bans.json:/server/bans.json
      - ./data/whitelist.json:/server/whitelist.json
      # Game files and data
      - ./game:/server/game
      - ./universe:/server/universe
      - ./logs:/server/logs
      - ./mods:/server/mods
      - ./.cache:/server/.cache
    stdin_open: true
    tty: true
    mem_limit: 8g
    mem_reservation: 2g
```

## Requirements

- Docker with Compose v2
- 4GB+ RAM (8GB recommended)
- Hytale game license for authentication
- UDP port 5520 open/forwarded

## Links

- [Full Documentation](https://github.com/JPyke3/hytale-server)
- [Issues](https://github.com/JPyke3/hytale-server/issues)
- [Official Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
