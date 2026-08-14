#!/bin/bash
# =============================================================================
# MikroWizard+ Terminal Gateway — Standalone Production Installer
# =============================================================================
# Pulls and launches the official pre-compiled Docker image from Docker Hub.
# Integrates seamlessly with local or remote MikroWizard backend deployments.
#
# Usage:
#   sudo bash install.sh
#   curl -fsSL https://raw.githubusercontent.com/MikroWizard/mikrowizard-terminal-gateway/main/install.sh | sudo bash
# =============================================================================

set -e

# Color helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[-] Error: Please run as root (use sudo).${NC}"
    exit 1
fi

IMAGE_NAME="mikrowizard/terminal-gateway"
DEFAULT_CONF="/opt/mikrowizard/server-conf.json"
CONF_FILE="$DEFAULT_CONF"
GATEWAY_DIR="/opt/mikrowizard/terminal-gateway"
mkdir -p "$GATEWAY_DIR"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}    MikroWizard+ Terminal Gateway — Installation Wizard     ${NC}"
echo -e "${BLUE}============================================================${NC}"

# Detect local MikroWizard installation
LOCAL=1
if [ ! -f "$CONF_FILE" ]; then
    LOCAL=0
    if [ -t 0 ]; then
        read -p "MikroWizard config not found at $DEFAULT_CONF. Enter path or press Enter for remote host install: " INPUT_CONF
        if [ -n "$INPUT_CONF" ] && [ -f "$INPUT_CONF" ]; then
            CONF_FILE="$INPUT_CONF"
            LOCAL=1
        fi
    fi
fi

if [ "$LOCAL" = "1" ]; then
    echo -e "${GREEN}[+] Local MikroWizard instance detected: $CONF_FILE${NC}"
    REDIS_HOST=$(jq -r '.PYSRV_REDIS_HOST // "127.0.0.1:6379"' "$CONF_FILE" 2>/dev/null || echo "127.0.0.1:6379")
    CRYPT_KEY=$(jq -r '.PYSRV_CRYPT_KEY // ""' "$CONF_FILE" 2>/dev/null || echo "")
    DB_HOST=$(jq -r '.PYSRV_DATABASE_HOST // "127.0.0.1"' "$CONF_FILE" 2>/dev/null || echo "127.0.0.1")
    DB_PORT=$(jq -r '.PYSRV_DATABASE_PORT // "5432"' "$CONF_FILE" 2>/dev/null || echo "5432")
    DB_NAME=$(jq -r '.PYSRV_DATABASE_NAME // "MIKROMAN"' "$CONF_FILE" 2>/dev/null || echo "MIKROMAN")
    DB_USER=$(jq -r '.PYSRV_DATABASE_USER // "mikroman"' "$CONF_FILE" 2>/dev/null || echo "mikroman")
    DB_PASSWORD=$(jq -r '.PYSRV_DATABASE_PASSWORD // "MIKROMAN_MY_PASSWORD"' "$CONF_FILE" 2>/dev/null || echo "MIKROMAN_MY_PASSWORD")

    TOKEN=$(jq -r '.terminal_gateway_token // ""' "$CONF_FILE" 2>/dev/null || echo "")
    if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
        TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || openssl rand -hex 32)
    fi
    GATEWAY_BIND="127.0.0.1"
else
    echo -e "${YELLOW}[+] Remote installation mode (separate gateway host).${NC}"
    TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || openssl rand -hex 32)
    GATEWAY_BIND="0.0.0.0"
    
    if [ -t 0 ]; then
        read -p "Backend Redis host:port [127.0.0.1:6379]: " REDIS_HOST; REDIS_HOST=${REDIS_HOST:-127.0.0.1:6379}
        read -p "Backend PostgreSQL host [127.0.0.1]: " DB_HOST; DB_HOST=${DB_HOST:-127.0.0.1}
        read -p "Backend PostgreSQL port [5432]: " DB_PORT; DB_PORT=${DB_PORT:-5432}
        read -p "Backend PostgreSQL database [MIKROMAN]: " DB_NAME; DB_NAME=${DB_NAME:-MIKROMAN}
        read -p "Backend PostgreSQL user [mikroman]: " DB_USER; DB_USER=${DB_USER:-mikroman}
        read -p "Backend PostgreSQL password: " DB_PASSWORD
        read -p "Backend crypt key (PYSRV_CRYPT_KEY): " CRYPT_KEY
    else
        REDIS_HOST="127.0.0.1:6379"
        DB_HOST="127.0.0.1"
        DB_PORT="5432"
        DB_NAME="MIKROMAN"
        DB_USER="mikroman"
        DB_PASSWORD=""
        CRYPT_KEY=""
    fi
fi

PORT=8200
RECORDINGS_DIR="/opt/mikrowizard/terminal_recordings"
mkdir -p "$RECORDINGS_DIR"
chown -R 10001:10001 "$RECORDINGS_DIR" 2>/dev/null || true

# Save environment configuration securely
cat > "$GATEWAY_DIR/gateway.env" <<EOF
PORT=$PORT
GATEWAY_BIND=$GATEWAY_BIND
GATEWAY_TOKEN=$TOKEN
PYSRV_REDIS_HOST=$REDIS_HOST
PYSRV_CRYPT_KEY=$CRYPT_KEY
PYSRV_DATABASE_HOST=$DB_HOST
PYSRV_DATABASE_PORT=$DB_PORT
PYSRV_DATABASE_NAME=$DB_NAME
PYSRV_DATABASE_USER=$DB_USER
PYSRV_DATABASE_PASSWORD=$DB_PASSWORD
PYSRV_TERMINAL_RECORDINGS_DIR=$RECORDINGS_DIR
EOF
chmod 600 "$GATEWAY_DIR/gateway.env"

echo -e "${BLUE}[+] Pulling latest official image: ${IMAGE_NAME}:latest...${NC}"
docker pull "$IMAGE_NAME:latest"

echo -e "${BLUE}[+] Starting container: mikrowizard-terminal-gateway...${NC}"
docker stop mikrowizard-terminal-gateway >/dev/null 2>&1 || true
docker rm mikrowizard-terminal-gateway >/dev/null 2>&1 || true

CONFIG_FLAG=""
[ "$LOCAL" = "1" ] && CONFIG_FLAG="-e PYSRV_CONFIG_PATH=$CONF_FILE"

docker run -d --name=mikrowizard-terminal-gateway \
  --network=host \
  -e PORT="$PORT" \
  -e GATEWAY_TOKEN="$TOKEN" \
  -e GATEWAY_BIND="$GATEWAY_BIND" \
  -e AGENT_BIND="$GATEWAY_BIND" \
  -e PYSRV_CRYPT_KEY="$CRYPT_KEY" \
  -e PYSRV_REDIS_HOST="$REDIS_HOST" \
  -e PYSRV_DATABASE_HOST="$DB_HOST" \
  -e PYSRV_DATABASE_PORT="$DB_PORT" \
  -e PYSRV_DATABASE_NAME="$DB_NAME" \
  -e PYSRV_DATABASE_USER="$DB_USER" \
  -e PYSRV_DATABASE_PASSWORD="$DB_PASSWORD" \
  -e PYSRV_TERMINAL_RECORDINGS_DIR="$RECORDINGS_DIR" \
  $CONFIG_FLAG \
  -v "$RECORDINGS_DIR":"$RECORDINGS_DIR":rw \
  --restart=unless-stopped \
  "$IMAGE_NAME:latest"

echo -n "[+] Waiting for gateway to initialize"
MAX_RETRIES=30
COUNT=0
until curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; do
    sleep 2
    echo -n "."
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo -e "\n${RED}[-] Error: Gateway healthcheck timed out.${NC}"
        docker logs mikrowizard-terminal-gateway --tail 30
        exit 1
    fi
done
echo -e " ${GREEN}[OK]${NC}"

if [ "$LOCAL" = "1" ]; then
    echo -e "${GREEN}[+] Updating MikroWizard configuration in $CONF_FILE...${NC}"
    jq ". += {terminal_gateway_enabled: true, terminal_gateway_url: \"http://127.0.0.1:$PORT\", terminal_gateway_token: \"$TOKEN\"}" "$CONF_FILE" > /tmp/server.json
    mv /tmp/server.json "$CONF_FILE"

    if [ "$(docker container inspect -f '{{.State.Running}}' mikroman 2>/dev/null)" == "true" ]; then
        echo -e "${GREEN}[+] Reloading MikroWizard server...${NC}"
        docker exec mikroman touch reload || true
    elif [ "$(docker container inspect -f '{{.State.Running}}' mikroman-dev 2>/dev/null)" == "true" ]; then
        echo -e "${GREEN}[+] Reloading MikroWizard server...${NC}"
        docker exec mikroman-dev touch /app/reload || true
    fi
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${GREEN} SUCCESS! MikroWizard+ Terminal Gateway is active and linked!${NC}"
    echo -e " Port: $PORT (Loopback: 127.0.0.1)"
    echo -e "${BLUE}============================================================${NC}"
else
    REMOTE_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$REMOTE_IP" ] && REMOTE_IP="<GATEWAY_HOST_IP>"
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${YELLOW} REMOTE INSTALLATION COMPLETE${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo " Add these keys to your backend /opt/mikrowizard/server-conf.json:"
    echo ""
    echo "   \"terminal_gateway_enabled\": true,"
    echo "   \"terminal_gateway_url\": \"http://$REMOTE_IP:$PORT\","
    echo "   \"terminal_gateway_token\": \"$TOKEN\""
    echo ""
    echo " Then reload the backend: docker exec mikroman touch reload"
    echo -e "${BLUE}============================================================${NC}"
fi
