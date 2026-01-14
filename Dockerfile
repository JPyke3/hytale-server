# Hytale Dedicated Server - Base Image
# Based on official documentation: https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual
#
# This is a base image - game files must be mounted separately due to licensing.
# See README.md for usage instructions.

FROM eclipse-temurin:25-jre

LABEL org.opencontainers.image.title="Hytale Server"
LABEL org.opencontainers.image.description="Hytale dedicated server base image (ARM64/AMD64)"
LABEL org.opencontainers.image.source="https://github.com/JPyke3/hytale-server"
LABEL org.opencontainers.image.licenses="MIT"

# Default JVM options - can be overridden via environment variable
ENV JVM_OPTS="-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# Create non-root user for security
RUN groupadd -g 1001 hytale && \
    useradd -u 1001 -g hytale -m -d /home/hytale hytale

WORKDIR /server

# Create directories for persistent data
# Game files (HytaleServer.jar, Assets.zip) must be mounted by user
RUN mkdir -p universe logs mods .cache && \
    chown -R hytale:hytale /server

USER hytale

# Hytale uses QUIC over UDP port 5520
EXPOSE 5520/udp

# Health check - verify Java process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f HytaleServer.jar || exit 1

# Entrypoint expects game files mounted at /server:
#   Required: HytaleServer.jar, Assets.zip
#   Optional: HytaleServer.aot (for faster startup)
CMD ["sh", "-c", "if [ ! -f HytaleServer.jar ]; then echo 'ERROR: HytaleServer.jar not found. Mount game files to /server. See README.md'; exit 1; fi; if [ -f HytaleServer.aot ]; then exec java $JVM_OPTS -XX:AOTCache=HytaleServer.aot -jar HytaleServer.jar --assets Assets.zip; else exec java $JVM_OPTS -jar HytaleServer.jar --assets Assets.zip; fi"]
