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

# ── Global state vars (init to avoid unbound errors with set -u) ─────────────
_TUN_NAME=""; _TUN_LOCAL=""; _TUN_PEER=""; _TUN_MTU="1400"
_RM_HS_TIMEOUT="10"; _RM_KEEPALIVE="15"; _RM_RBUF="4194304"
_RM_WBUF="4194304"; _RM_USE_PCAP="false"
_DM_IFACE=""; _DM_LOCAL_IP=""; _DM_ROUTER_MAC=""
_DM_MTU="1350"; _DM_SND_WND="1024"; _DM_RCV_WND="1024"
_DM_DATA_SHARD="10"; _DM_PARITY_SHARD="1"
_DM_LOCAL_FLAGS="PA,A"; _DM_REMOTE_FLAGS="PA,A"
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
    if command -v apt &>/dev/null; then
        apt-get update -qq
        apt-get install -y wget curl tar git openssl iproute2 libpcap-dev > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y wget curl tar git openssl iproute libpcap-devel > /dev/null 2>&1
        # BUG FIX #1: iproute2 is named "iproute" on RHEL/CentOS — was causing install failure
    else
        err "Unsupported package manager."; exit 1
    fi
    ok "Dependencies installed."
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

    local LATEST_VERSION
    LATEST_VERSION=$(curl -s "$LATEST_RELEASE_API" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$LATEST_VERSION" ]] && warn "Could not fetch latest version — using v1.3.5" && LATEST_VERSION="v1.3.5"

    local BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
    info "Latest version: ${GREEN}${LATEST_VERSION}${NC}"

    [[ -f "$INSTALL_DIR/DaggerConnect" ]] && mv "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.backup"

    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        rm -f "$INSTALL_DIR/DaggerConnect.backup"
        ok "Binary downloaded successfully."
    else
        err "Download failed."
        if [[ -f "$INSTALL_DIR/DaggerConnect.backup" ]]; then
            mv "$INSTALL_DIR/DaggerConnect.backup" "$INSTALL_DIR/DaggerConnect"
            warn "Restored previous version."
        fi
        exit 1
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

    sysctl -w net.core.rmem_max=8388608               > /dev/null 2>&1
    sysctl -w net.core.wmem_max=8388608               > /dev/null 2>&1
    sysctl -w net.core.rmem_default=131072            > /dev/null 2>&1
    sysctl -w net.core.wmem_default=131072            > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 65536 8388608"  > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 8388608"  > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_window_scaling=1           > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1               > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1                     > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_retries2=6                 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_syn_retries=2              > /dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=1000         > /dev/null 2>&1
    sysctl -w net.core.somaxconn=512                  > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_fastopen=3                 > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_low_latency=1              > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0    > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_no_metrics_save=1          > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_autocorking=0              > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1              > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_time=120         > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10         > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_probes=3         > /dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15             > /dev/null 2>&1
    sysctl -w net.ipv4.ip_forward=1                   > /dev/null 2>&1

    if modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr > /dev/null 2>&1
        sysctl -w net.core.default_qdisc=fq_codel     > /dev/null 2>&1
        ok "BBR congestion control enabled."
    else
        warn "BBR not available — using CUBIC."
    fi

    tc qdisc del dev "$INTERFACE" root 2>/dev/null || true
    if tc qdisc add dev "$INTERFACE" root fq_codel limit 500 target 3ms interval 50ms quantum 300 ecn 2>/dev/null; then
        ok "fq_codel qdisc configured."
    else
        warn "qdisc configuration skipped."
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
    echo -e "  ${WHITE}8)${NC} daggermux — ${PURPLE}Raw TCP/KCP via pcap${NC} (root + libpcap required)" >&2
    divider >&2
    echo "" >&2
    # BUG FIX #2: removed >&2 from read — read always reads from stdin (tty),
    # redirecting it to stderr caused "read: -p: invalid option" on some shells
    read -rp "  Choice [1-8]: " trans_choice || true
    case $trans_choice in
        1) echo "httpsmux"  ;;
        2) echo "httpmux"   ;;
        3) echo "wssmux"    ;;
        4) echo "wsmux"     ;;
        5) echo "kcpmux"    ;;
        6) echo "tcpmux"    ;;
        7) echo "rawmux"    ;;
        8) echo "daggermux" ;;
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
    # BUG FIX #3: IFS=',' with read -ra inside a function was not resetting IFS,
    # causing flag parsing to break. Save/restore IFS explicitly.
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
        [[ -n "$_DM_IFACE" ]]    && echo "  interface: \"${_DM_IFACE}\""
        [[ -n "$_DM_LOCAL_IP" ]] && echo "  local_ip: \"${_DM_LOCAL_IP}\""
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
        iptables-save > /etc/iptables/rules.v4 2>/dev/null && ok "Rules saved to /etc/iptables/rules.v4"
    fi

    # BUG FIX #4: heredoc with variable inside was not quoting PORT correctly —
    # using printf to write the file ensures $PORT is expanded at write time, not later
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
# HELPER: CONFIGURE TUN
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
# HELPER: BUILD PORT MAPPINGS
# ============================================================================

build_port_mappings() {
    local BIND_IP="0.0.0.0"
    local TARGET_IP="127.0.0.1"
    MAPPINGS=""
    local COUNT=0

    section "Port Mappings"
    echo -e "  ${DIM}Formats: 8080 | 1000/2000 | 5000=8080 | 1000/1010=2000/2010 | 5000=1.2.3.4:8080${NC}"
    echo ""

    while true; do
        echo ""
        echo -e "  ${YELLOW}── Mapping #$((COUNT+1)) ──${NC}"
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

        # BUG FIX #5: _add_mapping was declared as a nested function inside a while
        # loop — bash does not support nested functions reliably with local scope.
        # Moved the logic inline and made it a proper top-level helper.
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

        # Range with custom IP: 5000/5010=1.2.3.4:8000/8010
        if [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)/([0-9]+)$ ]]; then
            local BS="${BASH_REMATCH[1]}" BE="${BASH_REMATCH[2]}"
            local CTIP="${BASH_REMATCH[3]}" TS="${BASH_REMATCH[4]}" TE="${BASH_REMATCH[5]}"
            local BR=$((BE-BS+1)) TR=$((TE-TS+1))
            [[ "$BR" -ne "$TR" ]] && err "Range size mismatch!" && continue
            for ((i=0; i<BR; i++)); do _do_add_mapping $((BS+i)) "${CTIP}:$((TS+i))"; done
            ok "Added: ${BS}-${BE} → ${CTIP}:${TS}-${TE} (${PROTO})"

        # Range mapping: 1000/1010=2000/2010
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)=([0-9]+)/([0-9]+)$ ]]; then
            local BS="${BASH_REMATCH[1]}" BE="${BASH_REMATCH[2]}"
            local TS="${BASH_REMATCH[3]}" TE="${BASH_REMATCH[4]}"
            local BR=$((BE-BS+1)) TR=$((TE-TS+1))
            [[ "$BR" -ne "$TR" ]] && err "Range size mismatch!" && continue
            for ((i=0; i<BR; i++)); do _do_add_mapping $((BS+i)) "${TARGET_IP}:$((TS+i))"; done
            ok "Added: ${BS}-${BE} → ${TS}-${TE} (${BR} ports, ${PROTO})"

        # Range: 1000/2000
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)/([0-9]+)$ ]]; then
            local SP="${BASH_REMATCH[1]}" EP="${BASH_REMATCH[2]}"
            [[ "$SP" -gt "$EP" ]] && err "Start > end!" && continue
            local RS=$((EP-SP+1))
            if [[ "$RS" -gt 1000 ]]; then
                read -rp "  Large range (${RS} ports). Continue? [y/N]: " cr || true
                [[ ! $cr =~ ^[Yy]$ ]] && continue
            fi
            for ((port=SP; port<=EP; port++)); do _do_add_mapping "$port" "${TARGET_IP}:${port}"; done
            ok "Added: ${SP}-${EP} (${RS} ports, ${PROTO})"

        # Custom with IP: 5000=1.2.3.4:8080
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):([0-9]+)$ ]]; then
            _do_add_mapping "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
            ok "Added: ${BASH_REMATCH[1]} → ${BASH_REMATCH[2]}:${BASH_REMATCH[3]} (${PROTO})"

        # Custom: 5000=8080
        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            _do_add_mapping "${BASH_REMATCH[1]}" "${TARGET_IP}:${BASH_REMATCH[2]}"
            ok "Added: ${BASH_REMATCH[1]} → ${BASH_REMATCH[2]} (${PROTO})"

        # Single port: 8080
        elif [[ "$PORT_INPUT" =~ ^[0-9]+$ ]]; then
            [[ "$PORT_INPUT" -lt 1 || "$PORT_INPUT" -gt 65535 ]] && err "Invalid port!" && continue
            _do_add_mapping "$PORT_INPUT" "${TARGET_IP}:${PORT_INPUT}"
            ok "Added: ${PORT_INPUT} → ${PORT_INPUT} (${PROTO})"

        else
            err "Invalid format!"; continue
        fi

        read -rp "  Add another mapping? [y/N]: " am || true
        [[ ! "$am" =~ ^[Yy]$ ]] && break
    done

    if [[ "$COUNT" -eq 0 ]]; then
        warn "No mappings defined — using default 8080→8080."
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
    local CERT_OUT=$1; local KEY_OUT=$2; local DOMAIN=$3
    mkdir -p "$(dirname "$CERT_OUT")"
    if openssl req -x509 -newkey rsa:4096 -keyout "$KEY_OUT" -out "$CERT_OUT" \
        -days 365 -nodes -subj "/C=US/O=MyCompany/CN=${DOMAIN}" 2>/dev/null; then
        ok "SSL certificate generated."
    else
        err "SSL certificate generation failed."
    fi
}

# ============================================================================
# SYSTEMD SERVICE
# ============================================================================

create_systemd_service() {
    local MODE=$1
    # BUG FIX #6: ${MODE^} (capitalize first letter) is bash 4.0+.
    # On older systems this silently outputs empty string — use explicit logic.
    local MODE_CAP
    MODE_CAP="$(echo "${MODE:0:1}" | tr '[:lower:]' '[:upper:]')${MODE:1}"

    cat > "$SYSTEMD_DIR/DaggerConnect-${MODE}.service" << EOF
[Unit]
Description=DaggerConnect Reverse Tunnel — ${MODE_CAP}
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
    ok "Systemd service created: DaggerConnect-${MODE}"
}

# ============================================================================
# _write_transport_extras — writes rawmux/daggermux blocks if needed
# ============================================================================

_write_transport_extras() {
    local FILE=$1
    local SIDE=$2
    local TRANSPORT=$3
    [[ "$TRANSPORT" == "daggermux" ]] && write_daggermux_config "$FILE" "$SIDE"
    [[ "$TRANSPORT" == "rawmux"    ]] && write_rawmux_config    "$FILE"
}

# ============================================================================
# AUTOMATIC SERVER
# ============================================================================

install_server_automatic() {
    show_banner
    section "Automatic Server Setup"

    read -rp "  Tunnel port [2020]: " LISTEN_PORT || true; LISTEN_PORT=${LISTEN_PORT:-2020}

    if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [[ "$LISTEN_PORT" -lt 1 || "$LISTEN_PORT" -gt 65535 ]]; then
        err "Invalid port number. Using default 2020."
        LISTEN_PORT=2020
    fi
    if ! check_port_available "$LISTEN_PORT"; then
        read -rp "  Port ${LISTEN_PORT} is busy. Use it anyway? [y/N]: " frc || true
        [[ ! $frc =~ ^[Yy]$ ]] && install_server_automatic && return
    fi

    while true; do
        read -rsp "  PSK: " PSK || true; echo ""
        [[ -n "$PSK" ]] && break; err "PSK cannot be empty!"
    done

    TRANSPORT=$(select_transport)

    build_port_mappings
    AUTO_MAPPINGS="$MAPPINGS"

    CERT_FILE=""; KEY_FILE=""
    if [[ "$TRANSPORT" == "httpsmux" || "$TRANSPORT" == "wssmux" ]]; then
        read -rp "  Domain for SSL cert [www.google.com]: " CD || true; CD=${CD:-www.google.com}
        gen_ssl_cert "$CONFIG_DIR/certs/cert.pem" "$CONFIG_DIR/certs/key.pem" "$CD"
        CERT_FILE="$CONFIG_DIR/certs/cert.pem"; KEY_FILE="$CONFIG_DIR/certs/key.pem"
    fi

    [[ "$TRANSPORT" == "daggermux" ]] && configure_daggermux "server" && setup_daggermux_iptables "$LISTEN_PORT"
    [[ "$TRANSPORT" == "rawmux"    ]] && configure_rawmux

    CONFIG_FILE="$CONFIG_DIR/server.yaml"
    mkdir -p "$CONFIG_DIR"

    {
        echo "mode: \"server\""
        echo "psk: \"${PSK}\""
        echo "profile: \"latency\""
        echo "verbose: true"
        echo "heartbeat: 2"
        echo ""
        if [[ -n "$CERT_FILE" ]]; then
            echo "cert_file: \"${CERT_FILE}\""
            echo "key_file: \"${KEY_FILE}\""
            echo ""
        fi
        echo "listeners:"
        echo "  - addr: \"0.0.0.0:${LISTEN_PORT}\""
        echo "    transport: \"${TRANSPORT}\""
        if [[ -n "$CERT_FILE" ]]; then
            echo "    cert_file: \"${CERT_FILE}\""
            echo "    key_file: \"${KEY_FILE}\""
        fi
        echo "    maps:"
        printf '%b' "$AUTO_MAPPINGS" | sed 's/^/    /'
    } > "$CONFIG_FILE"
    # BUG FIX #8: Original code used chained && inside the {} block for cert lines.
    # When CERT_FILE was empty, the entire {} block would short-circuit and the
    # config file would be incomplete. Replaced with explicit if blocks above.

    _write_transport_extras "$CONFIG_FILE" "server" "$TRANSPORT"
    write_common_tail "$CONFIG_FILE"
    create_systemd_service "server"

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "iran"

    systemctl start DaggerConnect-server && systemctl enable DaggerConnect-server

    echo ""; divider
    ok "Server configured!"
    info "Port:      ${GREEN}${LISTEN_PORT}${NC}"
    info "Transport: ${GREEN}${TRANSPORT}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-server -f"
    [[ "$TRANSPORT" == "daggermux" ]] && warn "DaggerMux: iptables rules applied, root + libpcap required."
    divider; press_enter; main_menu
}

# ============================================================================
# MULTI-LISTENER SERVER
# ============================================================================

install_server_multilistener() {
    show_banner
    section "Multi-Listener Server Setup"
    echo -e "  ${DIM}Each listener is fully isolated — own sessions, own TUN.${NC}"
    echo ""

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
        gen_ssl_cert "$CONFIG_DIR/certs/cert.pem" "$CONFIG_DIR/certs/key.pem" "$CD"
        GLOBAL_CERT="$CONFIG_DIR/certs/cert.pem"; GLOBAL_KEY="$CONFIG_DIR/certs/key.pem"
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
        if [[ -n "$GLOBAL_CERT" ]]; then
            echo "cert_file: \"${GLOBAL_CERT}\""
            echo "key_file: \"${GLOBAL_KEY}\""
            echo ""
        fi
        echo "listeners:"
    } > "$CONFIG_FILE"
    # BUG FIX #9: Same && short-circuit issue as #8 — replaced with if block.

    local LISTENER_COUNT=0
    local HAS_DAGGERMUX=false HAS_RAWMUX=false

    while true; do
        echo ""; echo -e "  ${PURPLE}══ Listener #${LISTENER_COUNT} ══${NC}"

        read -rp "  Bind address [0.0.0.0:$((4000+LISTENER_COUNT))]: " L_ADDR || true
        L_ADDR=${L_ADDR:-"0.0.0.0:$((4000+LISTENER_COUNT))"}

        L_TRANSPORT=$(select_transport)

        L_CERT=""; L_KEY=""
        if [[ "$L_TRANSPORT" == "httpsmux" || "$L_TRANSPORT" == "wssmux" ]]; then
            if [[ -n "$GLOBAL_CERT" ]]; then
                L_CERT="$GLOBAL_CERT"; L_KEY="$GLOBAL_KEY"; ok "Using global SSL cert."
            else
                read -rp "  Generate cert for listener #${LISTENER_COUNT}? [Y/n]: " GLC || true
                if [[ ! $GLC =~ ^[Nn]$ ]]; then
                    read -rp "  Domain [www.google.com]: " LCD || true; LCD=${LCD:-www.google.com}
                    gen_ssl_cert "$CONFIG_DIR/certs/cert_${LISTENER_COUNT}.pem" \
                                 "$CONFIG_DIR/certs/key_${LISTENER_COUNT}.pem" "$LCD"
                    L_CERT="$CONFIG_DIR/certs/cert_${LISTENER_COUNT}.pem"
                    L_KEY="$CONFIG_DIR/certs/key_${LISTENER_COUNT}.pem"
                fi
            fi
        fi

        if [[ "$L_TRANSPORT" == "daggermux" ]]; then
            L_PORT=$(echo "$L_ADDR" | cut -d: -f2)
            # BUG FIX #10: L_PORT could be empty if L_ADDR has no colon (malformed input).
            # Add validation before passing to iptables.
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

        build_port_mappings; L_MAPPINGS="$MAPPINGS"

        read -rp "  Enable TUN for listener #${LISTENER_COUNT}? [y/N]: " L_TUN_EN || true
        L_TUN_ENABLED=false
        if [[ $L_TUN_EN =~ ^[Yy]$ ]]; then
            L_TUN_ENABLED=true; configure_tun "$LISTENER_COUNT" "server"
        fi

        {
            echo "  - addr: \"${L_ADDR}\""
            echo "    transport: \"${L_TRANSPORT}\""
            if [[ -n "$L_CERT" ]]; then
                echo "    cert_file: \"${L_CERT}\""
                echo "    key_file: \"${L_KEY}\""
            fi
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
        # BUG FIX #11: Same && short-circuit for cert_file/key_file — replaced with if block.

        LISTENER_COUNT=$((LISTENER_COUNT+1))
        ok "Listener #$((LISTENER_COUNT-1)): ${L_ADDR} (${L_TRANSPORT}) added."
        $L_TUN_ENABLED && info "TUN: ${_TUN_NAME} — ${_TUN_LOCAL}/32 ↔ ${_TUN_PEER}"

        read -rp "  Add another listener? [y/N]: " ML || true
        [[ ! $ML =~ ^[Yy]$ ]] && break
    done

    $HAS_DAGGERMUX && write_daggermux_config "$CONFIG_FILE" "server"
    $HAS_RAWMUX    && write_rawmux_config    "$CONFIG_FILE"

    write_common_tail "$CONFIG_FILE"
    create_systemd_service "server"

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "iran"

    systemctl start DaggerConnect-server && systemctl enable DaggerConnect-server

    echo ""; divider
    ok "Multi-Listener Server configured!"
    info "Listeners: ${GREEN}${LISTENER_COUNT}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-server -f"
    $HAS_DAGGERMUX && warn "DaggerMux: iptables rules applied, libpcap installed."
    divider; press_enter; main_menu
}

# ============================================================================
# SERVER ENTRY
# ============================================================================

install_server() {
    show_banner
    section "Server Configuration"
    echo -e "  ${WHITE}1)${NC} Automatic      — Single listener ${GREEN}(Recommended)${NC}"
    echo -e "  ${WHITE}2)${NC} Multi-Listener — Multiple isolated listeners + TUN"
    echo ""
    read -rp "  Choice [1-2]: " cm || true
    case $cm in
        2) install_server_multilistener ;;
        *) install_server_automatic     ;;
    esac
}

# ============================================================================
# AUTOMATIC CLIENT
# ============================================================================

install_client_automatic() {
    show_banner
    section "Automatic Client Setup"

    while true; do
        read -rsp "  PSK (must match server): " PSK || true; echo ""
        [[ -n "$PSK" ]] && break; err "PSK cannot be empty!"
    done

    TRANSPORT=$(select_transport)

    read -rp "  Server address:port [e.g., 1.2.3.4:2020]: " ADDR || true
    if [[ -z "$ADDR" ]]; then
        err "Address cannot be empty!"; install_client_automatic; return
    fi

    # BUG FIX #12: No validation on ADDR format — could produce broken YAML.
    # Simple sanity check that it contains a colon (host:port).
    if [[ "$ADDR" != *:* ]]; then
        err "Address must be in host:port format (e.g., 1.2.3.4:2020)."
        install_client_automatic; return
    fi

    [[ "$TRANSPORT" == "daggermux" ]] && configure_daggermux "client"
    [[ "$TRANSPORT" == "rawmux"    ]] && configure_rawmux

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

    _write_transport_extras "$CONFIG_FILE" "client" "$TRANSPORT"
    write_common_tail "$CONFIG_FILE"
    create_systemd_service "client"

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "foreign"

    systemctl start DaggerConnect-client && systemctl enable DaggerConnect-client

    echo ""; divider
    ok "Client configured!"
    info "Server:    ${GREEN}${ADDR}${NC}"
    info "Transport: ${GREEN}${TRANSPORT}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-client -f"
    [[ "$TRANSPORT" == "daggermux" ]] && warn "DaggerMux: ensure server has iptables rules applied."
    divider; press_enter; main_menu
}

# ============================================================================
# MULTI-PATH CLIENT
# ============================================================================

install_client_multipaths() {
    show_banner
    section "Multi-Path Client Setup"
    echo -e "  ${DIM}Each path can have its own PSK and TUN interface.${NC}"
    echo ""

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
    if [[ ! $OBE =~ ^[Nn]$ ]]; then
        OBFUS_ENABLED="true"
        read -rp "  Min padding [16]:  " OP1; OP1=${OP1:-16} || true
        read -rp "  Max padding [512]: " OP2; OP2=${OP2:-512} || true
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

    local PATH_COUNT=0
    local HAS_DAGGERMUX=false HAS_RAWMUX=false

    while true; do
        echo ""; echo -e "  ${PURPLE}══ Path #${PATH_COUNT} ══${NC}"

        P_TRANSPORT=$(select_transport)

        read -rp "  Server address:port: " P_ADDR || true
        [[ -z "$P_ADDR" ]] && err "Cannot be empty!" && continue

        # BUG FIX #13: Same host:port validation for multipaths client.
        if [[ "$P_ADDR" != *:* ]]; then
            err "Address must be in host:port format."; continue
        fi

        read -rsp "  Custom PSK? [blank = use global]: " P_PSK_RAW || true; echo ""
        P_PSK=""
        [[ -n "$P_PSK_RAW" ]] && P_PSK="$P_PSK_RAW" && ok "Custom PSK will be used."

        read -rp "  Connection pool  [2]:  " P_POOL || true;  P_POOL=${P_POOL:-2}
        read -rp "  Aggressive pool? [y/N]: " P_AGG || true
        [[ $P_AGG =~ ^[Yy]$ ]] && P_AGG_VAL="true" || P_AGG_VAL="false"
        read -rp "  Retry interval (s) [3]:  " P_RETRY || true; P_RETRY=${P_RETRY:-3}
        read -rp "  Dial timeout   (s) [10]: " P_DIAL || true;  P_DIAL=${P_DIAL:-10}

        [[ "$P_TRANSPORT" == "daggermux" ]] && configure_daggermux "client" && HAS_DAGGERMUX=true
        [[ "$P_TRANSPORT" == "rawmux"    ]] && configure_rawmux             && HAS_RAWMUX=true

        read -rp "  Enable TUN for this path? [y/N]: " P_TUN_EN || true
        P_TUN_ENABLED=false
        if [[ $P_TUN_EN =~ ^[Yy]$ ]]; then
            P_TUN_ENABLED=true; configure_tun "$PATH_COUNT" "client"
        fi

        {
            echo "  - transport: \"${P_TRANSPORT}\""
            echo "    addr: \"${P_ADDR}\""
            [[ -n "$P_PSK" ]] && echo "    psk: \"${P_PSK}\""
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
        ok "Path #$((PATH_COUNT-1)): ${P_TRANSPORT} → ${P_ADDR} added."
        [[ -n "$P_PSK" ]] && info "PSK: custom"
        $P_TUN_ENABLED && info "TUN: ${_TUN_NAME} — ${_TUN_LOCAL}/32 ↔ ${_TUN_PEER}"

        read -rp "  Add another path? [y/N]: " MP || true
        [[ ! $MP =~ ^[Yy]$ ]] && break
    done

    $HAS_DAGGERMUX && write_daggermux_config "$CONFIG_FILE" "client"
    $HAS_RAWMUX    && write_rawmux_config    "$CONFIG_FILE"

    # Write full config tail with user-chosen obfuscation values (no duplication)
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

    read -rp "  Optimize system? [Y/n]: " opt || true
    [[ ! $opt =~ ^[Nn]$ ]] && optimize_system "foreign"

    systemctl start DaggerConnect-client && systemctl enable DaggerConnect-client

    echo ""; divider
    ok "Multi-Path Client configured!"
    info "Paths:  ${GREEN}${PATH_COUNT}${NC}"
    info "Config: ${CONFIG_FILE}"
    info "Logs:   journalctl -u DaggerConnect-client -f"
    $HAS_DAGGERMUX && warn "DaggerMux: ensure server has iptables rules applied."
    divider; press_enter; main_menu
}

# ============================================================================
# CLIENT ENTRY
# ============================================================================

install_client() {
    show_banner
    section "Client Configuration"
    echo -e "  ${WHITE}1)${NC} Automatic  — Single path ${GREEN}(Recommended)${NC}"
    echo -e "  ${WHITE}2)${NC} Multi-Path — Multiple paths with per-PSK & TUN"
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

    # FIX: compare versions — skip if already up-to-date
    if [[ "$LATEST_VERSION" != "unknown" && "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        ok "Already on the latest version (${CURRENT_VERSION}). Nothing to do."
        read -rp "  Force re-download anyway? [y/N]: " force || true
        [[ ! $force =~ ^[Yy]$ ]] && press_enter && main_menu && return
    fi

    read -rp "  Continue with update? [y/N]: " c || true
    [[ ! $c =~ ^[Yy]$ ]] && main_menu && return

    systemctl stop DaggerConnect-server 2>/dev/null || true
    systemctl stop DaggerConnect-client 2>/dev/null || true
    sleep 1

    download_binary
    local NEW_VERSION; NEW_VERSION=$(get_current_version)
    ok "Updated: ${YELLOW}${CURRENT_VERSION}${NC} → ${GREEN}${NEW_VERSION}${NC}"

    if systemctl is-enabled DaggerConnect-server &>/dev/null || \
       systemctl is-enabled DaggerConnect-client &>/dev/null; then
        read -rp "  Restart services? [Y/n]: " r || true
        if [[ ! $r =~ ^[Nn]$ ]]; then
            systemctl is-enabled DaggerConnect-server &>/dev/null && \
                systemctl start DaggerConnect-server && ok "Server restarted."
            systemctl is-enabled DaggerConnect-client &>/dev/null && \
                systemctl start DaggerConnect-client && ok "Client restarted."
        fi
    fi
    press_enter; main_menu
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

service_management() {
    local MODE=$1
    local SERVICE_NAME="DaggerConnect-${MODE}"
    local CONFIG_FILE="$CONFIG_DIR/${MODE}.yaml"

    show_banner
    section "${MODE^^} — Service Management"

    systemctl is-active  --quiet "$SERVICE_NAME" && \
        echo -e "  Status:     ${GREEN}● RUNNING${NC}" || echo -e "  Status:     ${RED}● STOPPED${NC}"
    systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null && \
        echo -e "  Auto-start: ${GREEN}enabled${NC}" || echo -e "  Auto-start: ${YELLOW}disabled${NC}"

    echo ""; divider
    echo -e "  ${WHITE}1)${NC} Start        ${WHITE}2)${NC} Stop         ${WHITE}3)${NC} Restart"
    echo -e "  ${WHITE}4)${NC} Status       ${WHITE}5)${NC} Live Logs    ${WHITE}6)${NC} Enable auto-start"
    echo -e "  ${WHITE}7)${NC} Disable auto-start"
    divider
    echo -e "  ${WHITE}8)${NC} View Config  ${WHITE}9)${NC} Edit Config  ${WHITE}10)${NC} Delete"
    echo -e "  ${WHITE}0)${NC} Back"
    divider
    read -rp "  Select: " choice || true

    case $choice in
        1)  systemctl start   "$SERVICE_NAME"; ok "Started.";   sleep 2; service_management "$MODE" ;;
        2)  systemctl stop    "$SERVICE_NAME"; ok "Stopped.";   sleep 2; service_management "$MODE" ;;
        3)  systemctl restart "$SERVICE_NAME"; ok "Restarted."; sleep 2; service_management "$MODE" ;;
        4)  systemctl status  "$SERVICE_NAME" --no-pager; press_enter; service_management "$MODE" ;;
        5)  journalctl -u "$SERVICE_NAME" -f || true
            service_management "$MODE" ;;
        6)  systemctl enable  "$SERVICE_NAME"; ok "Auto-start enabled.";  sleep 2; service_management "$MODE" ;;
        7)  systemctl disable "$SERVICE_NAME"; ok "Auto-start disabled."; sleep 2; service_management "$MODE" ;;
        8)  [[ -f "$CONFIG_FILE" ]] && cat "$CONFIG_FILE" || err "Config not found."
            press_enter; service_management "$MODE" ;;
        9)  if [[ -f "$CONFIG_FILE" ]]; then
                local BACKUP="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
                cp "$CONFIG_FILE" "$BACKUP"
                ok "Backup saved: ${DIM}${BACKUP}${NC}"
                ${EDITOR:-nano} "$CONFIG_FILE"
                read -rp "  Restart to apply? [y/N]: " r || true
                [[ $r =~ ^[Yy]$ ]] && systemctl restart "$SERVICE_NAME" && ok "Restarted."
                sleep 2
            else
                err "Config not found."; sleep 2
            fi
            service_management "$MODE" ;;
        10) read -rp "  Delete ${MODE} service and config? [y/N]: " c
            if [[ $c =~ ^[Yy]$ ]]; then
                systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
                systemctl disable "$SERVICE_NAME" 2>/dev/null || true
                rm -f "$CONFIG_FILE" "$SYSTEMD_DIR/${SERVICE_NAME}.service"
                systemctl daemon-reload
                ok "Deleted."; sleep 2
            fi
            settings_menu ;;
        0)  settings_menu ;;
        *)  service_management "$MODE" ;;
    esac
}

settings_menu() {
    show_banner
    section "Settings"
    echo -e "  ${WHITE}1)${NC} Manage Server"
    echo -e "  ${WHITE}2)${NC} Manage Client"
    echo -e "  ${WHITE}0)${NC} Back"
    echo ""
    read -rp "  Select: " choice || true
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

uninstall_daggerconnect() {
    show_banner
    section "Uninstall DaggerConnect"
    warn "This will remove: binary, configs, services, certs, and optimizations."
    echo ""
    read -rp "  Are you sure? [y/N]: " c || true
    [[ ! $c =~ ^[Yy]$ ]] && main_menu && return

    systemctl stop    DaggerConnect-server 2>/dev/null || true
    systemctl stop    DaggerConnect-client 2>/dev/null || true
    systemctl disable DaggerConnect-server 2>/dev/null || true
    systemctl disable DaggerConnect-client 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/DaggerConnect-server.service"
    rm -f "$SYSTEMD_DIR/DaggerConnect-client.service"
    rm -f "$INSTALL_DIR/DaggerConnect"
    rm -rf "$CONFIG_DIR"
    rm -f /etc/sysctl.d/99-daggerconnect.conf
    rm -f /etc/network/if-pre-up.d/daggermux-iptables

    # FIX: flush all DaggerMux iptables rules that were applied
    section "Cleaning iptables rules"
    if command -v iptables &>/dev/null; then
        # Remove all NOTRACK rules injected by DaggerConnect (raw table)
        iptables -t raw    -S 2>/dev/null | grep -E 'NOTRACK' | sed 's/^-A/-D/' | \
            while read -r rule; do iptables -t raw    $rule 2>/dev/null || true; done
        # Remove DROP RST rules (mangle table)
        iptables -t mangle -S 2>/dev/null | grep -E 'RST.*DROP' | sed 's/^-A/-D/' | \
            while read -r rule; do iptables -t mangle $rule 2>/dev/null || true; done
        ok "iptables rules cleaned."
        # Save cleaned ruleset
        if command -v iptables-save &>/dev/null && [[ -f /etc/iptables/rules.v4 ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null && ok "iptables ruleset saved."
        fi
    fi

    sysctl -p > /dev/null 2>&1
    systemctl daemon-reload

    ok "DaggerConnect uninstalled successfully."
    exit 0
}

# ============================================================================
# PORT CONFLICT CHECK
# ============================================================================

check_port_available() {
    local PORT=$1
    local PROTO=${2:-tcp}
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || \
       ss -ulnp 2>/dev/null | grep -q ":${PORT} "; then
        local OWNER
        OWNER=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | awk '{print $NF}' | head -1)
        warn "Port ${PORT} is already in use! (${OWNER:-unknown process})"
        return 1
    fi
    return 0
}

# ============================================================================
# STATUS DASHBOARD
# ============================================================================

show_status_dashboard() {
    show_banner
    section "System Status Dashboard"

    # Binary
    if [[ -f "$INSTALL_DIR/DaggerConnect" ]]; then
        local VER; VER=$(get_current_version)
        echo -e "  ${WHITE}Binary:${NC}    ${GREEN}Installed${NC} (${VER})"
    else
        echo -e "  ${WHITE}Binary:${NC}    ${RED}Not installed${NC}"
    fi

    echo ""
    divider

    # Services
    for MODE in server client; do
        local SVC="DaggerConnect-${MODE}"
        local CFG="$CONFIG_DIR/${MODE}.yaml"
        echo ""
        local MODE_CAP
        MODE_CAP="$(echo "${MODE:0:1}" | tr '[:lower:]' '[:upper:]')${MODE:1}"
        echo -e "  ${WHITE}── ${MODE_CAP} ──${NC}"

        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            echo -e "  Status:     ${GREEN}● RUNNING${NC}"
            local UPTIME
            UPTIME=$(systemctl show "$SVC" --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
            [[ -n "$UPTIME" ]] && echo -e "  Started:    ${DIM}${UPTIME}${NC}"
            local MEM
            MEM=$(systemctl show "$SVC" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)
            if [[ -n "$MEM" && "$MEM" != "18446744073709551615" && "$MEM" != "[not set]" ]]; then
                MEM=$((MEM / 1024 / 1024))
                echo -e "  Memory:     ${DIM}${MEM} MB${NC}"
            fi
        elif systemctl is-enabled "$SVC" &>/dev/null 2>/dev/null; then
            echo -e "  Status:     ${RED}● STOPPED${NC} ${YELLOW}(enabled but not running)${NC}"
        else
            echo -e "  Status:     ${DIM}○ Not configured${NC}"
        fi

        if [[ -f "$CFG" ]]; then
            local TRANSPORT PORT_COUNT LISTEN_PORT
            TRANSPORT=$(grep 'transport:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
            PORT_COUNT=$(grep -c 'type:' "$CFG" 2>/dev/null || echo 0)
            LISTEN_PORT=$(grep 'addr:' "$CFG" | head -1 | awk '{print $2}' | tr -d '"' | cut -d: -f2)
            [[ -n "$TRANSPORT"   ]] && echo -e "  Transport:  ${DIM}${TRANSPORT}${NC}"
            [[ -n "$LISTEN_PORT" ]] && echo -e "  Port:       ${DIM}${LISTEN_PORT}${NC}"
            [[ "$PORT_COUNT" -gt 0 ]] && echo -e "  Mappings:   ${DIM}${PORT_COUNT}${NC}"
        fi
    done

    echo ""; divider

    # Network
    echo ""
    echo -e "  ${WHITE}── Network ──${NC}"
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

    # BBR status
    local CCN
    CCN=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo -e "  TCP CC:     ${DIM}${CCN}${NC}"

    echo ""; divider
    press_enter; main_menu
}

main_menu() {
    show_banner

    local CURRENT_VER; CURRENT_VER=$(get_current_version)
    [[ "$CURRENT_VER" != "not-installed" ]] && echo -e "  Version: ${GREEN}${CURRENT_VER}${NC}" && echo ""

    systemctl is-active --quiet DaggerConnect-server 2>/dev/null && echo -e "  Server : ${GREEN}● RUNNING${NC}"
    systemctl is-active --quiet DaggerConnect-client 2>/dev/null && echo -e "  Client : ${GREEN}● RUNNING${NC}"

    echo ""; divider
    echo -e "  ${WHITE}1)${NC} Install / Configure Server"
    echo -e "  ${WHITE}2)${NC} Install / Configure Client"
    echo -e "  ${WHITE}3)${NC} Settings — Manage Services & Configs"
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
show_banner
install_dependencies

if [[ ! -f "$INSTALL_DIR/DaggerConnect" ]]; then
    warn "DaggerConnect binary not found — downloading..."
    download_binary
    echo ""
fi

main_menu
