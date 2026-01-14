#!/bin/bash
# One-time script to get OAuth refresh token for server authentication
# This implements the Device Code Flow from the Server Provider Authentication Guide
#
# Usage: ./get-server-token.sh
# After running, complete the authorization in your browser.
# The refresh token will be saved to data/.hytale-server-credentials.json

set -e

CREDS_FILE="./data/.hytale-server-credentials.json"

echo "=== Hytale Server Authentication Setup ==="
echo ""
echo "This will get an OAuth refresh token for automatic server authentication."
echo "You only need to do this once - the token lasts 30 days and auto-refreshes."
echo ""

# Step 1: Request device code
echo "Requesting device authorization code..."
DEVICE_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/device/auth" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=hytale-server" \
    -d "scope=openid offline auth:server")

DEVICE_CODE=$(echo "$DEVICE_RESPONSE" | grep -o '"device_code":"[^"]*"' | cut -d'"' -f4)
USER_CODE=$(echo "$DEVICE_RESPONSE" | grep -o '"user_code":"[^"]*"' | cut -d'"' -f4)
VERIFY_URL=$(echo "$DEVICE_RESPONSE" | grep -o '"verification_uri_complete":"[^"]*"' | cut -d'"' -f4)
INTERVAL=$(echo "$DEVICE_RESPONSE" | grep -o '"interval":[0-9]*' | cut -d':' -f2)

if [ -z "$DEVICE_CODE" ]; then
    echo "Error: Failed to get device code"
    echo "Response: $DEVICE_RESPONSE"
    exit 1
fi

echo ""
echo "==================================================================="
echo "DEVICE AUTHORIZATION"
echo "==================================================================="
echo "Visit: $VERIFY_URL"
echo "Or go to: https://accounts.hytale.com/device"
echo "Enter code: $USER_CODE"
echo "==================================================================="
echo ""
echo "Waiting for authorization..."

# Step 2: Poll for token
while true; do
    sleep "${INTERVAL:-5}"

    TOKEN_RESPONSE=$(curl -s -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=hytale-server" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
        -d "device_code=$DEVICE_CODE")

    if echo "$TOKEN_RESPONSE" | grep -q '"access_token"'; then
        break
    fi

    if echo "$TOKEN_RESPONSE" | grep -q '"authorization_pending"'; then
        echo -n "."
        continue
    fi

    echo ""
    echo "Error: $TOKEN_RESPONSE"
    exit 1
done

echo ""
echo "Authorization successful!"

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)

# Step 3: Get profile UUID
echo "Fetching game profiles..."
PROFILES_RESPONSE=$(curl -s -X GET "https://account-data.hytale.com/my-account/get-profiles" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

PROFILE_UUID=$(echo "$PROFILES_RESPONSE" | grep -o '"uuid":"[^"]*"' | head -1 | cut -d'"' -f4)
PROFILE_NAME=$(echo "$PROFILES_RESPONSE" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$PROFILE_UUID" ]; then
    echo "Error: Failed to get profile"
    echo "Response: $PROFILES_RESPONSE"
    exit 1
fi

echo "Profile: $PROFILE_NAME ($PROFILE_UUID)"

# Step 4: Save credentials
mkdir -p ./data
echo "{\"refresh_token\":\"$REFRESH_TOKEN\",\"profile_uuid\":\"$PROFILE_UUID\"}" > "$CREDS_FILE"
chmod 600 "$CREDS_FILE"

echo ""
echo "==================================================================="
echo "SUCCESS!"
echo "==================================================================="
echo "Credentials saved to: $CREDS_FILE"
echo ""
echo "Your server will now automatically authenticate on startup."
echo "The refresh token is valid for 30 days and will be auto-renewed."
echo ""
echo "You can now start your server with: docker compose up -d"
