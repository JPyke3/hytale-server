#!/bin/bash
set -e

GAME_DIR="/server/game"
VERSION_FILE="/server/.current-version"
DOWNLOADER="/opt/hytale-downloader"
CREDENTIALS_FILE="/server/.hytale-downloader-credentials.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if auto-update is enabled (default: true)
AUTO_UPDATE="${AUTO_UPDATE:-true}"

check_and_update() {
    if [ "$AUTO_UPDATE" != "true" ]; then
        log_info "Auto-update disabled (AUTO_UPDATE=$AUTO_UPDATE)"
        return 0
    fi

    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_warn "No credentials file found at $CREDENTIALS_FILE"
        log_warn "Skipping update check - run downloader manually first to authenticate"
        return 0
    fi

    log_info "Checking for Hytale server updates..."

    # Get available version from server
    AVAILABLE_VERSION=$($DOWNLOADER -print-version -skip-update-check 2>/dev/null || echo "")

    if [ -z "$AVAILABLE_VERSION" ]; then
        log_warn "Could not fetch available version - skipping update"
        return 0
    fi

    log_info "Available version: $AVAILABLE_VERSION"

    # Get current installed version
    CURRENT_VERSION=""
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        log_info "Current version: $CURRENT_VERSION"
    else
        log_info "No version file found - will download game files"
    fi

    # Compare versions
    if [ "$AVAILABLE_VERSION" = "$CURRENT_VERSION" ]; then
        log_info "Already up to date!"
        return 0
    fi

    log_info "New version available! Downloading $AVAILABLE_VERSION..."

    # Create temp directory for download
    TEMP_DIR=$(mktemp -d)
    DOWNLOAD_PATH="$TEMP_DIR/hytale-server.zip"

    # Download new version
    if $DOWNLOADER -download-path "$DOWNLOAD_PATH" -skip-update-check; then
        log_info "Download complete, extracting..."

        # Backup current game files if they exist
        if [ -d "$GAME_DIR" ] && [ -n "$CURRENT_VERSION" ]; then
            log_info "Backing up current version..."
            mv "$GAME_DIR" "$GAME_DIR.backup-$CURRENT_VERSION" 2>/dev/null || true
        fi

        # Extract new files
        mkdir -p "$GAME_DIR"
        unzip -o "$DOWNLOAD_PATH" -d "$GAME_DIR"

        # Save new version
        echo "$AVAILABLE_VERSION" > "$VERSION_FILE"

        # Cleanup
        rm -rf "$TEMP_DIR"

        # Remove old backup after successful update (keep only 1 backup)
        find /server -maxdepth 1 -name "game.backup-*" -type d | sort | head -n -1 | xargs rm -rf 2>/dev/null || true

        log_info "Update complete! Now running version $AVAILABLE_VERSION"
    else
        log_error "Download failed - continuing with existing version"
        rm -rf "$TEMP_DIR"
    fi
}

# Find game files - check both old mount locations and new game directory
find_game_files() {
    # Check new self-contained game directory first
    if [ -f "$GAME_DIR/Server/HytaleServer.jar" ]; then
        SERVER_JAR="$GAME_DIR/Server/HytaleServer.jar"
        SERVER_AOT="$GAME_DIR/Server/HytaleServer.aot"
        ASSETS_ZIP="$GAME_DIR/Assets.zip"
        return 0
    fi

    # Check legacy mount locations (for backwards compatibility)
    if [ -f "/server/HytaleServer.jar" ]; then
        SERVER_JAR="/server/HytaleServer.jar"
        SERVER_AOT="/server/HytaleServer.aot"
        ASSETS_ZIP="/server/Assets.zip"
        return 0
    fi

    return 1
}

# Run update check
check_and_update

# Find game files
if ! find_game_files; then
    log_error "HytaleServer.jar not found!"
    log_error "Either:"
    log_error "  1. Mount game files to /server (legacy mode)"
    log_error "  2. Provide credentials for auto-download at /server/.hytale-downloader-credentials.json"
    exit 1
fi

log_info "Starting Hytale Server..."
log_info "  JAR: $SERVER_JAR"
log_info "  Assets: $ASSETS_ZIP"

# Start server with or without AOT cache
if [ -f "$SERVER_AOT" ]; then
    log_info "  AOT: $SERVER_AOT (faster startup)"
    exec java $JVM_OPTS -XX:AOTCache="$SERVER_AOT" -jar "$SERVER_JAR" --assets "$ASSETS_ZIP"
else
    exec java $JVM_OPTS -jar "$SERVER_JAR" --assets "$ASSETS_ZIP"
fi
