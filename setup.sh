#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

LAUNCHER="/usr/local/bin/DaggerLauncher"
CONFIG_DIR="/etc/DaggerConnect"
CONFIG=""
CONFIG_FMT=""
SERVICE_NAME=""
SERVICE_FILE=""
TRANSPORT=""
CHANNEL=""
VERSION=""
SERVER_PUBLIC_IP=""
SSL_MODE=""
DOMAIN=""
CERT_FILE=""
KEY_FILE=""

_ts()   { date '+%H:%M:%S'; }
info()  { echo -e "${DIM}$(_ts)${NC} ${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${DIM}$(_ts)${NC} ${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${DIM}$(_ts)${NC} ${YELLOW}[WARN]${NC}  $*"; }
step()  { echo -e "${DIM}$(_ts)${NC} ${MAGENTA}[STEP]${NC}  $*"; }

error() { echo -e "${DIM}$(_ts)${NC} ${RED}[ERR ]${NC}  $*"; exit 1; }
hr()    { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

ask() {
    local var="$1" prompt="$2" default="$3"
    if [ -n "$default" ]; then
        echo -ne "${YELLOW}?${NC} $prompt [${default}]: "
    else
        echo -ne "${YELLOW}?${NC} $prompt: "
    fi
    read -r input
    [ -z "$input" ] && [ -n "$default" ] && input="$default"
    eval "$var=\"$input\""
}

ask_required() {
    local var="$1" prompt="$2"
    while true; do
        ask "$var" "$prompt" ""
        eval "local val=\$$var"
        [ -n "$val" ] && break
        warn "This field cannot be empty."
    done
}

validate_label() {
    echo "$1" | grep -qE '^[A-Za-z0-9_-]+$'
}

ask_service_name() {
    local svc_name svc_file

    while true; do
        ask LABEL "Service Name    (e.g. iran1, client-home, relay01)" ""
        if [ -z "$LABEL" ]; then
            warn "Service Name cannot be empty."
            continue
        fi
        if ! validate_label "$LABEL"; then
            warn "Only letters, numbers, - and _ are allowed."
            continue
        fi

        svc_name="${LABEL}"
        svc_file="/etc/systemd/system/${svc_name}.service"

        if [ -f "$svc_file" ] || \
           [ -f "${CONFIG_DIR}/${svc_name}.json" ] || \
           [ -f "${CONFIG_DIR}/${svc_name}.yaml" ]; then
            echo ""
            warn "Already exists: ${svc_name}"
            ask OVERWRITE "Overwrite? (y/n)" "n"
            if [ "$OVERWRITE" = "y" ] || [ "$OVERWRITE" = "Y" ]; then
                break
            fi
            info "Enter a different service name."
            echo ""
            continue
        fi

        break
    done

    while true; do
        ask FMT "Config Format   (json/yaml)" "json"
        case "$FMT" in
            json|yaml) break ;;
            *) warn "Please enter json or yaml." ;;
        esac
    done

    CONFIG_FMT="$FMT"
    SERVICE_NAME="${LABEL}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    CONFIG="${CONFIG_DIR}/${SERVICE_NAME}.${CONFIG_FMT}"

    echo ""
    info "Service Name : ${SERVICE_NAME}"
    info "Config File  : ${CONFIG}"
}

detect_server_public_ip() {
    if [ -n "$DC_SERVER_PUBLIC_IP" ]; then
        echo "$DC_SERVER_PUBLIC_IP"
        return 0
    fi

    local ip svc
    for svc in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        ip=$(curl -fsSL --connect-timeout 5 --max-time 8 "$svc" 2>/dev/null | tr -d '[:space:]')
        if echo "$ip" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
            echo "$ip"
            return 0
        fi
    done

    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi

    return 1
}

ask_server_public_ip() {
    echo ""
    SERVER_PUBLIC_IP=$(detect_server_public_ip)
    if [ -z "$SERVER_PUBLIC_IP" ]; then
        error "Could not auto-detect this server's public IP (no route to the detection services, and no default route found). Set it manually and re-run: DC_SERVER_PUBLIC_IP=<your public IP> bash setup.sh"
    fi
    info "Public IP : ${SERVER_PUBLIC_IP}  (auto-detected)"
}

ask_transport() {
    echo ""
    echo -e "  ${BOLD}Available Transports:${NC}"
    echo "    1)  tcp     — Raw TCP tunnel"
    echo "    2)  ws      — WebSocket tunnel"
    echo "    3)  wss     — WebSocket Secure (TLS) tunnel"
    echo "    4)  http    — HTTP Mimicry tunnel"
    echo "    5)  https   — HTTP Mimicry Secure (TLS) tunnel"
    echo "    6)  quantum — Raw-packet tunnel"
    echo "    7)  quantum+ — KCP over UDP "
    echo "    8)  tun     — TUN kernel interface tunnel"
    echo ""
    while true; do
        ask T_CHOICE "Transport" "1"
        case "$T_CHOICE" in
            1|tcp)     TRANSPORT="tcp";     break ;;
            2|ws)      TRANSPORT="ws";      break ;;
            3|wss)     TRANSPORT="wss";     break ;;
            4|http)    TRANSPORT="http";    break ;;
            5|https)   TRANSPORT="https";   break ;;
            6|quantum) TRANSPORT="quantum"; break ;;
            7|quantum+|quantumplus|qplus) TRANSPORT="quantum+"; break ;;
            8|tun)     TRANSPORT="tun";     break ;;
            *) warn "Please enter 1-8 or transport name." ;;
        esac
    done
    info "Transport : ${TRANSPORT}"
}

install_certbot() {
    if command -v certbot &>/dev/null; then
        ok "certbot already installed."
        return
    fi
    info "Installing certbot..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq certbot
    elif command -v yum &>/dev/null; then
        yum install -y -q certbot
    elif command -v dnf &>/dev/null; then
        dnf install -y -q certbot
    else
        error "Cannot install certbot — package manager not found. Install it manually."
    fi
    ok "certbot installed."
}

obtain_cert_auto() {
    local domain="$1"
    local cert_dir="/etc/letsencrypt/live/${domain}"

    install_certbot

    if ss -tlnp 2>/dev/null | grep -q ':80 '; then
        warn "Port 80 is in use. Trying --webroot or stopping may be needed."
        warn "Attempting standalone anyway (will fail if 80 is busy)."
    fi

    info "Obtaining SSL certificate for: ${domain}"
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "$domain" \
        --http-01-port 80 2>&1 | grep -E "Congratulations|Certificate|error|Error|failed|Failed"; then
        ok "Certificate obtained successfully."
    else
        error "certbot failed. Make sure port 80 is open and domain points to this server."
    fi

    CERT_FILE="${cert_dir}/fullchain.pem"
    KEY_FILE="${cert_dir}/privkey.pem"

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        error "Certificate files not found at ${cert_dir}"
    fi

    ok "Cert : ${CERT_FILE}"
    ok "Key  : ${KEY_FILE}"

    local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
    mkdir -p "$hook_dir"
    cat > "${hook_dir}/daggerconnect-${SERVICE_NAME}.sh" << EOF
#!/bin/bash
systemctl restart ${SERVICE_NAME} 2>/dev/null || true
EOF
    chmod +x "${hook_dir}/daggerconnect-${SERVICE_NAME}.sh"
    ok "Auto-renew hook installed."
}

ask_ssl_server() {
    echo ""
    echo -e "  ${BOLD}SSL Mode:${NC}"
    echo "    1)  Automatic SSL  — Let's Encrypt (certbot)"
    echo "    2)  Custom SSL     — Provide your own cert/key paths"
    echo ""
    while true; do
        ask SSL_CHOICE "SSL Mode" "1"
        case "$SSL_CHOICE" in
            1|auto)   SSL_MODE="auto";   break ;;
            2|custom) SSL_MODE="custom"; break ;;
            *) warn "Please enter 1 (auto) or 2 (custom)." ;;
        esac
    done

    case "$SSL_MODE" in
        auto)
            echo ""
            ask_required DOMAIN "Domain name  (e.g. tunnel.example.com)"
            echo ""
            obtain_cert_auto "$DOMAIN"
            ;;
        custom)
            echo ""
            while true; do
                ask_required CERT_FILE "Certificate file path  (e.g. /etc/ssl/certs/cert.pem)"
                [ -f "$CERT_FILE" ] && break
                warn "File not found: ${CERT_FILE}"
            done
            while true; do
                ask_required KEY_FILE "Private key file path  (e.g. /etc/ssl/private/key.pem)"
                [ -f "$KEY_FILE" ] && break
                warn "File not found: ${KEY_FILE}"
            done
            echo ""
            ok "Cert : ${CERT_FILE}"
            ok "Key  : ${KEY_FILE}"
            ;;
    esac
}

ask_ssl_client() {
    echo ""
    echo -e "  ${BOLD}Server Certificate Verification:${NC}"
    echo "    1)  Verify  — Recommended (server has valid cert)"
    echo "    2)  Skip    — Skip TLS verification (self-signed)"
    echo ""
    while true; do
        ask TLS_CHOICE "TLS Verify" "1"
        case "$TLS_CHOICE" in
            1|verify) TLS_INSECURE="false"; break ;;
            2|skip)   TLS_INSECURE="true";  break ;;
            *) warn "Please enter 1 (verify) or 2 (skip)." ;;
        esac
    done
}

check_ptrace_scope() {
    local f=/proc/sys/kernel/yama/ptrace_scope
    [ -r "$f" ] || return 0
    local val
    val=$(cat "$f" 2>/dev/null)
    if [ "$val" = "0" ]; then
        echo ""
        warn "kernel.yama.ptrace_scope is 0 -- any same-user process can ptrace-attach and dump this binary from memory."
        echo -e "  ${DIM}Recommended: sysctl -w kernel.yama.ptrace_scope=2   (or 3, which needs a reboot to undo)${NC}"
        echo -e "  ${DIM}Persist across reboots: echo 'kernel.yama.ptrace_scope=2' >> /etc/sysctl.d/99-daggerconnect.conf${NC}"
    fi
}

# tune_network raises the kernel network limits that otherwise cap tunnel
# throughput and switches to the fq+BBR pair for the best goodput AND lowest
# latency. Applied immediately AND persisted across reboots. Idempotent and
# best-effort -- safe to run on every install. Mirrors the binary's built-in
# tuneHostNetwork() so bandwidth is high whether or not auto_tune is on.
tune_network() {
    hr "Network Tuning (fq + BBR, big buffers)"

    local sysctl_file="/etc/sysctl.d/99-daggerconnect-net.conf"
    step "Writing ${sysctl_file}"
    cat > "$sysctl_file" << 'EOF'
# DaggerConnect network tuning -- managed by setup.sh (safe to keep).
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 65536
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 8192
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.ipv4.udp_rmem_min = 131072
net.ipv4.udp_wmem_min = 131072
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF

    # BBR needs the tcp_bbr module -- load now and persist so it survives reboot.
    modprobe tcp_bbr 2>/dev/null || true
    if [ ! -f /etc/modules-load.d/daggerconnect-bbr.conf ]; then
        echo "tcp_bbr" > /etc/modules-load.d/daggerconnect-bbr.conf 2>/dev/null || true
    fi

    step "Applying now (sysctl)"
    if sysctl -p "$sysctl_file" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1; then
        ok "Applied and persisted (survives reboot)."
    else
        warn "Could not apply all sysctls now -- they will still take effect on next reboot."
    fi

    local cc qd
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    qd=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    info "Congestion control: ${BOLD}${cc:-unknown}${NC}   qdisc: ${BOLD}${qd:-unknown}${NC}"
    if [ "$cc" != "bbr" ]; then
        warn "BBR not active (kernel may lack tcp_bbr). Throughput tuning still applied; consider a newer kernel for BBR."
    fi
    echo ""
}

ensure_launcher() {
    local role="$1"
    if [ -f "$LAUNCHER" ]; then
        chmod +x "$LAUNCHER"
        return 0
    fi

    local github_url="https://github.com/itsFLoKi/daggerConnect/releases/download/v1.1/DaggerLauncher"

    info "Downloading DaggerLauncher..."
    if ! curl -fsSL --connect-timeout 10 --max-time 60 -o "$LAUNCHER" "$github_url"; then
        error "Failed to download DaggerLauncher -- check network/DNS, or place the binary at ${LAUNCHER} yourself (chmod +x) and re-run."
    fi
    chmod +x "$LAUNCHER"
    ok "DaggerLauncher downloaded"
}

update_launcher() {
    hr "Update Launcher"
    echo ""

    local github_url="https://github.com/itsFLoKi/daggerConnect/releases/latest/download/DaggerLauncher"
    local tmp
    tmp=$(mktemp "${LAUNCHER}.XXXXXX")

    step "Downloading latest DaggerLauncher from GitHub..."
    if ! curl -fsSL --connect-timeout 10 --max-time 60 -o "$tmp" "$github_url"; then
        rm -f "$tmp"
        error "Download failed -- check network/DNS. ${LAUNCHER} was left untouched."
    fi
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        error "Downloaded file is empty -- something is wrong with the release asset. ${LAUNCHER} was left untouched."
    fi

    chmod +x "$tmp"
    mv -f "$tmp" "$LAUNCHER"
    ok "DaggerLauncher updated : ${LAUNCHER}"

    mapfile -t SERVICES < <(list_services)
    local running=()
    for svc in "${SERVICES[@]}"; do
        systemctl is-active --quiet "$svc" && running+=("$svc")
    done

    if [ ${#running[@]} -eq 0 ]; then
        info "No running services to restart. The new launcher will be used the next time a service starts."
        return 0
    fi

    echo ""
    echo -e "  ${DIM}A running service keeps using the OLD launcher process in memory until${NC}"
    echo -e "  ${DIM}it restarts -- the file on disk alone isn't enough.${NC}"
    echo "    Currently running: ${running[*]}"
    echo ""
    ask RESTART_NOW "Restart these now so the update takes effect? (y/n)" "y"
    if [ "$RESTART_NOW" = "y" ] || [ "$RESTART_NOW" = "Y" ]; then
        for svc in "${running[@]}"; do
            step "Restarting ${svc} ..."
            systemctl restart "$svc"
            sleep 2
            if systemctl is-active --quiet "$svc"; then ok "Running."; else warn "Failed to start -- check: journalctl -u ${svc}"; fi
        done
    else
        warn "Not restarted -- the update won't take effect until you restart manually (menu option 4, or 'systemctl restart <service>')."
    fi
}

ask_version() {
    local role="$1"
    local cmd="/usr/local/bin/DaggerLauncher --list-versions --role ${role}"

    echo ""
    info "Fetching available versions..."

    local json
    json=$($cmd 2>/dev/null)

    local labels=() chans=() vers=()

    if [ -n "$json" ]; then
        local releases betas

        releases=$(echo "$json" | grep -oP '"release"\s*:\s*\[\K[^\]]*' | grep -oP '"[^"]*"' | tr -d '"')
        betas=$(echo "$json" | grep -oP '"beta"\s*:\s*\[\K[^\]]*' | grep -oP '"[^"]*"' | tr -d '"')

        while IFS= read -r t; do
            [ -z "$t" ] && continue
            labels+=("${t}  (release)")
            chans+=("release")
            vers+=("$t")
        done <<< "$releases"

        while IFS= read -r t; do
            [ -z "$t" ] && continue
            labels+=("${t}  (beta)")
            chans+=("beta")
            vers+=("$t")
        done <<< "$betas"
    fi

    if [ "${#labels[@]}" -eq 0 ]; then
        warn "Could not fetch a version list -- falling back to manual entry."
        ask_channel_manual
        return
    fi

    echo ""
    echo -e "  ${BOLD}Available versions:${NC}"

    local i=1
    for label in "${labels[@]}"; do
        echo "    ${i})  ${label}"
        i=$((i + 1))
    done

    echo ""

    while true; do
        ask VER_CHOICE "Pick a version" "1"

        if echo "$VER_CHOICE" | grep -qE '^[0-9]+$' \
            && [ "$VER_CHOICE" -ge 1 ] 2>/dev/null \
            && [ "$VER_CHOICE" -le "${#labels[@]}" ] 2>/dev/null; then

            local idx=$((VER_CHOICE - 1))

            CHANNEL="${chans[$idx]}"
            VERSION="${vers[$idx]}"

            break
        fi

        warn "Please enter a number between 1 and ${#labels[@]}."
    done

    info "Selected : ${VERSION} (${CHANNEL})"
}

ask_channel_manual() {
    echo ""
    echo -e "  ${BOLD}Release Channel:${NC}"
    echo "    1)  release  — Stable (recommended)"
    echo "    2)  beta     — Early access to new features, may be less stable"
    echo ""
    while true; do
        ask CH_CHOICE "Channel" "1"
        case "$CH_CHOICE" in
            1|release) CHANNEL="release"; break ;;
            2|beta)    CHANNEL="beta";    break ;;
            *) warn "Please enter 1 (release) or 2 (beta)." ;;
        esac
    done
    info "Channel : ${CHANNEL}"

    echo ""
    echo -e "  ${DIM}Pin a specific version (e.g. v3.3.1), or leave empty to always${NC}"
    echo -e "  ${DIM}track the newest version released on the '${CHANNEL}' channel.${NC}"
    while true; do
        ask VER_INPUT "Version  (empty = latest)" ""
        if [ -z "$VER_INPUT" ]; then
            VERSION="latest"
            break
        fi
        if echo "$VER_INPUT" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            VERSION="$VER_INPUT"
            break
        fi
        warn "Invalid format. Use vN.N.N (e.g. v3.3.1), or leave empty for latest."
    done
    info "Version : ${VERSION}"
}

switch_channel() {
    hr "Switch Release Channel / Version"
    echo ""
    pick_service "Switch channel for" || return 0
    local svc="${PICKED_SVC%.service}"
    local svc_file="/etc/systemd/system/${PICKED_SVC}"

    local cur_channel="release" cur_version="latest"
    if grep -q '^Environment=DC_CHANNEL=' "$svc_file" 2>/dev/null; then
        cur_channel=$(grep '^Environment=DC_CHANNEL=' "$svc_file" | head -1 | sed -E 's/^Environment=DC_CHANNEL=//')
    fi
    if grep -q '^Environment=DC_VERSION=' "$svc_file" 2>/dev/null; then
        cur_version=$(grep '^Environment=DC_VERSION=' "$svc_file" | head -1 | sed -E 's/^Environment=DC_VERSION=//')
    fi
    echo ""
    info "Current: channel=${cur_channel} version=${cur_version}"

    local svc_role=""
    for cfg_candidate in "${CONFIG_DIR}/${svc}.json" "${CONFIG_DIR}/${svc}.yaml"; do
        [ -f "$cfg_candidate" ] || continue
        if grep -qE '"mode"[[:space:]]*:[[:space:]]*"server"|^[[:space:]]*mode[[:space:]]*:[[:space:]]*server' "$cfg_candidate"; then
            svc_role="server"; break
        elif grep -qE '"mode"[[:space:]]*:[[:space:]]*"client"|^[[:space:]]*mode[[:space:]]*:[[:space:]]*client' "$cfg_candidate"; then
            svc_role="client"; break
        fi
    done

    if [ -n "$svc_role" ]; then
        ask_version "$svc_role"
    else
        warn "Could not determine whether '${svc}' is a server or client from its config -- falling back to manual entry."
        ask_channel_manual
    fi
    local new_channel="$CHANNEL" new_version="$VERSION"

    if [ "$new_channel" = "$cur_channel" ] && [ "$new_version" = "$cur_version" ]; then
        ok "Already on channel=${cur_channel} version=${cur_version}. Nothing to do."
        return 0
    fi

    set_unit_env() {
        local key="$1" val="$2"
        if grep -q "^Environment=${key}=" "$svc_file"; then
            sed -i "s|^Environment=${key}=.*|Environment=${key}=${val}|" "$svc_file"
        else
            sed -i "/^\[Service\]/a Environment=${key}=${val}" "$svc_file"
        fi
    }

    set_unit_env DC_CHANNEL "$new_channel"
    set_unit_env DC_VERSION "$new_version"
    systemctl daemon-reload

    step "Restarting ${svc} on channel=${new_channel} version=${new_version} ..."
    systemctl restart "$svc"
    sleep 2
    if systemctl is-active --quiet "$svc"; then
        ok "Now running on channel=${new_channel} version=${new_version}."
    else
        warn "Service failed to start on the new setting -- reverting. Logs:"
        journalctl -u "$svc" -n 20 --no-pager
        set_unit_env DC_CHANNEL "$cur_channel"
        set_unit_env DC_VERSION "$cur_version"
        systemctl daemon-reload
        systemctl restart "$svc"
    fi
}

ask_ports() {
    echo ""
    echo -e "  Ports to forward. One per line, or comma-separated. Empty line when done."
    echo -e "        Example : 22                   (bind :22 -> target :22)"
    echo -e "        Example : 2222=22              (bind :2222 -> target :22)"
    echo -e "        Example : 800,3005,4155,6550   (multiple at once, same type)"
    echo -e "  ${DIM}You'll be asked TCP or UDP for each line. Most things (websites, SSH, RDP) are TCP;${NC}"
    echo -e "  ${DIM}VPN-style tools (WireGuard, Cisco AnyConnect) are UDP.${NC}"
    PORTS=()
    while true; do
        ask P "Port" ""
        [ -z "$P" ] && break
        local ptype
        while true; do
            ask ptype "Type for '$P' - tcp or udp" "tcp"
            ptype="$(echo "$ptype" | tr '[:upper:]' '[:lower:]')"
            case "$ptype" in
                tcp|udp) break ;;
                *) warn "Please type 'tcp' or 'udp'." ;;
            esac
        done
        IFS="," read -ra _parts <<< "$P"
        for _p in "${_parts[@]}"; do
            _p="${_p// /}"
            [ -z "$_p" ] && continue
            if [[ "$_p" == */* ]]; then
                PORTS+=("$_p")
            else
                PORTS+=("${_p}/${ptype}")
            fi
        done
    done
    if [ ${#PORTS[@]} -eq 0 ]; then
        warn "No ports defined. Adding default 2222=22."
        PORTS=("2222=22")
    fi
}

parse_port_entry() {
    local entry="$1" ptype="tcp" pbind ptarget
    if [[ "$entry" == */* ]]; then
        ptype="${entry##*/}"
        entry="${entry%/*}"
        ptype="$(echo "$ptype" | tr '[:upper:]' '[:lower:]')"
        case "$ptype" in
            udp|both|any) ;;
            *) ptype="tcp" ;;
        esac
    fi
    if [[ "$entry" == *=* ]]; then
        pbind="${entry%%=*}"
        ptarget="${entry#*=}"
    else
        pbind="$entry"
        ptarget="$entry"
    fi
    echo "${ptype}|${pbind}|${ptarget}"
}

build_ports_json() {
    local first=1 p ptype pbind ptarget
    for p in "$@"; do
        IFS='|' read -r ptype pbind ptarget <<< "$(parse_port_entry "$p")"
        if [ "$first" = "1" ]; then
            printf '    { "type": "%s", "bind": "0.0.0.0:%s", "target": "127.0.0.1:%s" }' "$ptype" "$pbind" "$ptarget"
            first=0
        else
            printf ',
    { "type": "%s", "bind": "0.0.0.0:%s", "target": "127.0.0.1:%s" }' "$ptype" "$pbind" "$ptarget"
        fi
    done
    echo ""
}

build_ports_yaml() {
    local p ptype pbind ptarget
    for p in "$@"; do
        IFS='|' read -r ptype pbind ptarget <<< "$(parse_port_entry "$p")"
        printf '      - type: "%s"
        bind: "0.0.0.0:%s"
        target: "127.0.0.1:%s"
' "$ptype" "$pbind" "$ptarget"
    done
}

SOCKS5_ENABLED="false"
SOCKS5_BIND=""

CLIENT_CONN_POOL="8"

ask_connection_pool() {
    echo ""
    echo -e "  ${BOLD}Connection Pool:${NC}"
    echo -e "        Multiple parallel connections per path -- if one drops, the"
    echo -e "        others keep traffic flowing while it reconnects."
    echo ""
    ask CLIENT_CONN_POOL "Connections per path" "8"
}

ask_socks5() {
    echo ""
    echo -e "  ${BOLD}Standalone SOCKS5 Proxy:${NC}"
    echo -e "        Independent of the transport and port maps above — opens a local"
    echo -e "        SOCKS5 proxy on this server whose traffic is tunneled to the client."
    echo ""
    ask SOCKS5_CHOICE "Enable SOCKS5 proxy? (y/n)" "n"
    if [ "$SOCKS5_CHOICE" = "y" ] || [ "$SOCKS5_CHOICE" = "Y" ]; then
        SOCKS5_ENABLED="true"
        ask SOCKS5_BIND "SOCKS5 bind address  (keep on 127.0.0.1 unless you add auth)" "127.0.0.1:6060"
    else
        SOCKS5_ENABLED="false"
        SOCKS5_BIND=""
    fi
}

ADV_AUTO_TUNE="true"
ADV_PROFILE="auto"
ADV_TCP_KEEPALIVE="1"
ADV_CONN_TIMEOUT="30"
ADV_SESSION_TIMEOUT="60"
ADV_CLEANUP_INTERVAL="3"
ADV_TCP_READ_BUF="4194304"
ADV_TCP_WRITE_BUF="4194304"
ADV_UDP_BUF="4194304"
ADV_CHANNEL_BACKLOG="4096"
ADV_STREAM_CHAN_BUF="512"
ADV_KEEPALIVE_SEC="15"
ADV_DEAD_TIMEOUT_SEC="60"

apply_profile() {
    local p="$1"
    ADV_PROFILE="$p"
    case "$p" in
        stable)
            ADV_TCP_READ_BUF="4194304"   ADV_TCP_WRITE_BUF="4194304"
            ADV_UDP_BUF="4194304"
            ADV_CHANNEL_BACKLOG="4096"   ADV_STREAM_CHAN_BUF="512"
            ADV_TCP_KEEPALIVE="1"        ADV_CONN_TIMEOUT="30"
            ADV_SESSION_TIMEOUT="60"     ADV_CLEANUP_INTERVAL="3"
            ADV_KEEPALIVE_SEC="15"       ADV_DEAD_TIMEOUT_SEC="60"
            ;;
        aggressive)
            ADV_TCP_READ_BUF="16777216"  ADV_TCP_WRITE_BUF="16777216"
            ADV_UDP_BUF="16777216"
            ADV_CHANNEL_BACKLOG="8192"   ADV_STREAM_CHAN_BUF="2048"
            ADV_TCP_KEEPALIVE="1"        ADV_CONN_TIMEOUT="60"
            ADV_SESSION_TIMEOUT="120"    ADV_CLEANUP_INTERVAL="5"
            ADV_KEEPALIVE_SEC="20"       ADV_DEAD_TIMEOUT_SEC="80"
            ;;
        low_latency)
            ADV_TCP_READ_BUF="2097152"   ADV_TCP_WRITE_BUF="2097152"
            ADV_UDP_BUF="2097152"
            ADV_CHANNEL_BACKLOG="2048"   ADV_STREAM_CHAN_BUF="256"
            ADV_TCP_KEEPALIVE="1"        ADV_CONN_TIMEOUT="15"
            ADV_SESSION_TIMEOUT="30"     ADV_CLEANUP_INTERVAL="2"
            ADV_KEEPALIVE_SEC="10"       ADV_DEAD_TIMEOUT_SEC="30"
            ;;
        low_hardware)
            ADV_TCP_READ_BUF="524288"    ADV_TCP_WRITE_BUF="524288"
            ADV_UDP_BUF="524288"
            ADV_CHANNEL_BACKLOG="512"    ADV_STREAM_CHAN_BUF="128"
            ADV_TCP_KEEPALIVE="5"        ADV_CONN_TIMEOUT="20"
            ADV_SESSION_TIMEOUT="45"     ADV_CLEANUP_INTERVAL="3"
            ADV_KEEPALIVE_SEC="30"       ADV_DEAD_TIMEOUT_SEC="90"
            ;;
    esac
}

ask_advanced() {
    echo ""
    echo -e "  ${BOLD}Tuner Mode:${NC}"
    echo "    1)  auto         — Adaptive auto-tuner (recommended)"
    echo "    2)  stable       — Balanced, reliable for most setups"
    echo "    3)  aggressive   — Max throughput, high memory usage"
    echo "    4)  low_latency  — Minimum delay, small buffers"
    echo "    5)  low_hardware — Weak VPS / low RAM"
    echo "    6)  custom       — Set every value manually"
    echo ""
    ask ADV_CHOICE "Tuner Mode" "1"
    echo ""
    case "$ADV_CHOICE" in
        1|auto)
            ADV_AUTO_TUNE="true"
            apply_profile "stable"
            ;;
        2|stable)
            ADV_AUTO_TUNE="false"
            apply_profile "stable"
            ;;
        3|aggressive)
            ADV_AUTO_TUNE="false"
            apply_profile "aggressive"
            ;;
        4|low_latency)
            ADV_AUTO_TUNE="false"
            apply_profile "low_latency"
            ;;
        5|low_hardware)
            ADV_AUTO_TUNE="false"
            apply_profile "low_hardware"
            ;;
        6|custom)
            ADV_AUTO_TUNE="false"
            ADV_PROFILE="custom"
            echo -e "  ${BOLD}Timeouts & Intervals:${NC}"
            ask ADV_TCP_KEEPALIVE    "tcp_keepalive       (sec)"    "1"
            ask ADV_CONN_TIMEOUT     "connection_timeout  (sec)"    "30"
            ask ADV_SESSION_TIMEOUT  "session_timeout     (sec)"    "60"
            ask ADV_CLEANUP_INTERVAL "cleanup_interval    (sec)"    "3"
            echo ""
            echo -e "  ${BOLD}Heartbeat  (in-band session keepalive, all transports except tun):${NC}"
            echo -e "  ${DIM}Ping every keepalive_sec; tunnel is declared dead only after${NC}"
            echo -e "  ${DIM}dead_timeout_sec with zero inbound frames. Keep dead_timeout_sec${NC}"
            echo -e "  ${DIM}at least ~3x keepalive_sec so lost pings don't cause a false drop.${NC}"
            ask ADV_KEEPALIVE_SEC    "keepalive_sec       (sec)"    "15"
            ask ADV_DEAD_TIMEOUT_SEC "dead_timeout_sec    (sec)"    "60"
            echo ""
            echo -e "  ${BOLD}Buffers  (bytes, e.g. 4194304 = 4MB):${NC}"
            ask ADV_TCP_READ_BUF     "tcp_read_buffer     (bytes)"  "4194304"
            ask ADV_TCP_WRITE_BUF    "tcp_write_buffer    (bytes)"  "4194304"
            ask ADV_UDP_BUF          "udp_buffer_size     (bytes)"  "4194304"
            echo ""
            echo -e "  ${BOLD}Channel / Stream sizes:${NC}"
            ask ADV_CHANNEL_BACKLOG  "channel_backlog     (count)"  "4096"
            ask ADV_STREAM_CHAN_BUF  "stream_chan_buf     (count)"  "512"
            ;;
        *)
            ADV_AUTO_TUNE="true"
            apply_profile "stable"
            ;;
    esac
    info "Tuner Profile : ${ADV_PROFILE}$([ "$ADV_AUTO_TUNE" = "true" ] && echo " (adaptive)" || echo " (fixed)")"
}


build_advanced_json() {
    printf '  "advanced": {
'
    printf '    "auto_tune": %s,
'          "$ADV_AUTO_TUNE"
    printf '    "tcp_nodelay": true,
'
    printf '    "tcp_keepalive": %s,
'      "$ADV_TCP_KEEPALIVE"
    printf '    "connection_timeout": %s,
' "$ADV_CONN_TIMEOUT"
    printf '    "session_timeout": %s,
'    "$ADV_SESSION_TIMEOUT"
    printf '    "cleanup_interval": %s,
'   "$ADV_CLEANUP_INTERVAL"
    printf '    "tcp_read_buffer": %s,
'    "$ADV_TCP_READ_BUF"
    printf '    "tcp_write_buffer": %s,
'   "$ADV_TCP_WRITE_BUF"
    printf '    "udp_buffer_size": %s,
'    "$ADV_UDP_BUF"
    printf '    "channel_backlog": %s,
'    "$ADV_CHANNEL_BACKLOG"
    printf '    "stream_chan_buf": %s,
'      "$ADV_STREAM_CHAN_BUF"
    printf '    "keepalive_sec": %s,
'      "$ADV_KEEPALIVE_SEC"
    printf '    "dead_timeout_sec": %s
'   "$ADV_DEAD_TIMEOUT_SEC"
    printf '  }'
}

build_socks5_json() {
    printf '  "socks5": {
    "enabled": %s,
    "bind": "%s"
  },
' "$SOCKS5_ENABLED" "$SOCKS5_BIND"
}

build_socks5_yaml() {
    printf "socks5:
  enabled: %s
  bind: \"%s\"

" "$SOCKS5_ENABLED" "$SOCKS5_BIND"
}

build_advanced_yaml() {
    printf "advanced:
"
    printf "  auto_tune: %s
"          "$ADV_AUTO_TUNE"
    printf "  tcp_nodelay: true
"
    printf "  tcp_keepalive: %s
"      "$ADV_TCP_KEEPALIVE"
    printf "  connection_timeout: %s
" "$ADV_CONN_TIMEOUT"
    printf "  session_timeout: %s
"    "$ADV_SESSION_TIMEOUT"
    printf "  cleanup_interval: %s
"   "$ADV_CLEANUP_INTERVAL"
    printf "  tcp_read_buffer: %s
"    "$ADV_TCP_READ_BUF"
    printf "  tcp_write_buffer: %s
"   "$ADV_TCP_WRITE_BUF"
    printf "  udp_buffer_size: %s
"    "$ADV_UDP_BUF"
    printf "  channel_backlog: %s
"    "$ADV_CHANNEL_BACKLOG"
    printf "  stream_chan_buf: %s
"     "$ADV_STREAM_CHAN_BUF"
    printf "  keepalive_sec: %s
"     "$ADV_KEEPALIVE_SEC"
    printf "  dead_timeout_sec: %s
"  "$ADV_DEAD_TIMEOUT_SEC"
}

write_server_config_tcp() {
    local port="$1" psk="$2"
    shift 2
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "tcp",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "tcp",
      "maps": [
%s
      ]
    }
  ],
' "$psk" "$port" "$ports_json"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: tcp
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: tcp
    maps:
%s
' "$psk" "$port" "$ports_yaml"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_tcp() {
    local server_ip="$1" server_port="$2" psk="$3"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "tcp",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "tcp",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: tcp
psk: "%s"
log_level: info
paths:
  - transport: tcp
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_ws() {
    local port="$1" psk="$2" ws_path="$3"
    shift 3
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "ws",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "ws",
      "maps": [
%s
      ]
    }
  ],
  "ws_settings": {
    "path": "%s"
  },
' "$psk" "$port" "$ports_json" "$ws_path"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: ws
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: ws
    maps:
%s
ws_settings:
  path: "%s"

' "$psk" "$port" "$ports_yaml" "$ws_path"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_ws() {
    local server_ip="$1" server_port="$2" psk="$3" ws_path="$4"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "ws",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "ws",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "ws_settings": {
    "path": "%s"
  },
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: ws
psk: "%s"
log_level: info
paths:
  - transport: ws
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

ws_settings:
  path: "%s"

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_wss() {
    local port="$1" psk="$2" ws_path="$3" cert="$4" key="$5"
    shift 5
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "wss",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "wss",
      "cert_file": "%s",
      "key_file": "%s",
      "maps": [
%s
      ]
    }
  ],
  "ws_settings": {
    "path": "%s"
  },
' "$psk" "$port" "$cert" "$key" "$ports_json" "$ws_path"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: wss
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: wss
    cert_file: "%s"
    key_file: "%s"
    maps:
%s
ws_settings:
  path: "%s"

' "$psk" "$port" "$cert" "$key" "$ports_yaml" "$ws_path"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_wss() {
    local server_ip="$1" server_port="$2" psk="$3" ws_path="$4" tls_insecure="$5"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "wss",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "wss",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "ws_settings": {
    "path": "%s"
  },
  "tls_insecure": %s,
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path" "$tls_insecure"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: wss
psk: "%s"
log_level: info
paths:
  - transport: wss
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

ws_settings:
  path: "%s"

tls_insecure: %s

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path" "$tls_insecure"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_http() {
    local port="$1" psk="$2" http_domain="$3" http_path="$4"
    shift 4
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "http",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "http",
      "maps": [
%s
      ]
    }
  ],
  "http_settings": {
    "fake_domain": "%s",
    "path": "%s"
  },
' "$psk" "$port" "$ports_json" "$http_domain" "$http_path"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: http
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: http
    maps:
%s
http_settings:
  fake_domain: "%s"
  path: "%s"

' "$psk" "$port" "$ports_yaml" "$http_domain" "$http_path"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_https() {
    local port="$1" psk="$2" http_domain="$3" http_path="$4" cert="$5" key="$6"
    shift 6
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "https",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "https",
      "cert_file": "%s",
      "key_file": "%s",
      "maps": [
%s
      ]
    }
  ],
  "http_settings": {
    "fake_domain": "%s",
    "path": "%s"
  },
' "$psk" "$port" "$cert" "$key" "$ports_json" "$http_domain" "$http_path"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: https
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: https
    cert_file: "%s"
    key_file: "%s"
    maps:
%s
http_settings:
  fake_domain: "%s"
  path: "%s"

' "$psk" "$port" "$cert" "$key" "$ports_yaml" "$http_domain" "$http_path"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_https() {
    local server_ip="$1" server_port="$2" psk="$3" http_domain="$4" http_path="$5" tls_insecure="$6"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "https",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "https",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "http_settings": {
    "fake_domain": "%s",
    "path": "%s"
  },
  "tls_insecure": %s,
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path" "$tls_insecure"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: https
psk: "%s"
log_level: info
paths:
  - transport: https
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

http_settings:
  fake_domain: "%s"
  path: "%s"

tls_insecure: %s

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path" "$tls_insecure"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_quantum() {
    local port="$1" psk="$2" mtu="$3" block="$4"
    shift 4
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "quantum",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "quantum",
      "maps": [
%s
      ]
    }
  ],
  "quantum": {
    "mtu": %s,
    "block": "%s"
  },
' "$psk" "$port" "$ports_json" "$mtu" "$block"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: quantum
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: quantum
    maps:
%s
quantum:
  mtu: %s
  block: "%s"

' "$psk" "$port" "$ports_yaml" "$mtu" "$block"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_quantum() {
    local server_ip="$1" server_port="$2" psk="$3" mtu="$4" block="$5"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "quantum",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "quantum",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "quantum": {
    "mtu": %s,
    "block": "%s"
  },
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$mtu" "$block"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: quantum
psk: "%s"
log_level: info
paths:
  - transport: quantum
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

quantum:
  mtu: %s
  block: "%s"

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$mtu" "$block"; build_advanced_yaml; } > "$CONFIG"
    fi
}

# quantum+ (rawmux): KCP over UDP, dagMux core, FEC 10/1. Needs no extra
# block -- rawmux/kcp defaults are applied by the binary. Config shape is
# just like tcp but with transport "quantum+".
write_server_config_quantumplus() {
    local port="$1" psk="$2"
    shift 2
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "server",
  "transport": "quantum+",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "transport": "quantum+",
      "maps": [
%s
      ]
    }
  ],
' "$psk" "$port" "$ports_json"; build_socks5_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: server
transport: "quantum+"
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    transport: "quantum+"
    maps:
%s
' "$psk" "$port" "$ports_yaml"; build_socks5_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_quantumplus() {
    local server_ip="$1" server_port="$2" psk="$3"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "quantum+",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "quantum+",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: "quantum+"
psk: "%s"
log_level: info
paths:
  - transport: "quantum+"
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_http() {
    local server_ip="$1" server_port="$2" psk="$3" http_domain="$4" http_path="$5"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {         printf '{
  "mode": "client",
  "transport": "http",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "transport": "http",
      "addr": "%s:%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "http_settings": {
    "fake_domain": "%s",
    "path": "%s"
  },
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: http
psk: "%s"
log_level: info
paths:
  - transport: http
    addr: "%s:%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

http_settings:
  fake_domain: "%s"
  path: "%s"

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_tun() {
    local port="$1" psk="$2" listen_ip="$3" dst_ip="$4" local_addr="$5" remote_addr="$6"
    local encap="$7" profile="$8" iface="$9" spoof_src="${10}" spoof_dst="${11}" dcpi="${12}" tun_name="${13}"
    local heartbeat_sec="${14}" idle_timeout_sec="${15}"
    shift 15
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    [ -z "$tun_name" ] && tun_name="dagger0"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {
            printf '{
'
            printf '  "mode": "server",
'
            printf '  "transport": "tun",
'
            printf '  "psk": "%s",
'       "$psk"
            printf '  "log_level": "info",
'
            printf '  "listeners": [
'
            printf '    {
'
            printf '      "addr": "0.0.0.0:%s",\n' "$port"
            printf '      "transport": "tun",
'
            printf '      "maps": [
'
            printf '%s
'                   "$ports_json"
            printf '      ]
'
            printf '    }
'
            printf '  ],
'
            printf '  "tun": {
'
            printf '    "encapsulation": "%s",
' "$encap"
            printf '    "name": "%s",
'           "$tun_name"
            printf '    "local_addr": "%s",
'     "$local_addr"
            printf '    "remote_addr": "%s",
'    "$remote_addr"
            printf '    "mtu": 1420,
'
            printf '    "heartbeat_sec": %s,
' "$heartbeat_sec"
            printf '    "idle_timeout_sec": %s
' "$idle_timeout_sec"
            printf '  },
'
            printf '  "ipx": {
'
            printf '    "mode": "server",
'
            printf '    "profile": "%s",
'        "$profile"
            { [ "$profile" = "tcp" ] || [ "$profile" = "udp" ]; } && [ -n "$TUN_L4_PORT" ] && printf '    "l4_port": %s,
' "$TUN_L4_PORT"
            printf '    "listen_ip": "%s",
'      "$listen_ip"
            printf '    "dst_ip": "%s",
'         "$dst_ip"
            [ -n "$iface"     ] && printf '    "interface": "%s",
'   "$iface"
            [ "$dcpi" = "yes" ] && printf '    "dcpi_mode": true,
'
            [ -n "$spoof_src" ] && printf '    "spoof_src_ip": "%s",
' "$spoof_src"
            [ -n "$spoof_dst" ] && printf '    "spoof_dst_ip": "%s",
' "$spoof_dst"
            printf '    "sock_buf": 4194304
'
            printf '  },
'
            build_socks5_json
            build_advanced_json
            printf '}
'
        } > "$CONFIG"
    else
        {
            printf 'mode: server
'
            printf 'transport: tun
'
            printf 'psk: "%s"
'        "$psk"
            printf 'log_level: info
'
            printf 'listeners:
'
            printf '  - addr: "0.0.0.0:%s"\n' "$port"
            printf '    transport: tun
'
            printf '    maps:
'
            printf '%s
'               "$ports_yaml"
            printf 'tun:
'
            printf '  encapsulation: "%s"
' "$encap"
            printf '  name: "%s"
'          "$tun_name"
            printf '  local_addr: "%s"
'    "$local_addr"
            printf '  remote_addr: "%s"
'   "$remote_addr"
            printf '  mtu: 1420
'
            printf '  heartbeat_sec: %s
' "$heartbeat_sec"
            printf '  idle_timeout_sec: %s

' "$idle_timeout_sec"
            printf 'ipx:
'
            printf '  mode: server
'
            printf '  profile: "%s"
'       "$profile"
            { [ "$profile" = "tcp" ] || [ "$profile" = "udp" ]; } && [ -n "$TUN_L4_PORT" ] && printf '  l4_port: %s
' "$TUN_L4_PORT"
            printf '  listen_ip: "%s"
'     "$listen_ip"
            printf '  dst_ip: "%s"
'        "$dst_ip"
            [ -n "$iface"     ] && printf '  interface: "%s"
'   "$iface"
            [ "$dcpi" = "yes" ] && printf '  dcpi_mode: true
'
            [ -n "$spoof_src" ] && printf '  spoof_src_ip: "%s"
' "$spoof_src"
            [ -n "$spoof_dst" ] && printf '  spoof_dst_ip: "%s"
' "$spoof_dst"
            printf '  sock_buf: 4194304

'
            build_socks5_yaml
            build_advanced_yaml
        } > "$CONFIG"
    fi
}

write_client_config_tun() {
    local server_port="$1" psk="$2" listen_ip="$3" dst_ip="$4" local_addr="$5" remote_addr="$6"
    local encap="$7" profile="$8" iface="$9" spoof_src="${10}" spoof_dst="${11}" dcpi="${12}" tun_name="${13}"
    local heartbeat_sec="${14}" idle_timeout_sec="${15}"
    [ -z "$tun_name" ] && tun_name="dagger0"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {
            printf '{
'
            printf '  "mode": "client",
'
            printf '  "transport": "tun",
'
            printf '  "psk": "%s",
'        "$psk"
            printf '  "log_level": "info",
'
            printf '  "paths": [
'
            printf '    {
'
            printf '      "transport": "tun",
'
            printf '      "addr": "%s:%s",\n' "$dst_ip" "$server_port"

            printf '      "retry_interval": 3,
'
            printf '      "dial_timeout": 30
'
            printf '    }
'
            printf '  ],
'
            printf '  "tun": {
'
            printf '    "encapsulation": "%s",
' "$encap"
            printf '    "name": "%s",
'           "$tun_name"
            printf '    "local_addr": "%s",
'     "$local_addr"
            printf '    "remote_addr": "%s",
'    "$remote_addr"
            printf '    "mtu": 1420,
'
            printf '    "heartbeat_sec": %s,
' "$heartbeat_sec"
            printf '    "idle_timeout_sec": %s
' "$idle_timeout_sec"
            printf '  },
'
            printf '  "ipx": {
'
            printf '    "mode": "client",
'
            printf '    "profile": "%s",
'        "$profile"
            { [ "$profile" = "tcp" ] || [ "$profile" = "udp" ]; } && [ -n "$TUN_L4_PORT" ] && printf '    "l4_port": %s,
' "$TUN_L4_PORT"
            printf '    "listen_ip": "%s",
'      "$listen_ip"
            printf '    "dst_ip": "%s",
'         "$dst_ip"
            [ -n "$iface"     ] && printf '    "interface": "%s",
'   "$iface"
            [ "$dcpi" = "yes" ] && printf '    "dcpi_mode": true,
'
            [ -n "$spoof_src" ] && printf '    "spoof_src_ip": "%s",
' "$spoof_src"
            [ -n "$spoof_dst" ] && printf '    "spoof_dst_ip": "%s",
' "$spoof_dst"
            printf '    "sock_buf": 4194304
'
            printf '  },
'
            build_advanced_json
            printf '}
'
        } > "$CONFIG"
    else
        {
            printf 'mode: client
'
            printf 'transport: tun
'
            printf 'psk: "%s"
'         "$psk"
            printf 'log_level: info
'
            printf 'paths:
'
            printf '  - transport: tun
'
            printf '    addr: "%s:%s"\n' "$dst_ip" "$server_port"

            printf '    retry_interval: 3
'
            printf '    dial_timeout: 30

'
            printf 'tun:
'
            printf '  encapsulation: "%s"
' "$encap"
            printf '  name: "%s"
'          "$tun_name"
            printf '  local_addr: "%s"
'    "$local_addr"
            printf '  remote_addr: "%s"
'   "$remote_addr"
            printf '  mtu: 1420
'
            printf '  heartbeat_sec: %s
' "$heartbeat_sec"
            printf '  idle_timeout_sec: %s

' "$idle_timeout_sec"
            printf 'ipx:
'
            printf '  mode: client
'
            printf '  profile: "%s"
'       "$profile"
            { [ "$profile" = "tcp" ] || [ "$profile" = "udp" ]; } && [ -n "$TUN_L4_PORT" ] && printf '  l4_port: %s
' "$TUN_L4_PORT"
            printf '  listen_ip: "%s"
'     "$listen_ip"
            printf '  dst_ip: "%s"
'        "$dst_ip"
            [ -n "$iface"     ] && printf '  interface: "%s"
'   "$iface"
            [ "$dcpi" = "yes" ] && printf '  dcpi_mode: true
'
            [ -n "$spoof_src" ] && printf '  spoof_src_ip: "%s"
' "$spoof_src"
            [ -n "$spoof_dst" ] && printf '  spoof_dst_ip: "%s"
' "$spoof_dst"
            printf '  sock_buf: 4194304

'
            build_advanced_yaml
        } > "$CONFIG"
    fi
}

install_service() {
    local extra_env=""
    if [ -n "$SERVER_PUBLIC_IP" ]; then
        extra_env="Environment=DC_SERVER_PUBLIC_IP=${SERVER_PUBLIC_IP}"
    fi
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=DaggerConnect Tunnel (${SERVICE_NAME})
After=network.target
Wants=network-online.target

[Service]
Type=simple
Environment=DC_CHANNEL=${CHANNEL:-release}
Environment=DC_VERSION=${VERSION:-latest}
${extra_env}
ExecStart=${LAUNCHER} -c ${CONFIG}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=DaggerConnect

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" > /dev/null 2>&1
    ok "Service installed: ${SERVICE_NAME}"
}

start_service() {
    systemctl restart "$SERVICE_NAME"
    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        ok "Service is running."
    else
        warn "Service failed to start. Logs:"
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager
    fi
}

list_services() {
    local found=()
    for cfg in "${CONFIG_DIR}"/*.json "${CONFIG_DIR}"/*.yaml; do
        [ -f "$cfg" ] || continue
        local name
        name=$(basename "$cfg")
        name="${name%.*}"
        [ -f "/etc/systemd/system/${name}.service" ] && found+=("${name}.service")
    done
    [ ${#found[@]} -eq 0 ] && return 0
    printf '%s\n' "${found[@]}" | sort -u
}

install_server() {
    hr "Install Server"
    ensure_launcher server
    check_ptrace_scope
    tune_network
    echo ""

    ask_service_name
    echo ""

    CHANNEL="release"
    VERSION="latest"
    info "Version : ${VERSION} (${CHANNEL})"
    echo ""

    ask_server_public_ip
    echo ""

    ask_transport
    echo ""

    ask PORT "Listen port" "8443"
    echo ""

    ask_required PSK "PSK  (must match client)"
    echo ""

    case "$TRANSPORT" in
        ws|wss)
            ask WS_PATH "WebSocket path" "/ws"
            echo ""
            ;;
        http|https)
            ask HTTP_DOMAIN "Fake domain  (e.g. www.google.com)" "www.google.com"
            ask HTTP_PATH   "Fake path    (e.g. /search)" "/search"
            echo ""
            ;;
        quantum)
            echo -e "  ${DIM}Quantum auto-detects the network interface, source IP, and${NC}"
            echo -e "  ${DIM}gateway MAC at runtime — nothing to configure for those.${NC}"
            echo ""
            ask QM_MTU   "MTU" "1350"
            ask QM_BLOCK "KCP header cipher  (aes/salsa20/none)" "aes"
            echo ""
            ;;
        tun)
            echo ""
            echo -e "  ${BOLD}TUN Encapsulation (profile):${NC}"
            echo "    1)  tcp   — forged TCP segments"
            echo "    2)  udp   — forged UDP datagrams"
            echo "    3)  icmp  — ICMP encapsulation"
            echo "    4)  gre   — GRE   (proto 47)"
            echo "    5)  ipip  — IP-in-IP (proto 4)"
            echo "    6)  bip   — BIP/ICMP custom (raw IP_HDRINCL)"
            echo ""
            echo -e "  ${DIM}tcp/udp carry ports, so NAT/CGNAT and TCP-only firewalls pass them —${NC}"
            echo -e "  ${DIM}unlike gre/ipip which restrictive networks drop. Must match the other side.${NC}"
            echo ""
            ask TUN_PROFILE_CHOICE "Profile" "1"
            case "$TUN_PROFILE_CHOICE" in
                2|udp)  TUN_PROFILE="udp"  ;;
                3|icmp) TUN_PROFILE="icmp" ;;
                4|gre)  TUN_PROFILE="gre"  ;;
                5|ipip) TUN_PROFILE="ipip" ;;
                6|bip)  TUN_PROFILE="bip"  ;;
                *)      TUN_PROFILE="tcp"  ;;
            esac
            # 'encapsulation' is vestigial in the engine — 'profile' drives everything.
            TUN_ENCAP="ipx"
            TUN_L4_PORT=""
            if [ "$TUN_PROFILE" = "tcp" ] || [ "$TUN_PROFILE" = "udp" ]; then
                echo ""
                echo -e "  ${DIM}Service port = destination port of client→server frames.${NC}"
                echo -e "  ${DIM}443 looks like HTTPS and clears the most restrictive egress firewalls.${NC}"
                ask TUN_L4_PORT "L4 service port" "443"
            fi
            echo ""
            info "TUN : profile=${TUN_PROFILE}${TUN_L4_PORT:+  l4_port=${TUN_L4_PORT}}"
            echo ""
            _DEFAULT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
            ask TUN_LOCAL_IP "Server real IP" "${_DEFAULT_IP}"
            ask_required TUN_PEER_IP "Client real IP"
            echo ""
            ask_required TUN_LOCAL_ADDR  "TUN local IP   (server side, any IP, e.g. 10.0.0.1)"
            ask_required TUN_REMOTE_ADDR "TUN remote IP  (client side, any IP, e.g. 10.0.0.2)"
            TUN_LOCAL_ADDR="$(echo "$TUN_LOCAL_ADDR" | cut -d/ -f1)"
            TUN_REMOTE_ADDR="$(echo "$TUN_REMOTE_ADDR" | cut -d/ -f1)"
            echo ""
            ask TUN_IFACE "Network interface  (leave empty for auto-detect)" ""
            ask TUN_NAME  "TUN device name" "dagger0"
            echo ""
            ask TUN_HEARTBEAT_SEC    "Heartbeat interval (sec)  -- lower = faster failure detection" "5"
            ask TUN_IDLE_TIMEOUT_SEC "Idle timeout (sec)  -- how long with no traffic before reconnecting" "60"
            echo ""
            ask TUN_SPOOF_CHOICE "Enable IP Spoof (y/n)" "n"
            if [ "$TUN_SPOOF_CHOICE" = "y" ] || [ "$TUN_SPOOF_CHOICE" = "Y" ]; then
                ask TUN_SPOOF_SRC "Spoof Source IP" ""
                ask TUN_SPOOF_DST "Spoof Dest IP  " ""
            else
                TUN_SPOOF_SRC="" TUN_SPOOF_DST=""
            fi
            echo ""
            ask TUN_DCPI_CHOICE "Enable DCPI Mode  (ICMPv6/proto58) (y/n)" "n"
            [ "$TUN_DCPI_CHOICE" = "y" ] || [ "$TUN_DCPI_CHOICE" = "Y" ] && TUN_DCPI="yes" || TUN_DCPI="no"
            echo ""
            ;;
    esac

    if [ "$TRANSPORT" = "wss" ] || [ "$TRANSPORT" = "https" ]; then
        ask_ssl_server
        echo ""
    fi

    ask_ports
    echo ""

    ask_socks5
    echo ""

    ask_advanced
    echo ""

    case "$TRANSPORT" in
        tcp)     write_server_config_tcp     "$PORT" "$PSK" "${PORTS[@]}" ;;
        ws)      write_server_config_ws      "$PORT" "$PSK" "$WS_PATH" "${PORTS[@]}" ;;
        wss)     write_server_config_wss     "$PORT" "$PSK" "$WS_PATH" "$CERT_FILE" "$KEY_FILE" "${PORTS[@]}" ;;
        http)    write_server_config_http    "$PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" "${PORTS[@]}" ;;
        https)   write_server_config_https   "$PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" "$CERT_FILE" "$KEY_FILE" "${PORTS[@]}" ;;
        quantum) write_server_config_quantum "$PORT" "$PSK" "$QM_MTU" "$QM_BLOCK" "${PORTS[@]}" ;;
        quantum+) write_server_config_quantumplus "$PORT" "$PSK" "${PORTS[@]}" ;;
        tun)     write_server_config_tun     "$PORT" "$PSK" "$TUN_LOCAL_IP" "$TUN_PEER_IP" "$TUN_LOCAL_ADDR" "$TUN_REMOTE_ADDR" "$TUN_ENCAP" "$TUN_PROFILE" "$TUN_IFACE" "$TUN_SPOOF_SRC" "$TUN_SPOOF_DST" "$TUN_DCPI" "$TUN_NAME" "$TUN_HEARTBEAT_SEC" "$TUN_IDLE_TIMEOUT_SEC" "${PORTS[@]}" ;;
    esac
    ok "Config written: ${CONFIG}"

    install_service
    start_service

    echo ""
    echo -e "${GREEN}${BOLD}  Server installed successfully.${NC}"
    echo ""
    echo -e "  Service   : ${BOLD}${SERVICE_NAME}${NC}"
    echo -e "  Channel   : ${BOLD}${CHANNEL}${NC}"
    echo -e "  Version   : ${BOLD}${VERSION}${NC}"
    echo -e "  Public IP : ${BOLD}${SERVER_PUBLIC_IP}${NC}"
    echo -e "  Transport : ${BOLD}${TRANSPORT}${NC}"
    echo -e "  Port      : ${BOLD}${PORT}${NC}"
    echo -e "  PSK       : ${BOLD}${PSK}${NC}"
    [ "$TRANSPORT" = "ws"  ] && echo -e "  WS Path   : ${BOLD}${WS_PATH}${NC}"
    if [ "$TRANSPORT" = "wss" ]; then
        echo -e "  WS Path   : ${BOLD}${WS_PATH}${NC}"
        echo -e "  SSL Mode  : ${BOLD}${SSL_MODE}${NC}"
        [ "$SSL_MODE" = "auto" ] && echo -e "  Domain    : ${BOLD}${DOMAIN}${NC}"
        echo -e "  Cert      : ${BOLD}${CERT_FILE}${NC}"
        echo -e "  Key       : ${BOLD}${KEY_FILE}${NC}"
    fi
    if [ "$TRANSPORT" = "http" ]; then
        echo -e "  Fake Domain : ${BOLD}${HTTP_DOMAIN}${NC}"
        echo -e "  Fake Path   : ${BOLD}${HTTP_PATH}${NC}"
    fi
    if [ "$TRANSPORT" = "https" ]; then
        echo -e "  Fake Domain : ${BOLD}${HTTP_DOMAIN}${NC}"
        echo -e "  Fake Path   : ${BOLD}${HTTP_PATH}${NC}"
        echo -e "  SSL Mode    : ${BOLD}${SSL_MODE}${NC}"
        [ "$SSL_MODE" = "auto" ] && echo -e "  Domain      : ${BOLD}${DOMAIN}${NC}"
        echo -e "  Cert        : ${BOLD}${CERT_FILE}${NC}"
        echo -e "  Key         : ${BOLD}${KEY_FILE}${NC}"
    fi
    if [ "$TRANSPORT" = "quantum" ]; then
        echo -e "  Interface : ${BOLD}auto-detect${NC}"
        echo -e "  MTU       : ${BOLD}${QM_MTU}${NC}"
        echo -e "  Block     : ${BOLD}${QM_BLOCK}${NC}"
    fi
    if [ "$TRANSPORT" = "quantum+" ]; then
        echo -e "  Core      : ${BOLD}rawmux (dagMux, FEC 10/1)${NC}"
        echo -e "  ${YELLOW}Open UDP ${PORT} AND UDP $((PORT + 10000)) (knock port) in your firewall.${NC}"
    fi
    if [ "$TRANSPORT" = "tun" ]; then
        echo -e "  Encap     : ${BOLD}${TUN_ENCAP}${NC}"
        echo -e "  Profile   : ${BOLD}${TUN_PROFILE}${NC}"
        echo -e "  TUN Local : ${BOLD}${TUN_LOCAL_ADDR}${NC}"
        echo -e "  TUN Peer  : ${BOLD}${TUN_REMOTE_ADDR}${NC}"
        echo -e "  Wire IP   : ${BOLD}${TUN_LOCAL_IP} -> ${TUN_PEER_IP}${NC}"
        echo -e "  Device    : ${BOLD}${TUN_NAME}${NC}"
    fi
    if [ "$SOCKS5_ENABLED" = "true" ]; then
        echo -e "  SOCKS5    : ${BOLD}${SOCKS5_BIND}${NC}  (standalone, independent of maps)"
    fi
    echo -e "  Config    : ${BOLD}${CONFIG}${NC}"
    echo ""
    echo -e "  Logs      : journalctl -u ${SERVICE_NAME} -f"
    echo ""
}

install_client() {
    hr "Install Client"
    ensure_launcher client
    check_ptrace_scope
    tune_network
    echo ""

    ask_service_name
    echo ""

    CHANNEL="release"
    VERSION="latest"
    info "Version : ${VERSION} (${CHANNEL})"
    echo ""

    ask_transport
    echo ""

    if [ "$TRANSPORT" != "tun" ]; then
        ask_connection_pool
    fi

    while true; do
        echo -e "        Example : 1.1.1.1:8443"
        ask SERVER_ADDR "Server IP And Port" ""
        SERVER_IP="${SERVER_ADDR%%:*}"
        SERVER_PORT="${SERVER_ADDR##*:}"
        if [ -z "$SERVER_IP" ] || [ -z "$SERVER_PORT" ] || [ "$SERVER_IP" = "$SERVER_PORT" ]; then
            warn "Invalid format. Use IP:PORT (e.g. 1.1.1.1:8443)"
        else
            break
        fi
    done
    echo ""

    ask_required PSK "PSK  (must match server)"
    echo ""

    case "$TRANSPORT" in
        ws|wss)
            ask WS_PATH "WebSocket path  (must match server)" "/ws"
            echo ""
            ;;
        http|https)
            ask HTTP_DOMAIN "Fake domain  (must match server)" "www.google.com"
            ask HTTP_PATH   "Fake path    (must match server)" "/search"
            echo ""
            ;;
        quantum)
            echo -e "  ${DIM}Quantum auto-detects the network interface, source IP, and${NC}"
            echo -e "  ${DIM}gateway MAC at runtime — nothing to configure for those.${NC}"
            echo ""
            ask QM_MTU   "MTU" "1350"
            ask QM_BLOCK "KCP header cipher  (must match server, aes/salsa20/none)" "aes"
            echo ""
            ;;
        tun)
            echo ""
            echo -e "  ${BOLD}TUN Encapsulation / profile (must match server):${NC}"
            echo "    1)  tcp   2)  udp   3)  icmp   4)  gre   5)  ipip   6)  bip"
            echo ""
            ask TUN_PROFILE_CHOICE "Profile" "1"
            case "$TUN_PROFILE_CHOICE" in
                2|udp)  TUN_PROFILE="udp"  ;;
                3|icmp) TUN_PROFILE="icmp" ;;
                4|gre)  TUN_PROFILE="gre"  ;;
                5|ipip) TUN_PROFILE="ipip" ;;
                6|bip)  TUN_PROFILE="bip"  ;;
                *)      TUN_PROFILE="tcp"  ;;
            esac
            TUN_ENCAP="ipx"
            TUN_L4_PORT=""
            if [ "$TUN_PROFILE" = "tcp" ] || [ "$TUN_PROFILE" = "udp" ]; then
                echo ""
                echo -e "  ${DIM}L4 service port — must match the server's value exactly.${NC}"
                ask TUN_L4_PORT "L4 service port" "443"
            fi
            echo ""
            _DEFAULT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
            ask TUN_LOCAL_IP "Client real IP" "${_DEFAULT_IP}"
            ask_required TUN_PEER_IP "Server real IP"
            echo ""
            ask_required TUN_LOCAL_ADDR  "TUN local IP   (client side, any IP, e.g. 10.0.0.2)"
            ask_required TUN_REMOTE_ADDR "TUN remote IP  (server side, any IP, e.g. 10.0.0.1)"
            TUN_LOCAL_ADDR="$(echo "$TUN_LOCAL_ADDR" | cut -d/ -f1)"
            TUN_REMOTE_ADDR="$(echo "$TUN_REMOTE_ADDR" | cut -d/ -f1)"
            echo ""
            ask TUN_IFACE "Network interface  (leave empty for auto-detect)" ""
            ask TUN_NAME  "TUN device name" "dagger0"
            echo ""
            ask TUN_HEARTBEAT_SEC    "Heartbeat interval (sec)  -- doesn't need to match the server, but similar values make sense" "5"
            ask TUN_IDLE_TIMEOUT_SEC "Idle timeout (sec)  -- how long with no traffic before reconnecting" "60"
            echo ""
            ask TUN_SPOOF_CHOICE "Enable IP Spoof (y/n)" "n"
            if [ "$TUN_SPOOF_CHOICE" = "y" ] || [ "$TUN_SPOOF_CHOICE" = "Y" ]; then
                ask TUN_SPOOF_SRC "Spoof Source IP" ""
                ask TUN_SPOOF_DST "Spoof Dest IP  " ""
            else
                TUN_SPOOF_SRC="" TUN_SPOOF_DST=""
            fi
            echo ""
            ask TUN_DCPI_CHOICE "Enable DCPI Mode  (ICMPv6/proto58) (y/n)" "n"
            [ "$TUN_DCPI_CHOICE" = "y" ] || [ "$TUN_DCPI_CHOICE" = "Y" ] && TUN_DCPI="yes" || TUN_DCPI="no"
            echo ""
            ;;
    esac

    if [ "$TRANSPORT" = "wss" ] || [ "$TRANSPORT" = "https" ]; then
        ask_ssl_client
        echo ""
    fi

    ask_advanced
    echo ""

    case "$TRANSPORT" in
        tcp)     write_client_config_tcp     "$SERVER_IP" "$SERVER_PORT" "$PSK" ;;
        ws)      write_client_config_ws      "$SERVER_IP" "$SERVER_PORT" "$PSK" "$WS_PATH" ;;
        wss)     write_client_config_wss     "$SERVER_IP" "$SERVER_PORT" "$PSK" "$WS_PATH" "$TLS_INSECURE" ;;
        http)    write_client_config_http    "$SERVER_IP" "$SERVER_PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" ;;
        https)   write_client_config_https   "$SERVER_IP" "$SERVER_PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" "$TLS_INSECURE" ;;
        quantum) write_client_config_quantum "$SERVER_IP" "$SERVER_PORT" "$PSK" "$QM_MTU" "$QM_BLOCK" ;;
        quantum+) write_client_config_quantumplus "$SERVER_IP" "$SERVER_PORT" "$PSK" ;;
        tun)     write_client_config_tun     "$SERVER_PORT" "$PSK" "$TUN_LOCAL_IP" "$TUN_PEER_IP" "$TUN_LOCAL_ADDR" "$TUN_REMOTE_ADDR" "$TUN_ENCAP" "$TUN_PROFILE" "$TUN_IFACE" "$TUN_SPOOF_SRC" "$TUN_SPOOF_DST" "$TUN_DCPI" "$TUN_NAME" "$TUN_HEARTBEAT_SEC" "$TUN_IDLE_TIMEOUT_SEC" ;;
    esac
    ok "Config written: ${CONFIG}"

    install_service
    start_service

    echo ""
    echo -e "${GREEN}${BOLD}  Client installed successfully.${NC}"
    echo ""
    echo -e "  Service   : ${BOLD}${SERVICE_NAME}${NC}"
    echo -e "  Channel   : ${BOLD}${CHANNEL}${NC}"
    echo -e "  Version   : ${BOLD}${VERSION}${NC}"
    echo -e "  Transport : ${BOLD}${TRANSPORT}${NC}"
    echo -e "  Server    : ${BOLD}${SERVER_IP}:${SERVER_PORT}${NC}"
    echo -e "  PSK       : ${BOLD}${PSK}${NC}"
    [ "$TRANSPORT" = "ws"  ] && echo -e "  WS Path   : ${BOLD}${WS_PATH}${NC}"
    if [ "$TRANSPORT" = "wss" ]; then
        echo -e "  WS Path   : ${BOLD}${WS_PATH}${NC}"
        echo -e "  TLS Verify: ${BOLD}$([ "$TLS_INSECURE" = "true" ] && echo "Skipped" || echo "Enabled")${NC}"
    fi
    if [ "$TRANSPORT" = "http" ]; then
        echo -e "  Fake Domain : ${BOLD}${HTTP_DOMAIN}${NC}"
        echo -e "  Fake Path   : ${BOLD}${HTTP_PATH}${NC}"
    fi
    if [ "$TRANSPORT" = "https" ]; then
        echo -e "  Fake Domain : ${BOLD}${HTTP_DOMAIN}${NC}"
        echo -e "  Fake Path   : ${BOLD}${HTTP_PATH}${NC}"
        echo -e "  TLS Verify  : ${BOLD}$([ "$TLS_INSECURE" = "true" ] && echo "Skipped" || echo "Enabled")${NC}"
    fi
    if [ "$TRANSPORT" = "quantum" ]; then
        echo -e "  Interface : ${BOLD}auto-detect${NC}"
        echo -e "  MTU       : ${BOLD}${QM_MTU}${NC}"
        echo -e "  Block     : ${BOLD}${QM_BLOCK}${NC}"
    fi
    echo -e "  Config    : ${BOLD}${CONFIG}${NC}"
    echo ""
    echo -e "  Logs      : journalctl -u ${SERVICE_NAME} -f"
    echo ""
}

show_status() {
    hr "Service Status"
    echo ""

    mapfile -t SERVICES < <(list_services)

    if [ ${#SERVICES[@]} -eq 0 ]; then
        warn "No DaggerConnect services found."
        return
    fi

    for svc in "${SERVICES[@]}"; do
        echo -e "${BOLD}${svc}${NC}"
        systemctl status "$svc" --no-pager --lines=5 2>/dev/null || true
        echo ""
    done
}

show_logs() {
    hr "Logs"
    echo ""

    mapfile -t SERVICES < <(list_services)

    if [ ${#SERVICES[@]} -eq 0 ]; then
        warn "No DaggerConnect services found."
        return
    fi

    if [ ${#SERVICES[@]} -eq 1 ]; then
        TARGET="${SERVICES[0]}"
    else
        echo "Available services:"
        for i in "${!SERVICES[@]}"; do
            echo "  $((i+1)))  ${SERVICES[$i]}"
        done
        echo ""
        ask IDX "Select number" "1"
        TARGET="${SERVICES[$((IDX-1))]}"
    fi

    journalctl -u "$TARGET" -n 80 --no-pager
}

uninstall() {
    hr "Remove"
    echo ""

    mapfile -t SERVICES < <(list_services)

    if [ ${#SERVICES[@]} -eq 0 ]; then
        warn "No DaggerConnect services found."
        return
    fi

    echo "Installed services:"
    for i in "${!SERVICES[@]}"; do
        echo "  $((i+1)))  ${SERVICES[$i]}"
    done
    echo "  a)  Remove ALL"
    echo ""
    ask IDX "Select number (or a)" ""

    if [ "$IDX" = "a" ]; then
        TARGETS=("${SERVICES[@]}")
    else
        TARGETS=("${SERVICES[$((IDX-1))]}")
    fi

    echo ""
    warn "Will stop and remove: ${TARGETS[*]}"
    ask CONFIRM "Confirm? (yes/no)" "no"
    [ "$CONFIRM" != "yes" ] && { info "Cancelled."; return; }

    for svc in "${TARGETS[@]}"; do
        svc_name="${svc%.service}"
        systemctl stop    "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" 2>/dev/null || true
        rm -f "/etc/systemd/system/${svc_name}.service"
        cfg_json="${CONFIG_DIR}/${svc_name}.json"
        cfg_yaml="${CONFIG_DIR}/${svc_name}.yaml"
        [ -f "$cfg_json" ] && rm -f "$cfg_json" && ok "Removed config: ${cfg_json}"
        [ -f "$cfg_yaml" ] && rm -f "$cfg_yaml" && ok "Removed config: ${cfg_yaml}"
        rm -f "/etc/letsencrypt/renewal-hooks/deploy/daggerconnect-${svc_name}.sh" 2>/dev/null || true
        ok "Removed service: ${svc_name}"
    done

    systemctl daemon-reload
    [ -d "$CONFIG_DIR" ] && [ -z "$(ls -A "$CONFIG_DIR")" ] && rmdir "$CONFIG_DIR"
    ok "Done."
}

PICKED_SVC=""
pick_service() {
    PICKED_SVC=""
    local prompt="${1:-Select service}"
    mapfile -t SERVICES < <(list_services)

    if [ ${#SERVICES[@]} -eq 0 ]; then
        warn "No DaggerConnect services found."
        return 1
    fi

    if [ ${#SERVICES[@]} -eq 1 ]; then
        PICKED_SVC="${SERVICES[0]}"
        return 0
    fi

    echo -e "  ${BOLD}Available services:${NC}"
    for i in "${!SERVICES[@]}"; do
        local st="stopped"
        systemctl is-active --quiet "${SERVICES[$i]}" && st="${GREEN}running${NC}" || st="${RED}stopped${NC}"
        echo -e "    $((i+1)))  ${SERVICES[$i]}   [${st}]"
    done
    echo ""
    ask IDX "$prompt (number)" "1"
    if ! [[ "$IDX" =~ ^[0-9]+$ ]] || [ "$IDX" -lt 1 ] || [ "$IDX" -gt ${#SERVICES[@]} ]; then
        warn "Invalid selection."
        return 1
    fi
    PICKED_SVC="${SERVICES[$((IDX-1))]}"
    return 0
}

show_logs_live() {
    hr "Live Logs"
    echo ""
    pick_service "Follow logs for" || return 0
    info "Following ${PICKED_SVC} — press Ctrl+C to return to the menu."
    echo ""
    trap ' ' INT
    journalctl -u "$PICKED_SVC" -n 40 -f --no-pager
    trap - INT
    echo ""
    ok "Stopped following logs."
}

service_control() {
    hr "Service Control"
    echo ""
    pick_service "Manage" || return 0
    local svc="$PICKED_SVC"

    echo ""
    local st
    systemctl is-active --quiet "$svc" && st="${GREEN}running${NC}" || st="${RED}stopped${NC}"
    echo -e "  Selected : ${BOLD}${svc}${NC}   [${st}]"
    echo ""
    echo "  1)  Restart"
    echo "  2)  Stop"
    echo "  3)  Start"
    echo "  4)  Status"
    echo "  0)  Back"
    echo ""
    ask ACT "Action" "1"

    case "$ACT" in
        1)
            step "Restarting ${svc} ..."
            systemctl restart "$svc"
            sleep 2
            if systemctl is-active --quiet "$svc"; then ok "Running."; else warn "Failed to start — see logs."; fi
            ;;
        2)
            step "Stopping ${svc} ..."
            systemctl stop "$svc" && ok "Stopped." || warn "Could not stop."
            ;;
        3)
            step "Starting ${svc} ..."
            systemctl start "$svc"
            sleep 2
            if systemctl is-active --quiet "$svc"; then ok "Running."; else warn "Failed to start — see logs."; fi
            ;;
        4)
            systemctl status "$svc" --no-pager --lines=10 2>/dev/null || true
            ;;
        0|"") return 0 ;;
        *) warn "Invalid action." ;;
    esac
}

edit_config() {
    hr "Edit Config"
    echo ""
    pick_service "Edit config for" || return 0
    local svc="${PICKED_SVC%.service}"

    local cfg=""
    [ -f "${CONFIG_DIR}/${svc}.json" ] && cfg="${CONFIG_DIR}/${svc}.json"
    [ -f "${CONFIG_DIR}/${svc}.yaml" ] && cfg="${CONFIG_DIR}/${svc}.yaml"
    if [ -z "$cfg" ]; then
        warn "No config file found for ${svc}."
        return 0
    fi

    local ed="${EDITOR:-}"
    if [ -z "$ed" ]; then
        for cand in nano vim vi; do
            command -v "$cand" >/dev/null 2>&1 && { ed="$cand"; break; }
        done
    fi
    if [ -z "$ed" ]; then
        warn "No editor found (nano/vim/vi). Install one: apt install nano"
        return 0
    fi

    cp "$cfg" "${cfg}.bak" 2>/dev/null && info "Backup saved: ${cfg}.bak"
    info "Opening ${cfg} in ${ed} ..."
    "$ed" "$cfg"

    echo ""
    ask DORESTART "Restart the service to apply changes? (y/n)" "y"
    if [ "$DORESTART" = "y" ] || [ "$DORESTART" = "Y" ]; then
        step "Restarting ${svc} ..."
        systemctl restart "${svc}"
        sleep 2
        if systemctl is-active --quiet "${svc}"; then ok "Running with new config."; else
            warn "Service failed to start — config may be invalid."
            ask REVERT "Restore backup and restart? (y/n)" "y"
            if [ "$REVERT" = "y" ] || [ "$REVERT" = "Y" ]; then
                cp "${cfg}.bak" "$cfg" && systemctl restart "${svc}" && ok "Reverted to previous config."
            fi
        fi
    fi
}

show_banner() {
    echo ""
    echo -e "  ${CYAN}${BOLD}DaggerConnect Installer${NC}  -  @DaggerConnect"
    echo ""
}

show_menu() {
    echo -e "${BOLD}  Select an option:${NC}"
    echo ""
    echo -e "  ${BOLD}Install${NC}"
    echo "    1)  Install Server"
    echo "    2)  Install Client"
    echo ""
    echo -e "  ${BOLD}Manage${NC}"
    echo "    3)  Service Status"
    echo "    4)  Service Control  (restart / stop / start)"
    echo "    5)  Edit Config"
    echo ""
    echo -e "  ${BOLD}Logs${NC}"
    echo "    6)  View Logs        (last 80 lines)"
    echo "    7)  Live Logs        (follow)"
    echo ""
    echo -e "  ${BOLD}Other${NC}"
    echo "    8)  Remove"
    echo "    9)  Switch Release Channel  (release / beta + version)"
    echo "   10)  Update Launcher"
    echo "    0)  Exit"
    echo ""
    ask CHOICE "Choice" ""
}

run_action() {
    ( "$@" )
    return 0
}

pause() {
    echo ""
    echo -ne "${YELLOW}?${NC} Press Enter to return to the menu: "
    read -r _
}

[ "$EUID" -ne 0 ] && { echo -e "${RED}[ERR ]${NC}  Run as root: sudo bash setup.sh"; exit 1; }

while true; do
    clear 2>/dev/null || true
    show_banner
    show_menu

    case "$CHOICE" in
        1) run_action install_server ;;
        2) run_action install_client ;;
        3) run_action show_status     ;;
        4) run_action service_control ;;
        5) run_action edit_config     ;;
        6) run_action show_logs       ;;
        7) run_action show_logs_live  ;;
        8) run_action uninstall       ;;
        9) run_action switch_channel  ;;
        10) run_action update_launcher ;;
        0) echo -e "\n  ${CYAN}Bye.${NC}\n"; exit 0 ;;
        *) warn "Invalid choice: ${CHOICE}" ;;
    esac

    pause
done
