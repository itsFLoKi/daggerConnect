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
        apt install -y wget curl tar git openssl iproute2 > /dev/null 2>&1 || { echo -e "${RED}Failed to install dependencies${NC}"; exit 1; }
    elif command -v yum &>/dev/null; then
        yum install -y wget curl tar git openssl iproute2 > /dev/null 2>&1 || { echo -e "${RED}Failed to install dependencies${NC}"; exit 1; }
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
        echo -e "${YELLOW}⚠️  Could not fetch latest version, using v1.0${NC}"
        LATEST_VERSION="v1.0"
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

# ============================================================================
# SYSTEM OPTIMIZER
# ============================================================================

optimize_system() {
    local LOCATION=$1  # "iran" or "foreign"

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      SYSTEM OPTIMIZATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Optimizing system for: ${GREEN}${LOCATION^^}${NC}"
    echo ""

    # Detect network interface
    INTERFACE=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    if [ -z "$INTERFACE" ]; then
        INTERFACE="eth0"
        echo -e "${YELLOW}⚠️  Could not detect interface, using: $INTERFACE${NC}"
    else
        echo -e "${GREEN}✓ Detected interface: $INTERFACE${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Applying TCP optimizations...${NC}"

    # Anti-jitter & Low-latency TCP settings
    sysctl -w net.core.rmem_max=8388608 > /dev/null 2>&1
    sysctl -w net.core.wmem_max=8388608 > /dev/null 2>&1
    sysctl -w net.core.rmem_default=131072 > /dev/null 2>&1
    sysctl -w net.core.wmem_default=131072 > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_rmem="4096 65536 8388608" > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 8388608" > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_window_scaling=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_retries2=6 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_syn_retries=2 > /dev/null 2>&1

    sysctl -w net.core.netdev_max_backlog=1000 > /dev/null 2>&1
    sysctl -w net.core.somaxconn=512 > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_fastopen=3 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_low_latency=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_no_metrics_save=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_autocorking=0 > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_mtu_probing=1 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_base_mss=1024 > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_keepalive_time=120 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_probes=3 > /dev/null 2>&1

    sysctl -w net.ipv4.tcp_fin_timeout=15 > /dev/null 2>&1

    echo -e "${GREEN}✓ TCP settings optimized${NC}"

    # BBR Congestion Control
    echo ""
    echo -e "${YELLOW}Configuring BBR congestion control...${NC}"
    if modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel > /dev/null 2>&1
        echo -e "${GREEN}✓ BBR enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  BBR not available, using CUBIC${NC}"
    fi

    # Queue discipline (fq_codel for low latency)
    echo ""
    echo -e "${YELLOW}Configuring queue discipline...${NC}"
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    if tc qdisc add dev $INTERFACE root fq_codel limit 500 target 3ms interval 50ms quantum 300 ecn 2>/dev/null; then
        echo -e "${GREEN}✓ fq_codel queue configured${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not configure qdisc (may need manual setup)${NC}"
    fi

    # Make persistent
    echo ""
    echo -e "${YELLOW}Making settings persistent...${NC}"
    cat > /etc/sysctl.d/99-daggerconnect.conf << 'EOF'
# DaggerConnect Optimizations
net.core.rmem_max=8388608
net.core.wmem_max=8388608
net.core.rmem_default=131072
net.core.wmem_default=131072

net.ipv4.tcp_rmem=4096 65536 8388608
net.ipv4.tcp_wmem=4096 65536 8388608

net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_retries2=6
net.ipv4.tcp_syn_retries=2

net.core.netdev_max_backlog=1000
net.core.somaxconn=512

net.ipv4.tcp_fastopen=3
net.ipv4.tcp_low_latency=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_autocorking=0

net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_base_mss=1024

net.ipv4.tcp_keepalive_time=120
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=3

net.ipv4.tcp_fin_timeout=15

net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq_codel
EOF
    echo -e "${GREEN}✓ Settings will persist after reboot${NC}"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✓ System optimization complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
}

system_optimizer_menu() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      SYSTEM OPTIMIZER${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo "  1) Optimize for Iran Server"
    echo "  2) Optimize for Foreign Server"
    echo ""
    echo "  0) Back to Main Menu"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1)
            optimize_system "iran"
            read -p "Press Enter to continue..."
            main_menu
            ;;
        2)
            optimize_system "foreign"
            read -p "Press Enter to continue..."
            main_menu
            ;;
        0) main_menu ;;
        *) system_optimizer_menu ;;
    esac
}

# ============================================================================
# AUTOMATIC CONFIGURATION
# ============================================================================

install_server_automatic() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}   AUTOMATIC SERVER CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""

    # Only ask essential questions
    read -p "Tunnel Port [2020]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-2020}

    while true; do
        read -sp "Enter PSK (Pre-Shared Key): " PSK
        echo ""
        if [ -z "$PSK" ]; then
            echo -e "${RED}PSK cannot be empty!${NC}"
        else
            break
        fi
    done

    # Transport selection
    echo ""
    echo -e "${YELLOW}Select Transport:${NC}"
    echo "  1) httpsmux  - HTTPS Mimicry (Recommended)"
    echo "  2) httpmux   - HTTP Mimicry"
    echo "  3) wssmux    - WebSocket Secure (TLS)"
    echo "  4) wsmux     - WebSocket"
    echo "  5) kcpmux    - KCP (UDP based)"
    echo "  6) tcpmux    - Simple TCP"
    read -p "Choice [1-6]: " trans_choice
    case $trans_choice in
        1) TRANSPORT="httpsmux" ;;
        2) TRANSPORT="httpmux" ;;
        3) TRANSPORT="wssmux" ;;
        4) TRANSPORT="wsmux" ;;
        5) TRANSPORT="kcpmux" ;;
        6) TRANSPORT="tcpmux" ;;
        *) TRANSPORT="httpsmux" ;;
    esac

    # Port mappings
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

    # Generate SSL cert if needed
    CERT_FILE=""
    KEY_FILE=""
    if [ "$TRANSPORT" == "httpsmux" ] || [ "$TRANSPORT" == "wssmux" ]; then
        echo ""
        echo -e "${YELLOW}Generating SSL certificate...${NC}"
        read -p "Domain for certificate [www.google.com]: " CERT_DOMAIN
        CERT_DOMAIN=${CERT_DOMAIN:-www.google.com}

        mkdir -p "$CONFIG_DIR/certs"
        openssl req -x509 -newkey rsa:4096 -keyout "$CONFIG_DIR/certs/key.pem" \
            -out "$CONFIG_DIR/certs/cert.pem" -days 365 -nodes \
            -subj "/C=US/ST=California/L=San Francisco/O=MyCompany/CN=${CERT_DOMAIN}" \
            2>/dev/null

        CERT_FILE="$CONFIG_DIR/certs/cert.pem"
        KEY_FILE="$CONFIG_DIR/certs/key.pem"
        echo -e "${GREEN}✓ Certificate generated${NC}"
    fi

    # Write optimized config
    CONFIG_FILE="$CONFIG_DIR/server.yaml"
    cat > "$CONFIG_FILE" << EOF
mode: "server"
listen: "0.0.0.0:${LISTEN_PORT}"
transport: "${TRANSPORT}"
psk: "${PSK}"
profile: "latency"
verbose: true

heartbeat: 2

EOF

    if [[ -n "$CERT_FILE" ]]; then
        cat >> "$CONFIG_FILE" << EOF
cert_file: "$CERT_FILE"
key_file: "$KEY_FILE"

EOF
    fi

    echo -e "maps:\n$MAPPINGS" >> "$CONFIG_FILE"

    cat >> "$CONFIG_FILE" << 'EOF'

smux:
  keepalive: 1
  max_recv: 524288
  max_stream: 524288
  frame_size: 2048
  version: 2

kcp:
  nodelay: 1
  interval: 5
  resend: 2
  nc: 1
  sndwnd: 256
  rcvwnd: 256
  mtu: 1200

advanced:
  tcp_nodelay: true
  tcp_keepalive: 3
  tcp_read_buffer: 32768
  tcp_write_buffer: 32768
  websocket_read_buffer: 16384
  websocket_write_buffer: 16384
  websocket_compression: false
  cleanup_interval: 1
  session_timeout: 15
  connection_timeout: 20
  stream_timeout: 45
  max_connections: 300
  max_udp_flows: 150
  udp_flow_timeout: 90
  udp_buffer_size: 262144

obfuscation:
  enabled: true
  min_padding: 8
  max_padding: 32
  min_delay_ms: 0
  max_delay_ms: 0
  burst_chance: 0

http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  chunked_encoding: false
  session_cookie: true
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Accept-Encoding: gzip, deflate, br"
EOF

    create_systemd_service "server"

    # Optimize system
    echo ""
    read -p "Optimize system now? [Y/n]: " opt
    if [[ ! $opt =~ ^[Nn]$ ]]; then
        optimize_system "iran"
    fi

    systemctl start DaggerConnect-server
    systemctl enable DaggerConnect-server

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✓ Server configured (Optimized)${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "  Tunnel Port: ${GREEN}${LISTEN_PORT}${NC}"
    echo -e "  PSK: ${GREEN}${PSK}${NC}"
    echo -e "  Transport: ${GREEN}${TRANSPORT}${NC}"
    echo -e "  Config: $CONFIG_FILE"
    echo ""
    read -p "Press Enter to return..."
    main_menu
}

install_client_automatic() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}   AUTOMATIC CLIENT CONFIGURATION${NC}"
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
    echo -e "${YELLOW}Select Transport:${NC}"
    echo "  1) httpsmux  - HTTPS Mimicry (Recommended)"
    echo "  2) httpmux   - HTTP Mimicry"
    echo "  3) wssmux    - WebSocket Secure (TLS)"
    echo "  4) wsmux     - WebSocket"
    echo "  5) kcpmux    - KCP (UDP based)"
    echo "  6) tcpmux    - Simple TCP"
    read -p "Choice [1-6]: " trans_choice
    case $trans_choice in
        1) TRANSPORT="httpsmux" ;;
        2) TRANSPORT="httpmux" ;;
        3) TRANSPORT="wssmux" ;;
        4) TRANSPORT="wsmux" ;;
        5) TRANSPORT="kcpmux" ;;
        6) TRANSPORT="tcpmux" ;;
        *) TRANSPORT="httpsmux" ;;
    esac

    read -p "Server address with port (e.g., 1.2.3.4:2020): " ADDR
    if [ -z "$ADDR" ]; then
        echo -e "${RED}Address cannot be empty!${NC}"
        install_client_automatic
        return
    fi

    # Write optimized config
    CONFIG_FILE="$CONFIG_DIR/client.yaml"
    cat > "$CONFIG_FILE" << EOF
mode: "client"
psk: "${PSK}"
profile: "latency"
verbose: true

heartbeat: 2

paths:
  - transport: "${TRANSPORT}"
    addr: "${ADDR}"
    connection_pool: 3
    aggressive_pool: true
    retry_interval: 1
    dial_timeout: 5

smux:
  keepalive: 1
  max_recv: 524288
  max_stream: 524288
  frame_size: 2048
  version: 2

kcp:
  nodelay: 1
  interval: 5
  resend: 2
  nc: 1
  sndwnd: 256
  rcvwnd: 256
  mtu: 1200

advanced:
  tcp_nodelay: true
  tcp_keepalive: 3
  tcp_read_buffer: 32768
  tcp_write_buffer: 32768
  websocket_read_buffer: 16384
  websocket_write_buffer: 16384
  websocket_compression: false
  cleanup_interval: 1
  session_timeout: 15
  connection_timeout: 20
  stream_timeout: 45
  max_connections: 300
  max_udp_flows: 150
  udp_flow_timeout: 90
  udp_buffer_size: 262144

obfuscation:
  enabled: true
  min_padding: 8
  max_padding: 32
  min_delay_ms: 0
  max_delay_ms: 0
  burst_chance: 0

http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  chunked_encoding: false
  session_cookie: true
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Accept-Encoding: gzip, deflate, br"
EOF

    create_systemd_service "client"

    # Optimize system
    echo ""
    read -p "Optimize system now? [Y/n]: " opt
    if [[ ! $opt =~ ^[Nn]$ ]]; then
        optimize_system "foreign"
    fi

    systemctl start DaggerConnect-client
    systemctl enable DaggerConnect-client

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✓ Client configured (Optimized)${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "  Server: ${GREEN}${ADDR}${NC}"
    echo -e "  Transport: ${GREEN}${TRANSPORT}${NC}"
    echo -e "  Config: $CONFIG_FILE"
    echo ""
    read -p "Press Enter to return..."
    main_menu
}

# ============================================================================
# MANUAL CONFIGURATION (Original)
# ============================================================================

update_binary() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      UPDATE DaggerConnect CORE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""

    CURRENT_VERSION=$(get_current_version)

    if [ "$CURRENT_VERSION" == "not-installed" ]; then
        echo -e "${RED}❌ DaggerConnect is not installed yet${NC}"
        echo ""
        read -p "Press Enter to return to menu..."
        main_menu
        return
    fi

    echo -e "${CYAN}Current Version: ${GREEN}$CURRENT_VERSION${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  This will:${NC}"
    echo "  - Stop all running services"
    echo "  - Download latest version from GitHub"
    echo "  - Restart services automatically"
    echo ""
    read -p "Continue with update? [y/N]: " confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        main_menu
        return
    fi

    echo ""
    echo -e "${YELLOW}Stopping services...${NC}"
    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    sleep 2

    download_binary

    NEW_VERSION=$(get_current_version)

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}   ✓ Update completed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "  Previous Version: ${YELLOW}$CURRENT_VERSION${NC}"
    echo -e "  Current Version:  ${GREEN}$NEW_VERSION${NC}"
    echo ""

    if systemctl is-enabled DaggerConnect-server &>/dev/null || systemctl is-enabled DaggerConnect-client &>/dev/null; then
        read -p "Restart services now? [Y/n]: " restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            echo ""
            if systemctl is-enabled DaggerConnect-server &>/dev/null; then
                systemctl start DaggerConnect-server
                echo -e "${GREEN}✓ Server restarted${NC}"
            fi
            if systemctl is-enabled DaggerConnect-client &>/dev/null; then
                systemctl start DaggerConnect-client
                echo -e "${GREEN}✓ Client restarted${NC}"
            fi
        fi
    fi

    echo ""
    read -p "Press Enter to return to menu..."
    main_menu
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

install_server() {
    show_banner
    mkdir -p "$CONFIG_DIR"

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      SERVER CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""

    echo -e "${YELLOW}Configuration Mode:${NC}"
    echo "  1) Automatic - Optimized settings (Recommended)"
    echo "  2) Manual - Custom configuration"
    echo ""
    read -p "Choice [1-2]: " config_mode

    if [ "$config_mode" == "1" ]; then
        install_server_automatic
        return
    fi

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

    if [ "$TRANSPORT" == "httpmux" ] || [ "$TRANSPORT" == "httpsmux" ]; then
        configure_http_mimicry
    fi

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

    configure_advanced_settings "server"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      PORT MAPPINGS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Port Settings:${NC}"
    echo "  Bind   = Port opened on this server"
    echo "  Target = Destination port (usually localhost)"
    echo ""
    MAPPINGS=""
    COUNT=0
    while true; do
        echo ""
        echo -e "${YELLOW}Add Port Mapping #$((COUNT+1))${NC}"

        echo "Protocol:"
        echo "  1) tcp"
        echo "  2) udp"
        echo "  3) both (tcp + udp)"
        read -p "Choice [1-3]: " proto_choice

        while true; do
            echo ""
            echo -e "${CYAN}Bind Settings (port on this server):${NC}"
            read -p "Bind IP [0.0.0.0]: " BIND_IP
            BIND_IP=${BIND_IP:-0.0.0.0}

            read -p "Bind Port (e.g., 2222): " BIND_PORT
            if [[ -n "$BIND_PORT" ]] && [[ "$BIND_PORT" =~ ^[0-9]+$ ]] && [ "$BIND_PORT" -ge 1 ] && [ "$BIND_PORT" -le 65535 ]; then
                break
            else
                echo -e "${RED}⚠ Invalid port! Enter a number between 1-65535${NC}"
            fi
        done

        while true; do
            echo ""
            echo -e "${CYAN}Target Settings (destination port):${NC}"
            read -p "Target IP [127.0.0.1]: " TARGET_IP
            TARGET_IP=${TARGET_IP:-127.0.0.1}

            read -p "Target Port (e.g., 22): " TARGET_PORT
            if [[ -n "$TARGET_PORT" ]] && [[ "$TARGET_PORT" =~ ^[0-9]+$ ]] && [ "$TARGET_PORT" -ge 1 ] && [ "$TARGET_PORT" -le 65535 ]; then
                break
            else
                echo -e "${RED}⚠ Invalid port! Enter a number between 1-65535${NC}"
            fi
        done

        BIND="${BIND_IP}:${BIND_PORT}"
        TARGET="${TARGET_IP}:${TARGET_PORT}"

        echo ""
        echo -e "${GREEN}✓ Mapping: ${BIND} → ${TARGET}${NC}"

        case $proto_choice in
            1)
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND}\"\n    target: \"${TARGET}\"\n"
                ;;
            2)
                MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND}\"\n    target: \"${TARGET}\"\n"
                ;;
            3)
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND}\"\n    target: \"${TARGET}\"\n"
                MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND}\"\n    target: \"${TARGET}\"\n"
                ;;
            *)
                echo -e "${RED}Invalid choice, skipping...${NC}"
                continue
                ;;
        esac

        COUNT=$((COUNT+1))
        read -p "Add another port mapping? (y/n) [n]: " add_more
        [[ "$add_more" =~ ^[Yy] ]] || break
    done

    echo ""
    read -p "Enable verbose logging? [y/N]: " VERBOSE
    [[ $VERBOSE =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

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

    echo -e "${YELLOW}Configuration Mode:${NC}"
    echo "  1) Automatic - Optimized settings (Recommended)"
    echo "  2) Manual - Custom configuration"
    echo ""
    read -p "Choice [1-2]: " config_mode

    if [ "$config_mode" == "1" ]; then
        install_client_automatic
        return
    fi

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
EOF

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
    echo ""
    echo "  Config: $CONFIG_FILE"
    echo "  View logs: journalctl -u DaggerConnect-client -f"
    echo ""
    read -p "Press Enter to return to menu..."
    main_menu
}

service_management() {
    local MODE=$1
    local SERVICE_NAME="DaggerConnect-${MODE}"
    local CONFIG_FILE="$CONFIG_DIR/${MODE}.yaml"
    local TITLE="${MODE^} MANAGEMENT"

    show_banner
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}         ${TITLE}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo "  1) Start ${MODE^}"
    echo "  2) Stop ${MODE^}"
    echo "  3) Restart ${MODE^}"
    echo "  4) ${MODE^} Status"
    echo "  5) View ${MODE^} Logs (Live)"
    echo "  6) Enable ${MODE^} Auto-start"
    echo "  7) Disable ${MODE^} Auto-start"
    echo ""
    echo "  8) View ${MODE^} Config"
    echo "  9) Edit ${MODE^} Config"
    echo "  10) Delete ${MODE^} Config & Service"
    echo ""
    echo "  0) Back to Settings"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1) systemctl start "$SERVICE_NAME"; echo -e "${GREEN}✓ ${MODE^} started${NC}"; sleep 2; service_management "$MODE" ;;
        2) systemctl stop "$SERVICE_NAME"; echo -e "${GREEN}✓ ${MODE^} stopped${NC}"; sleep 2; service_management "$MODE" ;;
        3) systemctl restart "$SERVICE_NAME"; echo -e "${GREEN}✓ ${MODE^} restarted${NC}"; sleep 2; service_management "$MODE" ;;
        4) systemctl status "$SERVICE_NAME" --no-pager; read -p "Press Enter to continue..."; service_management "$MODE" ;;
        5) journalctl -u "$SERVICE_NAME" -f ;;
        6) systemctl enable "$SERVICE_NAME"; echo -e "${GREEN}✓ Auto-start enabled${NC}"; sleep 2; service_management "$MODE" ;;
        7) systemctl disable "$SERVICE_NAME"; echo -e "${GREEN}✓ Auto-start disabled${NC}"; sleep 2; service_management "$MODE" ;;
        8)
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo -e "${RED}${MODE^} config not found${NC}"
            fi
            read -p "Press Enter to continue..."
            service_management "$MODE"
            ;;
        9)
            if [ -f "$CONFIG_FILE" ]; then
                ${EDITOR:-nano} "$CONFIG_FILE"
                echo ""
                read -p "Restart service to apply changes? [y/N]: " restart
                if [[ $restart =~ ^[Yy]$ ]]; then
                    systemctl restart "$SERVICE_NAME"
                    echo -e "${GREEN}✓ Service restarted${NC}"
                    sleep 2
                fi
            else
                echo -e "${RED}${MODE^} config not found${NC}"
                sleep 2
            fi
            service_management "$MODE"
            ;;
        10)
            read -p "Delete ${MODE^} config and service? [y/N]: " c
            if [[ $c =~ ^[Yy]$ ]]; then
                systemctl stop "$SERVICE_NAME" 2>/dev/null
                systemctl disable "$SERVICE_NAME" 2>/dev/null
                rm -f "$CONFIG_FILE"
                rm -f "$SYSTEMD_DIR/${SERVICE_NAME}.service"
                systemctl daemon-reload
                echo -e "${GREEN}✓ ${MODE^} configuration and service deleted${NC}"
                sleep 2
            fi
            settings_menu
            ;;
        0) settings_menu ;;
        *) service_management "$MODE" ;;
    esac
}

settings_menu() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}            SETTINGS MENU${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo "  1) Manage Server"
    echo "  2) Manage Client"
    echo ""
    echo "  0) Back to Main Menu"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1) service_management "server" ;;
        2) service_management "client" ;;
        0) main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 2; settings_menu ;;
    esac
}

uninstall_DaggerConnect() {
    show_banner
    echo -e "${RED}═══════════════════════════════════════${NC}"
    echo -e "${RED}         UNINSTALL DaggerConnect${NC}"
    echo -e "${RED}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  This will remove:${NC}"
    echo "  - DaggerConnect binary"
    echo "  - All configurations (/etc/DaggerConnect)"
    echo "  - Systemd services (server/client)"
    echo "  - SSL certificates (if any)"
    echo "  - System optimizations"
    echo ""
    read -p "Are you sure? [y/N]: " c

    if [[ ! $c =~ ^[Yy]$ ]]; then
        main_menu
        return
    fi

    echo ""
    echo -e "${YELLOW}Stopping services and removing systemd files...${NC}"
    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    systemctl disable DaggerConnect-server 2>/dev/null
    systemctl disable DaggerConnect-client 2>/dev/null

    rm -f "$SYSTEMD_DIR/DaggerConnect-server.service"
    rm -f "$SYSTEMD_DIR/DaggerConnect-client.service"

    echo -e "${YELLOW}Removing binary and configs...${NC}"
    rm -f "$INSTALL_DIR/DaggerConnect"
    rm -rf "$CONFIG_DIR"

    echo -e "${YELLOW}Removing system optimizations...${NC}"
    rm -f /etc/sysctl.d/99-daggerconnect.conf
    sysctl -p > /dev/null 2>&1

    systemctl daemon-reload

    echo ""
    echo -e "${GREEN}✓ DaggerConnect uninstalled successfully${NC}"
    echo ""
    exit 0
}

main_menu() {
    show_banner

    CURRENT_VER=$(get_current_version)
    if [ "$CURRENT_VER" != "not-installed" ]; then
        echo -e "${CYAN}Current Version: ${GREEN}$CURRENT_VER${NC}"
        echo ""
    fi

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}            MAIN MENU${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo "  1) Install Server"
    echo "  2) Install Client"
    echo "  3) Settings (Manage Services & Configs)"
    echo "  4) System Optimizer"
    echo "  5) Update Core (Re-download Binary)"
    echo "  6) Uninstall DaggerConnect"
    echo ""
    echo "  0) Exit"
    echo ""
    read -p "Select option: " choice

    case $choice in
        1) install_server ;;
        2) install_client ;;
        3) settings_menu ;;
        4) system_optimizer_menu ;;
        5) update_binary ;;
        6) uninstall_DaggerConnect ;;
        0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 2; main_menu ;;
    esac
}

check_root
show_banner
install_dependencies

if [ ! -f "$INSTALL_DIR/DaggerConnect" ]; then
    echo -e "${YELLOW}DaggerConnect not found. Installing...${NC}"
    download_binary
    echo ""
fi

main_menu
