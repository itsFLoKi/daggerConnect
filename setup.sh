#!/bin/bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/DaggerConnect"
SYSTEMD_DIR="/etc/systemd/system"
LATEST_RELEASE_API="https://api.github.com/repos/itsFLoKi/DaggerConnect/releases/latest"

banner() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}       DaggerConnect Installer v1.4.1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Telegram: @DaggerConnect${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_root() { [[ $EUID -ne 0 ]] && { echo -e "${RED}Run as root${NC}"; exit 1; }; }

install_deps() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    if command -v apt &>/dev/null; then
        apt update -qq && apt install -y wget curl tar openssl iproute2 > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y wget curl tar openssl iproute2 > /dev/null 2>&1
    fi
    echo -e "${GREEN}Done${NC}"
}

download_binary() {
    echo -e "${YELLOW}Downloading DaggerConnect...${NC}"
    mkdir -p "$INSTALL_DIR"
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$LATEST_VERSION" ]] && LATEST_VERSION="v1.4.1"
    BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
    echo -e "  Version: ${GREEN}${LATEST_VERSION}${NC}"
    [[ -f "$INSTALL_DIR/DaggerConnect" ]] && cp "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.bak"
    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        rm -f "$INSTALL_DIR/DaggerConnect.bak"
        echo -e "${GREEN}Downloaded${NC}"
    else
        echo -e "${RED}Download failed${NC}"
        [[ -f "$INSTALL_DIR/DaggerConnect.bak" ]] && mv "$INSTALL_DIR/DaggerConnect.bak" "$INSTALL_DIR/DaggerConnect"
        exit 1
    fi
}

get_current_version() {
    if [[ -f "$INSTALL_DIR/DaggerConnect" ]]; then
        "$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+\.\d+' || echo "unknown"
    else
        echo "not-installed"
    fi
}

gen_cert() {
    local domain=${1:-www.google.com}
    mkdir -p "$CONFIG_DIR/certs"
    openssl req -x509 -newkey rsa:4096 \
        -keyout "$CONFIG_DIR/certs/key.pem" \
        -out "$CONFIG_DIR/certs/cert.pem" \
        -days 365 -nodes \
        -subj "/C=US/ST=CA/L=SF/O=Corp/CN=${domain}" 2>/dev/null
    echo -e "${GREEN}Certificate generated (${domain})${NC}"
}

create_service() {
    local mode=$1
    cat > "$SYSTEMD_DIR/DaggerConnect-${mode}.service" << EOF
[Unit]
Description=DaggerConnect ${mode}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/DaggerConnect -c $CONFIG_DIR/${mode}.yaml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo -e "${GREEN}Service DaggerConnect-${mode} created${NC}"
}

optimize_system() {
    echo -e "${CYAN}━━━ System Optimization ━━━${NC}"
    IFACE=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    [[ -z "$IFACE" ]] && IFACE="eth0"
    echo -e "  Interface: ${GREEN}$IFACE${NC}"

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
    modprobe tcp_bbr 2>/dev/null && {
        sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel > /dev/null 2>&1
    }
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc add dev $IFACE root fq_codel limit 500 target 3ms interval 50ms quantum 300 ecn 2>/dev/null

    cat > /etc/sysctl.d/99-daggerconnect.conf << 'SYSEOF'
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
SYSEOF
    echo -e "${GREEN}System optimized${NC}"
}

# ============================================================================
# PORT MAPPING COLLECTOR
# ============================================================================

collect_port_mappings() {
    MAPPINGS=""
    MAP_COUNT=0
    echo -e "  ${GREEN}Single${NC}: 8008  ${GREEN}Range${NC}: 1000/2000  ${GREEN}Custom${NC}: 5000=8008  ${GREEN}RangeMap${NC}: 1000/1010=2000/2010"
    echo ""
    while true; do
        echo -e "${YELLOW}  Mapping #$((MAP_COUNT+1))${NC}"
        echo "    1) tcp  2) udp  3) both"
        read -p "    Protocol [1]: " pc
        case $pc in 2) proto="udp" ;; 3) proto="both" ;; *) proto="tcp" ;; esac
        read -p "    Port(s): " pinput
        [[ -z "$pinput" ]] && { echo -e "${RED}    Empty${NC}"; continue; }
        pinput=$(echo "$pinput" | tr -d ' ')
        local bip="0.0.0.0" tip="127.0.0.1"
        _add() {
            local t=$1 bp=$2 tp=$3
            if [[ "$t" == "both" ]]; then
                MAPPINGS+="  - type: tcp\n    bind: \"${bip}:${bp}\"\n    target: \"${tip}:${tp}\"\n"
                MAPPINGS+="  - type: udp\n    bind: \"${bip}:${bp}\"\n    target: \"${tip}:${tp}\"\n"
                MAP_COUNT=$((MAP_COUNT+2))
            else
                MAPPINGS+="  - type: ${t}\n    bind: \"${bip}:${bp}\"\n    target: \"${tip}:${tp}\"\n"
                MAP_COUNT=$((MAP_COUNT+1))
            fi
        }
        if [[ "$pinput" =~ ^([0-9]+)/([0-9]+)=([0-9]+)/([0-9]+)$ ]]; then
            for ((i=0; i<=${BASH_REMATCH[2]}-${BASH_REMATCH[1]}; i++)); do
                _add "$proto" $(( ${BASH_REMATCH[1]}+i )) $(( ${BASH_REMATCH[3]}+i ))
            done
            echo -e "${GREEN}    Range map added${NC}"
        elif [[ "$pinput" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            for ((p=${BASH_REMATCH[1]}; p<=${BASH_REMATCH[2]}; p++)); do _add "$proto" $p $p; done
            echo -e "${GREEN}    Range added${NC}"
        elif [[ "$pinput" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            _add "$proto" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            echo -e "${GREEN}    ${BASH_REMATCH[1]} -> ${BASH_REMATCH[2]}${NC}"
        elif [[ "$pinput" =~ ^[0-9]+$ ]]; then
            _add "$proto" "$pinput" "$pinput"
            echo -e "${GREEN}    ${pinput} -> ${pinput}${NC}"
        else
            echo -e "${RED}    Invalid${NC}"; continue
        fi
        read -p "    Add more? [y/N]: " m
        [[ ! "$m" =~ ^[Yy]$ ]] && break
    done
    [[ $MAP_COUNT -eq 0 ]] && {
        MAPPINGS="  - type: tcp\n    bind: \"0.0.0.0:8080\"\n    target: \"127.0.0.1:8080\"\n"
        MAP_COUNT=1
        echo -e "${YELLOW}  Default: 8080->8080${NC}"
    }
}

# ============================================================================
# DEFAULTS PER PROFILE
# ============================================================================

set_defaults() {
    local p=$1
    case $p in
        aggressive) V_SMUX_KA=5;  V_SMUX_RECV=16777216; V_SMUX_STREAM=16777216; V_KCP_INT=8;  V_KCP_SNDWND=2048; V_KCP_RCVWND=2048 ;;
        latency)    V_SMUX_KA=3;  V_SMUX_RECV=4194304;  V_SMUX_STREAM=4194304;  V_KCP_INT=8;  V_KCP_SNDWND=1024; V_KCP_RCVWND=1024 ;;
        *)          V_SMUX_KA=8;  V_SMUX_RECV=8388608;  V_SMUX_STREAM=8388608;  V_KCP_INT=10; V_KCP_SNDWND=1024; V_KCP_RCVWND=1024 ;;
    esac
    V_SMUX_FRAME=32768; V_SMUX_VER=2
    V_KCP_NODELAY=1; V_KCP_RESEND=2; V_KCP_NC=1; V_KCP_MTU=1400
    V_ADV_TCP_ND=true; V_ADV_TCP_KA=15; V_ADV_TCP_RBUF=4194304; V_ADV_TCP_WBUF=4194304
    V_ADV_WS_RBUF=65536; V_ADV_WS_WBUF=65536; V_ADV_WS_COMP=false
    V_ADV_CLEANUP=3; V_ADV_SESS_TO=60; V_ADV_CONN_TO=30; V_ADV_STREAM_TO=120
    V_ADV_MAX_CONN=2000; V_ADV_MAX_UDP=1000; V_ADV_UDP_TO=300; V_ADV_UDP_BUF=4194304
    V_OBF_ON=true; V_OBF_MINP=16; V_OBF_MAXP=512; V_OBF_MIND=0; V_OBF_MAXD=0; V_OBF_BURST=0.15
    V_HTTP_DOM="www.google.com"; V_HTTP_PATH="/search"
    V_HTTP_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    V_HTTP_CHUNK=false; V_HTTP_COOK=true
    V_DPI_ON=false; V_DPI_SNI=true; V_DPI_TTL=false; V_DPI_SEG=1200; V_DPI_PACE=2; V_DPI_JITTER=1
    V_RAW_ON=false; V_RAW_IFACE="eth0"; V_RAW_LIP="0.0.0.0"; V_RAW_LPORT=0
    V_RAW_GWMAC="00:00:00:00:00:00"; V_RAW_BATCH=32; V_RAW_BUF=2097152; V_RAW_COAL=1
    V_RAW_MTU=1400; V_RAW_ZC=false; V_RAW_MINTTL=64; V_RAW_MAXTTL=128
    V_RAW_FRAG=true; V_RAW_FRAGSZ=40; V_RAW_RTTL=true; V_RAW_FAKE=false
    V_RAW_WSCALE=7; V_RAW_IPPAD=false; V_RAW_DESYNC="split"
    V_LB_STRAT="round_robin"; V_LB_HEALTH=10; V_LB_FAIL_DLY=500; V_LB_MAXFAIL=3; V_LB_RECOV=30; V_LB_STICKY=false
    V_MAX_SESS=0; V_HEARTBEAT=10; V_VERBOSE=false
}

# ============================================================================
# ADVANCED EDITOR
# ============================================================================

edit_advanced() {
    echo ""
    echo -e "${CYAN}━━━ Advanced Settings ━━━${NC}"
    echo -e "${YELLOW}SMUX:${NC}"
    read -p "  keepalive [$V_SMUX_KA]: " v; V_SMUX_KA=${v:-$V_SMUX_KA}
    read -p "  max_recv [$V_SMUX_RECV]: " v; V_SMUX_RECV=${v:-$V_SMUX_RECV}
    read -p "  max_stream [$V_SMUX_STREAM]: " v; V_SMUX_STREAM=${v:-$V_SMUX_STREAM}
    read -p "  frame_size [$V_SMUX_FRAME]: " v; V_SMUX_FRAME=${v:-$V_SMUX_FRAME}
    echo -e "${YELLOW}KCP:${NC}"
    read -p "  nodelay [$V_KCP_NODELAY]: " v; V_KCP_NODELAY=${v:-$V_KCP_NODELAY}
    read -p "  interval [$V_KCP_INT]: " v; V_KCP_INT=${v:-$V_KCP_INT}
    read -p "  sndwnd [$V_KCP_SNDWND]: " v; V_KCP_SNDWND=${v:-$V_KCP_SNDWND}
    read -p "  rcvwnd [$V_KCP_RCVWND]: " v; V_KCP_RCVWND=${v:-$V_KCP_RCVWND}
    read -p "  mtu [$V_KCP_MTU]: " v; V_KCP_MTU=${v:-$V_KCP_MTU}
    echo -e "${YELLOW}TCP:${NC}"
    read -p "  tcp_nodelay [$V_ADV_TCP_ND]: " v; V_ADV_TCP_ND=${v:-$V_ADV_TCP_ND}
    read -p "  tcp_keepalive [$V_ADV_TCP_KA]: " v; V_ADV_TCP_KA=${v:-$V_ADV_TCP_KA}
    read -p "  tcp_read_buffer [$V_ADV_TCP_RBUF]: " v; V_ADV_TCP_RBUF=${v:-$V_ADV_TCP_RBUF}
    read -p "  tcp_write_buffer [$V_ADV_TCP_WBUF]: " v; V_ADV_TCP_WBUF=${v:-$V_ADV_TCP_WBUF}
    echo -e "${YELLOW}Limits:${NC}"
    read -p "  max_connections [$V_ADV_MAX_CONN]: " v; V_ADV_MAX_CONN=${v:-$V_ADV_MAX_CONN}
    read -p "  max_sessions [$V_MAX_SESS]: " v; V_MAX_SESS=${v:-$V_MAX_SESS}
    read -p "  connection_timeout [$V_ADV_CONN_TO]: " v; V_ADV_CONN_TO=${v:-$V_ADV_CONN_TO}
    read -p "  stream_timeout [$V_ADV_STREAM_TO]: " v; V_ADV_STREAM_TO=${v:-$V_ADV_STREAM_TO}
    echo -e "${YELLOW}Obfuscation:${NC}"
    read -p "  enabled [$V_OBF_ON]: " v; V_OBF_ON=${v:-$V_OBF_ON}
    read -p "  min_padding [$V_OBF_MINP]: " v; V_OBF_MINP=${v:-$V_OBF_MINP}
    read -p "  max_padding [$V_OBF_MAXP]: " v; V_OBF_MAXP=${v:-$V_OBF_MAXP}
    echo -e "${YELLOW}HTTP Mimicry:${NC}"
    read -p "  fake_domain [$V_HTTP_DOM]: " v; V_HTTP_DOM=${v:-$V_HTTP_DOM}
    read -p "  fake_path [$V_HTTP_PATH]: " v; V_HTTP_PATH=${v:-$V_HTTP_PATH}
    echo -e "${YELLOW}DPI Bypass:${NC}"
    read -p "  enabled [$V_DPI_ON]: " v; V_DPI_ON=${v:-$V_DPI_ON}
    read -p "  sni_split [$V_DPI_SNI]: " v; V_DPI_SNI=${v:-$V_DPI_SNI}
    echo -e "${YELLOW}Raw Socket (DPI Bypass via pcap):${NC}"
    read -p "  enabled [$V_RAW_ON]: " v; V_RAW_ON=${v:-$V_RAW_ON}
    if [[ "$V_RAW_ON" == "true" ]]; then
        local auto_iface=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
        local auto_ip=$(ip -4 addr show "${auto_iface:-eth0}" | grep -oP 'inet \K[\d.]+' | head -1)
        local auto_gw_ip=$(ip route | grep default | awk '{print $3}' | head -1)
        local auto_gw_mac=$(ip neigh show "$auto_gw_ip" 2>/dev/null | awk '{print $5}' | head -1)
        [[ -z "$auto_iface" ]] && auto_iface="eth0"
        [[ -z "$auto_ip" ]] && auto_ip="0.0.0.0"
        [[ -z "$auto_gw_mac" ]] && auto_gw_mac="00:00:00:00:00:00"
        read -p "  interface [$auto_iface]: " v; V_RAW_IFACE=${v:-$auto_iface}
        read -p "  local_ip [$auto_ip]: " v; V_RAW_LIP=${v:-$auto_ip}
        read -p "  local_port [$V_RAW_LPORT]: " v; V_RAW_LPORT=${v:-$V_RAW_LPORT}
        read -p "  gateway_mac [$auto_gw_mac]: " v; V_RAW_GWMAC=${v:-$auto_gw_mac}
        echo "  Desync methods: split, disorder, fake"
        read -p "  desync_method [$V_RAW_DESYNC]: " v; V_RAW_DESYNC=${v:-$V_RAW_DESYNC}
        read -p "  max_packet_size [$V_RAW_MTU]: " v; V_RAW_MTU=${v:-$V_RAW_MTU}
        read -p "  buffer_size [$V_RAW_BUF]: " v; V_RAW_BUF=${v:-$V_RAW_BUF}
        read -p "  fragment_first_packet [$V_RAW_FRAG]: " v; V_RAW_FRAG=${v:-$V_RAW_FRAG}
        read -p "  randomize_ttl [$V_RAW_RTTL]: " v; V_RAW_RTTL=${v:-$V_RAW_RTTL}
        read -p "  fake_payload [$V_RAW_FAKE]: " v; V_RAW_FAKE=${v:-$V_RAW_FAKE}
    fi
}

# ============================================================================
# TRANSPORT & PROFILE SELECTORS
# ============================================================================

select_transport() {
    echo ""
    echo -e "${YELLOW}Transport:${NC}"
    echo "  1) httpsmux  [recommended]"
    echo "  2) httpmux"
    echo "  3) wssmux"
    echo "  4) wsmux"
    echo "  5) kcpmux"
    echo "  6) tcpmux"
    read -p "  Choice [1]: " tc
    case $tc in 2) V_TRANSPORT="httpmux" ;; 3) V_TRANSPORT="wssmux" ;; 4) V_TRANSPORT="wsmux" ;; 5) V_TRANSPORT="kcpmux" ;; 6) V_TRANSPORT="tcpmux" ;; *) V_TRANSPORT="httpsmux" ;; esac
}

select_profile() {
    echo ""
    echo -e "${YELLOW}Profile:${NC}"
    echo "  1) balanced [default]"
    echo "  2) aggressive"
    echo "  3) latency"
    read -p "  Choice [1]: " pc
    case $pc in 2) V_PROFILE="aggressive" ;; 3) V_PROFILE="latency" ;; *) V_PROFILE="balanced" ;; esac
}

# ============================================================================
# AUTO RAW SOCKET SETUP
# ============================================================================

auto_setup_raw_socket() {
    echo ""
    echo -e "${YELLOW}  Auto-detecting network...${NC}"
    local iface=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    [[ -z "$iface" ]] && iface="eth0"
    local lip=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    [[ -z "$lip" ]] && lip="0.0.0.0"
    local gw_ip=$(ip route | grep default | awk '{print $3}' | head -1)
    local gw_mac=""
    if [[ -n "$gw_ip" ]]; then
        ping -c 1 -W 1 "$gw_ip" > /dev/null 2>&1
        gw_mac=$(ip neigh show "$gw_ip" 2>/dev/null | awk '{print $5}' | head -1)
    fi
    [[ -z "$gw_mac" || "$gw_mac" == "FAILED" ]] && gw_mac="00:00:00:00:00:00"
    echo -e "    Interface: ${GREEN}$iface${NC}"
    echo -e "    Local IP:  ${GREEN}$lip${NC}"
    echo -e "    Gateway:   ${GREEN}$gw_ip${NC} (${gw_mac})"
    V_RAW_IFACE="$iface"; V_RAW_LIP="$lip"; V_RAW_GWMAC="$gw_mac"
    if [[ -n "$FIRST_LISTEN_PORT" ]]; then
        V_RAW_LPORT=$FIRST_LISTEN_PORT
    else
        read -p "    Raw socket port [443]: " rp; V_RAW_LPORT=${rp:-443}
    fi
    echo ""
    echo -e "${YELLOW}  Desync Method:${NC}"
    echo "    1) split [default]"
    echo "    2) disorder"
    echo "    3) fake (TTL=1)"
    read -p "    Choice [1]: " dm
    case $dm in 2) V_RAW_DESYNC="disorder" ;; 3) V_RAW_DESYNC="fake"; V_RAW_FAKE=true ;; *) V_RAW_DESYNC="split" ;; esac
    if [[ "$gw_mac" == "00:00:00:00:00:00" ]]; then
        echo ""
        echo -e "${YELLOW}  Warning: Gateway MAC not detected.${NC}"
        echo -e "  Run: ${GREEN}ip neigh show${NC} to find it manually."
        read -p "    Enter gateway MAC [00:00:00:00:00:00]: " manual_mac
        [[ -n "$manual_mac" ]] && V_RAW_GWMAC="$manual_mac"
    fi
}

# ============================================================================
# SHARED CONFIG (smux, kcp, advanced, etc.)
# ============================================================================

write_shared_config() {
    local f=$1
    cat >> "$f" << YAML

smux:
  keepalive: ${V_SMUX_KA}
  max_recv: ${V_SMUX_RECV}
  max_stream: ${V_SMUX_STREAM}
  frame_size: ${V_SMUX_FRAME}
  version: ${V_SMUX_VER}

kcp:
  nodelay: ${V_KCP_NODELAY}
  interval: ${V_KCP_INT}
  resend: ${V_KCP_RESEND}
  nc: ${V_KCP_NC}
  sndwnd: ${V_KCP_SNDWND}
  rcvwnd: ${V_KCP_RCVWND}
  mtu: ${V_KCP_MTU}

advanced:
  tcp_nodelay: ${V_ADV_TCP_ND}
  tcp_keepalive: ${V_ADV_TCP_KA}
  tcp_read_buffer: ${V_ADV_TCP_RBUF}
  tcp_write_buffer: ${V_ADV_TCP_WBUF}
  websocket_read_buffer: ${V_ADV_WS_RBUF}
  websocket_write_buffer: ${V_ADV_WS_WBUF}
  websocket_compression: ${V_ADV_WS_COMP}
  cleanup_interval: ${V_ADV_CLEANUP}
  session_timeout: ${V_ADV_SESS_TO}
  connection_timeout: ${V_ADV_CONN_TO}
  stream_timeout: ${V_ADV_STREAM_TO}
  max_connections: ${V_ADV_MAX_CONN}
  max_udp_flows: ${V_ADV_MAX_UDP}
  udp_flow_timeout: ${V_ADV_UDP_TO}
  udp_buffer_size: ${V_ADV_UDP_BUF}

obfuscation:
  enabled: ${V_OBF_ON}
  min_padding: ${V_OBF_MINP}
  max_padding: ${V_OBF_MAXP}
  min_delay_ms: ${V_OBF_MIND}
  max_delay_ms: ${V_OBF_MAXD}
  burst_chance: ${V_OBF_BURST}

http_mimic:
  fake_domain: "${V_HTTP_DOM}"
  fake_path: "${V_HTTP_PATH}"
  user_agent: "${V_HTTP_UA}"
  chunked_encoding: ${V_HTTP_CHUNK}
  session_cookie: ${V_HTTP_COOK}
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Accept-Encoding: gzip, deflate, br"

light_dpi_bypass:
  enabled: ${V_DPI_ON}
  sni_split: ${V_DPI_SNI}
  ttl_manipulation: ${V_DPI_TTL}
  segment_size: ${V_DPI_SEG}
  pacing_delay_ms: ${V_DPI_PACE}
  jitter_range_ms: ${V_DPI_JITTER}

raw_socket:
  enabled: ${V_RAW_ON}
  interface: "${V_RAW_IFACE}"
  local_ip: "${V_RAW_LIP}"
  local_port: ${V_RAW_LPORT}
  gateway_mac: "${V_RAW_GWMAC}"
  batch_size: ${V_RAW_BATCH}
  buffer_size: ${V_RAW_BUF}
  coalesce_ms: ${V_RAW_COAL}
  max_packet_size: ${V_RAW_MTU}
  use_zero_copy: ${V_RAW_ZC}
  min_ttl: ${V_RAW_MINTTL}
  max_ttl: ${V_RAW_MAXTTL}
  fragment_first_packet: ${V_RAW_FRAG}
  fragment_size: ${V_RAW_FRAGSZ}
  randomize_ttl: ${V_RAW_RTTL}
  fake_payload: ${V_RAW_FAKE}
  tcp_window_scale: ${V_RAW_WSCALE}
  ip_options_padding: ${V_RAW_IPPAD}
  desync_method: "${V_RAW_DESYNC}"
YAML
}

# ============================================================================
# MULTI-LISTENER COLLECTOR
# ============================================================================

collect_listeners() {
    LISTENERS_BLOCK=""
    LISTENER_COUNT=0
    FIRST_LISTEN_PORT=""
    CERT_GENERATED=false

    while true; do
        echo ""
        echo -e "${CYAN}━━━ Listener #$((LISTENER_COUNT+1)) ━━━${NC}"

        select_transport
        local l_transport="$V_TRANSPORT"

        local default_port=443
        [[ $LISTENER_COUNT -gt 0 ]] && default_port=$((443 + LISTENER_COUNT))
        read -p "  Listen port [$default_port]: " l_port
        l_port=${l_port:-$default_port}
        [[ $LISTENER_COUNT -eq 0 ]] && FIRST_LISTEN_PORT="$l_port"

        local l_cert="" l_key=""
        if [[ "$l_transport" == "httpsmux" || "$l_transport" == "wssmux" ]]; then
            if [[ "$CERT_GENERATED" != "true" ]]; then
                read -p "  Cert domain [$V_HTTP_DOM]: " cd; cd=${cd:-$V_HTTP_DOM}
                gen_cert "$cd"
                CERT_GENERATED=true
            fi
            l_cert="$CONFIG_DIR/certs/cert.pem"
            l_key="$CONFIG_DIR/certs/key.pem"
        fi

        echo ""
        echo -e "${YELLOW}  Port mappings for listener :${l_port} [${l_transport}]:${NC}"
        collect_port_mappings

        LISTENERS_BLOCK+="  - addr: \"0.0.0.0:${l_port}\"\n"
        LISTENERS_BLOCK+="    transport: \"${l_transport}\"\n"
        [[ -n "$l_cert" ]] && LISTENERS_BLOCK+="    cert_file: \"${l_cert}\"\n    key_file: \"${l_key}\"\n"
        LISTENERS_BLOCK+="    maps:\n"
        while IFS= read -r line; do
            [[ -n "$line" ]] && LISTENERS_BLOCK+="    ${line}\n"
        done <<< "$(echo -e "$MAPPINGS")"

        LISTENER_COUNT=$((LISTENER_COUNT+1))
        echo -e "${GREEN}  ✓ Listener #${LISTENER_COUNT}: :${l_port} [${l_transport}] ${MAP_COUNT} maps${NC}"

        read -p "  Add another listener? [y/N]: " more
        [[ ! "$more" =~ ^[Yy]$ ]] && break
    done
}

# ============================================================================
# YAML WRITERS
# ============================================================================

write_server_yaml() {
    local f="$CONFIG_DIR/server.yaml"
    cat > "$f" << YAML
mode: server
psk: "${V_PSK}"
profile: "${V_PROFILE}"
verbose: true
max_sessions: ${V_MAX_SESS}
heartbeat: ${V_HEARTBEAT}

listeners:
YAML
    echo -e "$LISTENERS_BLOCK" >> "$f"
    write_shared_config "$f"
    echo -e "${GREEN}Config: $f${NC}"
}

write_client_yaml() {
    local f="$CONFIG_DIR/client.yaml"
    cat > "$f" << YAML
mode: client
psk: "${V_PSK}"
profile: "${V_PROFILE}"
verbose: true
heartbeat: ${V_HEARTBEAT}

${V_PATHS_BLOCK}

load_balancer:
  strategy: "${V_LB_STRAT}"
  health_check_sec: ${V_LB_HEALTH}
  failover_delay_ms: ${V_LB_FAIL_DLY}
  max_failures: ${V_LB_MAXFAIL}
  recovery_time_sec: ${V_LB_RECOV}
  sticky_session: ${V_LB_STICKY}
YAML
    write_shared_config "$f"
    echo -e "${GREEN}Config: $f${NC}"
}

# ============================================================================
# SERVER INSTALLER
# ============================================================================

install_server() {
    banner
    mkdir -p "$CONFIG_DIR"
    echo -e "${CYAN}━━━ Server Setup ━━━${NC}"
    echo "  1) Single Listener (recommended)"
    echo "  2) Multi-Listener (multiple ports/transports)"
    echo "  3) Manual (full control)"
    read -p "  Mode [1]: " inst_mode

    while true; do
        read -sp "  PSK: " V_PSK; echo ""
        [[ -n "$V_PSK" ]] && break
        echo -e "${RED}  Required${NC}"
    done

    select_profile
    set_defaults "$V_PROFILE"

    case $inst_mode in
        2|3)
            echo ""
            echo -e "${CYAN}  Each listener gets its own transport + port mappings${NC}"
            collect_listeners
            ;;
        *)
            select_transport
            read -p "  Tunnel Port [443]: " lp; lp=${lp:-443}
            FIRST_LISTEN_PORT="$lp"
            CERT_GENERATED=false
            local l_cert="" l_key=""
            if [[ "$V_TRANSPORT" == "httpsmux" || "$V_TRANSPORT" == "wssmux" ]]; then
                read -p "  Cert domain [$V_HTTP_DOM]: " cd; cd=${cd:-$V_HTTP_DOM}
                gen_cert "$cd"
                CERT_GENERATED=true
                l_cert="$CONFIG_DIR/certs/cert.pem"
                l_key="$CONFIG_DIR/certs/key.pem"
            fi
            echo ""
            echo -e "${CYAN}━━━ Port Mappings ━━━${NC}"
            collect_port_mappings
            LISTENERS_BLOCK="  - addr: \"0.0.0.0:${lp}\"\n    transport: \"${V_TRANSPORT}\"\n"
            [[ -n "$l_cert" ]] && LISTENERS_BLOCK+="    cert_file: \"${l_cert}\"\n    key_file: \"${l_key}\"\n"
            LISTENERS_BLOCK+="    maps:\n"
            while IFS= read -r line; do
                [[ -n "$line" ]] && LISTENERS_BLOCK+="    ${line}\n"
            done <<< "$(echo -e "$MAPPINGS")"
            LISTENER_COUNT=1
            ;;
    esac

    # DPI Bypass (server = Iran side)
    echo ""
    echo -e "${CYAN}━━━ DPI Bypass ━━━${NC}"
    echo "  1) Off (default)"
    echo "  2) Light DPI Bypass (SNI split)"
    echo "  3) Raw Socket (pcap desync - needs root)"
    echo "  4) Both"
    read -p "  Choice [1]: " dpi_choice
    case $dpi_choice in
        2) V_DPI_ON=true; V_DPI_SNI=true; echo -e "${GREEN}  Light DPI enabled${NC}" ;;
        3) V_RAW_ON=true; auto_setup_raw_socket; echo -e "${GREEN}  Raw Socket enabled (${V_RAW_DESYNC})${NC}" ;;
        4) V_DPI_ON=true; V_DPI_SNI=true; V_RAW_ON=true; auto_setup_raw_socket; echo -e "${GREEN}  Both enabled${NC}" ;;
        *) echo -e "  DPI Bypass: off" ;;
    esac

    # Manual mode: advanced editing
    if [[ "$inst_mode" == "3" ]]; then
        read -p "  Heartbeat sec [$V_HEARTBEAT]: " v; V_HEARTBEAT=${v:-$V_HEARTBEAT}
        read -p "  Edit advanced? [y/N]: " ea; [[ $ea =~ ^[Yy]$ ]] && edit_advanced
    fi

    write_server_yaml
    create_service "server"

    echo ""
    read -p "  Optimize system? [Y/n]: " opt
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system

    systemctl enable DaggerConnect-server 2>/dev/null
    systemctl start DaggerConnect-server

    echo ""
    echo -e "${GREEN}━━━ Server Ready ━━━${NC}"
    echo -e "  Listeners: ${GREEN}${LISTENER_COUNT}${NC}"
    echo -e "  Profile: ${GREEN}${V_PROFILE}${NC}"
    echo -e "  Config: $CONFIG_DIR/server.yaml"
    echo -e "  Logs: journalctl -u DaggerConnect-server -f"
    echo ""
    read -p "Press Enter..."
    main_menu
}

# ============================================================================
# CLIENT INSTALLER
# ============================================================================

collect_client_paths() {
    V_PATHS_BLOCK="paths:"
    PATH_COUNT=0
    while true; do
        echo ""
        echo -e "${YELLOW}  Server #$((PATH_COUNT+1))${NC}"
        select_transport
        read -p "  Server address (ip:port): " addr
        [[ -z "$addr" ]] && { echo -e "${RED}  Required${NC}"; continue; }
        read -p "  Connection pool [2]: " pool; pool=${pool:-2}
        read -p "  Retry interval sec [3]: " retry; retry=${retry:-3}
        read -p "  Dial timeout sec [10]: " dtout; dtout=${dtout:-10}
        read -p "  Weight (for LB) [1]: " weight; weight=${weight:-1}
        read -p "  Priority (lower=higher) [0]: " prio; prio=${prio:-0}
        V_PATHS_BLOCK+="
  - transport: \"${V_TRANSPORT}\"
    addr: \"${addr}\"
    connection_pool: ${pool}
    retry_interval: ${retry}
    dial_timeout: ${dtout}
    weight: ${weight}
    priority: ${prio}"
        PATH_COUNT=$((PATH_COUNT+1))
        echo -e "${GREEN}  Added: ${addr} [${V_TRANSPORT}]${NC}"
        read -p "  Add another server? [y/N]: " m
        [[ ! "$m" =~ ^[Yy]$ ]] && break
    done
}

install_client() {
    banner
    mkdir -p "$CONFIG_DIR"
    echo -e "${CYAN}━━━ Client Setup ━━━${NC}"
    echo "  1) Automatic (recommended)"
    echo "  2) Manual"
    read -p "  Mode [1]: " inst_mode

    while true; do
        read -sp "  PSK (must match server): " V_PSK; echo ""
        [[ -n "$V_PSK" ]] && break
        echo -e "${RED}  Required${NC}"
    done

    select_profile
    set_defaults "$V_PROFILE"
    collect_client_paths

    if [[ $PATH_COUNT -gt 1 ]]; then
        echo ""
        echo -e "${YELLOW}  Load Balancer Strategy:${NC}"
        echo "    1) round_robin [default]"
        echo "    2) least_loaded"
        echo "    3) failover"
        echo "    4) weighted_random"
        read -p "    Choice [1]: " lbc
        case $lbc in 2) V_LB_STRAT="least_loaded" ;; 3) V_LB_STRAT="failover" ;; 4) V_LB_STRAT="weighted_random" ;; *) V_LB_STRAT="round_robin" ;; esac
    fi

    if [[ "$inst_mode" == "2" ]]; then
        read -p "  Heartbeat sec [$V_HEARTBEAT]: " v; V_HEARTBEAT=${v:-$V_HEARTBEAT}
        read -p "  Edit advanced? [y/N]: " ea; [[ $ea =~ ^[Yy]$ ]] && edit_advanced
    fi

    write_client_yaml
    create_service "client"

    echo ""
    read -p "  Optimize system? [Y/n]: " opt
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system

    systemctl enable DaggerConnect-client 2>/dev/null
    systemctl start DaggerConnect-client

    echo ""
    echo -e "${GREEN}━━━ Client Ready ━━━${NC}"
    echo -e "  Servers: ${GREEN}${PATH_COUNT}${NC}"
    echo -e "  LB: ${GREEN}${V_LB_STRAT}${NC}"
    echo -e "  Profile: ${GREEN}${V_PROFILE}${NC}"
    echo -e "  Config: $CONFIG_DIR/client.yaml"
    echo -e "  Logs: journalctl -u DaggerConnect-client -f"
    echo ""
    read -p "Press Enter..."
    main_menu
}

# ============================================================================
# UPDATE / UNINSTALL
# ============================================================================

update_binary() {
    banner
    echo -e "${CYAN}━━━ Update Core ━━━${NC}"
    local cur=$(get_current_version)
    [[ "$cur" == "not-installed" ]] && { echo -e "${RED}Not installed${NC}"; read -p "Enter..."; main_menu; return; }
    echo -e "  Current: ${YELLOW}$cur${NC}"
    read -p "  Continue? [y/N]: " c; [[ ! $c =~ ^[Yy]$ ]] && { main_menu; return; }
    systemctl stop DaggerConnect-server 2>/dev/null
    systemctl stop DaggerConnect-client 2>/dev/null
    download_binary
    local new=$(get_current_version)
    echo -e "  Updated: ${GREEN}$new${NC}"
    systemctl start DaggerConnect-server 2>/dev/null
    systemctl start DaggerConnect-client 2>/dev/null
    echo ""
    read -p "Press Enter..."
    main_menu
}

uninstall() {
    banner
    echo -e "${RED}━━━ Uninstall DaggerConnect ━━━${NC}"
    read -p "  Are you sure? [y/N]: " c; [[ ! $c =~ ^[Yy]$ ]] && { main_menu; return; }
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
    echo -e "${GREEN}Uninstalled${NC}"
    exit 0
}

# ============================================================================
# MAIN MENU
# ============================================================================

main_menu() {
    banner
    local ver=$(get_current_version)
    [[ "$ver" != "not-installed" ]] && echo -e "  Version: ${GREEN}$ver${NC}" && echo ""
    echo -e "${CYAN}━━━ Main Menu ━━━${NC}"
    echo ""
    echo "  1) Install Server (single or multi-listener)"
    echo "  2) Install Client"
    echo "  3) Update Core"
    echo "  4) System Optimizer"
    echo "  5) Uninstall"
    echo ""
    echo "  9) Control Panel (panel.sh)"
    echo "  0) Exit"
    echo ""
    read -p "  Choice: " c
    case $c in
        1) install_server ;;
        2) install_client ;;
        3) update_binary ;;
        4) optimize_system; read -p "Press Enter..."; main_menu ;;
        5) uninstall ;;
        9) [[ -f "/usr/local/bin/dagger-panel" ]] && /usr/local/bin/dagger-panel || echo -e "${YELLOW}Panel not installed${NC}"; read -p "Enter..."; main_menu ;;
        0) echo -e "${GREEN}Bye${NC}"; exit 0 ;;
        *) main_menu ;;
    esac
}

check_root
banner
install_deps

if [[ ! -f "$INSTALL_DIR/DaggerConnect" ]]; then
    echo -e "${YELLOW}DaggerConnect not found. Installing...${NC}"
    download_binary
    echo ""
fi

main_menu
