# Hytale Dedicated Server - Auto-Updating Image
# Based on official documentation: https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual
#
# Features:
#   - Auto-updates game files on startup when new versions are released
#   - Falls back to mounted game files if no credentials provided
#   - See README.md for usage instructions.

FROM eclipse-temurin:25-jre

LABEL org.opencontainers.image.title="Hytale Server"
LABEL org.opencontainers.image.description="Hytale dedicated server with auto-update (ARM64/AMD64)"
LABEL org.opencontainers.image.source="https://github.com/JPyke3/hytale-server"
LABEL org.opencontainers.image.licenses="MIT"

# Default JVM options - can be overridden via environment variable
ENV JVM_OPTS="-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
# Auto-update on startup (set to "false" to disable)
ENV AUTO_UPDATE="true"

# Install dependencies for auto-update
RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Download hytale-downloader for auto-updates
# Note: Only linux-amd64 binary available, runs via emulation on ARM64
ADD https://downloader.hytale.com/hytale-downloader.zip /tmp/downloader.zip
RUN unzip /tmp/downloader.zip -d /tmp && \
    mv /tmp/hytale-downloader-linux-amd64 /opt/hytale-downloader && \
    chmod +x /opt/hytale-downloader && \
    rm -rf /tmp/downloader.zip /tmp/*.exe /tmp/*.md

# Create non-root user for security
RUN groupadd -g 1001 hytale && \
    useradd -u 1001 -g hytale -m -d /home/hytale hytale

WORKDIR /server

# Create directories for persistent data
RUN mkdir -p universe logs mods config game .cache && \
    chown -R hytale:hytale /server

# Copy entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

USER hytale

# Hytale uses QUIC over UDP port 5520
EXPOSE 5520/udp

# Health check - verify Java process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f HytaleServer.jar || exit 1

# Entrypoint handles:
#   - Checking for game updates (if credentials provided)
#   - Downloading new versions automatically
#   - Starting the server
ENTRYPOINT ["/entrypoint.sh"]
