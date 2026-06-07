#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/DaggerConnect"
SYSTEMD_DIR="/etc/systemd/system"

GITHUB_REPO="https://github.com/itsFLoKi/DaggerConnect"
LATEST_RELEASE_API="https://api.github.com/repos/itsFLoKi/DaggerConnect/releases/latest"

show_banner() {
    echo -e "${CYAN}"
    echo -e "${GREEN}***  DaggerConnect  ***${NC}"
    echo -e "${BLUE}_____________________________${NC}"
    echo -e "${RED}***TELEGRAM : @DaggerConnect ***${RED}"
    echo -e "${BLUE}_____________________________${NC}"
    echo -e "${GREEN}***  DaggerConnect ***${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ This script must be run as root${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}📦 Installing dependencies...${NC}"
    if command -v apt &>/dev/null; then
        apt update -qq
        apt install -y wget curl tar git openssl libpcap-dev ipset > /dev/null 2>&1 || { echo -e "${RED}Failed to install dependencies${NC}"; exit 1; }
    elif command -v yum &>/dev/null; then
        yum install -y wget curl tar git openssl libpcap-devel ipset > /dev/null 2>&1 || { echo -e "${RED}Failed to install dependencies${NC}"; exit 1; }
    else
        echo -e "${RED}❌ Unsupported package manager${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Dependencies installed${NC}"
}

get_current_version() {
    if [ -f "$INSTALL_DIR/DaggerConnect" ]; then
        VERSION=$("$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+\.\d+' || echo "unknown")
        echo "$VERSION"
    else
        echo "not-installed"
    fi
}

download_binary() {
    echo -e "${YELLOW}⬇️  Downloading DaggerConnect binary...${NC}"
    mkdir -p "$INSTALL_DIR"

    echo -e "${CYAN}🔍 Fetching latest release info...${NC}"
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${YELLOW}⚠️  Could not fetch latest version, using v1.4${NC}"
        LATEST_VERSION="v1.4"
    fi

    BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"

    echo -e "${CYAN}📦 Latest version: ${GREEN}${LATEST_VERSION}${NC}"

    if [ -f "$INSTALL_DIR/DaggerConnect" ]; then
        mv "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.backup"
    fi

    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        echo -e "${GREEN}✓ DaggerConnect downloaded successfully${NC}"

        if "$INSTALL_DIR/DaggerConnect" -v &>/dev/null; then
            VERSION=$("$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+\.\d+' || echo "$LATEST_VERSION")
            echo -e "${CYAN}ℹ️  Installed version: $VERSION${NC}"
        fi

        rm -f "$INSTALL_DIR/DaggerConnect.backup"
    else
        echo -e "${RED}✖ Failed to download DaggerConnect binary${NC}"
        echo -e "${YELLOW}Please check your internet connection and try again${NC}"

        if [ -f "$INSTALL_DIR/DaggerConnect.backup" ]; then
            mv "$INSTALL_DIR/DaggerConnect.backup" "$INSTALL_DIR/DaggerConnect"
            echo -e "${YELLOW}⚠️  Restored previous version${NC}"
        fi
        exit 1
    fi
}

generate_ssl_cert() {
    echo -e "${YELLOW}Generating self-signed SSL certificate...${NC}"

    read -p "Domain name for certificate (e.g., www.google.com): " CERT_DOMAIN
    CERT_DOMAIN=${CERT_DOMAIN:-www.google.com}

    mkdir -p "$CONFIG_DIR/certs"

    openssl req -x509 -newkey rsa:4096 -keyout "$CONFIG_DIR/certs/key.pem" \
        -out "$CONFIG_DIR/certs/cert.pem" -days 365 -nodes \
        -subj "/C=US/ST=California/L=San Francisco/O=MyCompany/CN=${CERT_DOMAIN}" \
        2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ SSL certificate generated${NC}"
        echo -e "  Certificate: $CONFIG_DIR/certs/cert.pem"
        echo -e "  Private Key: $CONFIG_DIR/certs/key.pem"
        CERT_FILE="$CONFIG_DIR/certs/cert.pem"
        KEY_FILE="$CONFIG_DIR/certs/key.pem"
    else
        echo -e "${RED}✖ Failed to generate certificate${NC}"
        CERT_FILE=""
        KEY_FILE=""
    fi
}

create_systemd_service() {
    local MODE=$1
    local SERVICE_NAME="DaggerConnect-${MODE}"
    local SERVICE_FILE="$SYSTEMD_DIR/${SERVICE_NAME}.service"

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=DaggerConnect Reverse Tunnel ${MODE^}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/DaggerConnect -c $CONFIG_DIR/${MODE}.yaml
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd service for ${MODE^} created: ${SERVICE_NAME}.service${NC}"
}

# Advanced settings



configure_advanced_settings() {
    local MODE=$1

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      ADVANCED SETTINGS (Optional)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    read -p "Configure advanced settings? [y/N]: " ADV

    if [[ ! $ADV =~ ^[Yy]$ ]]; then
        SMUX_KEEPALIVE=""
        SMUX_MAXRECV=""
        SMUX_MAXSTREAM=""
        SMUX_FRAMESIZE=""
        TCP_NODELAY=""
        TCP_KEEPALIVE=""
        TCP_READBUFFER=""
        TCP_WRITEBUFFER=""
        MAX_CONNECTIONS=""
        return
    fi

    echo ""
    echo -e "${YELLOW}SMUX Configuration:${NC}"
    read -p "  KeepAlive interval (seconds) [8]: " SMUX_KEEPALIVE
    SMUX_KEEPALIVE=${SMUX_KEEPALIVE:-8}

    read -p "  Max receive buffer (bytes) [8388608]: " SMUX_MAXRECV
    SMUX_MAXRECV=${SMUX_MAXRECV:-8388608}

    read -p "  Max stream buffer (bytes) [8388608]: " SMUX_MAXSTREAM
    SMUX_MAXSTREAM=${SMUX_MAXSTREAM:-8388608}

    read -p "  Frame size (bytes) [32768]: " SMUX_FRAMESIZE
    SMUX_FRAMESIZE=${SMUX_FRAMESIZE:-32768}

    echo ""
    echo -e "${YELLOW}TCP Configuration:${NC}"
    read -p "  Enable TCP NoDelay? [Y/n]: " TCP_ND
    [[ $TCP_ND =~ ^[Nn]$ ]] && TCP_NODELAY="false" || TCP_NODELAY="true"

    read -p "  TCP KeepAlive (seconds) [15]: " TCP_KEEPALIVE
    TCP_KEEPALIVE=${TCP_KEEPALIVE:-15}

    read -p "  TCP Read Buffer (bytes) [8388608]: " TCP_READBUFFER
    TCP_READBUFFER=${TCP_READBUFFER:-8388608}

    read -p "  TCP Write Buffer (bytes) [8388608]: " TCP_WRITEBUFFER
    TCP_WRITEBUFFER=${TCP_WRITEBUFFER:-8388608}

    echo ""
    echo -e "${YELLOW}Connection Limits:${NC}"
    read -p "  Max connections [2000]: " MAX_CONNECTIONS
    MAX_CONNECTIONS=${MAX_CONNECTIONS:-2000}
}

configure_http_mimicry() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      HTTP MIMICRY SETTINGS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""

    read -p "Fake domain (e.g., www.google.com) [www.google.com]: " HTTP_DOMAIN
    HTTP_DOMAIN=${HTTP_DOMAIN:-www.google.com}

    read -p "Fake path (e.g., /search) [/search]: " HTTP_PATH
    HTTP_PATH=${HTTP_PATH:-/search}

    echo ""
    echo -e "${YELLOW}Select User-Agent:${NC}"
    echo "  1) Chrome Windows (default)"
    echo "  2) Firefox Windows"
    echo "  3) Chrome macOS"
    echo "  4) Safari macOS"
    echo "  5) Chrome Android"
    echo "  6) Custom"
    read -p "Choice [1-6]: " UA_CHOICE

    case $UA_CHOICE in
        1) HTTP_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" ;;
        2) HTTP_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0" ;;
        3) HTTP_UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" ;;
        4) HTTP_UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15" ;;
        5) HTTP_UA="Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36" ;;
        6)
            read -p "Enter custom User-Agent: " HTTP_UA
            ;;
        *) HTTP_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" ;;
    esac

    read -p "Enable chunked encoding? [Y/n]: " CHUNKED
    [[ $CHUNKED =~ ^[Nn]$ ]] && HTTP_CHUNKED="false" || HTTP_CHUNKED="true"

    read -p "Enable session cookies? [Y/n]: " COOKIES
    [[ $COOKIES =~ ^[Nn]$ ]] && HTTP_COOKIES="false" || HTTP_COOKIES="true"
}

# ============================================================================
# NEW: Raw Socket Configuration Function
# ============================================================================
configure_raw_socket() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}   RAW SOCKET CONFIGURATION (Advanced)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Raw Socket Mode:${NC}"
    echo "  - Bypasses OS network stack for maximum performance"
    echo "  - Requires root privileges and libpcap"
    echo "  - Best for high-throughput scenarios"
    echo "  - May help bypass some DPI systems"
    echo ""

    read -p "Enable Raw Socket mode? [y/N]: " RAW_ENABLED

    if [[ ! $RAW_ENABLED =~ ^[Yy]$ ]]; then
        RAW_SOCKET_ENABLED="false"
        return
    fi

    RAW_SOCKET_ENABLED="true"

    # Get network interface
    echo ""
    echo -e "${CYAN}Available network interfaces:${NC}"
    ip -brief link show | awk '{print "  - " $1}'
    echo ""
    read -p "Network interface [eth0]: " RAW_INTERFACE
    RAW_INTERFACE=${RAW_INTERFACE:-eth0}

    # Get local IP
    DEFAULT_IP=$(ip -4 addr show "$RAW_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -z "$DEFAULT_IP" ]; then
        DEFAULT_IP="0.0.0.0"
    fi
    read -p "Local IP address [$DEFAULT_IP]: " RAW_LOCAL_IP
    RAW_LOCAL_IP=${RAW_LOCAL_IP:-$DEFAULT_IP}

    # Get local port
    read -p "Raw socket port [9999]: " RAW_LOCAL_PORT
    RAW_LOCAL_PORT=${RAW_LOCAL_PORT:-9999}

    # Get gateway MAC
    echo ""
    echo -e "${YELLOW}Finding gateway MAC address...${NC}"
    GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -1)
    if [ -n "$GATEWAY_IP" ]; then
        GATEWAY_MAC=$(ip neigh show "$GATEWAY_IP" | awk '{print $5}' | head -1)
        if [ -z "$GATEWAY_MAC" ] || [ "$GATEWAY_MAC" == "" ]; then
            # Try to ping gateway to populate ARP cache
            ping -c 1 -W 1 "$GATEWAY_IP" > /dev/null 2>&1
            sleep 1
            GATEWAY_MAC=$(ip neigh show "$GATEWAY_IP" | awk '{print $5}' | head -1)
        fi
    fi

    if [ -z "$GATEWAY_MAC" ]; then
        GATEWAY_MAC="00:00:00:00:00:00"
    fi

    echo -e "${CYAN}Detected gateway: ${GREEN}$GATEWAY_IP${NC} → ${GREEN}$GATEWAY_MAC${NC}"
    read -p "Gateway MAC address [$GATEWAY_MAC]: " RAW_GATEWAY_MAC
    RAW_GATEWAY_MAC=${RAW_GATEWAY_MAC:-$GATEWAY_MAC}

    # Validate MAC address format
    if [[ ! $RAW_GATEWAY_MAC =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        echo -e "${RED}⚠️  Invalid MAC address format!${NC}"
        echo -e "${YELLOW}Using default: 00:00:00:00:00:00${NC}"
        RAW_GATEWAY_MAC="00:00:00:00:00:00"
    fi

    echo ""
    read -p "Configure advanced raw socket parameters? [y/N]: " RAW_ADV

    if [[ $RAW_ADV =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Packet Size Configuration:${NC}"
        read -p "  Min packet size (bytes) [1200]: " RAW_MIN_PKT
        RAW_MIN_PKT=${RAW_MIN_PKT:-1200}

        read -p "  Max packet size (bytes) [1400]: " RAW_MAX_PKT
        RAW_MAX_PKT=${RAW_MAX_PKT:-1400}

        echo ""
        echo -e "${YELLOW}Performance Tuning:${NC}"
        read -p "  Coalesce timeout (ms) [10]: " RAW_COALESCE
        RAW_COALESCE=${RAW_COALESCE:-10}

        read -p "  Batch size [64]: " RAW_BATCH
        RAW_BATCH=${RAW_BATCH:-64}

        read -p "  Buffer size (bytes) [16777216]: " RAW_BUFFER
        RAW_BUFFER=${RAW_BUFFER:-16777216}

        echo ""
        read -p "  Enable compression? [y/N]: " RAW_COMPRESS
        [[ $RAW_COMPRESS =~ ^[Yy]$ ]] && RAW_USE_COMPRESS="true" || RAW_USE_COMPRESS="false"

        if [ "$RAW_USE_COMPRESS" == "true" ]; then
            read -p "  Compression level (0-9) [6]: " RAW_COMPRESS_LVL
            RAW_COMPRESS_LVL=${RAW_COMPRESS_LVL:-6}
        else
            RAW_COMPRESS_LVL=0
        fi

        read -p "  Enable zero-copy? [Y/n]: " RAW_ZCOPY
        [[ $RAW_ZCOPY =~ ^[Nn]$ ]] && RAW_USE_ZCOPY="false" || RAW_USE_ZCOPY="true"

        read -p "  MTU size [1500]: " RAW_MTU
        RAW_MTU=${RAW_MTU:-1500}

        read -p "  Snap length [65536]: " RAW_SNAPLEN
        RAW_SNAPLEN=${RAW_SNAPLEN:-65536}
    else
        # Use defaults
        RAW_MIN_PKT=1200
        RAW_MAX_PKT=1400
        RAW_COALESCE=10
        RAW_BATCH=64
        RAW_BUFFER=16777216
        RAW_USE_COMPRESS="false"
        RAW_COMPRESS_LVL=0
        RAW_USE_ZCOPY="true"
        RAW_MTU=1500
        RAW_SNAPLEN=65536
    fi

    echo ""
    echo -e "${GREEN}✓ Raw Socket configuration completed${NC}"
    echo -e "${CYAN}Summary:${NC}"
    echo -e "  Interface: ${GREEN}$RAW_INTERFACE${NC}"
    echo -e "  Local: ${GREEN}$RAW_LOCAL_IP:$RAW_LOCAL_PORT${NC}"
    echo -e "  Gateway MAC: ${GREEN}$RAW_GATEWAY_MAC${NC}"
    echo -e "  Packet size: ${GREEN}$RAW_MIN_PKT-$RAW_MAX_PKT bytes${NC}"
    echo -e "  Compression: ${GREEN}$RAW_USE_COMPRESS${NC}"
}

install_server() {
    show_banner
    mkdir -p "$CONFIG_DIR"

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      SERVER CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""

    echo -e "${YELLOW}Select Transport Type:${NC}"
    echo "  1) tcpmux   - TCP Multiplexing (Simple & Fast)"
    echo "  2) kcpmux   - KCP Multiplexing (UDP based, High Speed)"
    echo "  3) wsmux    - WebSocket (HTTP compatible)"
    echo "  4) wssmux   - WebSocket Secure (HTTPS with TLS)"
    echo "  5) httpmux  - HTTP Mimicry (DPI bypass, Realistic)"
    echo "  6) httpsmux - HTTPS Mimicry (TLS + DPI bypass) ⭐ Recommended"
    echo ""
    read -p "Choice [1-6]: " transport_choice
    case $transport_choice in
        1) TRANSPORT="tcpmux" ;;
        2) TRANSPORT="kcpmux" ;;
        3) TRANSPORT="wsmux" ;;
        4) TRANSPORT="wssmux" ;;
        5) TRANSPORT="httpmux" ;;
        6) TRANSPORT="httpsmux" ;;
        *) TRANSPORT="tcpmux" ;;
    esac

    echo ""
    echo -e "${CYAN}Tunnel Port: Port for communication between Server and Client${NC}"
    read -p "Tunnel Port [4000]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-4000}

    echo ""
    while true; do
        read -sp "Enter PSK (Pre-Shared Key): " PSK
        echo ""
        if [ -z "$PSK" ]; then
            echo -e "${RED}PSK cannot be empty!${NC}"
        else
            break
        fi
    done

    echo ""
    echo -e "${YELLOW}Select Performance Profile:${NC}"
    echo "  1) balanced      - Standard balanced performance (Recommended)"
    echo "  2) aggressive    - High speed, aggressive settings"
    echo "  3) latency       - Optimized for low latency"
    echo "  4) cpu-efficient - Low CPU usage"
    echo "  5) gaming        - Optimized for gaming (low latency + high speed)"
    echo ""
    read -p "Choice [1-5]: " profile_choice
    case $profile_choice in
        1) PROFILE="balanced" ;;
        2) PROFILE="aggressive" ;;
        3) PROFILE="latency" ;;
        4) PROFILE="cpu-efficient" ;;
        5) PROFILE="gaming" ;;
        *) PROFILE="balanced" ;;
    esac

    CERT_FILE=""
    KEY_FILE=""
    if [ "$TRANSPORT" == "wssmux" ] || [ "$TRANSPORT" == "httpsmux" ]; then
        echo ""
        echo -e "${YELLOW}TLS Configuration (Required for wssmux/httpsmux):${NC}"
        echo "  1) Generate self-signed certificate (Quick & Easy)"
        echo "  2) Use existing certificate files"
        read -p "Choice [1-2]: " cert_choice

        if [ "$cert_choice" == "1" ]; then
            generate_ssl_cert
        else
            read -p "Certificate file path: " CERT_FILE
            read -p "Private key file path: " KEY_FILE
            if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
                echo -e "${YELLOW}⚠️  Certificate files not found. Generating self-signed...${NC}"
                generate_ssl_cert
            fi
        fi
    fi

    # HTTP Mimicry configuration
    if [ "$TRANSPORT" == "httpmux" ] || [ "$TRANSPORT" == "httpsmux" ]; then
        configure_http_mimicry
    fi

    # Raw Socket configuration (NEW)
    configure_raw_socket

    echo ""
    read -p "Enable Traffic Obfuscation? [Y/n]: " OBFUS_ENABLED
    if [[ ! $OBFUS_ENABLED =~ ^[Nn]$ ]]; then
        OBFUS_ENABLED="true"

        echo ""
        read -p "Configure obfuscation details? [y/N]: " OBFUS_DETAILS
        if [[ $OBFUS_DETAILS =~ ^[Yy]$ ]]; then
            read -p "  Min padding (bytes) [16]: " OBFUS_MIN_PAD
            OBFUS_MIN_PAD=${OBFUS_MIN_PAD:-16}

            read -p "  Max padding (bytes) [512]: " OBFUS_MAX_PAD
            OBFUS_MAX_PAD=${OBFUS_MAX_PAD:-512}

            read -p "  Min delay (ms) [5]: " OBFUS_MIN_DELAY
            OBFUS_MIN_DELAY=${OBFUS_MIN_DELAY:-5}

            read -p "  Max delay (ms) [50]: " OBFUS_MAX_DELAY
            OBFUS_MAX_DELAY=${OBFUS_MAX_DELAY:-50}
        else
            OBFUS_MIN_PAD=16
            OBFUS_MAX_PAD=512
            OBFUS_MIN_DELAY=5
            OBFUS_MAX_DELAY=50
        fi
    else
        OBFUS_ENABLED="false"
        OBFUS_MIN_PAD=16
        OBFUS_MAX_PAD=512
        OBFUS_MIN_DELAY=5
        OBFUS_MAX_DELAY=50
    fi

    # Advanced settings
    configure_advanced_settings "server"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      PORT MAPPINGS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Help Port Mapping:${NC}"
    echo "  ${GREEN}Single Port${NC}:        8008            → Bind=8008, Target=8008"
    echo "  ${GREEN}Range${NC}:             1000/2000       → Bind=Target (1000→1000, ...)"
    echo "  ${GREEN}Custom Mapping${NC}:    5000=8008       → Bind=5000, Target=8008"
    echo "  ${GREEN}Range Mapping${NC}:     1000/1010=2000/2010 → (1000→2000, 1001→2001, ...)"
    echo ""

    BIND_IP="0.0.0.0"
    TARGET_IP="127.0.0.1"
    MAPPINGS=""
    COUNT=0

    while true; do
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  Port Mapping #$((COUNT+1))${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # Select Protocol
        echo ""
        echo -e "${CYAN}Protocol:${NC}"
        echo "  1) tcp"
        echo "  2) udp"
        echo "  3) both (tcp + udp)"
        read -p "Choice [1-3]: " proto_choice

        case $proto_choice in
            1) PROTO="tcp" ;;
            2) PROTO="udp" ;;
            3) PROTO="both" ;;
            *) PROTO="tcp" ;;
        esac

        # Get Port Input
        echo ""
        echo -e "${CYAN}Port Configuration:${NC}"
        echo -e "${YELLOW}Examples: 8008 | 1000/2000 | 5000=8008 | 1000/1010=2000/2010${NC}"
        echo ""
        read -p "Enter port(s): " PORT_INPUT

        if [ -z "$PORT_INPUT" ]; then
            echo -e "${RED}⚠️  Port cannot be empty!${NC}"
            continue
        fi

        PORT_INPUT=$(echo "$PORT_INPUT" | tr -d ' ')

        # Check for Range Mapping (1000/1010=2000/2010)
        if [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+)/([0-9]+)$ ]]; then
            BIND_START="${BASH_REMATCH[1]}"
            BIND_END="${BASH_REMATCH[2]}"
            TARGET_START="${BASH_REMATCH[3]}"
            TARGET_END="${BASH_REMATCH[4]}"

            BIND_RANGE=$((BIND_END - BIND_START + 1))
            TARGET_RANGE=$((TARGET_END - TARGET_START + 1))

            if [ "$BIND_RANGE" -ne "$TARGET_RANGE" ]; then
                echo -e "${RED}⚠️  Range size mismatch! Bind: $BIND_RANGE ports, Target: $TARGET_RANGE ports${NC}"
                continue
            fi

            if [ "$BIND_START" -lt 1 ] || [ "$BIND_END" -gt 65535 ] || [ "$TARGET_START" -lt 1 ] || [ "$TARGET_END" -gt 65535 ]; then
                echo -e "${RED}⚠️  Invalid port range (1-65535)${NC}"
                continue
            fi

            for ((i=0; i<BIND_RANGE; i++)); do
                BP=$((BIND_START + i))
                TP=$((TARGET_START + i))
                if [ "$PROTO" == "both" ]; then
                    MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP}:${BP}\"\n    target: \"${TARGET_IP}:${TP}\"\n"
                    MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND_IP}:${BP}\"\n    target: \"${TARGET_IP}:${TP}\"\n"
                    COUNT=$((COUNT + 2))
                else
                    MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP}:${BP}\"\n    target: \"${TARGET_IP}:${TP}\"\n"
                    COUNT=$((COUNT + 1))
                fi
            done

            if [ "$PROTO" == "both" ]; then
                TOTAL_ADDED=$((BIND_RANGE * 2))
                echo -e "${GREEN}✓ Added ${TOTAL_ADDED} mappings (tcp+udp): ${BIND_START}→${TARGET_START} ... ${BIND_END}→${TARGET_END}${NC}"
            else
                echo -e "${GREEN}✓ Added ${BIND_RANGE} mappings: ${BIND_START}→${TARGET_START} ... ${BIND_END}→${TARGET_END} (${PROTO})${NC}"
            fi

        # Check for Range (1000/2000)
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            START_PORT="${BASH_REMATCH[1]}"
            END_PORT="${BASH_REMATCH[2]}"

            if [ "$START_PORT" -gt "$END_PORT" ]; then
                echo -e "${RED}⚠️  Start port cannot be greater than end port!${NC}"
                continue
            fi

            if [ "$START_PORT" -lt 1 ] || [ "$END_PORT" -gt 65535 ]; then
                echo -e "${RED}⚠️  Invalid port range (1-65535)${NC}"
                continue
            fi

            RANGE_SIZE=$((END_PORT - START_PORT + 1))

            if [ "$RANGE_SIZE" -gt 1000 ]; then
                echo -e "${YELLOW}⚠️  Large range: ${RANGE_SIZE} ports will be added${NC}"
                read -p "Continue? [y/N]: " confirm_range
                [[ ! $confirm_range =~ ^[Yy]$ ]] && continue
            fi

            for ((port=START_PORT; port<=END_PORT; port++)); do
                if [ "$PROTO" == "both" ]; then
                    MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP}:${port}\"\n    target: \"${TARGET_IP}:${port}\"\n"
                    MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND_IP}:${port}\"\n    target: \"${TARGET_IP}:${port}\"\n"
                    COUNT=$((COUNT + 2))
                else
                    MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP}:${port}\"\n    target: \"${TARGET_IP}:${port}\"\n"
                    COUNT=$((COUNT + 1))
                fi
            done

            if [ "$PROTO" == "both" ]; then
                TOTAL_ADDED=$((RANGE_SIZE * 2))
                echo -e "${GREEN}✓ Added ${TOTAL_ADDED} mappings (tcp+udp): ${START_PORT}→${START_PORT} ... ${END_PORT}→${END_PORT}${NC}"
            else
                echo -e "${GREEN}✓ Added ${RANGE_SIZE} mappings: ${START_PORT}→${START_PORT} ... ${END_PORT}→${END_PORT} (${PROTO})${NC}"
            fi

        # Check for Custom Mapping (5000=8008)
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            BIND_PORT="${BASH_REMATCH[1]}"
            TARGET_PORT="${BASH_REMATCH[2]}"

            if [ "$BIND_PORT" -lt 1 ] || [ "$BIND_PORT" -gt 65535 ] || [ "$TARGET_PORT" -lt 1 ] || [ "$TARGET_PORT" -gt 65535 ]; then
                echo -e "${RED}⚠️  Invalid port (1-65535)${NC}"
                continue
            fi

            if [ "$PROTO" == "both" ]; then
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP}:${BIND_PORT}\"\n    target: \"${TARGET_IP}:${TARGET_PORT}\"\n"
                MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND_IP}:${BIND_PORT}\"\n    target: \"${TARGET_IP}:${TARGET_PORT}\"\n"
                COUNT=$((COUNT + 2))
                echo -e "${GREEN}✓ Mapping: ${BIND_PORT} → ${TARGET_PORT} (tcp+udp)${NC}"
            else
                MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP}:${BIND_PORT}\"\n    target: \"${TARGET_IP}:${TARGET_PORT}\"\n"
                COUNT=$((COUNT + 1))
                echo -e "${GREEN}✓ Mapping: ${BIND_PORT} → ${TARGET_PORT} (${PROTO})${NC}"
            fi

        # Single Port (8008)
        elif [[ "$PORT_INPUT" =~ ^[0-9]+$ ]]; then
            SINGLE_PORT="$PORT_INPUT"

            if [ "$SINGLE_PORT" -lt 1 ] || [ "$SINGLE_PORT" -gt 65535 ]; then
                echo -e "${RED}⚠️  Invalid port (1-65535)${NC}"
                continue
            fi

            if [ "$PROTO" == "both" ]; then
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP}:${SINGLE_PORT}\"\n    target: \"${TARGET_IP}:${SINGLE_PORT}\"\n"
                MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND_IP}:${SINGLE_PORT}\"\n    target: \"${TARGET_IP}:${SINGLE_PORT}\"\n"
                COUNT=$((COUNT + 2))
                echo -e "${GREEN}✓ Mapping: ${SINGLE_PORT} → ${SINGLE_PORT} (tcp+udp)${NC}"
            else
                MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP}:${SINGLE_PORT}\"\n    target: \"${TARGET_IP}:${SINGLE_PORT}\"\n"
                COUNT=$((COUNT + 1))
                echo -e "${GREEN}✓ Mapping: ${SINGLE_PORT} → ${SINGLE_PORT} (${PROTO})${NC}"
            fi

        else
            echo -e "${RED}⚠️  Invalid format!${NC}"
            echo -e "${YELLOW}Use: 8008 | 1000/2000 | 5000=8008 | 1000/1010=2000/2010${NC}"
            continue
        fi

        echo ""
        read -p "Add another port mapping? [y/N]: " add_more
        [[ ! "$add_more" =~ ^[Yy]$ ]] && break
    done

    if [ "$COUNT" -eq 0 ]; then
        echo -e "${RED}⚠️  No port mappings added! Adding default 8080→8080...${NC}"
        MAPPINGS="  - type: tcp\n    bind: \"0.0.0.0:8080\"\n    target: \"127.0.0.1:8080\"\n"
    fi

    echo ""
    read -p "Enable verbose logging? [y/N]: " VERBOSE
    [[ $VERBOSE =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

    # Generate configuration file
    CONFIG_FILE="$CONFIG_DIR/server.yaml"
    cat > "$CONFIG_FILE" << EOF
mode: "server"
listen: "0.0.0.0:${LISTEN_PORT}"
transport: "${TRANSPORT}"
psk: "${PSK}"
profile: "${PROFILE}"
verbose: ${VERBOSE}

EOF

    if [[ -n "$CERT_FILE" ]]; then
        cat >> "$CONFIG_FILE" << EOF
cert_file: "$CERT_FILE"
key_file: "$KEY_FILE"

EOF
    fi

    echo -e "maps:\n$MAPPINGS" >> "$CONFIG_FILE"

    cat >> "$CONFIG_FILE" << EOF

obfuscation:
  enabled: ${OBFUS_ENABLED}
  min_padding: ${OBFUS_MIN_PAD}
  max_padding: ${OBFUS_MAX_PAD}
  min_delay_ms: ${OBFUS_MIN_DELAY}
  max_delay_ms: ${OBFUS_MAX_DELAY}
  burst_chance: 0.15
EOF

    # Add HTTP Mimicry config if needed
    if [ "$TRANSPORT" == "httpmux" ] || [ "$TRANSPORT" == "httpsmux" ]; then
        cat >> "$CONFIG_FILE" << EOF

http_mimic:
  fake_domain: "${HTTP_DOMAIN}"
  fake_path: "${HTTP_PATH}"
  user_agent: "${HTTP_UA}"
  chunked_encoding: ${HTTP_CHUNKED}
  session_cookie: ${HTTP_COOKIES}
  custom_headers:
    - "X-Requested-With: XMLHttpRequest"
    - "Referer: https://${HTTP_DOMAIN}/"
EOF
    fi

    # Add Raw Socket config (NEW)
    cat >> "$CONFIG_FILE" << EOF

raw_socket:
  enabled: ${RAW_SOCKET_ENABLED}
EOF

    if [ "$RAW_SOCKET_ENABLED" == "true" ]; then
        cat >> "$CONFIG_FILE" << EOF
  interface: "${RAW_INTERFACE}"
  local_ip: "${RAW_LOCAL_IP}"
  local_port: ${RAW_LOCAL_PORT}
  gateway_mac: "${RAW_GATEWAY_MAC}"
  min_packet_size: ${RAW_MIN_PKT}
  max_packet_size: ${RAW_MAX_PKT}
  coalesce_timeout_ms: ${RAW_COALESCE}
  use_compression: ${RAW_USE_COMPRESS}
  compression_level: ${RAW_COMPRESS_LVL}
  batch_size: ${RAW_BATCH}
  buffer_size: ${RAW_BUFFER}
  use_zero_copy: ${RAW_USE_ZCOPY}
  mtu: ${RAW_MTU}
  snap_len: ${RAW_SNAPLEN}
EOF
    fi

    # Add SMUX config if configured
    if [ -n "$SMUX_KEEPALIVE" ]; then
        cat >> "$CONFIG_FILE" << EOF

smux:
  keepalive: ${SMUX_KEEPALIVE}
  max_recv: ${SMUX_MAXRECV}
  max_stream: ${SMUX_MAXSTREAM}
  frame_size: ${SMUX_FRAMESIZE}
  version: 2
EOF
    fi

    # Add Advanced config if configured
    if [ -n "$TCP_NODELAY" ]; then
        cat >> "$CONFIG_FILE" << EOF

advanced:
  tcp_nodelay: ${TCP_NODELAY}
  tcp_keepalive: ${TCP_KEEPALIVE}
  tcp_read_buffer: ${TCP_READBUFFER}
  tcp_write_buffer: ${TCP_WRITEBUFFER}
  max_connections: ${MAX_CONNECTIONS}
  cleanup_interval: 3
  connection_timeout: 60
  stream_timeout: 120
  max_udp_flows: 1000
  udp_flow_timeout: 300
  udp_buffer_size: 4194304
EOF
    fi

    create_systemd_service "server"

    systemctl start DaggerConnect-server
    systemctl enable DaggerConnect-server

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✓ Server installation complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Important Info:${NC}"
    echo -e "  Tunnel Port: ${GREEN}${LISTEN_PORT}${NC}"
    echo -e "  PSK: ${GREEN}${PSK}${NC}"
    echo -e "  Transport: ${GREEN}${TRANSPORT}${NC}"
    echo -e "  Profile: ${GREEN}${PROFILE}${NC}"
    echo -e "  Obfuscation: ${GREEN}${OBFUS_ENABLED}${NC}"

    if [ "$RAW_SOCKET_ENABLED" == "true" ]; then
        echo -e "  Raw Socket: ${GREEN}Enabled${NC}"
        echo -e "    └─ Interface: ${GREEN}${RAW_INTERFACE}${NC}"
        echo -e "    └─ IP: ${GREEN}${RAW_LOCAL_IP}:${RAW_LOCAL_PORT}${NC}"
    fi

    if [ "$TRANSPORT" == "httpmux" ] || [ "$TRANSPORT" == "httpsmux" ]; then
        echo -e "  HTTP Mimicry: ${GREEN}Enabled${NC}"
        echo -e "    └─ Domain: ${GREEN}${HTTP_DOMAIN}${NC}"
    fi

    echo ""
    echo "  Config: $CONFIG_FILE"
    echo "  View logs: journalctl -u DaggerConnect-server -f"
    echo ""
    read -p "Press Enter to return to menu..."
    main_menu
}

install_client() {
    show_banner
    mkdir -p "$CONFIG_DIR"

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      CLIENT CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""

    while true; do
        read -sp "Enter PSK (must match server): " PSK
        echo ""
        if [ -z "$PSK" ]; then
            echo -e "${RED}PSK cannot be empty!${NC}"
        else
            break
        fi
    done

    echo ""
    echo -e "${YELLOW}Select Performance Profile:${NC}"
    echo "  1) balanced      - Standard balanced performance (Recommended)"
    echo "  2) aggressive    - High speed, aggressive settings"
    echo "  3) latency       - Optimized for low latency"
    echo "  4) cpu-efficient - Low CPU usage"
    echo "  5) gaming        - Optimized for gaming (low latency + high speed)"
    echo ""
    read -p "Choice [1-5]: " profile_choice
    case $profile_choice in
        1) PROFILE="balanced" ;;
        2) PROFILE="aggressive" ;;
        3) PROFILE="latency" ;;
        4) PROFILE="cpu-efficient" ;;
        5) PROFILE="gaming" ;;
        *) PROFILE="balanced" ;;
    esac

    echo ""
    read -p "Enable Traffic Obfuscation? [Y/n]: " OBFUS_ENABLED
    if [[ ! $OBFUS_ENABLED =~ ^[Nn]$ ]]; then
        OBFUS_ENABLED="true"
        OBFUS_MIN_PAD=16
        OBFUS_MAX_PAD=512
        OBFUS_MIN_DELAY=5
        OBFUS_MAX_DELAY=50
    else
        OBFUS_ENABLED="false"
        OBFUS_MIN_PAD=16
        OBFUS_MAX_PAD=512
        OBFUS_MIN_DELAY=5
        OBFUS_MAX_DELAY=50
    fi

    # Advanced settings
    configure_advanced_settings "client"

    # ============================================================================
    # Raw Socket Configuration for Client (NEW)
    # ============================================================================
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}   RAW SOCKET CONFIGURATION (Advanced)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Raw Socket Mode for Client:${NC}"
    echo "  - Bypasses OS network stack"
    echo "  - Requires root privileges and libpcap"
    echo "  - Best for high-throughput scenarios"
    echo "  - Must match server configuration"
    echo ""

    read -p "Enable Raw Socket mode? [y/N]: " CLIENT_RAW_ENABLED

    if [[ $CLIENT_RAW_ENABLED =~ ^[Yy]$ ]]; then
        CLIENT_RAW_SOCKET_ENABLED="true"

        # Get network interface
        echo ""
        echo -e "${CYAN}Available network interfaces:${NC}"
        ip -brief link show | awk '{print "  - " $1}'
        echo ""
        read -p "Network interface [eth0]: " CLIENT_RAW_INTERFACE
        CLIENT_RAW_INTERFACE=${CLIENT_RAW_INTERFACE:-eth0}

        # Get local IP
        CLIENT_DEFAULT_IP=$(ip -4 addr show "$CLIENT_RAW_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -z "$CLIENT_DEFAULT_IP" ]; then
            CLIENT_DEFAULT_IP="0.0.0.0"
        fi
        read -p "Local IP address [$CLIENT_DEFAULT_IP]: " CLIENT_RAW_LOCAL_IP
        CLIENT_RAW_LOCAL_IP=${CLIENT_RAW_LOCAL_IP:-$CLIENT_DEFAULT_IP}

        # Get local port
        read -p "Raw socket port [9999]: " CLIENT_RAW_LOCAL_PORT
        CLIENT_RAW_LOCAL_PORT=${CLIENT_RAW_LOCAL_PORT:-9999}

        # Get gateway MAC
        echo ""
        echo -e "${YELLOW}Finding gateway MAC address...${NC}"
        CLIENT_GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -1)
        if [ -n "$CLIENT_GATEWAY_IP" ]; then
            CLIENT_GATEWAY_MAC=$(ip neigh show "$CLIENT_GATEWAY_IP" | awk '{print $5}' | head -1)
            if [ -z "$CLIENT_GATEWAY_MAC" ] || [ "$CLIENT_GATEWAY_MAC" == "" ]; then
                ping -c 1 -W 1 "$CLIENT_GATEWAY_IP" > /dev/null 2>&1
                sleep 1
                CLIENT_GATEWAY_MAC=$(ip neigh show "$CLIENT_GATEWAY_IP" | awk '{print $5}' | head -1)
            fi
        fi

        if [ -z "$CLIENT_GATEWAY_MAC" ]; then
            CLIENT_GATEWAY_MAC="00:00:00:00:00:00"
        fi

        echo -e "${CYAN}Detected gateway: ${GREEN}$CLIENT_GATEWAY_IP${NC} → ${GREEN}$CLIENT_GATEWAY_MAC${NC}"
        read -p "Gateway MAC address [$CLIENT_GATEWAY_MAC]: " CLIENT_RAW_GATEWAY_MAC
        CLIENT_RAW_GATEWAY_MAC=${CLIENT_RAW_GATEWAY_MAC:-$CLIENT_GATEWAY_MAC}

        # Validate MAC address
        if [[ ! $CLIENT_RAW_GATEWAY_MAC =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            echo -e "${RED}⚠️  Invalid MAC address format!${NC}"
            echo -e "${YELLOW}Using default: 00:00:00:00:00:00${NC}"
            CLIENT_RAW_GATEWAY_MAC="00:00:00:00:00:00"
        fi

        echo ""
        read -p "Configure advanced raw socket parameters? [y/N]: " CLIENT_RAW_ADV

        if [[ $CLIENT_RAW_ADV =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${YELLOW}Packet Size Configuration:${NC}"
            read -p "  Min packet size (bytes) [1200]: " CLIENT_RAW_MIN_PKT
            CLIENT_RAW_MIN_PKT=${CLIENT_RAW_MIN_PKT:-1200}

            read -p "  Max packet size (bytes) [1400]: " CLIENT_RAW_MAX_PKT
            CLIENT_RAW_MAX_PKT=${CLIENT_RAW_MAX_PKT:-1400}

            echo ""
            echo -e "${YELLOW}Performance Tuning:${NC}"
            read -p "  Coalesce timeout (ms) [10]: " CLIENT_RAW_COALESCE
            CLIENT_RAW_COALESCE=${CLIENT_RAW_COALESCE:-10}

            read -p "  Batch size [64]: " CLIENT_RAW_BATCH
            CLIENT_RAW_BATCH=${CLIENT_RAW_BATCH:-64}

            read -p "  Buffer size (bytes) [16777216]: " CLIENT_RAW_BUFFER
            CLIENT_RAW_BUFFER=${CLIENT_RAW_BUFFER:-16777216}

            echo ""
            read -p "  Enable compression? [y/N]: " CLIENT_RAW_COMPRESS
            [[ $CLIENT_RAW_COMPRESS =~ ^[Yy]$ ]] && CLIENT_RAW_USE_COMPRESS="true" || CLIENT_RAW_USE_COMPRESS="false"

            if [ "$CLIENT_RAW_USE_COMPRESS" == "true" ]; then
                read -p "  Compression level (0-9) [6]: " CLIENT_RAW_COMPRESS_LVL
                CLIENT_RAW_COMPRESS_LVL=${CLIENT_RAW_COMPRESS_LVL:-6}
            else
                CLIENT_RAW_COMPRESS_LVL=0
            fi

            read -p "  Enable zero-copy? [Y/n]: " CLIENT_RAW_ZCOPY
            [[ $CLIENT_RAW_ZCOPY =~ ^[Nn]$ ]] && CLIENT_RAW_USE_ZCOPY="false" || CLIENT_RAW_USE_ZCOPY="true"

            read -p "  MTU size [1500]: " CLIENT_RAW_MTU
            CLIENT_RAW_MTU=${CLIENT_RAW_MTU:-1500}

            read -p "  Snap length [65536]: " CLIENT_RAW_SNAPLEN
            CLIENT_RAW_SNAPLEN=${CLIENT_RAW_SNAPLEN:-65536}
        else
            # Use defaults
            CLIENT_RAW_MIN_PKT=1200
            CLIENT_RAW_MAX_PKT=1400
            CLIENT_RAW_COALESCE=10
            CLIENT_RAW_BATCH=64
            CLIENT_RAW_BUFFER=16777216
            CLIENT_RAW_USE_COMPRESS="false"
            CLIENT_RAW_COMPRESS_LVL=0
            CLIENT_RAW_USE_ZCOPY="true"
            CLIENT_RAW_MTU=1500
            CLIENT_RAW_SNAPLEN=65536
        fi

        echo ""
        echo -e "${GREEN}✓ Raw Socket configuration completed${NC}"
        echo -e "${CYAN}Summary:${NC}"
        echo -e "  Interface: ${GREEN}$CLIENT_RAW_INTERFACE${NC}"
        echo -e "  Local: ${GREEN}$CLIENT_RAW_LOCAL_IP:$CLIENT_RAW_LOCAL_PORT${NC}"
        echo -e "  Gateway MAC: ${GREEN}$CLIENT_RAW_GATEWAY_MAC${NC}"
    else
        CLIENT_RAW_SOCKET_ENABLED="false"
    fi

    configure_advanced_settings "client"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      CONNECTION PATHS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"

    declare -a PATH_ENTRIES=()
    declare -a HTTP_CONFIGS=()
    COUNT=0

    while true; do
        echo ""
        echo -e "${YELLOW}Add Connection Path #$((COUNT+1))${NC}"

        echo "Select Transport Type:"
        echo "  1) tcpmux   - TCP Multiplexing"
        echo "  2) kcpmux   - KCP Multiplexing (UDP)"
        echo "  3) wsmux    - WebSocket"
        echo "  4) wssmux   - WebSocket Secure"
        echo "  5) httpmux  - HTTP Mimicry"
        echo "  6) httpsmux - HTTPS Mimicry ⭐"
        echo ""
        read -p "Choice [1-6]: " transport_choice
        case $transport_choice in
            1) T="tcpmux" ;;
            2) T="kcpmux" ;;
            3) T="wsmux" ;;
            4) T="wssmux" ;;
            5) T="httpmux" ;;
            6) T="httpsmux" ;;
            *) T="tcpmux" ;;
        esac

        read -p "Server address with Tunnel Port (e.g., 1.2.3.4:4000): " ADDR
        if [ -z "$ADDR" ]; then
            echo -e "${RED}Address cannot be empty!${NC}"
            continue
        fi

        read -p "Connection pool size [2]: " POOL
        POOL=${POOL:-2}

        read -p "Enable aggressive pool? [y/N]: " AGG
        [[ $AGG =~ ^[Yy]$ ]] && AGG_POOL="true" || AGG_POOL="false"

        read -p "Retry interval (seconds) [3]: " RETRY
        RETRY=${RETRY:-3}

        read -p "Dial timeout (seconds) [10]: " DIAL_TIMEOUT
        DIAL_TIMEOUT=${DIAL_TIMEOUT:-10}

        PATH_ENTRIES+=("  - transport: \"$T\"
    addr: \"$ADDR\"
    connection_pool: $POOL
    aggressive_pool: $AGG_POOL
    retry_interval: $RETRY
    dial_timeout: $DIAL_TIMEOUT")

        # HTTP Mimicry for this path
        if [ "$T" == "httpmux" ] || [ "$T" == "httpsmux" ]; then
            if [ ${#HTTP_CONFIGS[@]} -eq 0 ]; then
                configure_http_mimicry
                HTTP_CONFIGS+=("yes")
            fi
        fi

        COUNT=$((COUNT+1))
        echo -e "${GREEN}✓ Path added: $T -> $ADDR (pool: $POOL, aggressive: $AGG_POOL)${NC}"

        read -p "Add another path? [y/N]: " MORE
        [[ ! $MORE =~ ^[Yy]$ ]] && break
    done

    echo ""
    read -p "Enable verbose logging? [y/N]: " VERBOSE
    [[ $VERBOSE =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

    CONFIG_FILE="$CONFIG_DIR/client.yaml"

    cat > "$CONFIG_FILE" << EOF
mode: "client"
psk: "${PSK}"
profile: "${PROFILE}"
verbose: ${VERBOSE}

paths:
EOF

    for path_entry in "${PATH_ENTRIES[@]}"; do
        printf "%s\n" "$path_entry" >> "$CONFIG_FILE"
    done

    cat >> "$CONFIG_FILE" << EOF

obfuscation:
  enabled: ${OBFUS_ENABLED}
  min_padding: ${OBFUS_MIN_PAD}
  max_padding: ${OBFUS_MAX_PAD}
  min_delay_ms: ${OBFUS_MIN_DELAY}
  max_delay_ms: ${OBFUS_MAX_DELAY}
  burst_chance: 0.15

raw_socket:
  enabled: false
EOF

    # Add HTTP Mimicry config if needed
    if [ ${#HTTP_CONFIGS[@]} -gt 0 ]; then
        cat >> "$CONFIG_FILE" << EOF

http_mimic:
  fake_domain: "${HTTP_DOMAIN}"
  fake_path: "${HTTP_PATH}"
  user_agent: "${HTTP_UA}"
  chunked_encoding: ${HTTP_CHUNKED}
  session_cookie: ${HTTP_COOKIES}
  custom_headers:
    - "X-Requested-With: XMLHttpRequest"
    - "Referer: https://${HTTP_DOMAIN}/"
EOF
    fi

    # Add SMUX config if configured
    if [ -n "$SMUX_KEEPALIVE" ]; then
        cat >> "$CONFIG_FILE" << EOF

smux:
  keepalive: ${SMUX_KEEPALIVE}
  max_recv: ${SMUX_MAXRECV}
  max_stream: ${SMUX_MAXSTREAM}
  frame_size: ${SMUX_FRAMESIZE}
  version: 2
EOF
    fi

    # Add Advanced config if configured
    if [ -n "$TCP_NODELAY" ]; then
        cat >> "$CONFIG_FILE" << EOF

advanced:
  tcp_nodelay: ${TCP_NODELAY}
  tcp_keepalive: ${TCP_KEEPALIVE}
  tcp_read_buffer: ${TCP_READBUFFER}
  tcp_write_buffer: ${TCP_WRITEBUFFER}
  connection_timeout: 60
  stream_timeout: 120
  udp_buffer_size: 4194304
EOF
    fi

# Add Raw Socket detailed config if enabled
if [ "$CLIENT_RAW_SOCKET_ENABLED" == "true" ]; then
    cat >> "$CONFIG_FILE" << EOF
  interface: "${CLIENT_RAW_INTERFACE}"
  local_ip: "${CLIENT_RAW_LOCAL_IP}"
  local_port: ${CLIENT_RAW_LOCAL_PORT}
  gateway_mac: "${CLIENT_RAW_GATEWAY_MAC}"
  min_packet_size: ${CLIENT_RAW_MIN_PKT}
  max_packet_size: ${CLIENT_RAW_MAX_PKT}
  coalesce_timeout_ms: ${CLIENT_RAW_COALESCE}
  use_compression: ${CLIENT_RAW_USE_COMPRESS}
  compression_level: ${CLIENT_RAW_COMPRESS_LVL}
  batch_size: ${CLIENT_RAW_BATCH}
  buffer_size: ${CLIENT_RAW_BUFFER}
  use_zero_copy: ${CLIENT_RAW_USE_ZCOPY}
  mtu: ${CLIENT_RAW_MTU}
  snap_len: ${CLIENT_RAW_SNAPLEN}
EOF
fi
    create_systemd_service "client"

    systemctl start DaggerConnect-client
    systemctl enable DaggerConnect-client

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}   ✓ Client installation complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Important Info:${NC}"
echo -e "  Profile: ${GREEN}${PROFILE}${NC}"
echo -e "  Obfuscation: ${GREEN}${OBFUS_ENABLED}${NC}"

if [ "$CLIENT_RAW_SOCKET_ENABLED" == "true" ]; then
    echo -e "  Raw Socket: ${GREEN}Enabled${NC}"
    echo -e "    └─ Interface: ${GREEN}${CLIENT_RAW_INTERFACE}${NC}"
    echo -e "    └─ IP: ${GREEN}${CLIENT_RAW_LOCAL_IP}:${CLIENT_RAW_LOCAL_PORT}${NC}"
    echo -e "    └─ Gateway MAC: ${GREEN}${CLIENT_RAW_GATEWAY_MAC}${NC}"
else
    echo -e "  Raw Socket: ${YELLOW}Disabled${NC}"
fi

echo ""
echo "  Config: $CONFIG_FILE"
echo "  View logs: journalctl -u DaggerConnect-client -f"
echo ""
read -p "Press Enter to return to menu..."
main_menu

}

main_menu() {
    show_banner

    CURRENT_VER=$(get_current_version)
    if [ "$CURRENT_VER" != "not-installed" ]; then
        echo -e "${CYAN}Current Version: ${GREEN}$CURRENT_VER${NC}"
        echo ""
    fi

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}         INSTALLATION MENU${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo "  1) Install Server"
    echo "  2) Install Client"
    echo ""
    echo "  0) Exit"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1) install_server ;;
        2) install_client ;;
        0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 2; main_menu ;;
    esac
}

# Main execution
check_root
show_banner
install_dependencies

if [ ! -f "$INSTALL_DIR/DaggerConnect" ]; then
    echo -e "${YELLOW}DaggerConnect not found. Installing...${NC}"
    download_binary
    echo ""
fi

main_menu
