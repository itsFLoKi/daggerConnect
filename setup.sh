#!/bin/bash

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; DIM='\033[2m'; NC='\033[0m'

# ── Paths ────────────────────────────────────────────────────────────────────
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/DaggerConnect"
SYSTEMD_DIR="/etc/systemd/system"
LATEST_RELEASE_API="https://api.github.com/repos/itsFLoKi/DaggerConnect/releases/latest"
BINARY_DOWNLOAD_URL_1="http://88.218.16.242/DaggerConnect"
FIRST_RUN_FLAG="$CONFIG_DIR/.first_run_done"

# ── Global state vars ────────────────────────────────────────────────────────
_TUN_NAME=""; _TUN_LOCAL=""; _TUN_PEER=""; _TUN_MTU="1400"
_RM_HS_TIMEOUT="10"; _RM_KEEPALIVE="15"; _RM_RBUF="4194304"
_RM_WBUF="4194304"; _RM_USE_PCAP="false"
_DM_IFACE=""; _DM_LOCAL_IP=""; _DM_ROUTER_MAC=""
_DM_MTU="1350"; _DM_SND_WND="1024"; _DM_RCV_WND="1024"
_DM_DATA_SHARD="10"; _DM_PARITY_SHARD="1"
_DM_LOCAL_FLAGS="PA,A"; _DM_REMOTE_FLAGS="PA,A"

# TunTransport state vars (matches tun_transport yaml keys exactly)
_TT_DEVICE="dagger0"
_TT_LOCAL_CIDR="10.10.10.2/24"
_TT_REMOTE_CIDR="10.10.10.1/24"
_TT_MTU="1320"
_TT_PROFILE="tcp"
_TT_LISTEN_IP="0.0.0.0"
_TT_DEST_IP=""
_TT_HEALTH_PORT="1234"
_TT_WORKERS="0"
_TT_BATCH_SIZE="2048"
_TT_AUTO_TUNING="true"
_TT_TUNING_PROFILE="balanced"

MAPPINGS=""

# ============================================================================
# UI HELPERS
# ============================================================================

show_banner() {
    clear
    echo -e "${CYAN}"
    echo -e "  ╔══════════════════════════════════════════╗"
    echo -e "  ║       D A G G E R C O N N E C T         ║"
    echo -e "  ║     High-Performance Tunnel Manager      ║"
    echo -e "  ╠══════════════════════════════════════════╣"
    echo -e "  ║  ${BLUE}Telegram: @DaggerConnect${CYAN}                 ║"
    echo -e "  ╚══════════════════════════════════════════╝${NC}"
    echo ""
}

section()     { echo ""; echo -e "${CYAN}  ┌─ $1${NC}"; echo ""; }
ok()          { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()        { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()         { echo -e "  ${RED}✗${NC}  $1"; }
info()        { echo -e "  ${DIM}→${NC}  $1"; }
divider()     { echo -e "  ${DIM}──────────────────────────────────────────${NC}"; }
press_enter() { echo ""; read -rp "  Press Enter to continue..." _; }

# ============================================================================
# ROOT CHECK
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root."
        exit 1
    fi
}

# ============================================================================
# DEPENDENCIES
# ============================================================================

install_dependencies() {
    section "Installing Dependencies"
    ok "Dependencies ready."
}

# ============================================================================
# BINARY MANAGEMENT
# ============================================================================

get_current_version() {
    if [[ -f "$INSTALL_DIR/DaggerConnect" ]]; then
        "$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+\.\d+(\.\d+)?' || echo "unknown"
    else
        echo "not-installed"
    fi
}

download_binary() {
    section "Downloading DaggerConnect"
    mkdir -p "$INSTALL_DIR"

    echo ""
    echo -e "  ${YELLOW}Select download source:${NC}"
    echo -e "  ${WHITE}1)${NC} GitHub     — latest release (requires internet access to github.com)"

    local LATEST_VERSION
    LATEST_VERSION=$(curl -s --connect-timeout 5 "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -n "$LATEST_VERSION" ]] && echo -e "             ${DIM}(current: ${LATEST_VERSION})${NC}" || echo -e "             ${DIM}(could not fetch version)${NC}"

    echo -e "  ${WHITE}2)${NC} Server 1   — ${GREEN}${BINARY_DOWNLOAD_URL_1}${NC}"
    echo ""
    read -rp "  Choice [1]: " DL_CHOICE || true

    local BINARY_URL
    case ${DL_CHOICE:-1} in
        2)
            BINARY_URL="$BINARY_DOWNLOAD_URL_1"
            info "Source: ${GREEN}${BINARY_URL}${NC}"
            ;;
        3)
            BINARY_URL="$BINARY_DOWNLOAD_URL_2"
            info "Source: ${GREEN}${BINARY_URL}${NC}"
            ;;
        *)
            [[ -z "$LATEST_VERSION" ]] && warn "Could not fetch latest version — using v1.5" && LATEST_VERSION="v1.5"
            BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
            info "GitHub release: ${GREEN}${LATEST_VERSION}${NC}"
            ;;
    esac

    [[ -f "$INSTALL_DIR/DaggerConnect" ]] && mv "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.backup" || true

    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        rm -f "$INSTALL_DIR/DaggerConnect.backup"
        ok "Binary downloaded successfully."
    else
        err "Download failed — trying Server 1 as fallback..."
        BINARY_URL="$BINARY_DOWNLOAD_URL_1"
        if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
            chmod +x "$INSTALL_DIR/DaggerConnect"
            rm -f "$INSTALL_DIR/DaggerConnect.backup"
            ok "Binary downloaded from fallback source."
        else
            err "Download failed from all sources."
            if [[ -f "$INSTALL_DIR/DaggerConnect.backup" ]]; then
                mv "$INSTALL_DIR/DaggerConnect.backup" "$INSTALL_DIR/DaggerConnect"
                warn "Restored previous version."
            fi
            exit 1
        fi
    fi
}

# ============================================================================
# SYSTEM OPTIMIZER
# ============================================================================

optimize_system() {
    local LOCATION="${1:-iran}"
    section "System Optimization (${LOCATION^^})"

    local INTERFACE
    INTERFACE=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    [[ -z "$INTERFACE" ]] && INTERFACE="eth0"
    info "Interface: ${GREEN}${INTERFACE}${NC}"

    sysctl -w net.core.rmem_max=8388608               > /dev/null 2>&1 || true
    sysctl -w net.core.wmem_max=8388608               > /dev/null 2>&1 || true
    sysctl -w net.core.rmem_default=131072            > /dev/null 2>&1 || true
    sysctl -w net.core.wmem_default=131072            > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_rmem="4096 65536 8388608"  > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_wmem="4096 65536 8388608"  > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_window_scaling=1           > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_timestamps=1               > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_sack=1                     > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_retries2=6                 > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_syn_retries=2              > /dev/null 2>&1 || true
    sysctl -w net.core.netdev_max_backlog=1000         > /dev/null 2>&1 || true
    sysctl -w net.core.somaxconn=512                  > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_fastopen=3                 > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_low_latency=1              > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0    > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_no_metrics_save=1          > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_autocorking=0              > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_mtu_probing=1              > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_keepalive_time=120         > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_keepalive_intvl=10         > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_keepalive_probes=3         > /dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_fin_timeout=15             > /dev/null 2>&1 || true
    sysctl -w net.ipv4.ip_forward=1                   > /dev/null 2>&1 || true

    if modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1 || true
        sysctl -w net.core.default_qdisc=fq_codel     > /dev/null 2>&1 || true
        ok "BBR congestion control enabled."
    else
        warn "BBR not available — using CUBIC."
    fi

    tc qdisc del dev "$INTERFACE" root 2>/dev/null || true
    if tc qdisc add dev "$INTERFACE" root fq_codel limit 500 target 3ms interval 50ms quantum 300 ecn 2>/dev/null; then
        ok "fq_codel qdisc configured."
    else
        warn "qdisc configuration skipped (container/VPS may not support tc)."
    fi

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
    ok "Optimization settings persisted to /etc/sysctl.d/99-daggerconnect.conf"
}

system_optimizer_menu() {
    show_banner
    section "System Optimizer"
    echo -e "  ${WHITE}1)${NC} Optimize for Iran Server"
    echo -e "  ${WHITE}2)${NC} Optimize for Foreign Server"
    echo -e "  ${WHITE}0)${NC} Back"
    echo ""
    read -rp "  Select: " choice || true
    case $choice in
        1) optimize_system "iran";    press_enter; main_menu ;;
        2) optimize_system "foreign"; press_enter; main_menu ;;
        0) main_menu ;;
        *) system_optimizer_menu ;;
    esac
}

# ============================================================================
# HELPER: VALIDATE INSTANCE NAME
# ============================================================================

_validate_instance_name() {
    local NAME=$1
    # فقط حروف، عدد، خط تیره و underscore مجاز
    if [[ -z "$NAME" ]]; then
        echo -e "  ${RED}✗${NC}  Name cannot be empty!" >&2; return 1
    fi
    if ! [[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "  ${RED}✗${NC}  Name can only contain letters, numbers, '-' and '_'" >&2; return 1
    fi
    if [[ ${#NAME} -gt 32 ]]; then
        echo -e "  ${RED}✗${NC}  Name too long (max 32 chars)" >&2; return 1
    fi
    return 0
}

_pick_instance_name() {
    local ROLE=$1        # "server" or "client"
    local DEFAULT=$2     # default suggestion

    echo "" >&2
    echo -e "  ${YELLOW}Instance Name${NC} ${DIM}(used as DaggerConnect-{NAME})${NC}" >&2
    echo -e "  ${DIM}Letters, numbers, '-' and '_' only. Max 32 chars.${NC}" >&2
    echo -e "  ${DIM}Example: server-ir1 | client-de | tunnel-v2ray${NC}" >&2
    echo "" >&2

    local NAME
    while true; do
        read -rp "  Name [${DEFAULT}]: " NAME <>/dev/tty || true
        NAME=${NAME:-$DEFAULT}
        if _validate_instance_name "$NAME"; then
            # بررسی تکراری بودن
            if [[ -f "$CONFIG_DIR/${NAME}.yaml" ]]; then
                echo -e "  ${YELLOW}⚠${NC}  Instance '${NAME}' already exists!" >&2
                read -rp "  Overwrite? [y/N]: " OW <>/dev/tty || true
                [[ $OW =~ ^[Yy]$ ]] && break || continue
            fi
            break
        fi
    done
    echo "$NAME"
}

# ============================================================================
# HELPER: SELECT TRANSPORT
# ============================================================================

select_transport() {
    echo "" >&2
    echo -e "  ${YELLOW}Select Transport:${NC}" >&2
    divider >&2
    echo -e "  ${WHITE}1)${NC} httpsmux  — HTTPS Mimicry ${GREEN}(Recommended)${NC}" >&2
    echo -e "  ${WHITE}2)${NC} httpmux   — HTTP Mimicry" >&2
    echo -e "  ${WHITE}3)${NC} wssmux    — WebSocket Secure" >&2
    echo -e "  ${WHITE}4)${NC} wsmux     — WebSocket" >&2
    echo -e "  ${WHITE}5)${NC} kcpmux    — KCP over UDP" >&2
    echo -e "  ${WHITE}6)${NC} tcpmux    — Simple TCP" >&2
    echo -e "  ${WHITE}7)${NC} rawmux    — ${CYAN}Raw KCP/UDP + DPI Bypass${NC}" >&2
    echo -e "  ${WHITE}8)${NC} daggermux — ${PURPLE}Raw TCP/KCP via pcap${NC}" >&2
    echo -e "  ${WHITE}9)${NC} tun       — ${YELLOW}TUN Device + IPX Encapsulation${NC}" >&2
    divider >&2
    echo "" >&2
    read -rp "  Choice [1-9]: " trans_choice || true
    case $trans_choice in
        1) echo "httpsmux"  ;;
        2) echo "httpmux"   ;;
        3) echo "wssmux"    ;;
        4) echo "wsmux"     ;;
        5) echo "kcpmux"    ;;
        6) echo "tcpmux"    ;;
        7) echo "rawmux"    ;;
        8) echo "daggermux" ;;
        9) echo "tun"       ;;
        *) echo "httpsmux"  ;;
    esac
}

# ============================================================================
# HELPER: CONFIGURE RAWMUX
# ============================================================================

configure_rawmux() {
    section "RawMux Configuration"
    info "KCP over real UDP socket with optional pcap DPI bypass."
    echo ""

    read -rp "  Handshake timeout (s)    [10]:      " RM_HS_TIMEOUT || true; RM_HS_TIMEOUT=${RM_HS_TIMEOUT:-10}
    read -rp "  Keepalive (s)            [15]:      " RM_KEEPALIVE || true;  RM_KEEPALIVE=${RM_KEEPALIVE:-15}
    read -rp "  Read buffer (bytes)      [4194304]: " RM_RBUF || true;       RM_RBUF=${RM_RBUF:-4194304}
    read -rp "  Write buffer (bytes)     [4194304]: " RM_WBUF || true;       RM_WBUF=${RM_WBUF:-4194304}
    echo ""
    read -rp "  Enable pcap DPI bypass?  [y/N]: " RM_PCAP_EN || true
    local RM_USE_PCAP
    [[ "$RM_PCAP_EN" =~ ^[Yy]$ ]] && RM_USE_PCAP="true" || RM_USE_PCAP="false"

    _RM_HS_TIMEOUT="$RM_HS_TIMEOUT"
    _RM_KEEPALIVE="$RM_KEEPALIVE"
    _RM_RBUF="$RM_RBUF"
    _RM_WBUF="$RM_WBUF"
    _RM_USE_PCAP="$RM_USE_PCAP"
}

write_rawmux_config() {
    local FILE=$1
    {
        echo ""
        echo "rawmux:"
        echo "  handshake_timeout: ${_RM_HS_TIMEOUT}"
        echo "  keepalive: ${_RM_KEEPALIVE}"
        echo "  read_buffer: ${_RM_RBUF}"
        echo "  write_buffer: ${_RM_WBUF}"
        echo "  use_pcap: ${_RM_USE_PCAP}"
    } >> "$FILE"
}

# ============================================================================
# HELPER: CONFIGURE DAGGERMUX
# ============================================================================

configure_daggermux() {
    local SIDE=$1

    section "DaggerMux Configuration"
    warn "Uses raw TCP packets via pcap to bypass DPI/firewalls."
    warn "Requires: root access, libpcap-dev, and iptables rules on server."
    echo ""

    read -rp "  Network interface        [auto-detect]: " DM_IFACE || true
    read -rp "  Local IP                 [auto-detect]: " DM_LOCAL_IP || true

    if [[ "$SIDE" == "client" ]]; then
        read -rp "  Gateway/Router MAC       [auto-detect]: " DM_ROUTER_MAC || true
    else
        DM_ROUTER_MAC=""
    fi

    echo ""
    read -rp "  MTU                      [1350]: " DM_MTU || true;        DM_MTU=${DM_MTU:-1350}
    read -rp "  Send window              [1024]: " DM_SND_WND || true;    DM_SND_WND=${DM_SND_WND:-1024}
    read -rp "  Recv window              [1024]: " DM_RCV_WND || true;    DM_RCV_WND=${DM_RCV_WND:-1024}

    echo ""
    echo -e "  ${DIM}FEC — lower parity = less overhead (1 is usually optimal)${NC}"
    read -rp "  Data shards              [10]:   " DM_DATA_SHARD || true;   DM_DATA_SHARD=${DM_DATA_SHARD:-10}
    read -rp "  Parity shards            [1]:    " DM_PARITY_SHARD || true; DM_PARITY_SHARD=${DM_PARITY_SHARD:-1}

    echo ""
    echo -e "  ${DIM}TCP flags to inject: PA=Push+Ack, A=Ack, S=Syn${NC}"
    read -rp "  Local flags              [PA,A]: " DM_LOCAL_FLAGS || true;  DM_LOCAL_FLAGS=${DM_LOCAL_FLAGS:-"PA,A"}
    read -rp "  Remote flags             [PA,A]: " DM_REMOTE_FLAGS || true; DM_REMOTE_FLAGS=${DM_REMOTE_FLAGS:-"PA,A"}

    _DM_IFACE="$DM_IFACE"
    _DM_LOCAL_IP="$DM_LOCAL_IP"
    _DM_ROUTER_MAC="$DM_ROUTER_MAC"
    _DM_MTU="$DM_MTU"
    _DM_SND_WND="$DM_SND_WND"
    _DM_RCV_WND="$DM_RCV_WND"
    _DM_DATA_SHARD="$DM_DATA_SHARD"
    _DM_PARITY_SHARD="$DM_PARITY_SHARD"
    _DM_LOCAL_FLAGS="$DM_LOCAL_FLAGS"
    _DM_REMOTE_FLAGS="$DM_REMOTE_FLAGS"
}

write_daggermux_config() {
    local FILE=$1
    local SIDE=$2

    local LOCAL_FLAGS_YAML=""
    local OLD_IFS="$IFS"
    IFS=',' read -ra FLAGS <<< "$_DM_LOCAL_FLAGS"
    for f in "${FLAGS[@]}"; do
        f=$(echo "$f" | tr -d ' ')
        LOCAL_FLAGS_YAML="${LOCAL_FLAGS_YAML}    - \"${f}\"\n"
    done

    local REMOTE_FLAGS_YAML=""
    IFS=',' read -ra FLAGS <<< "$_DM_REMOTE_FLAGS"
    for f in "${FLAGS[@]}"; do
        f=$(echo "$f" | tr -d ' ')
        REMOTE_FLAGS_YAML="${REMOTE_FLAGS_YAML}    - \"${f}\"\n"
    done
    IFS="$OLD_IFS"

    {
        echo ""
        echo "daggermux:"
        [[ -n "$_DM_IFACE" ]]    && echo "  interface: \"${_DM_IFACE}\""   || true
        [[ -n "$_DM_LOCAL_IP" ]] && echo "  local_ip: \"${_DM_LOCAL_IP}\"" || true
        if [[ "$SIDE" == "client" && -n "$_DM_ROUTER_MAC" ]]; then
            echo "  router_mac: \"${_DM_ROUTER_MAC}\""
        fi
        echo "  mtu: ${_DM_MTU}"
        echo "  snd_wnd: ${_DM_SND_WND}"
        echo "  rcv_wnd: ${_DM_RCV_WND}"
        echo "  data_shard: ${_DM_DATA_SHARD}"
        echo "  parity_shard: ${_DM_PARITY_SHARD}"
        echo "  local_flags:"
        printf '%b' "$LOCAL_FLAGS_YAML"
        echo "  remote_flags:"
        printf '%b' "$REMOTE_FLAGS_YAML"
    } >> "$FILE"
}

setup_daggermux_iptables() {
    local PORT=$1
    section "DaggerMux iptables Rules"
    warn "These rules are MANDATORY — without them, kernel sends RST packets."
    echo ""

    iptables -t raw    -A PREROUTING -p tcp --dport "$PORT" -j NOTRACK                    2>/dev/null || true
    iptables -t raw    -A OUTPUT     -p tcp --sport "$PORT" -j NOTRACK                    2>/dev/null || true
    iptables -t mangle -A OUTPUT     -p tcp --sport "$PORT" --tcp-flags RST RST -j DROP   2>/dev/null || true
    ok "iptables rules applied for port ${PORT}."

    if command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null && ok "Rules saved to /etc/iptables/rules.v4" || true
    fi

    local IPRULES_FILE="/etc/network/if-pre-up.d/daggermux-iptables"
    mkdir -p "$(dirname "$IPRULES_FILE")"
    printf '#!/bin/bash\niptables -t raw    -A PREROUTING -p tcp --dport %s -j NOTRACK 2>/dev/null || true\niptables -t raw    -A OUTPUT     -p tcp --sport %s -j NOTRACK 2>/dev/null || true\niptables -t mangle -A OUTPUT     -p tcp --sport %s --tcp-flags RST RST -j DROP 2>/dev/null || true\n' \
        "$PORT" "$PORT" "$PORT" > "$IPRULES_FILE"
    chmod +x "$IPRULES_FILE" 2>/dev/null || true

    echo ""
    info "Manual commands (if needed):"
    echo -e "  ${DIM}iptables -t raw    -A PREROUTING -p tcp --dport ${PORT} -j NOTRACK"
    echo -e "  iptables -t raw    -A OUTPUT     -p tcp --sport ${PORT} -j NOTRACK"
    echo -e "  iptables -t mangle -A OUTPUT     -p tcp --sport ${PORT} --tcp-flags RST RST -j DROP${NC}"
}

# ============================================================================
# HELPER: CONFIGURE TUN TRANSPORT
# ============================================================================

configure_tun_transport() {
    local SIDE=$1

    section "TUN Transport Configuration"
    info "TUN device with IPX encapsulation. No smux — direct packet forwarding."
    warn "Requires: root access + tun kernel module."
    echo ""

    read -rp "  TUN device name          [dagger0]:       " TT_DEV || true
    TT_DEV=${TT_DEV:-dagger0}

    if [[ "$SIDE" == "server" ]]; then
        info "Server: local=10.10.10.1/24  remote=10.10.10.2/24"
        read -rp "  Local CIDR               [10.10.10.1/24]: " TT_LOCAL || true
        TT_LOCAL=${TT_LOCAL:-10.10.10.1/24}
        read -rp "  Remote CIDR              [10.10.10.2/24]: " TT_REMOTE || true
        TT_REMOTE=${TT_REMOTE:-10.10.10.2/24}
    else
        info "Client: local=10.10.10.2/24  remote=10.10.10.1/24"
        read -rp "  Local CIDR               [10.10.10.2/24]: " TT_LOCAL || true
        TT_LOCAL=${TT_LOCAL:-10.10.10.2/24}
        read -rp "  Remote CIDR              [10.10.10.1/24]: " TT_REMOTE || true
        TT_REMOTE=${TT_REMOTE:-10.10.10.1/24}
    fi

    read -rp "  MTU                      [1320]:          " TT_MTU || true
    TT_MTU=${TT_MTU:-1320}
    local TT_HEALTH=1234  # بعداً از LISTEN_PORT override میشه

    echo ""
    echo -e "  ${YELLOW}Encapsulation Profile:${NC}"
    echo -e "  ${WHITE}1)${NC} tcp  — TCP stream        ${GREEN}(Recommended, no root needed)${NC}"
    echo -e "  ${WHITE}2)${NC} udp  — UDP datagrams"
    echo -e "  ${WHITE}3)${NC} bip  — UDP + magic header ${DIM}(traffic blending)${NC}"
    echo -e "  ${WHITE}4)${NC} icmp — ICMP payload       ${YELLOW}(needs root/CAP_NET_RAW)${NC}"
    echo -e "  ${WHITE}5)${NC} ipip — IP-in-IP           ${YELLOW}(needs root/CAP_NET_RAW)${NC}"
    echo -e "  ${WHITE}6)${NC} gre  — GRE tunnel         ${YELLOW}(needs root/CAP_NET_RAW)${NC}"
    echo ""
    read -rp "  Profile [1]: " TT_PROF_CHOICE || true
    case $TT_PROF_CHOICE in
        2) TT_PROFILE="udp"  ;;
        3) TT_PROFILE="bip"  ;;
        4) TT_PROFILE="icmp" ;;
        5) TT_PROFILE="ipip" ;;
        6) TT_PROFILE="gre"  ;;
        *) TT_PROFILE="tcp"  ;;
    esac

    echo ""
    read -rp "  Listen IP (bind)         [0.0.0.0]:       " TT_LISTEN_IP || true
    TT_LISTEN_IP=${TT_LISTEN_IP:-0.0.0.0}

    TT_DEST_IP=""
    if [[ "$SIDE" == "client" ]]; then
        read -rp "  Server IP (dest_ip):     " TT_DEST_IP || true
        while [[ -z "$TT_DEST_IP" ]]; do
            err "dest_ip is required on client side!"
            read -rp "  Server IP (dest_ip):     " TT_DEST_IP || true
        done
    elif [[ "$TT_PROFILE" == "bip" || "$TT_PROFILE" == "icmp" || \
            "$TT_PROFILE" == "ipip" || "$TT_PROFILE" == "gre" ]]; then
        warn "Profile '${TT_PROFILE}' requires client IP for BPF filter on server side."
        read -rp "  Client IP (dest_ip):     " TT_DEST_IP || true
        while [[ -z "$TT_DEST_IP" ]]; do
            err "dest_ip is required for profile '${TT_PROFILE}'!"
            read -rp "  Client IP (dest_ip):     " TT_DEST_IP || true
        done
    fi

    echo ""
    echo -e "  ${YELLOW}Tuning Profile:${NC}"
    echo -e "  ${WHITE}1)${NC} balanced  ${GREEN}(Recommended)${NC}"
    echo -e "  ${WHITE}2)${NC} fast      — max throughput"
    echo -e "  ${WHITE}3)${NC} latency   — min latency, fewer workers"
    echo -e "  ${WHITE}4)${NC} resource  — low CPU/memory"
    read -rp "  Choice [1]: " TT_TUNING_CHOICE || true
    case $TT_TUNING_CHOICE in
        2) TT_TUNING="fast"     ;;
        3) TT_TUNING="latency"  ;;
        4) TT_TUNING="resource" ;;
        *) TT_TUNING="balanced" ;;
    esac

    read -rp "  Worker threads (0=auto)  [0]:             " TT_WORKERS || true
    TT_WORKERS=${TT_WORKERS:-0}
    read -rp "  Batch size               [2048]:          " TT_BATCH || true
    TT_BATCH=${TT_BATCH:-2048}

    _TT_DEVICE="$TT_DEV"
    _TT_LOCAL_CIDR="$TT_LOCAL"
    _TT_REMOTE_CIDR="$TT_REMOTE"
    _TT_MTU="$TT_MTU"
    _TT_PROFILE="$TT_PROFILE"
    _TT_LISTEN_IP="$TT_LISTEN_IP"
    _TT_DEST_IP="$TT_DEST_IP"
    _TT_HEALTH_PORT="$TT_HEALTH"
    _TT_WORKERS="$TT_WORKERS"
    _TT_BATCH_SIZE="$TT_BATCH"
    _TT_AUTO_TUNING="true"
    _TT_TUNING_PROFILE="$TT_TUNING"
}

write_tun_transport_config() {
    local FILE=$1
    local SIDE=$2

    {
        echo ""
        echo "tun_transport:"
        echo "  device_name: \"${_TT_DEVICE}\""
        echo "  local_cidr: \"${_TT_LOCAL_CIDR}\""
        echo "  remote_cidr: \"${_TT_REMOTE_CIDR}\""
        echo "  mtu: ${_TT_MTU}"
        echo "  health_port: ${_TT_HEALTH_PORT}"
        echo "  profile: \"${_TT_PROFILE}\""
        echo "  listen_ip: \"${_TT_LISTEN_IP}\""
        if [[ -n "${_TT_DEST_IP:-}" ]]; then
            echo "  dest_ip: \"${_TT_DEST_IP}\""
        fi
        echo "  auto_tuning: ${_TT_AUTO_TUNING}"
        echo "  tuning_profile: \"${_TT_TUNING_PROFILE}\""
        echo "  workers: ${_TT_WORKERS}"
        echo "  batch_size: ${_TT_BATCH_SIZE}"
    } >> "$FILE"

    modprobe tun 2>/dev/null || true
}

show_tun_transport_notes() {
    local SIDE=$1
    section "TUN Transport Notes"
    ok "TUN kernel module: $(modprobe tun 2>/dev/null && echo 'loaded' || echo 'already active')"
    info "Device '${_TT_DEVICE}' created automatically at startup."
    info "Local CIDR:  ${GREEN}${_TT_LOCAL_CIDR}${NC}"
    info "Remote CIDR: ${GREEN}${_TT_REMOTE_CIDR}${NC}"
    info "Profile:     ${GREEN}${_TT_PROFILE}${NC}"
    info "Tuning:      ${GREEN}${_TT_TUNING_PROFILE}${NC}"
    echo ""
    if [[ "$_TT_PROFILE" == "icmp" || "$_TT_PROFILE" == "ipip" || "$_TT_PROFILE" == "gre" ]]; then
        warn "Profile '${_TT_PROFILE}' requires root and CAP_NET_RAW."
        warn "Ensure firewall allows protocol: ${_TT_PROFILE}."
    fi
    info "Health check: tcp://$(hostname -I | awk '{print $1}'):$((${_TT_HEALTH_PORT}+1))/"
}

# ============================================================================
# HELPER: CONFIGURE TUN (legacy per-listener TUN via smux)
# ============================================================================

configure_tun() {
    local IDX=$1
    local SIDE=$2

    section "TUN Interface #${IDX}"
    warn "Each TUN must use a UNIQUE /32 IP pair to prevent conflicts."
    echo ""

    local DEFAULT_NAME="dagger${IDX}"
    read -rp "  Interface name    [${DEFAULT_NAME}]: " TUN_NAME || true; TUN_NAME=${TUN_NAME:-$DEFAULT_NAME}

    if [[ "$SIDE" == "server" ]]; then
        info "Example: local=20.40.${IDX}.1  peer=20.40.${IDX}.2"
        read -rp "  Local IP (server) [20.40.${IDX}.1]: " TUN_LOCAL || true; TUN_LOCAL=${TUN_LOCAL:-"20.40.${IDX}.1"}
        read -rp "  Peer  IP (client) [20.40.${IDX}.2]: " TUN_PEER || true;  TUN_PEER=${TUN_PEER:-"20.40.${IDX}.2"}
    else
        info "Example: local=20.40.${IDX}.2  peer=20.40.${IDX}.1"
        read -rp "  Local IP (client) [20.40.${IDX}.2]: " TUN_LOCAL || true; TUN_LOCAL=${TUN_LOCAL:-"20.40.${IDX}.2"}
        read -rp "  Peer  IP (server) [20.40.${IDX}.1]: " TUN_PEER || true;  TUN_PEER=${TUN_PEER:-"20.40.${IDX}.1"}
    fi

    read -rp "  MTU               [1400]: " TUN_MTU || true; TUN_MTU=${TUN_MTU:-1400}

    _TUN_NAME="$TUN_NAME"
    _TUN_LOCAL="$TUN_LOCAL"
    _TUN_PEER="$TUN_PEER"
    _TUN_MTU="$TUN_MTU"
}

# ============================================================================
# PORT VALIDATION HELPER
# ============================================================================

_validate_port() {
    local P=$1
    local LABEL=${2:-"Port"}
    if ! [[ "$P" =~ ^[0-9]+$ ]] || [[ "$P" -lt 1 || "$P" -gt 65535 ]]; then
        err "${LABEL} '${P}' is invalid (must be 1-65535)."
        return 1
    fi
    return 0
}

# ============================================================================
# HELPER: BUILD PORT MAPPINGS
# ============================================================================

_do_add_mapping() {
    local BIND_P=$1
    local TARGET_ADDR=$2
    if [[ "$PROTO" == "both" ]]; then
        MAPPINGS="${MAPPINGS}  - type: tcp\n    bind: \"${BIND_IP}:${BIND_P}\"\n    target: \"${TARGET_ADDR}\"\n"
        MAPPINGS="${MAPPINGS}  - type: udp\n    bind: \"${BIND_IP}:${BIND_P}\"\n    target: \"${TARGET_ADDR}\"\n"
        COUNT=$((COUNT+2))
    else
        MAPPINGS="${MAPPINGS}  - type: ${PROTO}\n    bind: \"${BIND_IP}:${BIND_P}\"\n    target: \"${TARGET_ADDR}\"\n"
        COUNT=$((COUNT+1))
    fi
}

build_port_mappings() {
    local BIND_IP="0.0.0.0"
    # اگه TUN انتخاب شده، target پیش‌فرض = peer IP تانل
    local TARGET_IP="127.0.0.1"
    local _IS_TUN=false
    [[ "${_CURRENT_TRANSPORT:-}" == "tun" ]] && _IS_TUN=true
    if $_IS_TUN; then
        TARGET_IP=$(echo "${_TT_REMOTE_CIDR}" | cut -d/ -f1)
    fi
    MAPPINGS=""
    local COUNT=0
    local PROTO="tcp"

    section "Port Mappings"
    if $_IS_TUN; then
        info "TUN mode — default target IP: ${GREEN}${TARGET_IP}${NC} (remote peer)"
    fi
    echo -e "  ${DIM}Formats: 8080 | 1000/2000 | 5000=8080 | 1000/1010=2000/2010 | 5000=1.2.3.4:8080${NC}"
    echo ""

    while true; do
        echo ""
        echo -e "  ${YELLOW}-- Mapping #$((COUNT+1)) --${NC}"
        echo -e "  Protocol: ${WHITE}1)${NC}tcp  ${WHITE}2)${NC}udp  ${WHITE}3)${NC}both"
        read -rp "  Choice [1]: " proto_choice || true
        case $proto_choice in
            2) PROTO="udp"  ;;
            3) PROTO="both" ;;
            *) PROTO="tcp"  ;;
        esac

        read -rp "  Port(s): " PORT_INPUT || true
        [[ -z "$PORT_INPUT" ]] && err "Cannot be empty!" && continue
        PORT_INPUT=$(echo "$PORT_INPUT" | tr -d ' ')

        if [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)/([0-9]+)$ ]]; then
            local BS="${BASH_REMATCH[1]}" BE="${BASH_REMATCH[2]}"
            local CTIP="${BASH_REMATCH[3]}" TS="${BASH_REMATCH[4]}" TE="${BASH_REMATCH[5]}"
            local _valid=true
            _validate_port "$BS" "Bind start" || _valid=false
            _validate_port "$BE" "Bind end"   || _valid=false
            _validate_port "$TS" "Target start" || _valid=false
            _validate_port "$TE" "Target end"   || _valid=false
            [[ "$_valid" == "false" ]] && continue
            local BR=$((BE-BS+1)) TR=$((TE-TS+1))
            if [[ "$BR" -ne "$TR" ]]; then err "Range size mismatch!"; continue; fi
            if [[ "$BS" -gt "$BE" ]]; then err "Bind start > end!"; continue; fi
            local _total_entries; [[ "$PROTO" == "both" ]] && _total_entries=$((BR*2)) || _total_entries=$BR
            for ((i=0; i<BR; i++)); do _do_add_mapping $((BS+i)) "${CTIP}:$((TS+i))"; done
            ok "Added: ${BS}-${BE} -> ${CTIP}:${TS}-${TE} (${PROTO}, ${_total_entries} entries)"

        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+)/([0-9]+)$ ]]; then
            local BS="${BASH_REMATCH[1]}" BE="${BASH_REMATCH[2]}"
            local TS="${BASH_REMATCH[3]}" TE="${BASH_REMATCH[4]}"
            local _valid=true
            _validate_port "$BS" "Bind start" || _valid=false
            _validate_port "$BE" "Bind end"   || _valid=false
            _validate_port "$TS" "Target start" || _valid=false
            _validate_port "$TE" "Target end"   || _valid=false
            [[ "$_valid" == "false" ]] && continue
            local BR=$((BE-BS+1)) TR=$((TE-TS+1))
            if [[ "$BR" -ne "$TR" ]]; then err "Range size mismatch!"; continue; fi
            if [[ "$BS" -gt "$BE" ]]; then err "Bind start > end!"; continue; fi
            local _total_entries; [[ "$PROTO" == "both" ]] && _total_entries=$((BR*2)) || _total_entries=$BR
            for ((i=0; i<BR; i++)); do _do_add_mapping $((BS+i)) "${TARGET_IP}:$((TS+i))"; done
            ok "Added: ${BS}-${BE} -> ${TS}-${TE} (${BR} ports, ${PROTO}, ${_total_entries} entries)"

        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            local SP="${BASH_REMATCH[1]}" EP="${BASH_REMATCH[2]}"
            local _valid=true
            _validate_port "$SP" "Start port" || _valid=false
            _validate_port "$EP" "End port"   || _valid=false
            [[ "$_valid" == "false" ]] && continue
            if [[ "$SP" -gt "$EP" ]]; then err "Start > end!"; continue; fi
            local RS=$((EP-SP+1))
            if [[ "$RS" -gt 1000 ]]; then
                read -rp "  Large range (${RS} ports). Continue? [y/N]: " cr || true
                [[ ! $cr =~ ^[Yy]$ ]] && continue
            fi
            local _total_entries; [[ "$PROTO" == "both" ]] && _total_entries=$((RS*2)) || _total_entries=$RS
            for ((port=SP; port<=EP; port++)); do _do_add_mapping "$port" "${TARGET_IP}:${port}"; done
            ok "Added: ${SP}-${EP} (${RS} ports, ${PROTO}, ${_total_entries} entries)"

        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
            local BPORT="${BASH_REMATCH[1]}" CTIP="${BASH_REMATCH[2]}" TPORT="${BASH_REMATCH[3]}"
            local _valid=true
            _validate_port "$BPORT" "Bind port"   || _valid=false
            _validate_port "$TPORT" "Target port" || _valid=false
            [[ "$_valid" == "false" ]] && continue
            _do_add_mapping "${BPORT}" "${CTIP}:${TPORT}"
            ok "Added: ${BPORT} -> ${CTIP}:${TPORT} (${PROTO})"

        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            local BPORT="${BASH_REMATCH[1]}" TPORT="${BASH_REMATCH[2]}"
            local _valid=true
            _validate_port "$BPORT" "Bind port"   || _valid=false
            _validate_port "$TPORT" "Target port" || _valid=false
            [[ "$_valid" == "false" ]] && continue
            _do_add_mapping "${BPORT}" "${TARGET_IP}:${TPORT}"
            ok "Added: ${BPORT} -> ${TPORT} (${PROTO})"

        elif [[ "$PORT_INPUT" =~ ^[0-9]+$ ]]; then
            if ! _validate_port "$PORT_INPUT" "Port"; then continue; fi
            _do_add_mapping "$PORT_INPUT" "${TARGET_IP}:${PORT_INPUT}"
            ok "Added: ${PORT_INPUT} -> ${PORT_INPUT} (${PROTO})"

        else
            err "Invalid format!"; continue
        fi

        read -rp "  Add another mapping? [y/N]: " am || true
        [[ ! "$am" =~ ^[Yy]$ ]] && break
    done

    if [[ "$COUNT" -eq 0 ]]; then
        warn "No mappings defined — using default 8080->8080."
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
  enabled: false
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

    DOMAIN=$(echo "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
    [[ -z "$DOMAIN" ]] && DOMAIN="www.google.com"

    mkdir -p "$(dirname "$CERT_OUT")"
    rm -f "$CERT_OUT" "$KEY_OUT"

    if openssl req -x509 -newkey rsa:4096 \
        -keyout "$KEY_OUT" \
        -out "$CERT_OUT" \
        -days 365 -nodes \
        -subj "/C=US/O=MyCompany/CN=${DOMAIN}" 2>/dev/null; then
        ok "SSL certificate generated for: ${DOMAIN}"
        return 0
    else
        err "SSL certificate generation failed."
        rm -f "$CERT_OUT" "$KEY_OUT"
        return 1
    fi
}

# ============================================================================
# SYSTEMD SERVICE
# ============================================================================

create_systemd_service() {
    local MODE=$1
    local INSTANCE_NAME=${2:-$MODE}
    local MODE_CAP
    MODE_CAP="$(echo "${INSTANCE_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${INSTANCE_NAME:1}"

    mkdir -p "$SYSTEMD_DIR"

    cat > "$SYSTEMD_DIR/DaggerConnect-${INSTANCE_NAME}.service" << EOF
[Unit]
Description=DaggerConnect Reverse Tunnel — ${MODE_CAP}
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/DaggerConnect -c $CONFIG_DIR/${INSTANCE_NAME}.yaml
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    if ! systemctl daemon-reload 2>/dev/null; then
        warn "systemctl daemon-reload failed — may happen in containers. Continuing."
    fi
    ok "Systemd service created: DaggerConnect-${INSTANCE_NAME}"
}

# ============================================================================
# _write_transport_extras
# ============================================================================

_write_transport_extras() {
    local FILE=$1
    local SIDE=$2
    local TRANSPORT=$3
    [[ "$TRANSPORT" == "daggermux" ]] && write_daggermux_config    "$FILE" "$SIDE" || true
    [[ "$TRANSPORT" == "rawmux"    ]] && write_rawmux_config        "$FILE"         || true
    [[ "$TRANSPORT" == "tun"       ]] && write_tun_transport_config "$FILE" "$SIDE" || true
}

# ============================================================================
# HELPER: SAFE SERVICE START+ENABLE
# ============================================================================

safe_start_enable() {
    local SERVICE=$1
    if [[ ! -f "$SYSTEMD_DIR/${SERVICE}.service" ]]; then
        err "Service file not found: $SYSTEMD_DIR/${SERVICE}.service"
        warn "Config was saved. Start manually: systemctl start ${SERVICE}"
        return 1
    fi
    systemctl start  "$SERVICE" 2>/dev/null || warn "Service start failed — check: journalctl -u ${SERVICE} -n 50"
    systemctl enable "$SERVICE" 2>/dev/null || warn "Service enable failed."
}

# ============================================================================
# PORT CONFLICT CHECK
# ============================================================================

check_port_available() {
    local PORT=$1
    local IN_USE=false

    if command -v ss &>/dev/null; then
        if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || \
           ss -ulnp 2>/dev/null | grep -q ":${PORT} "; then
            IN_USE=true
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -q ":${PORT} " || \
           netstat -ulnp 2>/dev/null | grep -q ":${PORT} "; then
            IN_USE=true
        fi
    fi

    if $IN_USE; then
        local OWNER=""
        command -v ss &>/dev/null && \
            OWNER=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | awk '{print $NF}' | head -1) || true
        warn "Port ${PORT} is already in use! (${OWNER:-unknown process})"
        return 1
    fi
    return 0
}

# ============================================================================
# LIST ALL INSTANCES HELPER
# ============================================================================

_list_all_instances() {
    # برمیگردونه لیست تمام INSTANCE_NAME های موجود
    local pattern="$SYSTEMD_DIR/DaggerConnect-*.service"
    local arr=()
    for f in $pattern; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .service)
        name="${name#DaggerConnect-}"
        [[ -n "$name" ]] && arr+=("$name")
    done
    printf '%s\n' "${arr[@]}"
}

# ============================================================================
# AUTOMATIC SERVER — با نام دلخواه
# ============================================================================

install_server_automatic() {
    show_banner
    section "Server Setup"

    # ── انتخاب نام instance ──────────────────────────────────────────────────
    local INSTANCE_NAME
    INSTANCE_NAME=$(_pick_instance_name "server" "server")

    read -rp "  Tunnel port [2020]: " LISTEN_PORT || true
    LISTEN_PORT=${LISTEN_PORT:-2020}

    if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [[ "$LISTEN_PORT" -lt 1 || "$LISTEN_PORT" -gt 65535 ]]; then
        err "Invalid port number. Using default 2020."
        LISTEN_PORT=2020
    fi

    if ! check_port_available "$LISTEN_PORT"; then
        read -rp "  Port ${LISTEN_PORT} is busy. Use it anyway? [y/N]: " frc || true
        if [[ ! $frc =~ ^[Yy]$ ]]; then
            install_server_automatic
            return
        fi
    fi

    while true; do
        read -rsp "  PSK: " PSK || true; echo ""
        [[ -n "$PSK" ]] && break
        err "PSK cannot be empty!"
    done

    TRANSPORT=$(select_transport)

    if [[ "$TRANSPORT" == "tun" ]]; then
        configure_tun_transport "server"
        _TT_HEALTH_PORT="$LISTEN_PORT"
    fi

    if [[ "$TRANSPORT" == "daggermux" ]]; then
        configure_daggermux "server"
        setup_daggermux_iptables "$LISTEN_PORT"
    fi

    if [[ "$TRANSPORT" == "rawmux" ]]; then
        configure_rawmux
    fi

    local AUTO_MAPPINGS=""
    _CURRENT_TRANSPORT="$TRANSPORT"
    build_port_mappings
    AUTO_MAPPINGS="$MAPPINGS"

    CERT_FILE=""
    KEY_FILE=""

    if [[ "$TRANSPORT" == "httpsmux" || "$TRANSPORT" == "wssmux" ]]; then
        read -rp "  Domain for SSL cert [www.google.com]: " CD || true
        CD=${CD:-www.google.com}

        if gen_ssl_cert "$CONFIG_DIR/certs/${INSTANCE_NAME}_cert.pem" \
                        "$CONFIG_DIR/certs/${INSTANCE_NAME}_key.pem" "$CD"; then
            CERT_FILE="$CONFIG_DIR/certs/${INSTANCE_NAME}_cert.pem"
            KEY_FILE="$CONFIG_DIR/certs/${INSTANCE_NAME}_key.pem"
        fi
    fi

    CONFIG_FILE="$CONFIG_DIR/${INSTANCE_NAME}.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"server\""
        echo "psk: \"${PSK}\""
        echo "profile: \"latency\""
        echo "verbose: true"
        echo "heartbeat: 2"
        echo ""

        if [[ -n "$CERT_FILE" && -f "$CERT_FILE" ]]; then
            echo "cert_file: \"${CERT_FILE}\""
            echo "key_file: \"${KEY_FILE}\""
            echo ""
        fi

        echo "listeners:"
        echo "  - addr: \"0.0.0.0:${LISTEN_PORT}\""
        echo "    transport: \"${TRANSPORT}\""

        if [[ -n "$CERT_FILE" && -f "$CERT_FILE" ]]; then
            echo "    cert_file: \"${CERT_FILE}\""
            echo "    key_file: \"${KEY_FILE}\""
        fi

        if [[ -n "$AUTO_MAPPINGS" ]]; then
            echo "    maps:"
            printf '%b' "$AUTO_MAPPINGS" | sed 's/^/    /'
        fi
    } > "$CONFIG_FILE"

    _write_transport_extras "$CONFIG_FILE" "server" "$TRANSPORT"
    write_common_tail "$CONFIG_FILE"

    create_systemd_service "server" "$INSTANCE_NAME"

    if [[ "$TRANSPORT" == "tun" ]]; then
        show_tun_transport_notes "server"
    fi

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "iran" || true

    safe_start_enable "DaggerConnect-${INSTANCE_NAME}"

    echo ""
    divider
    ok "Server '${INSTANCE_NAME}' configured!"
    info "Service:   ${GREEN}DaggerConnect-${INSTANCE_NAME}${NC}"
    info "Port:      ${GREEN}${LISTEN_PORT}${NC}"
    info "Transport: ${GREEN}${TRANSPORT}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-${INSTANCE_NAME} -f"
    divider

    press_enter
    main_menu
}

# ============================================================================
# MULTI-LISTENER SERVER — با نام دلخواه
# ============================================================================

install_server_multilistener() {
    show_banner
    section "Multi-Listener Server Setup"
    echo -e "  ${DIM}Each listener is fully isolated — own sessions, own TUN.${NC}"
    echo ""

    local INSTANCE_NAME
    INSTANCE_NAME=$(_pick_instance_name "server" "server-multi")

    while true; do
        read -rsp "  Global PSK: " GLOBAL_PSK || true; echo ""
        [[ -n "$GLOBAL_PSK" ]] && break; err "PSK cannot be empty!"
    done

    echo ""
    echo -e "  Profile: ${WHITE}1)${NC}balanced  ${WHITE}2)${NC}aggressive  ${WHITE}3)${NC}latency  ${WHITE}4)${NC}cpu-efficient  ${WHITE}5)${NC}gaming"
    read -rp "  Choice [1]: " pc || true
    case $pc in
        2) PROFILE="aggressive";; 3) PROFILE="latency";;
        4) PROFILE="cpu-efficient";; 5) PROFILE="gaming";; *) PROFILE="balanced";;
    esac

    read -rp "  Heartbeat (s) [10]: " HB || true; HB=${HB:-10}
    read -rp "  Verbose? [y/N]: " VB || true
    [[ $VB =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

    GLOBAL_CERT=""; GLOBAL_KEY=""
    read -rp "  Generate global SSL cert? [y/N]: " GC || true
    if [[ $GC =~ ^[Yy]$ ]]; then
        read -rp "  Domain [www.google.com]: " CD || true; CD=${CD:-www.google.com}
        if gen_ssl_cert "$CONFIG_DIR/certs/cert.pem" "$CONFIG_DIR/certs/key.pem" "$CD"; then
            GLOBAL_CERT="$CONFIG_DIR/certs/cert.pem"
            GLOBAL_KEY="$CONFIG_DIR/certs/key.pem"
        else
            warn "Global SSL cert failed — listeners needing TLS will prompt individually."
        fi
    fi

    CONFIG_FILE="$CONFIG_DIR/${INSTANCE_NAME}.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"server\""
        echo "psk: \"${GLOBAL_PSK}\""
        echo "profile: \"${PROFILE}\""
        echo "verbose: ${VERBOSE}"
        echo "heartbeat: ${HB}"
        echo ""
        if [[ -n "$GLOBAL_CERT" && -f "$GLOBAL_CERT" ]]; then
            echo "cert_file: \"${GLOBAL_CERT}\""
            echo "key_file: \"${GLOBAL_KEY}\""
            echo ""
        fi
        echo "listeners:"
    } > "$CONFIG_FILE"

    local LISTENER_COUNT=0
    local HAS_DAGGERMUX=false HAS_RAWMUX=false HAS_TUN=false

    while true; do
        echo ""; echo -e "  ${PURPLE}== Listener #${LISTENER_COUNT} ==${NC}"

        read -rp "  Bind address [0.0.0.0:$((4000+LISTENER_COUNT))]: " L_ADDR || true
        L_ADDR=${L_ADDR:-"0.0.0.0:$((4000+LISTENER_COUNT))"}

        L_TRANSPORT=$(select_transport)

        L_CERT=""; L_KEY=""
        if [[ "$L_TRANSPORT" == "httpsmux" || "$L_TRANSPORT" == "wssmux" ]]; then
            if [[ -n "$GLOBAL_CERT" && -f "$GLOBAL_CERT" ]]; then
                L_CERT="$GLOBAL_CERT"; L_KEY="$GLOBAL_KEY"; ok "Using global SSL cert."
            else
                read -rp "  Generate cert for listener #${LISTENER_COUNT}? [Y/n]: " GLC || true
                if [[ ! $GLC =~ ^[Nn]$ ]]; then
                    read -rp "  Domain [www.google.com]: " LCD || true; LCD=${LCD:-www.google.com}
                    if gen_ssl_cert "$CONFIG_DIR/certs/cert_${LISTENER_COUNT}.pem" \
                                    "$CONFIG_DIR/certs/key_${LISTENER_COUNT}.pem" "$LCD"; then
                        L_CERT="$CONFIG_DIR/certs/cert_${LISTENER_COUNT}.pem"
                        L_KEY="$CONFIG_DIR/certs/key_${LISTENER_COUNT}.pem"
                    else
                        warn "Cert failed for listener #${LISTENER_COUNT} — continuing without TLS."
                    fi
                fi
            fi
        fi

        if [[ "$L_TRANSPORT" == "daggermux" ]]; then
            L_PORT=$(echo "$L_ADDR" | cut -d: -f2)
            if [[ -z "$L_PORT" ]] || ! [[ "$L_PORT" =~ ^[0-9]+$ ]]; then
                err "Could not parse port from address '${L_ADDR}'. Skipping iptables."
            else
                configure_daggermux "server"
                setup_daggermux_iptables "$L_PORT"
            fi
            HAS_DAGGERMUX=true
        fi

        if [[ "$L_TRANSPORT" == "rawmux" ]]; then
            configure_rawmux
            HAS_RAWMUX=true
        fi

        if [[ "$L_TRANSPORT" == "tun" ]]; then
            configure_tun_transport "server"
            local L_PORT_TUN; L_PORT_TUN=$(echo "$L_ADDR" | cut -d: -f2)
            [[ "$L_PORT_TUN" =~ ^[0-9]+$ ]] && _TT_HEALTH_PORT="$L_PORT_TUN" || true
            HAS_TUN=true
        fi

        L_MAPPINGS=""
        _CURRENT_TRANSPORT="$L_TRANSPORT"
        build_port_mappings; L_MAPPINGS="$MAPPINGS"

        read -rp "  Enable per-listener smux TUN? [y/N]: " L_TUN_EN || true
        L_TUN_ENABLED=false
        if [[ $L_TUN_EN =~ ^[Yy]$ ]]; then
            L_TUN_ENABLED=true; configure_tun "$LISTENER_COUNT" "server"
        fi

        {
            echo "  - addr: \"${L_ADDR}\""
            echo "    transport: \"${L_TRANSPORT}\""
            if [[ -n "$L_CERT" && -f "$L_CERT" ]]; then
                echo "    cert_file: \"${L_CERT}\""
                echo "    key_file: \"${L_KEY}\""
            fi
            if [[ -n "$L_MAPPINGS" ]]; then
                echo "    maps:"
                printf '%b' "$L_MAPPINGS" | sed 's/^/    /'
            fi
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
        ok "Listener #$((LISTENER_COUNT-1)): ${L_ADDR} (${L_TRANSPORT}) added."

        read -rp "  Add another listener? [y/N]: " ML || true
        [[ ! $ML =~ ^[Yy]$ ]] && break
    done

    $HAS_DAGGERMUX && write_daggermux_config    "$CONFIG_FILE" "server" || true
    $HAS_RAWMUX    && write_rawmux_config        "$CONFIG_FILE"          || true
    $HAS_TUN       && write_tun_transport_config "$CONFIG_FILE" "server" || true

    write_common_tail "$CONFIG_FILE"
    create_systemd_service "server" "$INSTANCE_NAME"

    if $HAS_TUN; then
        show_tun_transport_notes "server"
    fi

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "iran" || true

    safe_start_enable "DaggerConnect-${INSTANCE_NAME}"

    echo ""; divider
    ok "Multi-Listener Server '${INSTANCE_NAME}' configured!"
    info "Service:   ${GREEN}DaggerConnect-${INSTANCE_NAME}${NC}"
    info "Listeners: ${GREEN}${LISTENER_COUNT}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-${INSTANCE_NAME} -f"
    $HAS_DAGGERMUX && warn "DaggerMux: iptables rules applied." || true
    $HAS_TUN       && warn "TUN transport: tun module loaded (modprobe tun)." || true
    divider; press_enter; main_menu
}

# ============================================================================
# SERVER ENTRY
# ============================================================================

install_server() {
    show_banner
    section "Server Configuration"

    echo -e "  ${WHITE}1)${NC} Automatic      — Single listener ${GREEN}(Recommended)${NC}"
    echo -e "  ${WHITE}2)${NC} Multi-Listener — Multiple isolated listeners"
    echo ""
    read -rp "  Choice [1-2]: " cm || true

    case $cm in
        2) install_server_multilistener ;;
        *) install_server_automatic     ;;
    esac
}

# ============================================================================
# AUTOMATIC CLIENT — با نام دلخواه
# ============================================================================

install_client_automatic() {
    show_banner
    section "Client Setup"

    local INSTANCE_NAME
    INSTANCE_NAME=$(_pick_instance_name "client" "client")

    while true; do
        read -rsp "  PSK (must match server): " PSK || true; echo ""
        [[ -n "$PSK" ]] && break
        err "PSK cannot be empty!"
    done

    TRANSPORT=$(select_transport)

    read -rp "  Server address:port [e.g., 1.2.3.4:2020]: " ADDR || true

    if [[ -z "$ADDR" || "$ADDR" != *:* ]]; then
        err "Address must be in host:port format."
        install_client_automatic
        return
    fi

    if [[ "$TRANSPORT" == "tun" ]]; then
        local SERVER_HOST
        SERVER_HOST=$(echo "$ADDR" | cut -d: -f1)
        local SERVER_PORT; SERVER_PORT=$(echo "$ADDR" | cut -d: -f2)
        configure_tun_transport "client"
        [[ -z "${_TT_DEST_IP:-}" ]] && _TT_DEST_IP="$SERVER_HOST"
        [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && _TT_HEALTH_PORT="$SERVER_PORT" || true
    fi

    if [[ "$TRANSPORT" == "daggermux" ]]; then
        configure_daggermux "client"
    fi

    if [[ "$TRANSPORT" == "rawmux" ]]; then
        configure_rawmux
    fi

    CONFIG_FILE="$CONFIG_DIR/${INSTANCE_NAME}.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"client\""
        echo "psk: \"${PSK}\""
        echo "profile: \"latency\""
        echo "verbose: true"
        echo "heartbeat: 2"
        echo ""
        echo "paths:"
        echo "  - transport: \"${TRANSPORT}\""
        echo "    addr: \"${ADDR}\""
        if [[ "$TRANSPORT" == "tun" ]]; then
            echo "    connection_pool: 1"
        else
            echo "    connection_pool: 3"
            echo "    aggressive_pool: true"
        fi
        echo "    retry_interval: 1"
        echo "    dial_timeout: 5"
    } > "$CONFIG_FILE"

    _write_transport_extras "$CONFIG_FILE" "client" "$TRANSPORT"
    write_common_tail "$CONFIG_FILE"

    create_systemd_service "client" "$INSTANCE_NAME"

    if [[ "$TRANSPORT" == "tun" ]]; then
        show_tun_transport_notes "client"
    fi

    safe_start_enable "DaggerConnect-${INSTANCE_NAME}"

    echo ""
    divider
    ok "Client '${INSTANCE_NAME}' configured!"
    info "Service:   ${GREEN}DaggerConnect-${INSTANCE_NAME}${NC}"
    info "Server:    ${GREEN}${ADDR}${NC}"
    info "Transport: ${GREEN}${TRANSPORT}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-${INSTANCE_NAME} -f"
    divider

    press_enter
    main_menu
}

# ============================================================================
# MULTI-PATH CLIENT — با نام دلخواه
# ============================================================================

install_client_multipaths() {
    show_banner
    section "Multi-Path Client Setup"
    echo -e "  ${DIM}Each path can have its own PSK and transport.${NC}"
    echo ""

    local INSTANCE_NAME
    INSTANCE_NAME=$(_pick_instance_name "client" "client-multi")

    while true; do
        read -rsp "  Global PSK: " GLOBAL_PSK || true; echo ""
        [[ -n "$GLOBAL_PSK" ]] && break; err "PSK cannot be empty!"
    done

    echo ""
    echo -e "  Profile: ${WHITE}1)${NC}balanced  ${WHITE}2)${NC}aggressive  ${WHITE}3)${NC}latency  ${WHITE}4)${NC}cpu-efficient  ${WHITE}5)${NC}gaming"
    read -rp "  Choice [1]: " pc || true
    case $pc in
        2) PROFILE="aggressive";; 3) PROFILE="latency";;
        4) PROFILE="cpu-efficient";; 5) PROFILE="gaming";; *) PROFILE="balanced";;
    esac

    read -rp "  Heartbeat (s) [10]: " HB || true; HB=${HB:-10}
    read -rp "  Verbose? [y/N]: " VB || true
    [[ $VB =~ ^[Yy]$ ]] && VERBOSE="true" || VERBOSE="false"

    read -rp "  Enable obfuscation? [Y/n]: " OBE || true
    local OBFUS_ENABLED OP1 OP2
    if [[ ! $OBE =~ ^[Nn]$ ]]; then
        OBFUS_ENABLED="true"
        read -rp "  Min padding [16]:  " OP1 || true; OP1=${OP1:-16}
        read -rp "  Max padding [512]: " OP2 || true; OP2=${OP2:-512}
    else
        OBFUS_ENABLED="false"; OP1=16; OP2=512
    fi

    CONFIG_FILE="$CONFIG_DIR/${INSTANCE_NAME}.yaml"
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

    local PATH_COUNT=0
    local HAS_DAGGERMUX=false HAS_RAWMUX=false HAS_TUN=false

    while true; do
        echo ""; echo -e "  ${PURPLE}== Path #${PATH_COUNT} ==${NC}"

        P_TRANSPORT=$(select_transport)

        read -rp "  Server address:port: " P_ADDR || true
        [[ -z "$P_ADDR" ]] && err "Cannot be empty!" && continue

        if [[ "$P_ADDR" != *:* ]]; then
            err "Address must be in host:port format."; continue
        fi

        read -rsp "  Custom PSK? [blank = use global]: " P_PSK_RAW || true; echo ""
        P_PSK=""
        [[ -n "$P_PSK_RAW" ]] && P_PSK="$P_PSK_RAW" && ok "Custom PSK will be used." || true

        if [[ "$P_TRANSPORT" == "tun" ]]; then
            P_POOL=1
            P_AGG_VAL="false"
        else
            read -rp "  Connection pool  [2]:  " P_POOL || true;  P_POOL=${P_POOL:-2}
            read -rp "  Aggressive pool? [y/N]: " P_AGG || true
            [[ $P_AGG =~ ^[Yy]$ ]] && P_AGG_VAL="true" || P_AGG_VAL="false"
        fi
        read -rp "  Retry interval (s) [3]:  " P_RETRY || true; P_RETRY=${P_RETRY:-3}
        read -rp "  Dial timeout   (s) [10]: " P_DIAL || true;  P_DIAL=${P_DIAL:-10}

        if [[ "$P_TRANSPORT" == "tun" ]]; then
            local P_HOST; P_HOST=$(echo "$P_ADDR" | cut -d: -f1)
            local P_PORT_TUN; P_PORT_TUN=$(echo "$P_ADDR" | cut -d: -f2)
            configure_tun_transport "client"
            [[ -z "${_TT_DEST_IP:-}" ]] && _TT_DEST_IP="$P_HOST"
            [[ "$P_PORT_TUN" =~ ^[0-9]+$ ]] && _TT_HEALTH_PORT="$P_PORT_TUN" || true
            HAS_TUN=true
        fi
        if [[ "$P_TRANSPORT" == "daggermux" ]]; then configure_daggermux "client"; HAS_DAGGERMUX=true; fi
        if [[ "$P_TRANSPORT" == "rawmux"    ]]; then configure_rawmux;             HAS_RAWMUX=true;    fi

        read -rp "  Enable per-path smux TUN? [y/N]: " P_TUN_EN || true
        P_TUN_ENABLED=false
        if [[ $P_TUN_EN =~ ^[Yy]$ ]]; then
            P_TUN_ENABLED=true; configure_tun "$PATH_COUNT" "client"
        fi

        {
            echo "  - transport: \"${P_TRANSPORT}\""
            echo "    addr: \"${P_ADDR}\""
            if [[ -n "$P_PSK" ]]; then
                echo "    psk: \"${P_PSK}\""
            fi
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
        ok "Path #$((PATH_COUNT-1)): ${P_TRANSPORT} -> ${P_ADDR} added."

        read -rp "  Add another path? [y/N]: " MP || true
        [[ ! $MP =~ ^[Yy]$ ]] && break
    done

    $HAS_DAGGERMUX && write_daggermux_config    "$CONFIG_FILE" "client" || true
    $HAS_RAWMUX    && write_rawmux_config        "$CONFIG_FILE"          || true
    $HAS_TUN       && write_tun_transport_config "$CONFIG_FILE" "client" || true

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

    create_systemd_service "client" "$INSTANCE_NAME"

    if $HAS_TUN; then
        show_tun_transport_notes "client"
    fi

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "foreign" || true

    safe_start_enable "DaggerConnect-${INSTANCE_NAME}"

    echo ""; divider
    ok "Multi-Path Client '${INSTANCE_NAME}' configured!"
    info "Service: ${GREEN}DaggerConnect-${INSTANCE_NAME}${NC}"
    info "Paths:   ${GREEN}${PATH_COUNT}${NC}"
    info "Config:  ${CONFIG_FILE}"
    info "Logs:    journalctl -u DaggerConnect-${INSTANCE_NAME} -f"
    $HAS_DAGGERMUX && warn "DaggerMux: ensure server has iptables rules applied." || true
    $HAS_TUN       && warn "TUN transport: tun module loaded (modprobe tun)."     || true
    divider; press_enter; main_menu
}

# ============================================================================
# CLIENT ENTRY
# ============================================================================

install_client() {
    show_banner
    section "Client Configuration"

    echo -e "  ${WHITE}1)${NC} Automatic  — Single path ${GREEN}(Recommended)${NC}"
    echo -e "  ${WHITE}2)${NC} Multi-Path — Multiple paths with per-PSK"
    echo ""
    read -rp "  Choice [1-2]: " cm || true

    case $cm in
        2) install_client_multipaths ;;
        *) install_client_automatic  ;;
    esac
}

# ============================================================================
# UPDATE
# ============================================================================

update_binary() {
    show_banner
    section "Update Core Binary"

    local CURRENT_VERSION; CURRENT_VERSION=$(get_current_version)
    if [[ "$CURRENT_VERSION" == "not-installed" ]]; then
        err "DaggerConnect is not installed yet."; press_enter; main_menu; return
    fi

    info "Current version: ${GREEN}${CURRENT_VERSION}${NC}"
    info "Checking latest version..."

    local LATEST_VERSION
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$LATEST_VERSION" ]]; then
        warn "Could not reach GitHub API. Proceeding anyway."
        LATEST_VERSION="unknown"
    else
        info "Latest version:  ${GREEN}${LATEST_VERSION}${NC}"
    fi

    if [[ "$LATEST_VERSION" != "unknown" && "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        ok "Already on the latest version (${CURRENT_VERSION}). Nothing to do."
        read -rp "  Force re-download anyway? [y/N]: " force || true
        [[ ! $force =~ ^[Yy]$ ]] && press_enter && main_menu && return
    fi

    read -rp "  Continue with update? [y/N]: " c || true
    [[ ! $c =~ ^[Yy]$ ]] && main_menu && return

    # توقف همه سرویس‌های فعال
    while IFS= read -r inst; do
        systemctl stop "DaggerConnect-${inst}" 2>/dev/null || true
    done < <(_list_all_instances)
    sleep 1

    download_binary
    local NEW_VERSION; NEW_VERSION=$(get_current_version)
    ok "Updated: ${YELLOW}${CURRENT_VERSION}${NC} -> ${GREEN}${NEW_VERSION}${NC}"

    local HAS_ENABLED=false
    while IFS= read -r inst; do
        systemctl is-enabled "DaggerConnect-${inst}" &>/dev/null && HAS_ENABLED=true && break
    done < <(_list_all_instances)

    if $HAS_ENABLED; then
        read -rp "  Restart all services? [Y/n]: " r || true
        if [[ ! $r =~ ^[Nn]$ ]]; then
            while IFS= read -r inst; do
                if systemctl is-enabled "DaggerConnect-${inst}" &>/dev/null 2>/dev/null; then
                    systemctl start "DaggerConnect-${inst}" && ok "Restarted: ${inst}" || true
                fi
            done < <(_list_all_instances)
        fi
    fi
    press_enter; main_menu
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

service_management() {
    local SERVICE_NAME
    SERVICE_NAME=$(echo "$1" | tr -d '\r\n')

    local NAME="${SERVICE_NAME#DaggerConnect-}"
    local CONFIG_FILE="$CONFIG_DIR/${NAME}.yaml"

    while true; do
        show_banner
        section "Manage — ${CYAN}DaggerConnect-${NAME}${NC}"

        # نمایش نوع (server/client) از config
        if [[ -f "$CONFIG_FILE" ]]; then
            local INST_MODE
            INST_MODE=$(grep '^mode:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"')
            [[ -n "$INST_MODE" ]] && info "Type: ${WHITE}${INST_MODE}${NC}" || true
        fi

        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "  Status:     ${GREEN}● RUNNING${NC}"
        else
            echo -e "  Status:     ${RED}● STOPPED${NC}"
        fi

        echo ""; divider
        echo -e "  ${WHITE}1)${NC} Start        ${WHITE}2)${NC} Stop         ${WHITE}3)${NC} Restart"
        echo -e "  ${WHITE}4)${NC} Status       ${WHITE}5)${NC} Live Logs"
        echo -e "  ${WHITE}6)${NC} View Config  ${WHITE}7)${NC} Delete"
        echo -e "  ${WHITE}0)${NC} Back"
        divider
        echo ""

        read -rp "  Select: " choice || true

        case $choice in
            1) systemctl start   "$SERVICE_NAME" 2>/dev/null || true; sleep 1 ;;
            2) systemctl stop    "$SERVICE_NAME" 2>/dev/null || true; sleep 1 ;;
            3) systemctl restart "$SERVICE_NAME" 2>/dev/null || true; sleep 1 ;;
            4) systemctl status  "$SERVICE_NAME" --no-pager || true; press_enter ;;
            5) journalctl -u "$SERVICE_NAME" -f || true ;;
            6)
                if [[ -f "$CONFIG_FILE" ]]; then cat "$CONFIG_FILE"
                else err "Config not found."; fi
                press_enter ;;
            7)
                read -rp "  Delete '${NAME}'? [y/N]: " c || true
                if [[ $c =~ ^[Yy]$ ]]; then
                    systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
                    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
                    rm -f "$CONFIG_FILE"
                    rm -f "$SYSTEMD_DIR/${SERVICE_NAME}.service"
                    systemctl daemon-reload 2>/dev/null || true
                    ok "Instance '${NAME}' deleted."
                    press_enter
                    return
                fi ;;
            0) return ;;
        esac
    done
}

# ============================================================================
# SETTINGS MENU — همه instances نامحدود
# ============================================================================

settings_menu() {
    show_banner
    section "Manage DaggerConnect Instances"

    # جمع‌آوری همه سرویس‌ها
    local INSTANCES=()
    while IFS= read -r inst; do
        [[ -n "$inst" ]] && INSTANCES+=("$inst")
    done < <(_list_all_instances)

    if [[ ${#INSTANCES[@]} -eq 0 ]]; then
        err "No DaggerConnect instances found."
        info "Create a server or client first."
        press_enter
        main_menu
        return
    fi

    echo ""
    echo -e "  ${DIM}Total instances: ${#INSTANCES[@]}${NC}"
    echo ""

    local i=1
    for inst in "${INSTANCES[@]}"; do
        local STATUS_ICON STATUS_COLOR
        local CFG="$CONFIG_DIR/${inst}.yaml"
        local INST_MODE=""

        if systemctl is-active --quiet "DaggerConnect-${inst}" 2>/dev/null; then
            STATUS_ICON="●"; STATUS_COLOR="$GREEN"
        else
            STATUS_ICON="○"; STATUS_COLOR="$RED"
        fi

        # خواندن mode از config
        if [[ -f "$CFG" ]]; then
            INST_MODE=$(grep '^mode:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
        fi

        printf "  ${WHITE}%2d)${NC} ${STATUS_COLOR}%s${NC} %-28s ${DIM}%s${NC}\n" \
            "$i" "$STATUS_ICON" "DaggerConnect-${inst}" "${INST_MODE:-unknown}"
        ((i++))
    done

    echo ""
    echo -e "  ${WHITE} 0)${NC} Back"
    divider
    echo ""

    read -rp "  Select instance: " choice || true

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if (( choice == 0 )); then
            main_menu
            return
        fi
        if (( choice >= 1 && choice <= ${#INSTANCES[@]} )); then
            service_management "DaggerConnect-${INSTANCES[$((choice-1))]}"
            settings_menu
            return
        fi
    fi

    settings_menu
}

# ============================================================================
# UNINSTALL — همه instances
# ============================================================================

uninstall_daggerconnect() {
    show_banner
    section "Uninstall DaggerConnect"
    warn "This will remove: binary, ALL configs, ALL services, certs, and optimizations."
    echo ""

    local INSTANCES=()
    while IFS= read -r inst; do
        [[ -n "$inst" ]] && INSTANCES+=("$inst")
    done < <(_list_all_instances)

    if [[ ${#INSTANCES[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}Instances to be removed:${NC}"
        for inst in "${INSTANCES[@]}"; do
            echo -e "    ${DIM}• DaggerConnect-${inst}${NC}"
        done
        echo ""
    fi

    read -rp "  Are you sure? [y/N]: " c || true
    [[ ! $c =~ ^[Yy]$ ]] && main_menu && return

    # حذف همه سرویس‌ها
    for inst in "${INSTANCES[@]}"; do
        systemctl stop    "DaggerConnect-${inst}" 2>/dev/null || true
        systemctl disable "DaggerConnect-${inst}" 2>/dev/null || true
        rm -f "$SYSTEMD_DIR/DaggerConnect-${inst}.service"
        ok "Removed service: DaggerConnect-${inst}"
    done

    rm -f "$INSTALL_DIR/DaggerConnect"
    rm -rf "$CONFIG_DIR"
    rm -f /etc/sysctl.d/99-daggerconnect.conf
    rm -f /etc/network/if-pre-up.d/daggermux-iptables

    section "Cleaning iptables rules"
    if command -v iptables &>/dev/null; then
        while IFS= read -r rule; do
            [[ -n "$rule" ]] && iptables -t raw $rule 2>/dev/null || true
        done < <(iptables -t raw -S 2>/dev/null | grep -E 'NOTRACK' | sed 's/^-A/-D/' || true)

        while IFS= read -r rule; do
            [[ -n "$rule" ]] && iptables -t mangle $rule 2>/dev/null || true
        done < <(iptables -t mangle -S 2>/dev/null | grep -E 'RST.*DROP' | sed 's/^-A/-D/' || true)

        ok "iptables rules cleaned."
        if command -v iptables-save &>/dev/null && [[ -f /etc/iptables/rules.v4 ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null && ok "iptables ruleset saved." || true
        fi
    fi

    sysctl -p > /dev/null 2>&1 || true
    systemctl daemon-reload 2>/dev/null || true

    ok "DaggerConnect uninstalled successfully."
    exit 0
}

# ============================================================================
# STATUS DASHBOARD — همه instances
# ============================================================================

show_status_dashboard() {
    show_banner
    section "System Status Dashboard"

    if [[ -f "$INSTALL_DIR/DaggerConnect" ]]; then
        local VER; VER=$(get_current_version)
        echo -e "  ${WHITE}Binary:${NC}    ${GREEN}Installed${NC} (${VER})"
    else
        echo -e "  ${WHITE}Binary:${NC}    ${RED}Not installed${NC}"
    fi

    echo ""
    divider

    # نمایش همه instances
    local INSTANCES=()
    while IFS= read -r inst; do
        [[ -n "$inst" ]] && INSTANCES+=("$inst")
    done < <(_list_all_instances)

    if [[ ${#INSTANCES[@]} -eq 0 ]]; then
        echo ""
        warn "No instances configured yet."
    else
        for inst in "${INSTANCES[@]}"; do
            local SVC="DaggerConnect-${inst}"
            local CFG="$CONFIG_DIR/${inst}.yaml"

            echo ""
            echo -e "  ${WHITE}── ${CYAN}${inst}${NC} ──"

            if systemctl is-active --quiet "$SVC" 2>/dev/null; then
                echo -e "  Status:     ${GREEN}● RUNNING${NC}"
                local UPTIME
                UPTIME=$(systemctl show "$SVC" --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
                [[ -n "$UPTIME" ]] && echo -e "  Started:    ${DIM}${UPTIME}${NC}" || true
                local MEM
                MEM=$(systemctl show "$SVC" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)
                if [[ -n "$MEM" && "$MEM" != "18446744073709551615" && "$MEM" != "[not set]" ]]; then
                    MEM=$((MEM / 1024 / 1024))
                    echo -e "  Memory:     ${DIM}${MEM} MB${NC}"
                fi
            elif systemctl is-enabled "$SVC" &>/dev/null 2>/dev/null; then
                echo -e "  Status:     ${RED}● STOPPED${NC} ${YELLOW}(enabled but not running)${NC}"
            else
                echo -e "  Status:     ${DIM}○ Not enabled${NC}"
            fi

            if [[ -f "$CFG" ]]; then
                local INST_MODE TRANSPORT PORT_COUNT LISTEN_PORT
                INST_MODE=$(grep '^mode:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
                TRANSPORT=$(grep 'transport:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
                PORT_COUNT=$(grep -c 'type:' "$CFG" 2>/dev/null || echo 0)
                LISTEN_PORT=$(grep 'addr:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"' | cut -d: -f2)

                [[ -n "$INST_MODE"    ]] && echo -e "  Mode:       ${DIM}${INST_MODE}${NC}"      || true
                [[ -n "$TRANSPORT"    ]] && echo -e "  Transport:  ${DIM}${TRANSPORT}${NC}"      || true
                [[ -n "$LISTEN_PORT"  ]] && echo -e "  Port:       ${DIM}${LISTEN_PORT}${NC}"    || true
                [[ "$PORT_COUNT" -gt 0 ]] && echo -e "  Mappings:   ${DIM}${PORT_COUNT}${NC}"   || true

                if grep -q 'tun_transport:' "$CFG" 2>/dev/null; then
                    local TT_DEV TT_PROF
                    TT_DEV=$(grep 'device_name:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
                    TT_PROF=$(grep 'profile:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
                    [[ -n "$TT_DEV" ]] && echo -e "  TUN:        ${DIM}dev=${TT_DEV} profile=${TT_PROF}${NC}" || true
                    if [[ -n "$TT_DEV" ]] && ip link show "$TT_DEV" &>/dev/null 2>/dev/null; then
                        echo -e "  TUN State:  ${GREEN}● UP${NC}"
                    fi
                fi
            fi
        done
    fi

    echo ""; divider

    echo ""
    echo -e "  ${WHITE}-- Network --${NC}"
    local IFACE
    IFACE=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    if [[ -n "$IFACE" ]]; then
        local RX TX
        RX=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
        TX=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)
        RX=$((RX / 1024 / 1024)); TX=$((TX / 1024 / 1024))
        echo -e "  Interface:  ${DIM}${IFACE}${NC}"
        echo -e "  RX / TX:    ${DIM}${RX} MB / ${TX} MB${NC}"
    fi

    local CONNS
    CONNS=$(ss -tn 2>/dev/null | grep -c ESTAB || echo 0)
    echo -e "  Connections:${DIM} ${CONNS} established${NC}"

    local CCN
    CCN=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo -e "  TCP CC:     ${DIM}${CCN}${NC}"

    echo ""; divider
    press_enter; main_menu
}

# ============================================================================
# FIRST RUN
# ============================================================================

first_run_check() {
    [[ -f "$FIRST_RUN_FLAG" ]] && return

    show_banner
    section "Initial Setup"

    echo -e "  ${WHITE}Download DaggerConnect core from GitHub?${NC}"
    echo -e "  ${DIM}(Default: Yes)${NC}"
    echo ""

    read -rp "  Proceed with download? [Y/n]: " ans || true

    if [[ $ans =~ ^[Nn]$ ]]; then
        mkdir -p "$CONFIG_DIR"
        touch "$FIRST_RUN_FLAG"
        return
    fi

    install_dependencies
    download_binary

    mkdir -p "$CONFIG_DIR"
    touch "$FIRST_RUN_FLAG"

    press_enter
}

# ============================================================================
# MAIN MENU
# ============================================================================

main_menu() {
    show_banner

    local CURRENT_VER
    CURRENT_VER=$(get_current_version)

    [[ "$CURRENT_VER" != "not-installed" ]] && \
        echo -e "  Version: ${GREEN}${CURRENT_VER}${NC}" && echo "" || true

    # نمایش تعداد و وضعیت همه instances
    local RUNNING_COUNT=0 TOTAL_COUNT=0
    while IFS= read -r inst; do
        [[ -z "$inst" ]] && continue
        TOTAL_COUNT=$((TOTAL_COUNT+1))
        systemctl is-active --quiet "DaggerConnect-${inst}" 2>/dev/null && \
            RUNNING_COUNT=$((RUNNING_COUNT+1)) || true
    done < <(_list_all_instances)

    if [[ "$TOTAL_COUNT" -gt 0 ]]; then
        echo -e "  Instances: ${GREEN}${RUNNING_COUNT} running${NC} / ${WHITE}${TOTAL_COUNT} total${NC}"
        echo ""
    fi

    divider
    echo -e "  ${WHITE}1)${NC} Install / Configure Server"
    echo -e "  ${WHITE}2)${NC} Install / Configure Client"
    echo -e "  ${WHITE}3)${NC} Settings — Manage All Instances"
    echo -e "  ${WHITE}4)${NC} System Optimizer"
    echo -e "  ${WHITE}5)${NC} Status Dashboard"
    echo -e "  ${WHITE}6)${NC} Update Core"
    echo -e "  ${WHITE}7)${NC} Uninstall DaggerConnect"
    echo -e "  ${WHITE}0)${NC} Exit"
    divider; echo ""

    read -rp "  Select option: " choice || true

    case $choice in
        1) install_server          ;;
        2) install_client          ;;
        3) settings_menu           ;;
        4) system_optimizer_menu   ;;
        5) show_status_dashboard   ;;
        6) update_binary           ;;
        7) uninstall_daggerconnect ;;
        0) echo -e "${GREEN}  Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid option."; sleep 1; main_menu ;;
    esac
}

# ============================================================================
# ENTRY POINT
# ============================================================================
check_root
first_run_check
main_menu
