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
BINARY_DOWNLOAD_URL="http://ir.daggerconnect.site/DaggerConnect"
FIRST_RUN_FLAG="$CONFIG_DIR/.first_run_done"

# ── State vars ───────────────────────────────────────────────────────────────
# RawMux
_RM_HS_TIMEOUT="10"; _RM_KEEPALIVE="15"; _RM_USE_PCAP="false"

# QuantumMux (spoof fields are all optional and default to empty)
_QM_IFACE=""; _QM_LOCAL_IP=""; _QM_ROUTER_MAC=""
_QM_DATA_SHARD="10"; _QM_PARITY_SHARD="1"
_QM_SPOOF_SRC_IP=""; _QM_SPOOF_SRC_MAC=""
_QM_CLIENT_SPOOF_IP=""; _QM_CLIENT_REAL_IP=""
_QM_SERVER_SPOOF_IP=""
_QM_USE_PCAP="false"
_QM_MTU=""; _QM_ICMPV6_MODE="false"; _QM_NATURAL_SEND="false"

# Tun transport (TUN interface + IPX/TCP encapsulation)
_TUN_ENCAP="ipx"
_TUN_NAME="dagger0"
_TUN_LOCAL_ADDR=""          # e.g. 10.10.1.1/24
_TUN_REMOTE_ADDR=""         # e.g. 10.10.1.2/24
_TUN_HEALTH_PORT="1234"
_TUN_MTU=""
# IPX fields (only when _TUN_ENCAP=ipx)
_TUN_PROFILE="icmp"         # icmp | gre | ipip | bip
_TUN_LISTEN_IP=""
_TUN_DST_IP=""
_TUN_IFACE=""
_TUN_ICMP_TYPE=""
_TUN_ICMP_CODE=""
_TUN_SPOOF_SRC_IP=""
_TUN_SPOOF_DST_IP=""
# Optional advanced features
_TUN_PROTO58="false"        # extra IPv6+NH=58 shell over the primary profile
_TUN_PROTO58_SRC_IPV6=""    # link-local default if blank
_TUN_PROTO58_DST_IPV6=""

MAPPINGS=""
LOG_LEVEL="info"

# ============================================================================
# UI HELPERS
# ============================================================================

show_banner() {
    clear
    echo -e "${CYAN}"
    echo -e "  \u2554\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2557"
    echo -e "  \u2551       D A G G E R C O N N E C T         \u2551"
    echo -e "  \u2551     High-Performance Tunnel Manager      \u2551"
    echo -e "  \u2560\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2563"
    echo -e "  \u2551  ${BLUE}Telegram: @DaggerConnect${CYAN}                 \u2551"
    echo -e "  \u255a\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u255d${NC}"
    echo ""
}

section()     { echo ""; echo -e "${CYAN}  \u250c\u2500 $1${NC}"; echo ""; }
ok()          { echo -e "  ${GREEN}v${NC}  $1"; }
warn()        { echo -e "  ${YELLOW}!${NC}  $1"; }
err()         { echo -e "  ${RED}x${NC}  $1"; }
info()        { echo -e "  ${DIM}>${NC}  $1"; }
divider()     { echo -e "  ${DIM}\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500${NC}"; }
press_enter() { echo ""; read -rp "  Press Enter to continue..." _; }

# Yes/No helper (default No)
_yn() {
    local prompt=$1 default=${2:-N}
    local v
    read -rp "  ${prompt} [$( [[ $default == Y ]] && echo 'Y/n' || echo 'y/N' )]: " v || true
    if [[ -z "$v" ]]; then
        [[ "$default" == "Y" ]] && return 0 || return 1
    fi
    [[ "$v" =~ ^[Yy]$ ]] && return 0 || return 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root."
        exit 1
    fi
}

install_dependencies() {
    section "Installing Dependencies"
    # libpcap is required for pcap-based transports (rawmux, quantummux, tunmux/ipx)
    if command -v apt-get &>/dev/null; then
        apt-get install -y libpcap0.8 iptables openssl python3 wget curl >/dev/null 2>&1 \
            && ok "Dependencies installed (apt)." \
            || warn "Some packages may already be present."
    elif command -v dnf &>/dev/null; then
        dnf install -y libpcap iptables openssl python3 wget curl >/dev/null 2>&1 \
            && ok "Dependencies installed (dnf)." \
            || warn "Some packages may already be present."
    else
        ok "Dependencies ready (manual install assumed)."
    fi
}

# ============================================================================
# BINARY MANAGEMENT
# ============================================================================

get_current_version() {
    if [[ -f "$INSTALL_DIR/DaggerConnect" ]]; then
        "$INSTALL_DIR/DaggerConnect" -v 2>&1 | grep -oP 'v\d+(\.\d+(\.\d+)?)?' || echo "unknown"
    else
        echo "not-installed"
    fi
}

download_binary() {
    section "Downloading DaggerConnect"
    mkdir -p "$INSTALL_DIR"
    echo ""
    echo -e "  ${YELLOW}Select download source:${NC}"
    echo -e "  ${WHITE}1)${NC} GitHub     -- latest release"
    echo -e "  ${WHITE}2)${NC} Direct     -- ${GREEN}${BINARY_DOWNLOAD_URL}${NC} ${DIM}(recommended)${NC}"
    echo ""
    read -rp "  Choice [2]: " DL_CHOICE || true

    local BINARY_URL LATEST_VERSION
    case ${DL_CHOICE:-2} in
        1)
            info "Fetching latest version from GitHub..."
            LATEST_VERSION=$(curl -s --connect-timeout 8 --max-time 10 "$LATEST_RELEASE_API" \
                | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
            if [[ -z "$LATEST_VERSION" ]]; then
                warn "Could not reach GitHub -- falling back to direct server."
                BINARY_URL="$BINARY_DOWNLOAD_URL"
            else
                BINARY_URL="https://github.com/itsFLoKi/DaggerConnect/releases/download/${LATEST_VERSION}/DaggerConnect"
                info "GitHub release: ${GREEN}${LATEST_VERSION}${NC}"
            fi
            ;;
        *)
            BINARY_URL="$BINARY_DOWNLOAD_URL"
            info "Source: ${GREEN}${BINARY_URL}${NC}"
            ;;
    esac

    [[ -f "$INSTALL_DIR/DaggerConnect" ]] && \
        mv "$INSTALL_DIR/DaggerConnect" "$INSTALL_DIR/DaggerConnect.backup" || true

    if wget -q --show-progress "$BINARY_URL" -O "$INSTALL_DIR/DaggerConnect"; then
        chmod +x "$INSTALL_DIR/DaggerConnect"
        rm -f "$INSTALL_DIR/DaggerConnect.backup"
        ok "Binary downloaded successfully."
    else
        if [[ "$BINARY_URL" != "$BINARY_DOWNLOAD_URL" ]]; then
            warn "GitHub download failed -- trying direct server..."
            if wget -q --show-progress "$BINARY_DOWNLOAD_URL" -O "$INSTALL_DIR/DaggerConnect"; then
                chmod +x "$INSTALL_DIR/DaggerConnect"
                rm -f "$INSTALL_DIR/DaggerConnect.backup"
                ok "Binary downloaded from direct server."
                return
            fi
        fi
        err "Download failed from all sources."
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

    sysctl -w net.core.rmem_max=8388608 net.core.wmem_max=8388608 \
              net.core.rmem_default=131072 net.core.wmem_default=131072 \
              "net.ipv4.tcp_rmem=4096 65536 8388608" \
              "net.ipv4.tcp_wmem=4096 65536 8388608" \
              net.ipv4.tcp_window_scaling=1 net.ipv4.tcp_timestamps=1 \
              net.ipv4.tcp_sack=1 net.ipv4.tcp_retries2=6 \
              net.ipv4.tcp_syn_retries=2 net.core.netdev_max_backlog=1000 \
              net.core.somaxconn=512 net.ipv4.tcp_fastopen=3 \
              net.ipv4.tcp_low_latency=1 net.ipv4.tcp_slow_start_after_idle=0 \
              net.ipv4.tcp_no_metrics_save=1 net.ipv4.tcp_autocorking=0 \
              net.ipv4.tcp_mtu_probing=1 net.ipv4.tcp_keepalive_time=120 \
              net.ipv4.tcp_keepalive_intvl=10 net.ipv4.tcp_keepalive_probes=3 \
              net.ipv4.tcp_fin_timeout=15 net.ipv4.ip_forward=1 > /dev/null 2>&1 || true

    if modprobe tcp_bbr 2>/dev/null; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr \
                  net.core.default_qdisc=fq_codel > /dev/null 2>&1 || true
        ok "BBR congestion control enabled."
    else
        warn "BBR not available -- using CUBIC."
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
    ok "Optimization settings saved."
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
# INSTANCE NAME
# ============================================================================

_validate_instance_name() {
    local NAME=$1
    [[ -z "$NAME" ]]                    && { err "Name cannot be empty!" >&2; return 1; }
    ! [[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] && { err "Name: letters, numbers, '-', '_' only" >&2; return 1; }
    [[ ${#NAME} -gt 32 ]]               && { err "Name too long (max 32 chars)" >&2; return 1; }
    return 0
}

_pick_instance_name() {
    local ROLE=$1 DEFAULT=$2
    echo "" >&2
    echo -e "  ${YELLOW}Instance Name${NC} ${DIM}(DaggerConnect-{NAME})${NC}" >&2
    echo "" >&2
    local NAME
    while true; do
        read -rp "  Name [${DEFAULT}]: " NAME <>/dev/tty || true
        NAME=${NAME:-$DEFAULT}
        if _validate_instance_name "$NAME"; then
            if [[ -f "$CONFIG_DIR/${NAME}.yaml" ]] || [[ -f "$CONFIG_DIR/${NAME}.json" ]]; then
                warn "Instance '${NAME}' already exists!" >&2
                read -rp "  Overwrite? [y/N]: " OW <>/dev/tty || true
                [[ $OW =~ ^[Yy]$ ]] && break || continue
            fi
            break
        fi
    done
    echo "$NAME"
}

# ============================================================================
# SELECT TRANSPORT
# ============================================================================

select_transport() {
    echo "" >&2
    echo -e "  ${YELLOW}Select Transport:${NC}" >&2
    divider >&2
    echo -e "  ${WHITE}1)${NC} httpsmux   -- HTTPS Mimicry ${GREEN}(Recommended)${NC}" >&2
    echo -e "  ${WHITE}2)${NC} httpmux    -- HTTP Mimicry" >&2
    echo -e "  ${WHITE}3)${NC} wssmux     -- WebSocket Secure" >&2
    echo -e "  ${WHITE}4)${NC} wsmux      -- WebSocket" >&2
    echo -e "  ${WHITE}5)${NC} kcpmux     -- KCP over UDP" >&2
    echo -e "  ${WHITE}6)${NC} tcpmux     -- Simple TCP" >&2
    echo -e "  ${WHITE}7)${NC} rawmux     -- ${CYAN}Raw KCP/UDP + DPI Bypass${NC}" >&2
    echo -e "  ${WHITE}8)${NC} quantummux -- ${CYAN}Raw TCP via pcap + KCP + FEC${NC}" >&2
    echo -e "  ${WHITE}9)${NC} tunmux     -- ${PURPLE}TUN interface + pcap encap (icmp/gre/ipip/bip) — zero HOL${NC}" >&2
    divider >&2; echo "" >&2
    read -rp "  Choice [1-9]: " trans_choice || true
    case $trans_choice in
        2) echo "httpmux"    ;; 3) echo "wssmux"     ;; 4) echo "wsmux"      ;;
        5) echo "kcpmux"     ;; 6) echo "tcpmux"     ;; 7) echo "rawmux"     ;;
        8) echo "quantummux" ;; 9) echo "tunmux"     ;;
        *) echo "httpsmux"   ;;
    esac
}

# ============================================================================
# RAWMUX
# ============================================================================

configure_rawmux() {
    section "RawMux Configuration"
    read -rp "  Handshake timeout (s)    [10]: " v || true; _RM_HS_TIMEOUT=${v:-10}
    read -rp "  Keepalive (s)            [15]: " v || true; _RM_KEEPALIVE=${v:-15}
    echo ""
    if _yn "Enable pcap DPI bypass?" N; then _RM_USE_PCAP="true"; else _RM_USE_PCAP="false"; fi
}

# ============================================================================
# QUANTUMMUX
# ============================================================================

configure_quantummux() {
    local SIDE=$1
    section "QuantumMux Configuration"
    warn "Uses raw TCP packets via pcap. Requires root + libpcap + iptables rules."
    echo ""
    read -rp "  Network interface        [auto-detect]: " v || true; _QM_IFACE="${v:-}"
    read -rp "  Local IP                 [auto-detect]: " v || true; _QM_LOCAL_IP="${v:-}"
    if [[ "$SIDE" == "client" ]]; then
        read -rp "  Gateway/Router MAC       [auto-detect]: " v || true; _QM_ROUTER_MAC="${v:-}"
    else
        _QM_ROUTER_MAC=""
    fi

    # ── IP/MAC spoofing — fully optional, each field independent ────────────
    _QM_SPOOF_SRC_IP=""; _QM_SPOOF_SRC_MAC=""
    _QM_SERVER_SPOOF_IP=""; _QM_CLIENT_SPOOF_IP=""; _QM_CLIENT_REAL_IP=""
    echo ""
    echo -e "  ${DIM}── Spoofing (all fields optional, leave blank to disable) ──${NC}"
    if _yn "Configure IP/MAC spoofing?" N; then
        read -rp "  Spoof source IP          [skip]: " v || true; _QM_SPOOF_SRC_IP="${v:-}"
        read -rp "  Spoof source MAC         [skip]: " v || true; _QM_SPOOF_SRC_MAC="${v:-}"
        if [[ "$SIDE" == "server" ]]; then
            read -rp "  Client spoof IP          [skip]: " v || true; _QM_CLIENT_SPOOF_IP="${v:-}"
            read -rp "  Client real IP           [skip]: " v || true; _QM_CLIENT_REAL_IP="${v:-}"
        else
            read -rp "  Server spoof IP          [skip]: " v || true; _QM_SERVER_SPOOF_IP="${v:-}"
        fi
    else
        info "Spoofing disabled."
    fi

    # FEC params (kept simple — AdaptiveTuner manages perf-related stuff)
    _QM_DATA_SHARD=10; _QM_PARITY_SHARD=1

    echo ""
    if _yn "Enable pcap RX mode?" N; then _QM_USE_PCAP="true"; else _QM_USE_PCAP="false"; fi

    echo ""
    read -rp "  MTU                      [auto]: " v || true; _QM_MTU="${v:-}"
    if _yn "Enable ICMPv6 mode?" N; then _QM_ICMPV6_MODE="true"; else _QM_ICMPV6_MODE="false"; fi
    if _yn "Enable Natural Send?"  N; then _QM_NATURAL_SEND="true"; else _QM_NATURAL_SEND="false"; fi
}

setup_quantummux_iptables() {
    local PORT=$1
    section "QuantumMux iptables Rules"
    warn "MANDATORY -- without these rules, kernel sends RST packets."
    iptables -t raw    -A PREROUTING -p tcp --dport "$PORT" -j NOTRACK                  2>/dev/null || true
    iptables -t raw    -A OUTPUT     -p tcp --sport "$PORT" -j NOTRACK                  2>/dev/null || true
    iptables -t mangle -A OUTPUT     -p tcp --sport "$PORT" --tcp-flags RST RST -j DROP 2>/dev/null || true
    ok "iptables rules applied for port ${PORT}."
    if command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null && ok "Rules saved." || true
    fi
    local F="/etc/network/if-pre-up.d/quantummux-iptables"
    mkdir -p "$(dirname "$F")"
    printf '#!/bin/bash\niptables -t raw    -A PREROUTING -p tcp --dport %s -j NOTRACK 2>/dev/null || true\niptables -t raw    -A OUTPUT     -p tcp --sport %s -j NOTRACK 2>/dev/null || true\niptables -t mangle -A OUTPUT     -p tcp --sport %s --tcp-flags RST RST -j DROP 2>/dev/null || true\n' \
        "$PORT" "$PORT" "$PORT" > "$F"
    chmod +x "$F" 2>/dev/null || true
}

# ============================================================================
# TUNMUX (v2.2 — TUN interface + IPX/TCP encapsulation, zero HOL blocking)
# ============================================================================

configure_tunmux() {
    local SIDE=$1
    section "Tun Transport Configuration"
    warn "TUN + pcap transport, no smux, zero HOL blocking"
    warn "Requires: root + libpcap"
    echo ""

    # Reset
    _TUN_NAME="dagger0"; _TUN_LOCAL_ADDR=""; _TUN_REMOTE_ADDR=""
    _TUN_HEALTH_PORT="1234"; _TUN_MTU="1320"
    _TUN_PROFILE="icmp"; _TUN_LISTEN_IP=""; _TUN_DST_IP=""; _TUN_IFACE=""
    _TUN_ICMP_TYPE=""; _TUN_ICMP_CODE=""
    _TUN_SPOOF_SRC_IP=""; _TUN_SPOOF_DST_IP=""
_TUN_TARGET_IP=""         # remote tun IP (without /prefix) — used as port-forward target
    _TUN_PROTO58="false"; _TUN_PROTO58_SRC_IPV6=""; _TUN_PROTO58_DST_IPV6=""

    # ── TUN interface ─────────────────────────────────────────────────────────
    echo -e "  ${YELLOW}TUN Interface:${NC}"
    read -rp "  Device name              [dagger0]: " v || true; _TUN_NAME="${v:-dagger0}"

    local def_local def_remote
    if [[ "$SIDE" == "server" ]]; then
        def_local="10.10.10.1/24"; def_remote="10.10.10.2/24"
    else
        def_local="10.10.10.2/24"; def_remote="10.10.10.1/24"
    fi

    while true; do
        read -rp "  Local TUN addr   (e.g. ${def_local}): " v || true
        _TUN_LOCAL_ADDR="${v:-$def_local}"
        [[ "$_TUN_LOCAL_ADDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] && break
        warn "Invalid CIDR!"
    done
    while true; do
        read -rp "  Remote TUN addr  (e.g. ${def_remote}): " v || true
        _TUN_REMOTE_ADDR="${v:-$def_remote}"
        [[ "$_TUN_REMOTE_ADDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] && break
        warn "Invalid CIDR!"
    done
    # Extract just the IP part (strip /prefix) for use as port-forward target
    _TUN_TARGET_IP="${_TUN_REMOTE_ADDR%%/*}"
    read -rp "  MTU                      [1320]: " v || true; _TUN_MTU="${v:-1320}"
    echo ""

    # ── IPX Wire Profile ──────────────────────────────────────────────────────
    echo -e "  ${YELLOW}IPX Wire Profile:${NC}"
    echo -e "  ${WHITE}1)${NC} icmp  -- ICMP ${GREEN}(Recommended)${NC}"
    echo -e "  ${WHITE}2)${NC} gre   -- GRE (proto 47)"
    echo -e "  ${WHITE}3)${NC} ipip  -- IP-in-IP (proto 4)"
    echo -e "  ${WHITE}4)${NC} bip   -- IPv6+NH=58 (extreme stealth)"
    echo ""
    read -rp "  Choice [1]: " v || true
    case ${v:-1} in
        2) _TUN_PROFILE="gre"  ;;
        3) _TUN_PROFILE="ipip" ;;
        4) _TUN_PROFILE="bip"  ;;
        *) _TUN_PROFILE="icmp" ;;
    esac
    info "Profile: ${GREEN}${_TUN_PROFILE}${NC}"
    echo ""

    # ── Physical IPs ──────────────────────────────────────────────────────────
    while true; do
        if [[ "$SIDE" == "server" ]]; then
            read -rp "  Listen IP (this server)  (required): " v || true
        else
            read -rp "  Listen IP (this client)  (required): " v || true
        fi
        [[ -n "$v" ]] && { _TUN_LISTEN_IP="$v"; break; }
        warn "Required for pcap BPF filter!"
    done
    if [[ "$SIDE" == "client" && -n "$_TUN_DST_IP" ]]; then
        info "Dst IP (server): ${GREEN}${_TUN_DST_IP}${NC} (auto-filled from server address)"
    else
        while true; do
            if [[ "$SIDE" == "server" ]]; then
                read -rp "  Dst IP (client)          (required): " v || true
            else
                read -rp "  Dst IP (server)          (required): " v || true
            fi
            [[ -n "$v" ]] && { _TUN_DST_IP="$v"; break; }
            warn "Required!"
        done
    fi
    read -rp "  Network interface        [auto-detect]: " v || true; _TUN_IFACE="${v:-}"
    echo ""

    # ── Spoofing (optional) ───────────────────────────────────────────────────
    if _yn "Configure IP spoofing?" N; then
        read -rp "  Spoof source IP  [skip]: " v || true; _TUN_SPOOF_SRC_IP="${v:-}"
        read -rp "  Spoof dest IP    [skip]: " v || true; _TUN_SPOOF_DST_IP="${v:-}"
        [[ -n "$_TUN_SPOOF_SRC_IP" ]] && info "Spoof src: ${GREEN}${_TUN_SPOOF_SRC_IP}${NC}"
        [[ -n "$_TUN_SPOOF_DST_IP" ]] && info "Spoof dst: ${GREEN}${_TUN_SPOOF_DST_IP}${NC}"
    fi
    echo ""

    # ── Proto58 (optional) ────────────────────────────────────────────────────
    if _yn "Enable proto58 outer shell? (extra stealth)" N; then
        _TUN_PROTO58="true"
        read -rp "  proto58 src IPv6   [fe80::1]: " v || true; _TUN_PROTO58_SRC_IPV6="${v:-}"
        read -rp "  proto58 dst IPv6   [fe80::2]: " v || true; _TUN_PROTO58_DST_IPV6="${v:-}"
        info "Proto58: ${GREEN}enabled${NC}"
    fi
    echo ""
}

# ============================================================================
# PORT MAPPINGS
# ============================================================================

_validate_port() {
    local P=$1
    if ! [[ "$P" =~ ^[0-9]+$ ]] || [[ "$P" -lt 1 || "$P" -gt 65535 ]]; then
        err "Port '${P}' is invalid (must be 1-65535)."; return 1
    fi
    return 0
}

_do_add_mapping() {
    local BIND_P=$1 TARGET_ADDR=$2
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
    # For tunmux: forward to the remote TUN IP, not localhost
    local TARGET_IP="127.0.0.1"
    if [[ "$TRANSPORT" == "tunmux" && -n "$_TUN_TARGET_IP" ]]; then
        TARGET_IP="$_TUN_TARGET_IP"
    fi
    MAPPINGS=""
    local COUNT=0
    local PROTO="tcp"

    section "Port Mappings"
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
            _validate_port "$BS" || _valid=false
            _validate_port "$BE" || _valid=false
            _validate_port "$TS" || _valid=false
            _validate_port "$TE" || _valid=false
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
            _validate_port "$BS" || _valid=false
            _validate_port "$BE" || _valid=false
            _validate_port "$TS" || _valid=false
            _validate_port "$TE" || _valid=false
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
            _validate_port "$SP" || _valid=false
            _validate_port "$EP" || _valid=false
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
            _validate_port "$BPORT" || _valid=false
            _validate_port "$TPORT" || _valid=false
            [[ "$_valid" == "false" ]] && continue
            _do_add_mapping "${BPORT}" "${CTIP}:${TPORT}"
            ok "Added: ${BPORT} -> ${CTIP}:${TPORT} (${PROTO})"

        elif [[ "$PORT_INPUT" =~ ^([0-9]+)=([0-9]+)$ ]]; then
            local BPORT="${BASH_REMATCH[1]}" TPORT="${BASH_REMATCH[2]}"
            local _valid=true
            _validate_port "$BPORT" || _valid=false
            _validate_port "$TPORT" || _valid=false
            [[ "$_valid" == "false" ]] && continue
            _do_add_mapping "${BPORT}" "${TARGET_IP}:${TPORT}"
            ok "Added: ${BPORT} -> ${TPORT} (${PROTO})"

        elif [[ "$PORT_INPUT" =~ ^[0-9]+$ ]]; then
            if ! _validate_port "$PORT_INPUT"; then continue; fi
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
        MAPPINGS="  - type: tcp\n    bind: \"0.0.0.0:8080\"\n    target: \"${TARGET_IP}:8080\"\n"
    fi
}

# ============================================================================
# PRESET SELECTOR
# ============================================================================

select_preset() {
    echo "" >&2
    section "Connection Preset"
    echo -e "  ${WHITE}1)${NC} ${GREEN}Optimized${NC}    -- Balanced speed and stability ${DIM}(Recommended)${NC}" >&2
    echo -e "  ${WHITE}2)${NC} ${CYAN}High-Speed${NC}   -- Maximum throughput, aggressive KCP" >&2
    echo -e "  ${WHITE}3)${NC} ${BLUE}Stable${NC}       -- Conservative, tolerates high packet loss" >&2
    echo -e "  ${WHITE}4)${NC} ${YELLOW}Low-Latency${NC}  -- Minimum delay, for gaming / VoIP" >&2
    echo -e "  ${WHITE}5)${NC} ${DIM}Eco${NC}           -- Low CPU/memory, for weak VPS" >&2
    divider >&2; echo "" >&2
    read -rp "  Choice [1]: " v || true
    case ${v:-1} in
        2) PRESET_PROFILE="aggressive";    PRESET_HEARTBEAT=5  ;;
        3) PRESET_PROFILE="balanced";      PRESET_HEARTBEAT=15 ;;
        4) PRESET_PROFILE="gaming";        PRESET_HEARTBEAT=3  ;;
        5) PRESET_PROFILE="cpu-efficient"; PRESET_HEARTBEAT=20 ;;
        *) PRESET_PROFILE="latency";       PRESET_HEARTBEAT=8  ;;
    esac
}

write_preset_tail() {
    local FILE=$1 PROFILE=$2 HEARTBEAT=$3

    if [[ "$FILE" == *.json ]]; then
        python3 - "$FILE" << PEOF
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

cfg["obfuscation"] = {
    "enabled": False,
    "min_padding": 16,
    "max_padding": 512,
    "min_delay_ms": 0,
    "max_delay_ms": 0,
    "burst_chance": 0.15
}
cfg["http_mimic"] = {
    "fake_domain": "www.google.com",
    "fake_path": "/search",
    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "chunked_encoding": False,
    "session_cookie": True,
    "custom_headers": ["Accept-Language: en-US,en;q=0.9", "Accept-Encoding: gzip, deflate, br"]
}

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
PEOF
        return 0
    fi

    cat >> "$FILE" << EOF

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
# LOG SETTINGS
# ============================================================================

select_log_settings() {
    echo "" >&2
    section "Log Settings" >&2
    echo -e "  ${YELLOW}Log Level:${NC}" >&2
    echo -e "  ${WHITE}1)${NC} info   -- normal operational events ${GREEN}(Recommended)${NC}" >&2
    echo -e "  ${WHITE}2)${NC} warn   -- only warnings and errors" >&2
    echo -e "  ${WHITE}3)${NC} error  -- only errors" >&2
    echo -e "  ${WHITE}4)${NC} debug  -- all events (verbose, noisy)" >&2
    echo "" >&2
    read -rp "  Level [1]: " v || true
    case ${v:-1} in
        2) LOG_LEVEL="warn"  ;;
        3) LOG_LEVEL="error" ;;
        4) LOG_LEVEL="debug" ;;
        *) LOG_LEVEL="info"  ;;
    esac
}

# ============================================================================
# SSL CERT
# ============================================================================

gen_ssl_cert() {
    local CERT_OUT=$1 KEY_OUT=$2 DOMAIN=$3
    DOMAIN=$(echo "$DOMAIN" | tr -cd 'a-zA-Z0-9._-')
    [[ -z "$DOMAIN" ]] && DOMAIN="www.google.com"
    mkdir -p "$(dirname "$CERT_OUT")"; rm -f "$CERT_OUT" "$KEY_OUT"
    if openssl req -x509 -newkey rsa:4096 -keyout "$KEY_OUT" -out "$CERT_OUT" \
        -days 365 -nodes -subj "/C=US/O=MyCompany/CN=${DOMAIN}" 2>/dev/null; then
        ok "SSL certificate generated for: ${DOMAIN}"; return 0
    else
        err "SSL certificate generation failed."; rm -f "$CERT_OUT" "$KEY_OUT"; return 1
    fi
}

# ============================================================================
# SYSTEMD SERVICE
# ============================================================================

create_systemd_service() {
    local MODE=$1 INSTANCE_NAME=${2:-$MODE} CONFIG_PATH=${3:-"$CONFIG_DIR/${INSTANCE_NAME}.yaml"}
    local CAP="$(echo "${INSTANCE_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${INSTANCE_NAME:1}"
    mkdir -p "$SYSTEMD_DIR"
    cat > "$SYSTEMD_DIR/DaggerConnect-${INSTANCE_NAME}.service" << EOF
[Unit]
Description=DaggerConnect Reverse Tunnel -- ${CAP}
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$INSTALL_DIR/DaggerConnect -c ${CONFIG_PATH}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || \
        warn "daemon-reload failed -- may happen in containers."
    ok "Service created: DaggerConnect-${INSTANCE_NAME}"
}

# ============================================================================
# TRANSPORT-SPECIFIC CONFIG INJECTION (JSON merge via Python)
# ============================================================================

_inject_rawmux_json() {
    local FILE=$1
    python3 - "$FILE" << PEOF
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)
cfg["rawmux"] = {
    "handshake_timeout": $_RM_HS_TIMEOUT,
    "keepalive": $_RM_KEEPALIVE,
    "use_pcap": "$_RM_USE_PCAP" == "true"
}
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
PEOF
}

_inject_tunmux_json() {
    local FILE=$1 SIDE=$2
    python3 - "$FILE" "$SIDE" << PEOF
import json, sys
path, side = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)

# [tun] block
tun = {
    "encapsulation": "ipx",
    "name":          "$_TUN_NAME",
    "local_addr":    "$_TUN_LOCAL_ADDR",
    "remote_addr":   "$_TUN_REMOTE_ADDR",
    "health_port":   int("$_TUN_HEALTH_PORT") if "$_TUN_HEALTH_PORT" else 1234,
    "mtu":           int("$_TUN_MTU") if "$_TUN_MTU" else 1320,
}
cfg["tun"] = tun

# [ipx] block
ipx = {
    "mode":      side,
    "profile":   "$_TUN_PROFILE",
    "listen_ip": "$_TUN_LISTEN_IP",
    "dst_ip":    "$_TUN_DST_IP",
}
if "$_TUN_IFACE":        ipx["interface"]    = "$_TUN_IFACE"
if "$_TUN_ICMP_TYPE":    ipx["icmp_type"]    = int("$_TUN_ICMP_TYPE")
if "$_TUN_ICMP_CODE":    ipx["icmp_code"]    = int("$_TUN_ICMP_CODE")
if "$_TUN_SPOOF_SRC_IP": ipx["spoof_src_ip"] = "$_TUN_SPOOF_SRC_IP"
if "$_TUN_SPOOF_DST_IP": ipx["spoof_dst_ip"] = "$_TUN_SPOOF_DST_IP"
if "$_TUN_PROTO58" == "true":
    ipx["proto58"] = True
    if "$_TUN_PROTO58_SRC_IPV6": ipx["proto58_src_ipv6"] = "$_TUN_PROTO58_SRC_IPV6"
    if "$_TUN_PROTO58_DST_IPV6": ipx["proto58_dst_ipv6"] = "$_TUN_PROTO58_DST_IPV6"
cfg["ipx"] = ipx

with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
PEOF
}

_write_transport_extras() {
    local FILE=$1 SIDE=$2 TRANSPORT=$3
    if [[ "$FILE" == *.json ]]; then
        case "$TRANSPORT" in
            rawmux)     _inject_rawmux_json "$FILE" ;;
            tunmux)     _inject_tunmux_json "$FILE" "$SIDE" ;;
            quantummux) : ;; # written inline in install_server/install_client
        esac
        return 0
    fi
    # YAML fallback handled inline above; nothing to do here.
}

safe_start_enable() {
    local SERVICE=$1
    if [[ ! -f "$SYSTEMD_DIR/${SERVICE}.service" ]]; then
        err "Service file not found: $SYSTEMD_DIR/${SERVICE}.service"
        warn "Config saved. Start manually: systemctl start ${SERVICE}"; return 1
    fi
    systemctl start  "$SERVICE" 2>/dev/null || warn "Service start failed -- check: journalctl -u ${SERVICE} -n 50"
    systemctl enable "$SERVICE" 2>/dev/null || warn "Service enable failed."
}

check_port_available() {
    local PORT=$1 IN_USE=false
    if command -v ss &>/dev/null; then
        { ss -tlnp 2>/dev/null | grep -q ":${PORT} " || \
          ss -ulnp 2>/dev/null | grep -q ":${PORT} "; } && IN_USE=true || true
    elif command -v netstat &>/dev/null; then
        { netstat -tlnp 2>/dev/null | grep -q ":${PORT} " || \
          netstat -ulnp 2>/dev/null | grep -q ":${PORT} "; } && IN_USE=true || true
    fi
    if $IN_USE; then
        local OWN; OWN=$(ss -tlnp 2>/dev/null | grep ":${PORT} " | awk '{print $NF}' | head -1) || true
        warn "Port ${PORT} is in use! (${OWN:-unknown})"; return 1
    fi
    return 0
}

_instance_config() {
    local inst=$1
    if   [[ -f "$CONFIG_DIR/${inst}.yaml" ]]; then echo "$CONFIG_DIR/${inst}.yaml"
    elif [[ -f "$CONFIG_DIR/${inst}.json" ]]; then echo "$CONFIG_DIR/${inst}.json"
    else echo ""
    fi
}

_list_all_instances() {
    for f in "$SYSTEMD_DIR"/DaggerConnect-*.service; do
        [[ -f "$f" ]] || continue
        local n; n=$(basename "$f" .service); n="${n#DaggerConnect-}"
        [[ -n "$n" ]] && echo "$n"
    done
}

# ============================================================================
# INSTALL SERVER
# ============================================================================

install_server() {
    show_banner
    section "Server Setup"

    local INSTANCE_NAME
    INSTANCE_NAME=$(_pick_instance_name "server" "server")

    read -rp "  Tunnel port [2020]: " LISTEN_PORT || true
    LISTEN_PORT=${LISTEN_PORT:-2020}
    if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || \
       [[ "$LISTEN_PORT" -lt 1 || "$LISTEN_PORT" -gt 65535 ]]; then
        err "Invalid port. Using 2020."; LISTEN_PORT=2020
    fi

    if ! check_port_available "$LISTEN_PORT"; then
        read -rp "  Port busy. Use anyway? [y/N]: " frc || true
        [[ ! $frc =~ ^[Yy]$ ]] && install_server && return
    fi

    while true; do
        read -rsp "  PSK: " PSK || true; echo ""
        [[ -n "$PSK" ]] && break; err "PSK cannot be empty!"
    done

    TRANSPORT=$(select_transport)
    select_preset
    local PROFILE="$PRESET_PROFILE" HEARTBEAT="$PRESET_HEARTBEAT"
    select_log_settings
    local LOG_LVL="$LOG_LEVEL"

    local CFG_FORMAT="json"

    # Per-transport configuration prompts
    case "$TRANSPORT" in
        rawmux)     configure_rawmux ;;
        quantummux) configure_quantummux "server"; setup_quantummux_iptables "$LISTEN_PORT" ;;
        tunmux)     configure_tunmux "server" ;;
    esac

    build_port_mappings
    local AUTO_MAPPINGS="$MAPPINGS"
    CERT_FILE=""; KEY_FILE=""

    if [[ "$TRANSPORT" == "httpsmux" || "$TRANSPORT" == "wssmux" ]]; then
        read -rp "  Domain for SSL cert [www.google.com]: " CD || true; CD=${CD:-www.google.com}
        if gen_ssl_cert "$CONFIG_DIR/certs/${INSTANCE_NAME}_cert.pem" \
                        "$CONFIG_DIR/certs/${INSTANCE_NAME}_key.pem" "$CD"; then
            CERT_FILE="$CONFIG_DIR/certs/${INSTANCE_NAME}_cert.pem"
            KEY_FILE="$CONFIG_DIR/certs/${INSTANCE_NAME}_key.pem"
        fi
    fi

    local CONFIG_FILE="$CONFIG_DIR/${INSTANCE_NAME}.${CFG_FORMAT}"
    mkdir -p "$CONFIG_DIR"

    # Build MAPS JSON fragment from MAPPINGS string
    local MAPS_JSON="[]"
    if [[ -n "$AUTO_MAPPINGS" ]]; then
        MAPS_JSON=$(printf '%b' "$AUTO_MAPPINGS" | python3 -c '
import sys, json, re
items = []
for line in sys.stdin:
    line = line.strip()
    m = re.match(r"- type: (.+)", line)
    if m: cur={"type":m.group(1)}; items.append(cur)
    m = re.match(r"bind: \"(.+)\"", line)
    if m and items: items[-1]["bind"]=m.group(1)
    m = re.match(r"target: \"(.+)\"", line)
    if m and items: items[-1]["target"]=m.group(1)
print(json.dumps(items))
')
    fi

    # Emit base JSON config (mode, psk, profile, listener, quantummux if applicable)
    python3 - > "$CONFIG_FILE" << PEOF
import json

TRANSPORT     = "$TRANSPORT"
QM_SPOOF_IP   = "$_QM_SPOOF_SRC_IP"
QM_SPOOF_MAC  = "$_QM_SPOOF_SRC_MAC"
QM_CLI_SPOOF  = "$_QM_CLIENT_SPOOF_IP"
QM_CLI_REAL   = "$_QM_CLIENT_REAL_IP"

cfg = {
  "mode": "server",
  "psk": ${PSK@Q},
  "profile": "$PROFILE",
  "log_level": "$LOG_LVL",
  "heartbeat": $HEARTBEAT,
}
CERT = "$CERT_FILE"
KEY  = "$KEY_FILE"
if CERT:
    cfg["cert_file"] = CERT
    cfg["key_file"]  = KEY

listener = {
  "addr": "0.0.0.0:$LISTEN_PORT",
  "transport": TRANSPORT,
  "maps": $MAPS_JSON,
}
if CERT:
    listener["cert_file"] = CERT
    listener["key_file"]  = KEY

# Per-listener spoof passthrough (quantummux only — tunmux uses [ipx] block)
if TRANSPORT == "quantummux":
    if QM_CLI_SPOOF: listener["client_spoof_ip"] = QM_CLI_SPOOF
    if QM_CLI_REAL:  listener["client_real_ip"]  = QM_CLI_REAL

cfg["listeners"] = [listener]

# QuantumMux block (only emit fields that have values — spoof is fully optional)
if TRANSPORT == "quantummux":
    qm = {"data_shard": 10, "parity_shard": 1}
    if "$_QM_IFACE":    qm["interface"]  = "$_QM_IFACE"
    if "$_QM_LOCAL_IP": qm["local_ip"]   = "$_QM_LOCAL_IP"
    if QM_SPOOF_IP:     qm["spoof_src_ip"]    = QM_SPOOF_IP
    if QM_SPOOF_MAC:    qm["spoof_src_mac"]   = QM_SPOOF_MAC
    if QM_CLI_SPOOF:    qm["client_spoof_ip"] = QM_CLI_SPOOF
    if QM_CLI_REAL:     qm["client_real_ip"]  = QM_CLI_REAL
    qm["use_pcap"] = "$_QM_USE_PCAP" == "true"
    if "$_QM_MTU":
        try: qm["mtu"] = int("$_QM_MTU")
        except ValueError: pass
    if "$_QM_ICMPV6_MODE"  == "true": qm["icmpv6_mode"]  = True
    if "$_QM_NATURAL_SEND" == "true": qm["natural_send"] = True
    cfg["quantummux"] = qm

print(json.dumps(cfg, indent=2))
PEOF

    # Inject transport-specific blocks (tunmux/rawmux)
    _write_transport_extras "$CONFIG_FILE" "server" "$TRANSPORT"
    write_preset_tail "$CONFIG_FILE" "$PROFILE" "$HEARTBEAT"
    create_systemd_service "server" "$INSTANCE_NAME" "$CONFIG_FILE"

    read -rp "  Optimize system? [Y/n]: " v || true
    [[ ! $v =~ ^[Nn]$ ]] && optimize_system "iran" || true
    safe_start_enable "DaggerConnect-${INSTANCE_NAME}"

    echo ""; divider
    ok "Server '${INSTANCE_NAME}' configured!"
    info "Service:   ${GREEN}DaggerConnect-${INSTANCE_NAME}${NC}"
    info "Port:      ${GREEN}${LISTEN_PORT}${NC}"
    info "Transport: ${GREEN}${TRANSPORT}${NC}"
    [[ "$TRANSPORT" == "tunmux" ]] && info "Encap:     ${GREEN}${_TUN_ENCAP}${NC}"
    [[ "$TRANSPORT" == "tunmux" && "$_TUN_ENCAP" == "ipx" ]] && info "Profile:   ${GREEN}${_TUN_PROFILE}${NC}"
    [[ "$TRANSPORT" == "tunmux" && "$_TUN_PROTO58" == "true" ]] && info "Proto58:   ${GREEN}enabled${NC}"
    info "Preset:    ${GREEN}${PROFILE}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-${INSTANCE_NAME} -f"
    divider; press_enter; main_menu
}

# ============================================================================
# INSTALL CLIENT
# ============================================================================

install_client() {
    show_banner
    section "Client Setup"

    local INSTANCE_NAME
    INSTANCE_NAME=$(_pick_instance_name "client" "client")

    while true; do
        read -rsp "  PSK (must match server): " PSK || true; echo ""
        [[ -n "$PSK" ]] && break; err "PSK cannot be empty!"
    done

    TRANSPORT=$(select_transport)

    read -rp "  Server address:port [e.g., 1.2.3.4:2020]: " ADDR || true
    if [[ -z "$ADDR" || "$ADDR" != *:* ]]; then
        err "Address must be host:port format."; install_client; return
    fi
    # Extract the server host (strip port) — used to auto-fill tunmux dst_ip
    _TUN_DST_IP="${ADDR%%:*}"

    select_preset
    local PROFILE="$PRESET_PROFILE" HEARTBEAT="$PRESET_HEARTBEAT"

    case "$TRANSPORT" in
        rawmux)     configure_rawmux ;;
        quantummux) configure_quantummux "client" ;;
        tunmux)     configure_tunmux "client" ;;
    esac

    select_log_settings
    local LOG_LVL="$LOG_LEVEL"

    local CFG_FORMAT="json"
    # tunmux: point-to-point — no connection pool
    local POOL=3 AGGRESSIVE="true"
    [[ "$TRANSPORT" == "tunmux" ]] && POOL=1 && AGGRESSIVE="false"
    local CONFIG_FILE="$CONFIG_DIR/${INSTANCE_NAME}.${CFG_FORMAT}"
    mkdir -p "$CONFIG_DIR"

    python3 - > "$CONFIG_FILE" << PEOF
import json

TRANSPORT     = "$TRANSPORT"
QM_SPOOF_IP   = "$_QM_SPOOF_SRC_IP"
QM_SPOOF_MAC  = "$_QM_SPOOF_SRC_MAC"
QM_SRV_SPOOF  = "$_QM_SERVER_SPOOF_IP"

path_entry = {
  "transport": TRANSPORT,
  "addr": "$ADDR",
}
# connection_pool, aggressive_pool, retry_interval, dial_timeout
# are only relevant for non-tunmux transports
if TRANSPORT != "tunmux":
    path_entry["connection_pool"] = $POOL
    path_entry["aggressive_pool"] = $( [[ "$AGGRESSIVE" == "true" ]] && echo "True" || echo "False" )
    path_entry["retry_interval"]  = 1
    path_entry["dial_timeout"]    = 5
# Per-path server_spoof_ip (quantummux only — tunmux uses [ipx] block)
if TRANSPORT == "quantummux" and QM_SRV_SPOOF:
    path_entry["server_spoof_ip"] = QM_SRV_SPOOF

cfg = {
  "mode": "client",
  "psk": ${PSK@Q},
  "profile": "$PROFILE",
  "log_level": "$LOG_LVL",
  "heartbeat": $HEARTBEAT,
  "paths": [path_entry],
}

# QuantumMux block
if TRANSPORT == "quantummux":
    qm = {"data_shard": 10, "parity_shard": 1}
    if "$_QM_IFACE":      qm["interface"]   = "$_QM_IFACE"
    if "$_QM_LOCAL_IP":   qm["local_ip"]    = "$_QM_LOCAL_IP"
    if "$_QM_ROUTER_MAC": qm["router_mac"]  = "$_QM_ROUTER_MAC"
    if QM_SPOOF_IP:       qm["spoof_src_ip"]    = QM_SPOOF_IP
    if QM_SPOOF_MAC:      qm["spoof_src_mac"]   = QM_SPOOF_MAC
    if QM_SRV_SPOOF:      qm["server_spoof_ip"] = QM_SRV_SPOOF
    qm["use_pcap"] = "$_QM_USE_PCAP" == "true"
    if "$_QM_MTU":
        try: qm["mtu"] = int("$_QM_MTU")
        except ValueError: pass
    if "$_QM_ICMPV6_MODE"  == "true": qm["icmpv6_mode"]  = True
    if "$_QM_NATURAL_SEND" == "true": qm["natural_send"] = True
    cfg["quantummux"] = qm

print(json.dumps(cfg, indent=2))
PEOF

    # Inject tunmux/rawmux blocks (handles all the optional tunmux fields)
    _write_transport_extras "$CONFIG_FILE" "client" "$TRANSPORT"
    write_preset_tail "$CONFIG_FILE" "$PROFILE" "$HEARTBEAT"
    create_systemd_service "client" "$INSTANCE_NAME" "$CONFIG_FILE"

    safe_start_enable "DaggerConnect-${INSTANCE_NAME}"

    echo ""; divider
    ok "Client '${INSTANCE_NAME}' configured!"
    info "Service:   ${GREEN}DaggerConnect-${INSTANCE_NAME}${NC}"
    info "Server:    ${GREEN}${ADDR}${NC}"
    info "Transport: ${GREEN}${TRANSPORT}${NC}"
    [[ "$TRANSPORT" == "tunmux" ]] && info "Encap:     ${GREEN}${_TUN_ENCAP}${NC}"
    [[ "$TRANSPORT" == "tunmux" && "$_TUN_ENCAP" == "ipx" ]] && info "Profile:   ${GREEN}${_TUN_PROFILE}${NC}"
    [[ "$TRANSPORT" == "tunmux" && "$_TUN_PROTO58" == "true" ]] && info "Proto58:   ${GREEN}enabled${NC}"
    info "Preset:    ${GREEN}${PROFILE}${NC}"
    info "Config:    ${CONFIG_FILE}"
    info "Logs:      journalctl -u DaggerConnect-${INSTANCE_NAME} -f"
    divider; press_enter; main_menu
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
    local LATEST_VERSION=""
    if curl -s --connect-timeout 4 --max-time 6 "$LATEST_RELEASE_API" &>/dev/null; then
        LATEST_VERSION=$(curl -s --connect-timeout 4 --max-time 6 "$LATEST_RELEASE_API" \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    if [[ -n "$LATEST_VERSION" ]]; then
        info "Latest on GitHub: ${GREEN}${LATEST_VERSION}${NC}"
        if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
            ok "Already on the latest version."; read -rp "  Force re-download? [y/N]: " v || true
            [[ ! $v =~ ^[Yy]$ ]] && press_enter && main_menu && return
        fi
    else
        warn "GitHub unreachable -- will download from direct server."
    fi
    read -rp "  Continue with update? [y/N]: " v || true
    [[ ! $v =~ ^[Yy]$ ]] && main_menu && return
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
        read -rp "  Restart all services? [Y/n]: " v || true
        if [[ ! $v =~ ^[Nn]$ ]]; then
            while IFS= read -r inst; do
                systemctl is-enabled "DaggerConnect-${inst}" &>/dev/null && \
                    systemctl start "DaggerConnect-${inst}" && ok "Restarted: ${inst}" || true
            done < <(_list_all_instances)
        fi
    fi
    press_enter; main_menu
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

service_management() {
    local SERVICE_NAME; SERVICE_NAME=$(echo "$1" | tr -d '\r\n')
    local NAME="${SERVICE_NAME#DaggerConnect-}"
    local CONFIG_FILE; CONFIG_FILE=$(_instance_config "$NAME")
    [[ -z "$CONFIG_FILE" ]] && CONFIG_FILE="$CONFIG_DIR/${NAME}.json"

    while true; do
        show_banner
        section "Manage -- ${CYAN}DaggerConnect-${NAME}${NC}"
        if [[ -f "$CONFIG_FILE" ]]; then
            local M
            if [[ "$CONFIG_FILE" == *.json ]]; then
                M=$(python3 -c "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('mode',''))" 2>/dev/null || true)
            else
                M=$(grep '^mode:' "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"')
            fi
            [[ -n "$M" ]] && info "Type: ${WHITE}${M}${NC}" || true
        fi
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo -e "  Status:     ${GREEN}RUNNING${NC}"
        else
            echo -e "  Status:     ${RED}STOPPED${NC}"
        fi
        echo ""; divider
        echo -e "  ${WHITE}1)${NC} Start   ${WHITE}2)${NC} Stop    ${WHITE}3)${NC} Restart"
        echo -e "  ${WHITE}4)${NC} Status  ${WHITE}5)${NC} Logs    ${WHITE}6)${NC} Config  ${WHITE}7)${NC} Delete"
        echo -e "  ${WHITE}0)${NC} Back"
        divider; echo ""
        read -rp "  Select: " choice || true
        case $choice in
            1) systemctl start   "$SERVICE_NAME" 2>/dev/null || true; sleep 1 ;;
            2) systemctl stop    "$SERVICE_NAME" 2>/dev/null || true; sleep 1 ;;
            3) systemctl restart "$SERVICE_NAME" 2>/dev/null || true; sleep 1 ;;
            4) systemctl status  "$SERVICE_NAME" --no-pager || true; press_enter ;;
            5) journalctl -u "$SERVICE_NAME" -f --output=cat \
                   | sed -u 's/^[0-9]\{4\}\/[0-9]\{2\}\/[0-9]\{2\} //' \
                   || true ;;
            6) if [[ -f "$CONFIG_FILE" ]]; then
                   if [[ "$CONFIG_FILE" == *.json ]]; then python3 -m json.tool "$CONFIG_FILE"; else cat "$CONFIG_FILE"; fi
               else err "Config not found."; fi; press_enter ;;
            7)
                read -rp "  Delete '${NAME}'? [y/N]: " v || true
                if [[ $v =~ ^[Yy]$ ]]; then
                    systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
                    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
                    rm -f "$CONFIG_DIR/${NAME}.yaml" "$CONFIG_DIR/${NAME}.json" \
                          "$SYSTEMD_DIR/${SERVICE_NAME}.service"
                    systemctl daemon-reload 2>/dev/null || true
                    ok "Instance '${NAME}' deleted."; press_enter; return
                fi ;;
            0) return ;;
        esac
    done
}

# ============================================================================
# SETTINGS MENU
# ============================================================================

settings_menu() {
    show_banner
    section "Manage Instances"
    local INSTANCES=()
    while IFS= read -r inst; do [[ -n "$inst" ]] && INSTANCES+=("$inst"); done < <(_list_all_instances)

    if [[ ${#INSTANCES[@]} -eq 0 ]]; then
        err "No instances found."; info "Create a server or client first."
        press_enter; main_menu; return
    fi
    echo ""; echo -e "  ${DIM}Total: ${#INSTANCES[@]}${NC}"; echo ""
    local i=1
    for inst in "${INSTANCES[@]}"; do
        local SC="$RED" SI="o" M=""
        systemctl is-active --quiet "DaggerConnect-${inst}" 2>/dev/null && SC="$GREEN" && SI="*" || true
        local _CFG; _CFG=$(_instance_config "$inst")
        if [[ -n "$_CFG" ]]; then
            if [[ "$_CFG" == *.json ]]; then
                M=$(python3 -c "import json; d=json.load(open('$_CFG')); print(d.get('mode',''))" 2>/dev/null || true)
            else
                M=$(grep '^mode:' "$_CFG" | head -1 | awk '{print $2}' | tr -d '"')
            fi
        fi
        printf "  ${WHITE}%2d)${NC} ${SC}%s${NC} %-28s ${DIM}%s${NC}\n" "$i" "$SI" "DaggerConnect-${inst}" "${M:-unknown}"
        ((i++))
    done
    echo ""; echo -e "  ${WHITE} 0)${NC} Back"; divider; echo ""
    read -rp "  Select: " choice || true
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        (( choice == 0 )) && main_menu && return
        if (( choice >= 1 && choice <= ${#INSTANCES[@]} )); then
            service_management "DaggerConnect-${INSTANCES[$((choice-1))]}"
            settings_menu; return
        fi
    fi
    settings_menu
}

# ============================================================================
# UNINSTALL
# ============================================================================

uninstall_daggerconnect() {
    show_banner
    section "Uninstall DaggerConnect"
    warn "This will remove: binary, ALL configs, ALL services, certs, and optimizations."
    echo ""
    local INSTANCES=()
    while IFS= read -r inst; do [[ -n "$inst" ]] && INSTANCES+=("$inst"); done < <(_list_all_instances)
    if [[ ${#INSTANCES[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}Instances to be removed:${NC}"
        for inst in "${INSTANCES[@]}"; do echo -e "    ${DIM}- DaggerConnect-${inst}${NC}"; done
        echo ""
    fi
    read -rp "  Are you sure? [y/N]: " v || true
    [[ ! $v =~ ^[Yy]$ ]] && main_menu && return
    for inst in "${INSTANCES[@]}"; do
        systemctl stop    "DaggerConnect-${inst}" 2>/dev/null || true
        systemctl disable "DaggerConnect-${inst}" 2>/dev/null || true
        rm -f "$SYSTEMD_DIR/DaggerConnect-${inst}.service"
        ok "Removed: DaggerConnect-${inst}"
    done
    rm -f "$INSTALL_DIR/DaggerConnect"; rm -rf "$CONFIG_DIR"
    rm -f /etc/sysctl.d/99-daggerconnect.conf
    rm -f /etc/network/if-pre-up.d/quantummux-iptables
    rm -f /etc/network/if-pre-up.d/tunmux-iptables-*
    section "Cleaning iptables rules"
    if command -v iptables &>/dev/null; then
        while IFS= read -r r; do [[ -n "$r" ]] && iptables -t raw $r 2>/dev/null || true; done \
            < <(iptables -t raw -S 2>/dev/null | grep -E 'NOTRACK' | sed 's/^-A/-D/' || true)
        while IFS= read -r r; do [[ -n "$r" ]] && iptables -t mangle $r 2>/dev/null || true; done \
            < <(iptables -t mangle -S 2>/dev/null | grep -E 'RST.*DROP' | sed 's/^-A/-D/' || true)
        ok "iptables rules cleaned."
        if command -v iptables-save &>/dev/null && [[ -f /etc/iptables/rules.v4 ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
    fi
    sysctl -p > /dev/null 2>&1 || true
    systemctl daemon-reload 2>/dev/null || true
    ok "DaggerConnect uninstalled successfully."
    exit 0
}

# ============================================================================
# STATUS DASHBOARD
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
    echo ""; divider
    local INSTANCES=()
    while IFS= read -r inst; do [[ -n "$inst" ]] && INSTANCES+=("$inst"); done < <(_list_all_instances)
    if [[ ${#INSTANCES[@]} -eq 0 ]]; then
        echo ""; warn "No instances configured yet."
    else
        for inst in "${INSTANCES[@]}"; do
            local SVC="DaggerConnect-${inst}" CFG; CFG=$(_instance_config "$inst")
            echo ""; echo -e "  ${WHITE}-- ${CYAN}${inst}${NC} --"
            if systemctl is-active --quiet "$SVC" 2>/dev/null; then
                echo -e "  Status:     ${GREEN}RUNNING${NC}"
                local UP; UP=$(systemctl show "$SVC" --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
                [[ -n "$UP" ]] && echo -e "  Started:    ${DIM}${UP}${NC}" || true
                local MEM; MEM=$(systemctl show "$SVC" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)
                if [[ -n "$MEM" && "$MEM" != "18446744073709551615" && "$MEM" != "[not set]" ]]; then
                    echo -e "  Memory:     ${DIM}$((MEM / 1024 / 1024)) MB${NC}"
                fi
            elif systemctl is-enabled "$SVC" &>/dev/null; then
                echo -e "  Status:     ${RED}STOPPED${NC} ${YELLOW}(enabled but not running)${NC}"
            else
                echo -e "  Status:     ${DIM}Not enabled${NC}"
            fi
            if [[ -f "$CFG" ]]; then
                local M T PC LP
                if [[ "$CFG" == *.json ]]; then
                    M=$(python3  -c "import json,sys; d=json.load(open('$CFG')); print(d.get('mode',''))"  2>/dev/null || true)
                    T=$(python3  -c "import json,sys; d=json.load(open('$CFG')); l=d.get('listeners',d.get('paths',[])); print(l[0].get('transport','') if l else '')" 2>/dev/null || true)
                    PC=$(python3 -c "import json,sys; d=json.load(open('$CFG')); l=d.get('listeners',[]); print(sum(len(x.get('maps',[])) for x in l))" 2>/dev/null || echo 0)
                    LP=$(python3 -c "import json,sys; d=json.load(open('$CFG')); l=d.get('listeners',d.get('paths',[])); a=l[0].get('addr','') if l else ''; print(a.split(':')[-1])" 2>/dev/null || true)
                else
                    M=$(grep '^mode:'      "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
                    T=$(grep 'transport:'  "$CFG" | head -1 | awk '{print $2}' | tr -d '"')
                    PC=$(grep -c 'type:'   "$CFG" 2>/dev/null || echo 0)
                    LP=$(grep 'addr:'      "$CFG" | head -1 | awk '{print $2}' | tr -d '"' | cut -d: -f2)
                fi
                [[ -n "$M"  ]] && echo -e "  Mode:       ${DIM}${M}${NC}"  || true
                [[ -n "$T"  ]] && echo -e "  Transport:  ${DIM}${T}${NC}"  || true
                [[ -n "$LP" ]] && echo -e "  Port:       ${DIM}${LP}${NC}" || true
                [[ "$PC" -gt 0 ]] && echo -e "  Mappings:   ${DIM}${PC}${NC}" || true
            fi
        done
    fi
    echo ""; divider; echo ""
    echo -e "  ${WHITE}-- Network --${NC}"
    local IFACE; IFACE=$(ip link show | grep "state UP" | head -1 | awk '{print $2}' | cut -d: -f1)
    if [[ -n "$IFACE" ]]; then
        local RX TX
        RX=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
        TX=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)
        echo -e "  Interface:  ${DIM}${IFACE}${NC}"
        echo -e "  RX / TX:    ${DIM}$((RX/1024/1024)) MB / $((TX/1024/1024)) MB${NC}"
    fi
    local CC; CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    local CN; CN=$(ss -tn 2>/dev/null | grep -c ESTAB || echo 0)
    echo -e "  Connections:${DIM} ${CN} established${NC}"
    echo -e "  TCP CC:     ${DIM}${CC}${NC}"
    echo ""; divider; press_enter; main_menu
}

# ============================================================================
# FIRST RUN
# ============================================================================

first_run_check() {
    [[ -f "$FIRST_RUN_FLAG" ]] && return
    show_banner
    section "Initial Setup"
    echo -e "  ${WHITE}Download DaggerConnect core binary?${NC}"
    echo -e "  ${DIM}(Default: Yes)${NC}"; echo ""
    read -rp "  Proceed with download? [Y/n]: " ans || true
    if [[ $ans =~ ^[Nn]$ ]]; then
        mkdir -p "$CONFIG_DIR"; touch "$FIRST_RUN_FLAG"; return
    fi
    install_dependencies; download_binary
    mkdir -p "$CONFIG_DIR"; touch "$FIRST_RUN_FLAG"
    press_enter
}

# ============================================================================
# MAIN MENU
# ============================================================================

main_menu() {
    show_banner
    local CURRENT_VER; CURRENT_VER=$(get_current_version)
    [[ "$CURRENT_VER" != "not-installed" ]] && echo -e "  Version: ${GREEN}${CURRENT_VER}${NC}" && echo "" || true

    local RUNNING=0 TOTAL=0
    while IFS= read -r inst; do
        [[ -z "$inst" ]] && continue; TOTAL=$((TOTAL+1))
        systemctl is-active --quiet "DaggerConnect-${inst}" 2>/dev/null && RUNNING=$((RUNNING+1)) || true
    done < <(_list_all_instances)
    [[ "$TOTAL" -gt 0 ]] && echo -e "  Instances: ${GREEN}${RUNNING} running${NC} / ${WHITE}${TOTAL} total${NC}" && echo "" || true

    divider
    echo -e "  ${WHITE}1)${NC} Install / Configure Server"
    echo -e "  ${WHITE}2)${NC} Install / Configure Client"
    echo -e "  ${WHITE}3)${NC} Settings -- Manage Instances"
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
