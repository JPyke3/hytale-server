# Hytale Dedicated Server
# Based on official documentation: https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual

FROM eclipse-temurin:25-jre

LABEL org.opencontainers.image.title="Hytale Server"
LABEL org.opencontainers.image.description="Hytale dedicated server with ARM64 support"
LABEL org.opencontainers.image.source="https://github.com/jacobpyke/hytale-server"

# Default JVM options - can be overridden via environment variable
ENV JVM_OPTS="-Xms2G -Xmx6G -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# Create non-root user for security (use different GID to avoid conflicts)
RUN groupadd -g 1001 hytale && \
    useradd -u 1001 -g hytale -m -d /home/hytale hytale

WORKDIR /server

# Copy server files (from build context)
COPY --chown=hytale:hytale Server/HytaleServer.jar ./
COPY --chown=hytale:hytale Server/HytaleServer.aot ./
COPY --chown=hytale:hytale Assets.zip ./

# Create directories for persistent data
RUN mkdir -p universe logs mods .cache && \
    chown -R hytale:hytale /server

USER hytale

# Hytale uses QUIC over UDP port 5520
EXPOSE 5520/udp

# Health check - verify Java process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f HytaleServer.jar || exit 1

# Start server with AOT cache for faster boot
CMD ["sh", "-c", "exec java $JVM_OPTS -XX:AOTCache=HytaleServer.aot -jar HytaleServer.jar --assets Assets.zip"]
