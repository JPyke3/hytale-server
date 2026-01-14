# Hytale Server Docker

A lightweight base image for running Hytale dedicated servers. Supports **AMD64** and **ARM64** (Apple Silicon, Raspberry Pi, AWS Graviton).

## Quick Start

```bash
# 1. Create project directory
mkdir hytale-server && cd hytale-server

# 2. Download game files (requires Hytale account)
curl -sL https://downloader.hytale.com/hytale-downloader.zip -o downloader.zip
unzip downloader.zip
./hytale-downloader-linux-amd64  # Follow browser auth prompt
unzip *.zip -d game/

# 3. Create docker-compose.yml (see below)

# 4. Start the server
docker compose up -d

# 5. Authenticate
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
    volumes:
      - ./game/Server/HytaleServer.jar:/server/HytaleServer.jar:ro
      - ./game/Server/HytaleServer.aot:/server/HytaleServer.aot:ro
      - ./game/Assets.zip:/server/Assets.zip:ro
      - ./universe:/server/universe
      - ./logs:/server/logs
    stdin_open: true
    tty: true
```

## Features

- ☕ **Java 25** - Adoptium Temurin JRE
- 🔒 **Non-root** - Runs as unprivileged user
- ⚡ **AOT Cache** - Faster startup with HytaleServer.aot
- 🏗️ **Multi-arch** - AMD64 + ARM64 native builds

## Why Base Image?

Hytale game files require authentication to download and cannot be redistributed. This image provides the runtime environment - you download the game files separately with your Hytale account.

## Network

- **Port**: 5520/UDP (QUIC protocol)
- **Connect**: `your-server-ip:5520`

## Links

- 📖 [Full Documentation](https://github.com/JPyke3/hytale-server)
- 🐛 [Issues](https://github.com/JPyke3/hytale-server/issues)
- 📋 [Official Hytale Server Manual](https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual)
