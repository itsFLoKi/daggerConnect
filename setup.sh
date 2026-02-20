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
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    if command -v apt &>/dev/null; then
        apt update -qq
        apt install -y wget curl tar git openssl iproute2 > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y wget curl tar git openssl iproute2 > /dev/null 2>&1
    else
        echo -e "${RED}Unsupported package manager${NC}"; exit 1
    fi
    echo -e "${GREEN}Dependencies installed${NC}"
}

get_current_version() {
    if [ -f "$INSTALL_DIR/DaggerConnect" ]; then
        VERSION=$("$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+\.\d+(\.\d+)?' || echo "unknown")
        echo "$VERSION"
    else
        echo "not-installed"
    fi
}

download_binary() {
    echo -e "${YELLOW}Downloading DaggerConnect binary...${NC}"
    mkdir -p "$INSTALL_DIR"
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${YELLOW}Could not fetch latest version, using v1.3.3${NC}"
        LATEST_VERSION="v1.3.3"
    fi
    BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
    echo -e "${CYAN}Latest version: ${GREEN}${LATEST_VERSION}${NC}"
    if [ -f "$INSTALL_DIR/DaggerConnect" ]; then
        mv "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.backup"
    fi
    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        echo -e "${GREEN}Downloaded successfully${NC}"
        rm -f "$INSTALL_DIR/DaggerConnect.backup"
    else
        echo -e "${RED}Download failed${NC}"
        if [ -f "$INSTALL_DIR/DaggerConnect.backup" ]; then
            mv "$INSTALL_DIR/DaggerConnect.backup" "$INSTALL_DIR/DaggerConnect"
            echo -e "${YELLOW}Restored previous version${NC}"
        fi
        exit 1
    fi
}

# ============================================================================
# SYSTEM OPTIMIZER
# ============================================================================

optimize_system() {
    local LOCATION=$1
    echo -e "${CYAN}System optimization for: ${GREEN}${LOCATION^^}${NC}"
    INTERFACE=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    [ -z "$INTERFACE" ] && INTERFACE="eth0"
    echo -e "${GREEN}Interface: $INTERFACE${NC}"

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
    sysctl -w net.ipv4.tcp_keepalive_time=120 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_probes=3 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15 > /dev/null 2>&1
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1

    if modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel > /dev/null 2>&1
        echo -e "${GREEN}BBR enabled${NC}"
    else
        echo -e "${YELLOW}BBR not available, using CUBIC${NC}"
    fi

    tc qdisc del dev "$INTERFACE" root 2>/dev/null || true
    tc qdisc add dev "$INTERFACE" root fq_codel limit 500 target 3ms interval 50ms quantum 300 ecn 2>/dev/null && \
        echo -e "${GREEN}fq_codel configured${NC}" || echo -e "${YELLOW}qdisc skipped${NC}"

    cat > /etc/sysctl.d/99-daggerconnect.conf << 'EOF'
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
net.ipv4.tcp_keepalive_time=120
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq_codel
net.ipv4.ip_forward=1
EOF
    echo -e "${GREEN}Optimization complete!${NC}"
}

system_optimizer_menu() {
    show_banner
    echo -e "${CYAN}═══ SYSTEM OPTIMIZER ═══${NC}"
    echo ""
    echo "  1) Optimize for Iran Server"
    echo "  2) Optimize for Foreign Server"
    echo "  0) Back"
    echo ""
    read -p "Select: " choice
    case $choice in
        1) optimize_system "iran"; read -p "Press Enter..."; main_menu ;;
        2) optimize_system "foreign"; read -p "Press Enter..."; main_menu ;;
        0) main_menu ;;
        *) system_optimizer_menu ;;
    esac
}

# ============================================================================
# HELPER: Select Transport
# ============================================================================
select_transport() {
    echo "" >&2
    echo -e "${YELLOW}Select Transport:${NC}" >&2
    echo "  1) httpsmux  - HTTPS Mimicry (Recommended)" >&2
    echo "  2) httpmux   - HTTP Mimicry" >&2
    echo "  3) wssmux    - WebSocket Secure" >&2
    echo "  4) wsmux     - WebSocket" >&2
    echo "  5) kcpmux    - KCP (UDP)" >&2
    echo "  6) tcpmux    - Simple TCP" >&2
    read -p "Choice [1-6]: " trans_choice >&2
    case $trans_choice in
        1) echo "httpsmux" ;;
        2) echo "httpmux" ;;
        3) echo "wssmux" ;;
        4) echo "wsmux" ;;
        5) echo "kcpmux" ;;
        6) echo "tcpmux" ;;
        *) echo "httpsmux" ;;
    esac
}

# ============================================================================
# HELPER: Configure TUN
# ============================================================================
configure_tun() {
    local IDX=$1
    local SIDE=$2

    echo ""
    echo -e "${CYAN}─── TUN Interface #${IDX} ───${NC}"
    echo -e "${YELLOW}IMPORTANT: Each TUN must use a UNIQUE /32 IP pair!${NC}"
    echo -e "${YELLOW}  /32 is used automatically to prevent subnet conflicts.${NC}"
    echo ""

    local DEFAULT_NAME="dagger${IDX}"
    read -p "Interface name [${DEFAULT_NAME}]: " TUN_NAME
    TUN_NAME=${TUN_NAME:-$DEFAULT_NAME}

    if [ "$SIDE" == "server" ]; then
        echo -e "${YELLOW}Example: local=20.40.${IDX}.1  peer=20.40.${IDX}.2${NC}"
        read -p "Local IP (server) [20.40.${IDX}.1]: " TUN_LOCAL
        TUN_LOCAL=${TUN_LOCAL:-"20.40.${IDX}.1"}
        read -p "Peer IP  (client) [20.40.${IDX}.2]: " TUN_PEER
        TUN_PEER=${TUN_PEER:-"20.40.${IDX}.2"}
    else
        echo -e "${YELLOW}Example: local=20.40.${IDX}.2  peer=20.40.${IDX}.1${NC}"
        read -p "Local IP (client) [20.40.${IDX}.2]: " TUN_LOCAL
        TUN_LOCAL=${TUN_LOCAL:-"20.40.${IDX}.2"}
        read -p "Peer IP  (server) [20.40.${IDX}.1]: " TUN_PEER
        TUN_PEER=${TUN_PEER:-"20.40.${IDX}.1"}
    fi

    read -p "MTU [1400]: " TUN_MTU
    TUN_MTU=${TUN_MTU:-1400}

    _TUN_NAME="$TUN_NAME"
    _TUN_LOCAL="$TUN_LOCAL"
    _TUN_PEER="$TUN_PEER"
    _TUN_MTU="$TUN_MTU"
}

# ============================================================================
# HELPER: Build port mappings
# ============================================================================
build_port_mappings() {
    local BIND_IP_DEFAULT="0.0.0.0"
    local TARGET_IP_DEFAULT="127.0.0.1"
    MAPPINGS=""
    local COUNT=0

    echo ""
    echo -e "${CYAN}═══ PORT MAPPINGS ═══${NC}"
    echo -e "${YELLOW}Formats: 8008 | 1000/2000 | 5000=8008 | 1000/1010=2000/2010 | 5000=1.2.3.4:8008${NC}"
    echo ""

    while true; do
        echo ""
        echo -e "${YELLOW}─ Mapping #$((COUNT+1)) ─${NC}"
        echo "  Protocol: 1)tcp  2)udp  3)both"
        read -p "  Choice [1]: " proto_choice
        case $proto_choice in
            2) PROTO="udp" ;;
            3) PROTO="both" ;;
            *) PROTO="tcp" ;;
        esac

        read -p "  Port(s): " PORT_INPUT
        if [ -z "$PORT_INPUT" ]; then
            echo -e "${RED}Cannot be empty!${NC}"; continue
        fi
        PORT_INPUT=$(echo "$PORT_INPUT" | tr -d ' ')

        # Range Mapping with custom IP: 5000/5010=1.2.3.4:8000/8010
        if [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)/([0-9]+)$ ]]; then
            BS="${BASH_REMATCH[1]}"; BE="${BASH_REMATCH[2]}"
            CTIP="${BASH_REMATCH[3]}"; TS="${BASH_REMATCH[4]}"; TE="${BASH_REMATCH[5]}"
            BR=$((BE-BS+1)); TR=$((TE-TS+1))
            [ "$BR" -ne "$TR" ] && echo -e "${RED}Range mismatch!${NC}" && continue
            for ((i=0;i<BR;i++)); do
                BP=$((BS+i)); TP=$((TS+i))
                [ "$PROTO" == "both" ] && \
                    MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${CTIP}:${TP}\"\n  - type: udp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${CTIP}:${TP}\"\n" && COUNT=$((COUNT+2)) || \
                    MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${CTIP}:${TP}\"\n" && COUNT=$((COUNT+1))
            done
            echo -e "${GREEN}Added: ${BS}-${BE} → ${CTIP}:${TS}-${TE}${NC}"

        # Range Mapping: 1000/1010=2000/2010
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+)/([0-9]+)$ ]]; then
            BS="${BASH_REMATCH[1]}"; BE="${BASH_REMATCH[2]}"
            TS="${BASH_REMATCH[3]}"; TE="${BASH_REMATCH[4]}"
            BR=$((BE-BS+1)); TR=$((TE-TS+1))
            [ "$BR" -ne "$TR" ] && echo -e "${RED}Range mismatch!${NC}" && continue
            for ((i=0;i<BR;i++)); do
                BP=$((BS+i)); TP=$((TS+i))
                [ "$PROTO" == "both" ] && \
                    MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${TARGET_IP_DEFAULT}:${TP}\"\n  - type: udp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${TARGET_IP_DEFAULT}:${TP}\"\n" && COUNT=$((COUNT+2)) || \
                    MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${TARGET_IP_DEFAULT}:${TP}\"\n" && COUNT=$((COUNT+1))
            done
            echo -e "${GREEN}Added: ${BS}-${BE} → ${TS}-${TE} (${BR} ports, ${PROTO})${NC}"

        # Range: 1000/2000
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            SP="${BASH_REMATCH[1]}"; EP="${BASH_REMATCH[2]}"
            [ "$SP" -gt "$EP" ] && echo -e "${RED}Start > end!${NC}" && continue
            RS=$((EP-SP+1))
            [ "$RS" -gt 1000 ] && read -p "Large range (${RS} ports). Continue? [y/N]: " cr && [[ ! $cr =~ ^[Yy]$ ]] && continue
            for ((port=SP;port<=EP;port++)); do
                [ "$PROTO" == "both" ] && \
                    MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP_DEFAULT}:${port}\"\n    target: \"${TARGET_IP_DEFAULT}:${port}\"\n  - type: udp\n    bind: \"${BIND_IP_DEFAULT}:${port}\"\n    target: \"${TARGET_IP_DEFAULT}:${port}\"\n" && COUNT=$((COUNT+2)) || \
                    MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP_DEFAULT}:${port}\"\n    target: \"${TARGET_IP_DEFAULT}:${port}\"\n" && COUNT=$((COUNT+1))
            done
            echo -e "${GREEN}Added: ${SP}-${EP} (${RS} ports, ${PROTO})${NC}"

        # Custom with IP: 5000=1.2.3.4:8008
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
            BP="${BASH_REMATCH[1]}"; CTIP="${BASH_REMATCH[2]}"; TP="${BASH_REMATCH[3]}"
            [ "$PROTO" == "both" ] && \
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${CTIP}:${TP}\"\n  - type: udp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${CTIP}:${TP}\"\n" && COUNT=$((COUNT+2)) || \
                MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${CTIP}:${TP}\"\n" && COUNT=$((COUNT+1))
            echo -e "${GREEN}Added: ${BP} → ${CTIP}:${TP} (${PROTO})${NC}"

        # Custom: 5000=8008
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            BP="${BASH_REMATCH[1]}"; TP="${BASH_REMATCH[2]}"
            [ "$PROTO" == "both" ] && \
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${TARGET_IP_DEFAULT}:${TP}\"\n  - type: udp\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${TARGET_IP_DEFAULT}:${TP}\"\n" && COUNT=$((COUNT+2)) || \
                MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP_DEFAULT}:${BP}\"\n    target: \"${TARGET_IP_DEFAULT}:${TP}\"\n" && COUNT=$((COUNT+1))
            echo -e "${GREEN}Added: ${BP} → ${TP} (${PROTO})${NC}"

        # Single: 8008
        elif [[ "$PORT_INPUT" =~ ^[0-9]+$ ]]; then
            [ "$PORT_INPUT" -lt 1 ] || [ "$PORT_INPUT" -gt 65535 ] && echo -e "${RED}Invalid port!${NC}" && continue
            [ "$PROTO" == "both" ] && \
                MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP_DEFAULT}:${PORT_INPUT}\"\n    target: \"${TARGET_IP_DEFAULT}:${PORT_INPUT}\"\n  - type: udp\n    bind: \"${BIND_IP_DEFAULT}:${PORT_INPUT}\"\n    target: \"${TARGET_IP_DEFAULT}:${PORT_INPUT}\"\n" && COUNT=$((COUNT+2)) || \
                MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP_DEFAULT}:${PORT_INPUT}\"\n    target: \"${TARGET_IP_DEFAULT}:${PORT_INPUT}\"\n" && COUNT=$((COUNT+1))
            echo -e "${GREEN}Added: ${PORT_INPUT} → ${PORT_INPUT} (${PROTO})${NC}"
        else
            echo -e "${RED}Invalid format!${NC}"; continue
        fi

        read -p "Add another mapping? [y/N]: " am
        [[ ! "$am" =~ ^[Yy]$ ]] && break
    done

    if [ "$COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No mappings — using default 8080→8080${NC}"
        MAPPINGS="  - type: tcp\n    bind: \"0.0.0.0:8080\"\n    target: \"127.0.0.1:8080\"\n"
    fi
}

# ============================================================================
# WRITE COMMON CONFIG TAIL
# ============================================================================
write_common_tail() {
    local FILE=$1
    cat >> "$FILE" << 'EOF'

smux:
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768
  version: 2

kcp:
  nodelay: 1
  interval: 10
  resend: 2
  nc: 1
  sndwnd: 1024
  rcvwnd: 1024
  mtu: 1400

advanced:
  tcp_nodelay: true
  tcp_keepalive: 15
  tcp_read_buffer: 4194304
  tcp_write_buffer: 4194304
  websocket_read_buffer: 65536
  websocket_write_buffer: 65536
  websocket_compression: false
  cleanup_interval: 3
  session_timeout: 60
  connection_timeout: 30
  stream_timeout: 120
  max_connections: 2000
  max_udp_flows: 1000
  udp_flow_timeout: 300
  udp_buffer_size: 4194304

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 512
  min_delay_ms: 0
  max_delay_ms: 0
  burst_chance: 0.15

http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  chunked_encoding: false
  session_cookie: true
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Accept-Encoding: gzip, deflate, br"
EOF
}

# ============================================================================
# SSL CERT HELPER
# ============================================================================
gen_ssl_cert() {
    local CERT_OUT=$1
    local KEY_OUT=$2
    local DOMAIN=$3
    mkdir -p "$(dirname "$CERT_OUT")"
    openssl req -x509 -newkey rsa:4096 -keyout "$KEY_OUT" -out "$CERT_OUT" \
        -days 365 -nodes -subj "/C=US/O=MyCompany/CN=${DOMAIN}" 2>/dev/null && \
        echo -e "${GREEN}SSL cert generated${NC}" || echo -e "${RED}SSL cert generation failed${NC}"
}

# ============================================================================
# AUTOMATIC SERVER
# ============================================================================
install_server_automatic() {
    echo ""
    echo -e "${CYAN}═══ AUTOMATIC SERVER ═══${NC}"
    echo ""

    read -p "Tunnel Port [2020]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-2020}

    while true; do
        read -sp "PSK: " PSK; echo ""
        [ -n "$PSK" ] && break
        echo -e "${RED}PSK cannot be empty!${NC}"
    done

    TRANSPORT=$(select_transport)

    build_port_mappings
    AUTO_MAPPINGS="$MAPPINGS"

    CERT_FILE=""; KEY_FILE=""
    if [ "$TRANSPORT" == "httpsmux" ] || [ "$TRANSPORT" == "wssmux" ]; then
        read -p "Domain for SSL cert [www.google.com]: " CD; CD=${CD:-www.google.com}
        gen_ssl_cert "$CONFIG_DIR/certs/cert.pem" "$CONFIG_DIR/certs/key.pem" "$CD"
        CERT_FILE="$CONFIG_DIR/certs/cert.pem"
        KEY_FILE="$CONFIG_DIR/certs/key.pem"
    fi

    CONFIG_FILE="$CONFIG_DIR/server.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"server\""
        echo "psk: \"${PSK}\""
        echo "profile: \"latency\""
        echo "verbose: true"
        echo "heartbeat: 2"
        echo ""
        [ -n "$CERT_FILE" ] && echo "cert_file: \"${CERT_FILE}\"" && echo "key_file: \"${KEY_FILE}\"" && echo ""
        echo "listeners:"
        echo "  - addr: \"0.0.0.0:${LISTEN_PORT}\""
        echo "    transport: \"${TRANSPORT}\""
        [ -n "$CERT_FILE" ] && echo "    cert_file: \"${CERT_FILE}\"" && echo "    key_file: \"${KEY_FILE}\""
        echo "    maps:"
        printf '%b' "$AUTO_MAPPINGS" | sed 's/^/    /'
    } > "$CONFIG_FILE"

    write_common_tail "$CONFIG_FILE"
    create_systemd_service "server"

    read -p "Optimize system? [Y/n]: " opt
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "iran"

    systemctl start DaggerConnect-server
    systemctl enable DaggerConnect-server

    echo -e "${GREEN}Server configured! Port=${LISTEN_PORT} Transport=${TRANSPORT}${NC}"
    read -p "Press Enter..."; main_menu
}

# ============================================================================
# MANUAL SERVER - MULTI-LISTENER
# ============================================================================
install_server_multilistener() {
    echo ""
    echo -e "${CYAN}═══ SERVER — MULTI-LISTENER ═══${NC}"
    echo -e "${YELLOW}Each listener is fully isolated (own sessions, own TUN).${NC}"
    echo ""

    while true; do
        read -sp "Global PSK: " GLOBAL_PSK; echo ""
        [ -n "$GLOBAL_PSK" ] && break
        echo -e "${RED}PSK cannot be empty!${NC}"
    done

    echo ""
    echo "Profile: 1)balanced 2)aggressive 3)latency 4)cpu-efficient 5)gaming"
    read -p "Choice [1]: " pc
    case $pc in 2) PROFILE="aggressive";; 3) PROFILE="latency";; 4) PROFILE="cpu-efficient";; 5) PROFILE="gaming";; *) PROFILE="balanced";; esac

    read -p "Heartbeat (seconds) [10]: " HB; HB=${HB:-10}
    read -p "Verbose? [y/N]: " VB; [[ $VB =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

    # Global SSL
    GLOBAL_CERT=""; GLOBAL_KEY=""
    read -p "Generate global SSL cert? [y/N]: " GC
    if [[ $GC =~ ^[Yy]$ ]]; then
        read -p "Domain [www.google.com]: " CD; CD=${CD:-www.google.com}
        gen_ssl_cert "$CONFIG_DIR/certs/cert.pem" "$CONFIG_DIR/certs/key.pem" "$CD"
        GLOBAL_CERT="$CONFIG_DIR/certs/cert.pem"
        GLOBAL_KEY="$CONFIG_DIR/certs/key.pem"
    fi

    CONFIG_FILE="$CONFIG_DIR/server.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"server\""
        echo "psk: \"${GLOBAL_PSK}\""
        echo "profile: \"${PROFILE}\""
        echo "verbose: ${VERBOSE}"
        echo "heartbeat: ${HB}"
        echo ""
        [ -n "$GLOBAL_CERT" ] && echo "cert_file: \"${GLOBAL_CERT}\"" && echo "key_file: \"${GLOBAL_KEY}\"" && echo ""
        echo "listeners:"
    } > "$CONFIG_FILE"

    LISTENER_COUNT=0
    while true; do
        echo ""
        echo -e "${PURPLE}══ LISTENER #${LISTENER_COUNT} ══${NC}"

        read -p "Bind address [0.0.0.0:$((4000+LISTENER_COUNT))]: " L_ADDR
        L_ADDR=${L_ADDR:-"0.0.0.0:$((4000+LISTENER_COUNT))"}

        L_TRANSPORT=$(select_transport)

        # Per-listener cert
        L_CERT=""; L_KEY=""
        if [ "$L_TRANSPORT" == "httpsmux" ] || [ "$L_TRANSPORT" == "wssmux" ]; then
            if [ -n "$GLOBAL_CERT" ]; then
                L_CERT="$GLOBAL_CERT"; L_KEY="$GLOBAL_KEY"
                echo -e "${GREEN}Using global SSL cert${NC}"
            else
                read -p "Generate cert for listener #${LISTENER_COUNT}? [Y/n]: " GLC
                if [[ ! $GLC =~ ^[Nn]$ ]]; then
                    read -p "Domain [www.google.com]: " LCD; LCD=${LCD:-www.google.com}
                    gen_ssl_cert "$CONFIG_DIR/certs/cert_${LISTENER_COUNT}.pem" "$CONFIG_DIR/certs/key_${LISTENER_COUNT}.pem" "$LCD"
                    L_CERT="$CONFIG_DIR/certs/cert_${LISTENER_COUNT}.pem"
                    L_KEY="$CONFIG_DIR/certs/key_${LISTENER_COUNT}.pem"
                fi
            fi
        fi

        # Port mappings for this listener
        build_port_mappings
        L_MAPPINGS="$MAPPINGS"

        # TUN for this listener
        read -p "Enable TUN for listener #${LISTENER_COUNT}? [y/N]: " L_TUN_EN
        L_TUN_ENABLED=false
        if [[ $L_TUN_EN =~ ^[Yy]$ ]]; then
            L_TUN_ENABLED=true
            configure_tun "$LISTENER_COUNT" "server"
        fi

        # Write listener block
        {
            echo "  - addr: \"${L_ADDR}\""
            echo "    transport: \"${L_TRANSPORT}\""
            [ -n "$L_CERT" ] && echo "    cert_file: \"${L_CERT}\"" && echo "    key_file: \"${L_KEY}\""
            echo "    maps:"
            printf '%b' "$L_MAPPINGS" | sed 's/^/    /'
            if $L_TUN_ENABLED; then
                echo "    tun:"
                echo "      enabled: true"
                echo "      name: \"${_TUN_NAME}\""
                echo "      local_ip: \"${_TUN_LOCAL}\""
                echo "      peer_ip: \"${_TUN_PEER}\""
                echo "      mtu: ${_TUN_MTU}"
            fi
        } >> "$CONFIG_FILE"

        LISTENER_COUNT=$((LISTENER_COUNT+1))
        echo -e "${GREEN}Listener #$((LISTENER_COUNT-1)): ${L_ADDR} (${L_TRANSPORT}) added${NC}"
        $L_TUN_ENABLED && echo -e "  TUN: ${GREEN}${_TUN_NAME} — ${_TUN_LOCAL}/32 ↔ ${_TUN_PEER}${NC}"

        read -p "Add another listener? [y/N]: " ML
        [[ ! $ML =~ ^[Yy]$ ]] && break
    done

    write_common_tail "$CONFIG_FILE"
    create_systemd_service "server"

    read -p "Optimize system? [Y/n]: " opt
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "iran"

    systemctl start DaggerConnect-server
    systemctl enable DaggerConnect-server

    echo ""
    echo -e "${GREEN}Multi-Listener Server configured!${NC}"
    echo -e "  Listeners : ${GREEN}${LISTENER_COUNT}${NC}"
    echo -e "  Config    : ${CONFIG_FILE}"
    echo -e "  Logs      : journalctl -u DaggerConnect-server -f"
    read -p "Press Enter..."; main_menu
}

# ============================================================================
# INSTALL SERVER ENTRY
# ============================================================================
install_server() {
    show_banner
    mkdir -p "$CONFIG_DIR"
    echo -e "${CYAN}═══ SERVER CONFIGURATION ═══${NC}"
    echo ""
    echo "  1) Automatic      - Single listener (Recommended)"
    echo "  2) Multi-Listener - Multiple isolated listeners + TUN"
    echo ""
    read -p "Choice [1-2]: " cm
    case $cm in
        2) install_server_multilistener ;;
        *) install_server_automatic ;;
    esac
}

# ============================================================================
# AUTOMATIC CLIENT
# ============================================================================
install_client_automatic() {
    echo ""
    echo -e "${CYAN}═══ AUTOMATIC CLIENT ═══${NC}"
    echo ""

    while true; do
        read -sp "PSK (must match server): " PSK; echo ""
        [ -n "$PSK" ] && break
        echo -e "${RED}PSK cannot be empty!${NC}"
    done

    TRANSPORT=$(select_transport)

    read -p "Server address:port (e.g., 1.2.3.4:2020): " ADDR
    if [ -z "$ADDR" ]; then
        echo -e "${RED}Address cannot be empty!${NC}"
        install_client_automatic; return
    fi

    CONFIG_FILE="$CONFIG_DIR/client.yaml"
    mkdir -p "$CONFIG_DIR"

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
EOF

    write_common_tail "$CONFIG_FILE"
    create_systemd_service "client"

    read -p "Optimize system? [Y/n]: " opt
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "foreign"

    systemctl start DaggerConnect-client
    systemctl enable DaggerConnect-client

    echo -e "${GREEN}Client configured! Server=${ADDR} Transport=${TRANSPORT}${NC}"
    read -p "Press Enter..."; main_menu
}

# ============================================================================
# MANUAL CLIENT - MULTI-PATH with per-PSK and TUN
# ============================================================================
install_client_multipaths() {
    echo ""
    echo -e "${CYAN}═══ CLIENT — MULTI-PATH ═══${NC}"
    echo -e "${YELLOW}Each path can have its own PSK and TUN interface.${NC}"
    echo ""

    while true; do
        read -sp "Global PSK: " GLOBAL_PSK; echo ""
        [ -n "$GLOBAL_PSK" ] && break
        echo -e "${RED}PSK cannot be empty!${NC}"
    done

    echo ""
    echo "Profile: 1)balanced 2)aggressive 3)latency 4)cpu-efficient 5)gaming"
    read -p "Choice [1]: " pc
    case $pc in 2) PROFILE="aggressive";; 3) PROFILE="latency";; 4) PROFILE="cpu-efficient";; 5) PROFILE="gaming";; *) PROFILE="balanced";; esac

    read -p "Heartbeat (seconds) [10]: " HB; HB=${HB:-10}
    read -p "Verbose? [y/N]: " VB; [[ $VB =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

    read -p "Enable obfuscation? [Y/n]: " OBE
    if [[ ! $OBE =~ ^[Nn]$ ]]; then
        OBFUS_ENABLED="true"
        read -p "  Min padding [16]: " OP1; OP1=${OP1:-16}
        read -p "  Max padding [512]: " OP2; OP2=${OP2:-512}
    else
        OBFUS_ENABLED="false"; OP1=16; OP2=512
    fi

    CONFIG_FILE="$CONFIG_DIR/client.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"client\""
        echo "psk: \"${GLOBAL_PSK}\""
        echo "profile: \"${PROFILE}\""
        echo "verbose: ${VERBOSE}"
        echo "heartbeat: ${HB}"
        echo ""
        echo "paths:"
    } > "$CONFIG_FILE"

    PATH_COUNT=0
    while true; do
        echo ""
        echo -e "${PURPLE}══ PATH #${PATH_COUNT} ══${NC}"

        P_TRANSPORT=$(select_transport)

        read -p "Server address:port: " P_ADDR
        [ -z "$P_ADDR" ] && echo -e "${RED}Cannot be empty!${NC}" && continue

        # Per-path PSK
        echo ""
        read -sp "  Custom PSK for this path? (blank = use global): " P_PSK_RAW; echo ""
        P_PSK=""
        if [ -n "$P_PSK_RAW" ]; then
            P_PSK="$P_PSK_RAW"
            echo -e "${GREEN}  Custom PSK will be used${NC}"
        fi

        read -p "  Connection pool [2]: " P_POOL; P_POOL=${P_POOL:-2}
        read -p "  Aggressive pool? [y/N]: " P_AGG
        [[ $P_AGG =~ ^[Yy]$ ]] && P_AGG_VAL="true" || P_AGG_VAL="false"
        read -p "  Retry interval (seconds) [3]: " P_RETRY; P_RETRY=${P_RETRY:-3}
        read -p "  Dial timeout (seconds) [10]: " P_DIAL; P_DIAL=${P_DIAL:-10}

        # TUN for this path
        read -p "  Enable TUN for this path? [y/N]: " P_TUN_EN
        P_TUN_ENABLED=false
        if [[ $P_TUN_EN =~ ^[Yy]$ ]]; then
            P_TUN_ENABLED=true
            configure_tun "$PATH_COUNT" "client"
        fi

        # Write path
        {
            echo "  - transport: \"${P_TRANSPORT}\""
            echo "    addr: \"${P_ADDR}\""
            [ -n "$P_PSK" ] && echo "    psk: \"${P_PSK}\""
            echo "    connection_pool: ${P_POOL}"
            echo "    aggressive_pool: ${P_AGG_VAL}"
            echo "    retry_interval: ${P_RETRY}"
            echo "    dial_timeout: ${P_DIAL}"
            if $P_TUN_ENABLED; then
                echo "    tun:"
                echo "      enabled: true"
                echo "      name: \"${_TUN_NAME}\""
                echo "      local_ip: \"${_TUN_LOCAL}\""
                echo "      peer_ip: \"${_TUN_PEER}\""
                echo "      mtu: ${_TUN_MTU}"
            fi
        } >> "$CONFIG_FILE"

        PATH_COUNT=$((PATH_COUNT+1))
        echo -e "${GREEN}Path #$((PATH_COUNT-1)): ${P_TRANSPORT} → ${P_ADDR} added${NC}"
        [ -n "$P_PSK" ] && echo -e "  PSK: ${GREEN}custom${NC}"
        $P_TUN_ENABLED && echo -e "  TUN: ${GREEN}${_TUN_NAME} — ${_TUN_LOCAL}/32 ↔ ${_TUN_PEER}${NC}"

        read -p "Add another path? [y/N]: " MP
        [[ ! $MP =~ ^[Yy]$ ]] && break
    done

    # Write obfuscation and rest
    cat >> "$CONFIG_FILE" << EOF

smux:
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768
  version: 2

kcp:
  nodelay: 1
  interval: 10
  resend: 2
  nc: 1
  sndwnd: 1024
  rcvwnd: 1024
  mtu: 1400

advanced:
  tcp_nodelay: true
  tcp_keepalive: 15
  tcp_read_buffer: 4194304
  tcp_write_buffer: 4194304
  websocket_read_buffer: 65536
  websocket_write_buffer: 65536
  websocket_compression: false
  cleanup_interval: 3
  session_timeout: 60
  connection_timeout: 30
  stream_timeout: 120
  max_connections: 2000
  max_udp_flows: 1000
  udp_flow_timeout: 300
  udp_buffer_size: 4194304

obfuscation:
  enabled: ${OBFUS_ENABLED}
  min_padding: ${OP1}
  max_padding: ${OP2}
  min_delay_ms: 0
  max_delay_ms: 0
  burst_chance: 0.15

http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  chunked_encoding: false
  session_cookie: true
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Accept-Encoding: gzip, deflate, br"
EOF

    create_systemd_service "client"

    read -p "Optimize system? [Y/n]: " opt
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "foreign"

    systemctl start DaggerConnect-client
    systemctl enable DaggerConnect-client

    echo ""
    echo -e "${GREEN}Multi-Path Client configured!${NC}"
    echo -e "  Paths  : ${GREEN}${PATH_COUNT}${NC}"
    echo -e "  Config : ${CONFIG_FILE}"
    echo -e "  Logs   : journalctl -u DaggerConnect-client -f"
    read -p "Press Enter..."; main_menu
}

# ============================================================================
# INSTALL CLIENT ENTRY
# ============================================================================
install_client() {
    show_banner
    mkdir -p "$CONFIG_DIR"
    echo -e "${CYAN}═══ CLIENT CONFIGURATION ═══${NC}"
    echo ""
    echo "  1) Automatic  - Single path (Recommended)"
    echo "  2) Multi-Path - Multiple paths with per-PSK & TUN"
    echo ""
    read -p "Choice [1-2]: " cm
    case $cm in
        2) install_client_multipaths ;;
        *) install_client_automatic ;;
    esac
}

# ============================================================================
# SYSTEMD
# ============================================================================
create_systemd_service() {
    local MODE=$1
    local SERVICE_NAME="DaggerConnect-${MODE}"
    cat > "$SYSTEMD_DIR/${SERVICE_NAME}.service" << EOF
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
    echo -e "${GREEN}Service created: ${SERVICE_NAME}${NC}"
}

# ============================================================================
# UPDATE
# ============================================================================
update_binary() {
    show_banner
    echo -e "${CYAN}═══ UPDATE CORE ═══${NC}"
    CURRENT_VERSION=$(get_current_version)
    if [ "$CURRENT_VERSION" == "not-installed" ]; then
        echo -e "${RED}Not installed yet${NC}"; read -p "Press Enter..."; main_menu; return
    fi
    echo -e "Current: ${GREEN}$CURRENT_VERSION${NC}"
    read -p "Continue update? [y/N]: " c
    [[ ! $c =~ ^[Yy]$ ]] && main_menu && return

    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    sleep 1
    download_binary
    NEW_VERSION=$(get_current_version)
    echo -e "Updated: ${YELLOW}$CURRENT_VERSION${NC} → ${GREEN}$NEW_VERSION${NC}"

    if systemctl is-enabled DaggerConnect-server &>/dev/null || systemctl is-enabled DaggerConnect-client &>/dev/null; then
        read -p "Restart services? [Y/n]: " r
        if [[ ! $r =~ ^[Nn]$ ]]; then
            systemctl is-enabled DaggerConnect-server &>/dev/null && systemctl start DaggerConnect-server && echo -e "${GREEN}Server restarted${NC}"
            systemctl is-enabled DaggerConnect-client &>/dev/null && systemctl start DaggerConnect-client && echo -e "${GREEN}Client restarted${NC}"
        fi
    fi
    read -p "Press Enter..."; main_menu
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================
service_management() {
    local MODE=$1
    local SERVICE_NAME="DaggerConnect-${MODE}"
    local CONFIG_FILE="$CONFIG_DIR/${MODE}.yaml"

    show_banner
    echo -e "${CYAN}═══ ${MODE^^} MANAGEMENT ═══${NC}"
    echo ""
    systemctl is-active --quiet "$SERVICE_NAME" && \
        echo -e "  Status: ${GREEN}● RUNNING${NC}" || echo -e "  Status: ${RED}● STOPPED${NC}"
    systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null && \
        echo -e "  Auto-start: ${GREEN}enabled${NC}" || echo -e "  Auto-start: ${YELLOW}disabled${NC}"
    echo ""
    echo "  1) Start       2) Stop        3) Restart"
    echo "  4) Status      5) Live Logs   6) Enable auto-start"
    echo "  7) Disable auto-start"
    echo ""
    echo "  8) View Config  9) Edit Config  10) Delete"
    echo "  0) Back"
    echo ""
    read -p "Select: " choice

    case $choice in
        1)  systemctl start "$SERVICE_NAME"; echo -e "${GREEN}Started${NC}"; sleep 2; service_management "$MODE" ;;
        2)  systemctl stop "$SERVICE_NAME"; echo -e "${GREEN}Stopped${NC}"; sleep 2; service_management "$MODE" ;;
        3)  systemctl restart "$SERVICE_NAME"; echo -e "${GREEN}Restarted${NC}"; sleep 2; service_management "$MODE" ;;
        4)  systemctl status "$SERVICE_NAME" --no-pager; read -p "Enter..."; service_management "$MODE" ;;
        5)  journalctl -u "$SERVICE_NAME" -f ;;
        6)  systemctl enable "$SERVICE_NAME"; echo -e "${GREEN}Enabled${NC}"; sleep 2; service_management "$MODE" ;;
        7)  systemctl disable "$SERVICE_NAME"; echo -e "${GREEN}Disabled${NC}"; sleep 2; service_management "$MODE" ;;
        8)  [ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE" || echo -e "${RED}Config not found${NC}"; read -p "Enter..."; service_management "$MODE" ;;
        9)  if [ -f "$CONFIG_FILE" ]; then
                ${EDITOR:-nano} "$CONFIG_FILE"
                read -p "Restart to apply? [y/N]: " r
                [[ $r =~ ^[Yy]$ ]] && systemctl restart "$SERVICE_NAME" && echo -e "${GREEN}Restarted${NC}"; sleep 2
            else
                echo -e "${RED}Config not found${NC}"; sleep 2
            fi
            service_management "$MODE" ;;
        10) read -p "Delete? [y/N]: " c
            if [[ $c =~ ^[Yy]$ ]]; then
                systemctl stop "$SERVICE_NAME" 2>/dev/null
                systemctl disable "$SERVICE_NAME" 2>/dev/null
                rm -f "$CONFIG_FILE" "$SYSTEMD_DIR/${SERVICE_NAME}.service"
                systemctl daemon-reload
                echo -e "${GREEN}Deleted${NC}"; sleep 2
            fi
            settings_menu ;;
        0) settings_menu ;;
        *) service_management "$MODE" ;;
    esac
}

settings_menu() {
    show_banner
    echo -e "${CYAN}═══ SETTINGS ═══${NC}"
    echo ""
    echo "  1) Manage Server"
    echo "  2) Manage Client"
    echo "  0) Back"
    echo ""
    read -p "Select: " choice
    case $choice in
        1) service_management "server" ;;
        2) service_management "client" ;;
        0) main_menu ;;
        *) settings_menu ;;
    esac
}

# ============================================================================
# UNINSTALL
# ============================================================================
uninstall_DaggerConnect() {
    show_banner
    echo -e "${RED}═══ UNINSTALL ═══${NC}"
    echo ""
    echo -e "${YELLOW}This will remove: binary, configs, services, certs, optimizations${NC}"
    read -p "Are you sure? [y/N]: " c
    [[ ! $c =~ ^[Yy]$ ]] && main_menu && return

    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    systemctl disable DaggerConnect-server 2>/dev/null
    systemctl disable DaggerConnect-client 2>/dev/null
    rm -f "$SYSTEMD_DIR/DaggerConnect-server.service" "$SYSTEMD_DIR/DaggerConnect-client.service"
    rm -f "$INSTALL_DIR/DaggerConnect"
    rm -rf "$CONFIG_DIR"
    rm -f /etc/sysctl.d/99-daggerconnect.conf
    sysctl -p > /dev/null 2>&1
    systemctl daemon-reload

    echo -e "${GREEN}Uninstalled successfully${NC}"
    exit 0
}

# ============================================================================
# MAIN MENU
# ============================================================================
main_menu() {
    show_banner
    CURRENT_VER=$(get_current_version)
    [ "$CURRENT_VER" != "not-installed" ] && echo -e "${CYAN}Version: ${GREEN}$CURRENT_VER${NC}" && echo ""

    systemctl is-active --quiet DaggerConnect-server 2>/dev/null && echo -e "  Server : ${GREEN}● RUNNING${NC}"
    systemctl is-active --quiet DaggerConnect-client 2>/dev/null && echo -e "  Client : ${GREEN}● RUNNING${NC}"
    echo ""

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}              MAIN MENU${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo "  1) Install / Configure Server"
    echo "     └─ Auto (single listener)  OR  Multi-Listener + TUN"
    echo ""
    echo "  2) Install / Configure Client"
    echo "     └─ Auto (single path)  OR  Multi-Path + per-PSK + TUN"
    echo ""
    echo "  3) Settings (Manage Services & Configs)"
    echo "  4) System Optimizer"
    echo "  5) Update Core"
    echo "  6) Uninstall DaggerConnect"
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
        *) echo -e "${RED}Invalid${NC}"; sleep 2; main_menu ;;
    esac
}

# ============================================================================
# ENTRY
# ============================================================================
check_root
show_banner
install_dependencies

if [ ! -f "$INSTALL_DIR/DaggerConnect" ]; then
    echo -e "${YELLOW}DaggerConnect not found. Downloading...${NC}"
    download_binary
    echo ""
fi

main_menu
