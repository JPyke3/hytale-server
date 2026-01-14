#!/bin/bash
set -e

GAME_DIR="/server/game"
VERSION_FILE="/server/game/.current-version"
DOWNLOADER_BIN="/opt/hytale-downloader"
CREDENTIALS_INPUT="/server/.hytale-downloader-credentials.json"
CREDENTIALS_WORK="/tmp/.hytale-downloader-credentials.json"

# Use qemu for x86-64 emulation on ARM64
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    DOWNLOADER="qemu-x86_64-static $DOWNLOADER_BIN"
else
    DOWNLOADER="$DOWNLOADER_BIN"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Server auth credentials file (stores OAuth refresh token with auth:server scope)
SERVER_AUTH_FILE="/server/.hytale-server-credentials.json"

# Authenticate server using stored OAuth refresh token
# This implements the GSP token passthrough method
authenticate_server() {
    if [ ! -f "$SERVER_AUTH_FILE" ]; then
        log_warn "=========================================="
        log_warn "FIRST-TIME SETUP REQUIRED"
        log_warn "=========================================="
        log_warn "No server credentials found."
        log_warn "To enable automatic authentication:"
        log_warn "  1. Run ./get-server-token.sh on the host"
        log_warn "  2. Restart the container"
        log_warn ""
        log_warn "Or authenticate manually after startup:"
        log_warn "  docker attach hytale-server"
        log_warn "  /auth login device"
        log_warn "=========================================="
        return 1
    fi

    log_info "Authenticating server using stored credentials..."

    # Read stored credentials
    REFRESH_TOKEN=$(cat "$SERVER_AUTH_FILE" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)
    PROFILE_UUID=$(cat "$SERVER_AUTH_FILE" | grep -o '"profile_uuid":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$REFRESH_TOKEN" ]; then
        log_error "No refresh token found in credentials file"
        return 1
    fi

    # Step 1: Refresh OAuth access token
    log_info "  Refreshing OAuth access token..."
    TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=hytale-server" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=$REFRESH_TOKEN" 2>/dev/null)

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    NEW_REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$ACCESS_TOKEN" ]; then
        log_error "Failed to refresh access token"
        log_error "Response: $TOKEN_RESPONSE"
        return 1
    fi

    # Update stored refresh token if we got a new one
    if [ -n "$NEW_REFRESH_TOKEN" ]; then
        log_info "  Updating stored refresh token..."
        echo "{\"refresh_token\":\"$NEW_REFRESH_TOKEN\",\"profile_uuid\":\"$PROFILE_UUID\"}" > "$SERVER_AUTH_FILE" 2>/dev/null || true
    fi

    # Step 2: Get profile UUID if not stored
    if [ -z "$PROFILE_UUID" ]; then
        log_info "  Fetching game profiles..."
        PROFILES_RESPONSE=$(curl -s -X GET "https://account-data.hytale.com/my-account/get-profiles" \
            -H "Authorization: Bearer $ACCESS_TOKEN" 2>/dev/null)

        PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | grep -o '"uuid":"[^"]*"' | head -1 | cut -d'"' -f4)

        if [ -z "$PROFILE_UUID" ]; then
            log_error "Failed to get game profile"
            log_error "Response: $PROFILES_RESPONSE"
            return 1
        fi

        # Save profile UUID
        echo "{\"refresh_token\":\"${NEW_REFRESH_TOKEN:-$REFRESH_TOKEN}\",\"profile_uuid\":\"$PROFILE_UUID\"}" > "$SERVER_AUTH_FILE" 2>/dev/null || true
    fi

    log_info "  Profile UUID: $PROFILE_UUID"

    # Step 3: Create game session
    log_info "  Creating game session..."
    SESSION_RESPONSE=$(curl -s -X POST "https://sessions.hytale.com/game-session/new" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"$PROFILE_UUID\"}" 2>/dev/null)

    export HYTALE_SERVER_SESSION_TOKEN=$(echo "$SESSION_RESPONSE" | grep -o '"sessionToken":"[^"]*"' | cut -d'"' -f4)
    export HYTALE_SERVER_IDENTITY_TOKEN=$(echo "$SESSION_RESPONSE" | grep -o '"identityToken":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$HYTALE_SERVER_SESSION_TOKEN" ] || [ -z "$HYTALE_SERVER_IDENTITY_TOKEN" ]; then
        log_error "Failed to create game session"
        log_error "Response: $SESSION_RESPONSE"
        return 1
    fi

    log_info "  Game session created successfully!"
    return 0
}

# Check if auto-update is enabled (default: true)
AUTO_UPDATE="${AUTO_UPDATE:-true}"

check_and_update() {
    if [ "$AUTO_UPDATE" != "true" ]; then
        log_info "Auto-update disabled (AUTO_UPDATE=$AUTO_UPDATE)"
        return 0
    fi

    if [ ! -f "$CREDENTIALS_INPUT" ]; then
        log_warn "No credentials file found at $CREDENTIALS_INPUT"
        log_warn "Skipping update check - run downloader manually first to authenticate"
        return 0
    fi

    # Copy credentials to writable location (downloader updates tokens)
    cp "$CREDENTIALS_INPUT" "$CREDENTIALS_WORK"
    cd /tmp  # Downloader looks for credentials in current directory

    log_info "Checking for Hytale server updates..."

    # Get available version from server
    AVAILABLE_VERSION=$($DOWNLOADER -print-version -skip-update-check 2>/dev/null || echo "")

    # Try to save updated credentials back (if source is writable)
    cp "$CREDENTIALS_WORK" "$CREDENTIALS_INPUT" 2>/dev/null || true
    cd /server

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

    # Download new version (run from /tmp where credentials are)
    cd /tmp
    if $DOWNLOADER -download-path "$DOWNLOAD_PATH" -skip-update-check; then
        # Save updated credentials back if possible
        cp "$CREDENTIALS_WORK" "$CREDENTIALS_INPUT" 2>/dev/null || true
        cd /server
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
        cd /server
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

# Attempt automatic authentication using stored credentials
# This uses the GSP token passthrough method from the Server Provider Authentication Guide
authenticate_server

# Build extra arguments array (tokens are passed via environment variables automatically)

# Start server with or without AOT cache
if [ -f "$SERVER_AOT" ]; then
    log_info "  AOT: $SERVER_AOT (faster startup)"
    exec java $JVM_OPTS -XX:AOTCache="$SERVER_AOT" -jar "$SERVER_JAR" --assets "$ASSETS_ZIP" "${EXTRA_ARGS[@]}"
else
    exec java $JVM_OPTS -jar "$SERVER_JAR" --assets "$ASSETS_ZIP" "${EXTRA_ARGS[@]}"
fi
