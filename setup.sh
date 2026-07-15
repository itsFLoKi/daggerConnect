#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

BINARY="/usr/local/bin/DaggerConnect"
GITHUB_REPO="itsFLoKi/daggerConnect"
LATEST_RELEASE_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
CONFIG_DIR="/etc/DaggerConnect"
CONFIG=""
CONFIG_FMT=""
SERVICE_NAME=""
SERVICE_FILE=""
TRANSPORT=""
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

ask_transport() {
    echo ""
    echo -e "  ${BOLD}Available Transports:${NC}"
    echo "    1)  tcp     — Raw TCP tunnel"
    echo "    2)  ws      — WebSocket tunnel"
    echo "    3)  wss     — WebSocket Secure (TLS) tunnel"
    echo "    4)  http    — HTTP Mimicry tunnel"
    echo "    5)  https   — HTTP Mimicry Secure (TLS) tunnel"
    echo "    6)  quantum — QuantumMux raw-packet tunnel"
    echo "    7)  tun     — TUN kernel interface tunnel"
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
            7|tun)     TRANSPORT="tun";     break ;;
            *) warn "Please enter 1-7 or transport name." ;;
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

download_binary() {
    echo ""
    step "Checking for the latest DaggerConnect release ..."

    LATEST_VERSION=$(curl -fsSL "$LATEST_RELEASE_API" 2>/dev/null | grep '"tag_name":' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$LATEST_VERSION" ]; then
        warn "Could not reach GitHub to check the latest version."
        if [ -f "$BINARY" ]; then
            chmod +x "$BINARY"
            ok "Using existing local binary: ${BINARY}"
            return 0
        fi
        error "No local binary found and GitHub is unreachable. Cannot continue."
    fi

    info "Latest release: ${LATEST_VERSION}"

    CURRENT_VERSION=""
    if [ -f "$BINARY" ]; then
        chmod +x "$BINARY"
        CURRENT_VERSION=$("$BINARY" -v 2>&1 | grep -oE 'v?[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    fi

    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        ok "Already on the latest version (${CURRENT_VERSION})."
        return 0
    fi

    if [ -n "$CURRENT_VERSION" ]; then
        step "Updating DaggerConnect: ${CURRENT_VERSION} -> ${LATEST_VERSION} ..."
    else
        step "Downloading DaggerConnect ${LATEST_VERSION} ..."
    fi

    BINARY_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}/DaggerConnect"
    mkdir -p "$(dirname "$BINARY")"

    [ -f "$BINARY" ] && cp "$BINARY" "${BINARY}.backup"

    if curl -fL --progress-bar "$BINARY_URL" -o "${BINARY}.new"; then
        chmod +x "${BINARY}.new"
        if "${BINARY}.new" -v >/dev/null 2>&1; then
            mv -f "${BINARY}.new" "$BINARY"
            rm -f "${BINARY}.backup"
            ok "DaggerConnect updated to ${LATEST_VERSION}."

            mapfile -t SERVICES < <(list_services)
            if [ ${#SERVICES[@]} -gt 0 ]; then
                echo ""
                warn "Running services are still using the old binary in memory until restarted."
                ask RESTART_CHOICE "Restart all DaggerConnect services now? (y/n)" "y"
                if [ "$RESTART_CHOICE" = "y" ] || [ "$RESTART_CHOICE" = "Y" ]; then
                    for svc in "${SERVICES[@]}"; do
                        systemctl restart "$svc" && ok "Restarted: ${svc}" || warn "Failed to restart: ${svc}"
                    done
                fi
            fi
        else
            rm -f "${BINARY}.new"
            warn "Downloaded binary failed to run -- keeping the previous version."
            [ -f "${BINARY}.backup" ] && mv -f "${BINARY}.backup" "$BINARY"
        fi
    else
        rm -f "${BINARY}.new"
        warn "Download failed."
        if [ -f "${BINARY}.backup" ]; then
            mv -f "${BINARY}.backup" "$BINARY"
            warn "Keeping existing binary."
        elif [ -f "$BINARY" ]; then
            ok "Using existing binary: ${BINARY}"
        else
            error "No binary available and download failed. Cannot continue."
        fi
    fi
}

ask_ports() {
    echo ""
    echo -e "  Ports to forward. One per line, or comma-separated. Empty line when done."
    echo -e "        Example : 22                   (bind :22 -> target :22)"
    echo -e "        Example : 2222=22              (bind :2222 -> target :22)"
    echo -e "        Example : 800,3005,4155,6550   (multiple at once)"
    PORTS=()
    while true; do
        ask P "Port" ""
        [ -z "$P" ] && break
        IFS="," read -ra _parts <<< "$P"
        for _p in "${_parts[@]}"; do
            _p="${_p// /}"
            [ -n "$_p" ] && PORTS+=("$_p")
        done
    done
    if [ ${#PORTS[@]} -eq 0 ]; then
        warn "No ports defined. Adding default 2222=22."
        PORTS=("2222=22")
    fi
}

build_ports_json() {
    local first=1
    for p in "$@"; do
        if [ "$first" = "1" ]; then
            printf '    "%s"' "$p"
            first=0
        else
            printf ',
    "%s"' "$p"
        fi
    done
    echo ""
}

build_ports_yaml() {
    for p in "$@"; do
        printf '  - "%s"
' "$p"
    done
}

SOCKS5_ENABLED="false"
SOCKS5_BIND=""

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
            ADV_KEEPALIVE_SEC="5"        ADV_DEAD_TIMEOUT_SEC="25"
            ;;
        aggressive)
            ADV_TCP_READ_BUF="16777216"  ADV_TCP_WRITE_BUF="16777216"
            ADV_UDP_BUF="16777216"
            ADV_CHANNEL_BACKLOG="8192"   ADV_STREAM_CHAN_BUF="2048"
            ADV_TCP_KEEPALIVE="1"        ADV_CONN_TIMEOUT="60"
            ADV_SESSION_TIMEOUT="120"    ADV_CLEANUP_INTERVAL="5"
            ADV_KEEPALIVE_SEC="6"        ADV_DEAD_TIMEOUT_SEC="30"
            ;;
        low_latency)
            ADV_TCP_READ_BUF="2097152"   ADV_TCP_WRITE_BUF="2097152"
            ADV_UDP_BUF="2097152"
            ADV_CHANNEL_BACKLOG="2048"   ADV_STREAM_CHAN_BUF="256"
            ADV_TCP_KEEPALIVE="1"        ADV_CONN_TIMEOUT="15"
            ADV_SESSION_TIMEOUT="30"     ADV_CLEANUP_INTERVAL="2"
            ADV_KEEPALIVE_SEC="4"        ADV_DEAD_TIMEOUT_SEC="16"
            ;;
        low_hardware)
            ADV_TCP_READ_BUF="524288"    ADV_TCP_WRITE_BUF="524288"
            ADV_UDP_BUF="524288"
            ADV_CHANNEL_BACKLOG="512"    ADV_STREAM_CHAN_BUF="128"
            ADV_TCP_KEEPALIVE="5"        ADV_CONN_TIMEOUT="20"
            ADV_SESSION_TIMEOUT="45"     ADV_CLEANUP_INTERVAL="3"
            ADV_KEEPALIVE_SEC="8"        ADV_DEAD_TIMEOUT_SEC="40"
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
            echo -e "  ${BOLD}Heartbeat  (session-level keepalive, all transports except tun):${NC}"
            ask ADV_KEEPALIVE_SEC    "keepalive_sec       (sec)"    "5"
            ask ADV_DEAD_TIMEOUT_SEC "dead_timeout_sec    (sec)"    "25"
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
      "ports": [
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
    ports:
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
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
' "$psk" "$server_ip" "$server_port"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: tcp
psk: "%s"
log_level: info
paths:
  - transport: tcp
    addr: "%s:%s"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

' "$psk" "$server_ip" "$server_port"; build_advanced_yaml; } > "$CONFIG"
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
      "ports": [
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
    ports:
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
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "ws_settings": {
    "path": "%s"
  },
' "$psk" "$server_ip" "$server_port" "$ws_path"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: ws
psk: "%s"
log_level: info
paths:
  - transport: ws
    addr: "%s:%s"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

ws_settings:
  path: "%s"

' "$psk" "$server_ip" "$server_port" "$ws_path"; build_advanced_yaml; } > "$CONFIG"
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
      "ports": [
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
    ports:
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
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "ws_settings": {
    "path": "%s"
  },
  "tls_insecure": %s,
' "$psk" "$server_ip" "$server_port" "$ws_path" "$tls_insecure"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: wss
psk: "%s"
log_level: info
paths:
  - transport: wss
    addr: "%s:%s"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

ws_settings:
  path: "%s"

tls_insecure: %s

' "$psk" "$server_ip" "$server_port" "$ws_path" "$tls_insecure"; build_advanced_yaml; } > "$CONFIG"
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
      "ports": [
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
    ports:
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
      "ports": [
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
    ports:
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
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "http_settings": {
    "fake_domain": "%s",
    "path": "%s"
  },
  "tls_insecure": %s,
' "$psk" "$server_ip" "$server_port" "$http_domain" "$http_path" "$tls_insecure"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: https
psk: "%s"
log_level: info
paths:
  - transport: https
    addr: "%s:%s"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

http_settings:
  fake_domain: "%s"
  path: "%s"

tls_insecure: %s

' "$psk" "$server_ip" "$server_port" "$http_domain" "$http_path" "$tls_insecure"; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_quantum() {
    local port="$1" psk="$2" iface="$3" use_spoof="$4" spoof_src_ip="$5" client_spoof_ip="$6" client_real_ip="$7" use_dcpi="$8"
    shift 8
    local ports_json ports_yaml
    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {
            printf '{
'
            printf '  "mode": "server",
'
            printf '  "transport": "quantum",
'
            printf '  "psk": "%s",
'        "$psk"
            printf '  "log_level": "info",
'
            printf '  "listeners": [
'
            printf '    {
'
            printf '      "addr": "0.0.0.0:%s",
' "$port"
            printf '      "transport": "quantum",
'
            printf '      "ports": [
'
            printf '%s
'                    "$ports_json"
            printf '      ]
'
            printf '    }
'
            printf '  ],
'
            printf '  "qSettings": {
'
            [ -n "$iface" ]       && printf '    "interface": "%s",
'     "$iface"
            [ "$use_spoof" = "yes" ] && printf '    "dcpi_mode": false,
'
            [ "$use_spoof" = "yes" ] && [ -n "$spoof_src_ip"    ] && printf '    "spoof_src_ip": "%s",
'    "$spoof_src_ip"
            [ "$use_spoof" = "yes" ] && [ -n "$client_spoof_ip" ] && printf '    "client_spoof_ip": "%s",
' "$client_spoof_ip"
            [ "$use_spoof" = "yes" ] && [ -n "$client_real_ip"  ] && printf '    "client_real_ip": "%s",
'  "$client_real_ip"
            [ "$use_dcpi"  = "yes" ] && printf '    "dcpi_mode": true,
'
            printf '    "mtu": 1280,
'
            printf '    "data_shard": 10,
'
            printf '    "parity_shard": 1
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
            printf 'transport: quantum
'
            printf 'psk: "%s"
'          "$psk"
            printf 'log_level: info
'
            printf '
'
            printf 'listeners:
'
            printf '  - addr: "0.0.0.0:%s"
' "$port"
            printf '    transport: quantum
'
            printf '    ports:
'
            printf '%s
'                  "$ports_yaml"
            printf 'qSettings:
'
            [ -n "$iface" ]       && printf '  interface: "%s"
'     "$iface"
            [ "$use_spoof" = "yes" ] && printf '  dcpi_mode: false
'
            [ "$use_spoof" = "yes" ] && [ -n "$spoof_src_ip"    ] && printf '  spoof_src_ip: "%s"
'    "$spoof_src_ip"
            [ "$use_spoof" = "yes" ] && [ -n "$client_spoof_ip" ] && printf '  client_spoof_ip: "%s"
' "$client_spoof_ip"
            [ "$use_spoof" = "yes" ] && [ -n "$client_real_ip"  ] && printf '  client_real_ip: "%s"
'  "$client_real_ip"
            [ "$use_dcpi"  = "yes" ] && printf '  dcpi_mode: true
'
            printf '  mtu: 1280
'
            printf '  data_shard: 10
'
            printf '  parity_shard: 1
'
            printf '
'
            build_socks5_yaml
            build_advanced_yaml
        } > "$CONFIG"
    fi
}

write_client_config_quantum() {
    local server_ip="$1" server_port="$2" psk="$3" iface="$4" use_spoof="$5" spoof_src_ip="$6" server_spoof_ip="$7" use_dcpi="$8"
    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {
            printf '{
'
            printf '  "mode": "client",
'
            printf '  "transport": "quantum",
'
            printf '  "psk": "%s",
'        "$psk"
            printf '  "log_level": "info",
'
            printf '  "paths": [
'
            printf '    {
'
            printf '      "transport": "quantum",
'
            printf '      "addr": "%s:%s",
'  "$server_ip" "$server_port"
            printf '      "connection_pool": 2,
'
            printf '      "retry_interval": 3,
'
            printf '      "dial_timeout": 10
'
            printf '    }
'
            printf '  ],
'
            printf '  "qSettings": {
'
            [ -n "$iface" ]          && printf '    "interface": "%s",
'      "$iface"
            [ "$use_spoof" = "yes" ] && printf '    "dcpi_mode": false,
'
            [ "$use_spoof" = "yes" ] && [ -n "$spoof_src_ip"    ] && printf '    "spoof_src_ip": "%s",
'    "$spoof_src_ip"
            [ "$use_spoof" = "yes" ] && [ -n "$server_spoof_ip" ] && printf '    "server_spoof_ip": "%s",
' "$server_spoof_ip"
            [ "$use_dcpi"  = "yes" ] && printf '    "dcpi_mode": true,
'
            printf '    "mtu": 1280,
'
            printf '    "data_shard": 10,
'
            printf '    "parity_shard": 1
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
            printf 'transport: quantum
'
            printf 'psk: "%s"
'          "$psk"
            printf 'log_level: info
'
            printf '
'
            printf 'paths:
'
            printf '  - transport: quantum
'
            printf '    addr: "%s:%s"
'   "$server_ip" "$server_port"
            printf '    connection_pool: 2
'
            printf '    retry_interval: 3
'
            printf '    dial_timeout: 10
'
            printf '
'
            printf 'qSettings:
'
            [ -n "$iface" ]          && printf '  interface: "%s"
'      "$iface"
            [ "$use_spoof" = "yes" ] && printf '  dcpi_mode: false
'
            [ "$use_spoof" = "yes" ] && [ -n "$spoof_src_ip"    ] && printf '  spoof_src_ip: "%s"
'    "$spoof_src_ip"
            [ "$use_spoof" = "yes" ] && [ -n "$server_spoof_ip" ] && printf '  server_spoof_ip: "%s"
' "$server_spoof_ip"
            [ "$use_dcpi"  = "yes" ] && printf '  dcpi_mode: true
'
            printf '  mtu: 1280
'
            printf '  data_shard: 10
'
            printf '  parity_shard: 1
'
            printf '
'
            build_advanced_yaml
        } > "$CONFIG"
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
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "http_settings": {
    "fake_domain": "%s",
    "path": "%s"
  },
' "$psk" "$server_ip" "$server_port" "$http_domain" "$http_path"; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {         printf 'mode: client
transport: http
psk: "%s"
log_level: info
paths:
  - transport: http
    addr: "%s:%s"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

http_settings:
  fake_domain: "%s"
  path: "%s"

' "$psk" "$server_ip" "$server_port" "$http_domain" "$http_path"; build_advanced_yaml; } > "$CONFIG"
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
            printf '      "ports": [
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
            printf '    ports:
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
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=DaggerConnect Tunnel (${SERVICE_NAME})
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY} -c ${CONFIG}
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
    download_binary
    echo ""

    ask_service_name
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
            ask QM_IFACE "Network interface  (leave empty for auto-detect)" ""
            echo ""
            ask QM_SPOOF_CHOICE "Enable Spoof Mode (y/n)" "n"
            if [ "$QM_SPOOF_CHOICE" = "y" ] || [ "$QM_SPOOF_CHOICE" = "Y" ]; then
                echo ""
                ask QM_SPOOF_SRC    "Server Spoof IP  (spoof source IP, e.g. 1.2.3.4)" ""
                ask QM_CLIENT_SPOOF "Client Spoof IP  (expected client spoof IP, optional)" ""
                ask QM_CLIENT_REAL  "Client Real IP   (real client IP behind spoof, optional)" ""
                QM_USE_SPOOF="yes"
                QM_DCPI="no"
            else
                echo ""
                ask QM_DCPI_CHOICE "Enable DCPI Mode  (proto58) (y/n)" "n"
                QM_USE_SPOOF="no"
                QM_SPOOF_SRC="" QM_CLIENT_SPOOF="" QM_CLIENT_REAL=""
                if [ "$QM_DCPI_CHOICE" = "y" ] || [ "$QM_DCPI_CHOICE" = "Y" ]; then
                    QM_DCPI="yes"
                else
                    QM_DCPI="no"
                fi
            fi
            echo ""
            ;;
        tun)
            echo ""
            echo -e "  ${BOLD}TUN Encapsulation:${NC}"
            echo "    1)  tcp   — plain TCP over TUN"
            echo "    2)  ipx   — raw IP encapsulation (icmp/gre/ipip/bip)"
            echo ""
            ask TUN_ENCAP_CHOICE "Encapsulation" "1"
            case "$TUN_ENCAP_CHOICE" in
                2|ipx) TUN_ENCAP="ipx" ;;
                *)     TUN_ENCAP="tcp" ;;
            esac

            if [ "$TUN_ENCAP" = "ipx" ]; then
                echo ""
                echo -e "  ${BOLD}IPX Profile:${NC}"
                echo "    1)  icmp  — ICMP encapsulation"
                echo "    2)  gre   — GRE (proto 47)"
                echo "    3)  ipip  — IP-in-IP (proto 4)"
                echo "    4)  bip   — BIP/ICMP custom"
                echo ""
                ask TUN_PROFILE_CHOICE "Profile" "1"
                case "$TUN_PROFILE_CHOICE" in
                    2|gre)  TUN_PROFILE="gre"  ;;
                    3|ipip) TUN_PROFILE="ipip" ;;
                    4|bip)  TUN_PROFILE="bip"  ;;
                    *)      TUN_PROFILE="icmp" ;;
                esac
            else
                TUN_PROFILE="icmp"
            fi
            echo ""
            info "TUN : encapsulation=${TUN_ENCAP}  profile=${TUN_PROFILE}"
            echo ""
            _DEFAULT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
            ask TUN_LOCAL_IP "Server real IP" "${_DEFAULT_IP}"
            ask_required TUN_PEER_IP "Client real IP"
            echo ""
            ask_required TUN_LOCAL_ADDR  "TUN local IP   (server side, any IP, e.g. 10.0.0.1)"
            ask_required TUN_REMOTE_ADDR "TUN remote IP  (client side, any IP, e.g. 10.0.0.2)"
            # NOTE: entered as a bare IP, no /xx suffix needed or wanted --
            # tunIfaceCreate() strips any suffix you give it anyway and
            # always configures the interface as /32 point-to-point
            # internally, so writing "10.0.0.1/24" here would be actively
            # misleading (it's never actually used as a /24).
            TUN_LOCAL_ADDR="$(echo "$TUN_LOCAL_ADDR" | cut -d/ -f1)"
            TUN_REMOTE_ADDR="$(echo "$TUN_REMOTE_ADDR" | cut -d/ -f1)"
            echo ""
            ask TUN_IFACE "Network interface  (leave empty for auto-detect)" ""
            ask TUN_NAME  "TUN device name" "dagger0"
            echo ""
            ask TUN_HEARTBEAT_SEC    "Heartbeat interval (sec)  -- lower = faster failure detection" "5"
            ask TUN_IDLE_TIMEOUT_SEC "Idle timeout (sec)  -- how long with no traffic before reconnecting" "40"
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
        quantum) write_server_config_quantum "$PORT" "$PSK" "$QM_IFACE" "$QM_USE_SPOOF" "$QM_SPOOF_SRC" "$QM_CLIENT_SPOOF" "$QM_CLIENT_REAL" "$QM_DCPI" "${PORTS[@]}" ;;
        tun)     write_server_config_tun     "$PORT" "$PSK" "$TUN_LOCAL_IP" "$TUN_PEER_IP" "$TUN_LOCAL_ADDR" "$TUN_REMOTE_ADDR" "$TUN_ENCAP" "$TUN_PROFILE" "$TUN_IFACE" "$TUN_SPOOF_SRC" "$TUN_SPOOF_DST" "$TUN_DCPI" "$TUN_NAME" "$TUN_HEARTBEAT_SEC" "$TUN_IDLE_TIMEOUT_SEC" "${PORTS[@]}" ;;
    esac
    ok "Config written: ${CONFIG}"

    install_service
    start_service

    echo ""
    echo -e "${GREEN}${BOLD}  Server installed successfully.${NC}"
    echo ""
    echo -e "  Service   : ${BOLD}${SERVICE_NAME}${NC}"
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
        echo -e "  Interface : ${BOLD}$([ -n "$QM_IFACE" ] && echo "$QM_IFACE" || echo "auto-detect")${NC}"
        echo -e "  Mode      : ${BOLD}$([ "$QM_USE_SPOOF" = "yes" ] && echo "Spoof (TCP)" || echo "DCPI (proto58)")${NC}"
        [ "$QM_USE_SPOOF" = "yes" ] && [ -n "$QM_SPOOF_SRC" ] && echo -e "  Spoof IP  : ${BOLD}${QM_SPOOF_SRC}${NC}"
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
    download_binary
    echo ""

    ask_service_name
    echo ""

    ask_transport
    echo ""

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
            ask QM_IFACE "Network interface  (leave empty for auto-detect)" ""
            echo ""
            ask QM_SPOOF_CHOICE "Enable Spoof Mode (y/n)" "n"
            if [ "$QM_SPOOF_CHOICE" = "y" ] || [ "$QM_SPOOF_CHOICE" = "Y" ]; then
                echo ""
                ask QM_SPOOF_SRC    "Client Spoof IP  (spoof source IP on client, e.g. 5.6.7.8)" ""
                ask QM_SERVER_SPOOF "Server Spoof IP  (expected spoof IP from server, optional)" ""
                QM_USE_SPOOF="yes"
                QM_DCPI="no"
            else
                echo ""
                ask QM_DCPI_CHOICE "Enable DCPI Mode  (proto58) (y/n)" "n"
                QM_USE_SPOOF="no"
                QM_SPOOF_SRC="" QM_SERVER_SPOOF=""
                if [ "$QM_DCPI_CHOICE" = "y" ] || [ "$QM_DCPI_CHOICE" = "Y" ]; then
                    QM_DCPI="yes"
                else
                    QM_DCPI="no"
                fi
            fi
            echo ""
            ;;
        tun)
            echo ""
            echo -e "  ${BOLD}TUN Encapsulation (must match server):${NC}"
            echo "    1)  tcp   — plain TCP over TUN"
            echo "    2)  ipx   — raw IP encapsulation"
            echo ""
            ask TUN_ENCAP_CHOICE "Encapsulation" "1"
            case "$TUN_ENCAP_CHOICE" in
                2|ipx) TUN_ENCAP="ipx" ;;
                *)     TUN_ENCAP="tcp" ;;
            esac
            if [ "$TUN_ENCAP" = "ipx" ]; then
                echo ""
                echo -e "  ${BOLD}IPX Profile (must match server):${NC}"
                echo "    1)  icmp  2)  gre  3)  ipip  4)  bip"
                echo ""
                ask TUN_PROFILE_CHOICE "Profile" "1"
                case "$TUN_PROFILE_CHOICE" in
                    2|gre)  TUN_PROFILE="gre"  ;;
                    3|ipip) TUN_PROFILE="ipip" ;;
                    4|bip)  TUN_PROFILE="bip"  ;;
                    *)      TUN_PROFILE="icmp" ;;
                esac
            else
                TUN_PROFILE="icmp"
            fi
            echo ""
            _DEFAULT_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
            ask TUN_LOCAL_IP "Client real IP" "${_DEFAULT_IP}"
            ask_required TUN_PEER_IP "Server real IP"
            echo ""
            ask_required TUN_LOCAL_ADDR  "TUN local IP   (client side, any IP, e.g. 10.0.0.2)"
            ask_required TUN_REMOTE_ADDR "TUN remote IP  (server side, any IP, e.g. 10.0.0.1)"
            # NOTE: bare IP, no /xx suffix -- see the matching comment in
            # install_server, same reasoning applies here.
            TUN_LOCAL_ADDR="$(echo "$TUN_LOCAL_ADDR" | cut -d/ -f1)"
            TUN_REMOTE_ADDR="$(echo "$TUN_REMOTE_ADDR" | cut -d/ -f1)"
            echo ""
            ask TUN_IFACE "Network interface  (leave empty for auto-detect)" ""
            ask TUN_NAME  "TUN device name" "dagger0"
            echo ""
            ask TUN_HEARTBEAT_SEC    "Heartbeat interval (sec)  -- doesn't need to match the server, but similar values make sense" "5"
            ask TUN_IDLE_TIMEOUT_SEC "Idle timeout (sec)  -- how long with no traffic before reconnecting" "40"
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
        quantum) write_client_config_quantum "$SERVER_IP" "$SERVER_PORT" "$PSK" "$QM_IFACE" "$QM_USE_SPOOF" "$QM_SPOOF_SRC" "$QM_SERVER_SPOOF" "$QM_DCPI" ;;
        tun)     write_client_config_tun     "$SERVER_PORT" "$PSK" "$TUN_LOCAL_IP" "$TUN_PEER_IP" "$TUN_LOCAL_ADDR" "$TUN_REMOTE_ADDR" "$TUN_ENCAP" "$TUN_PROFILE" "$TUN_IFACE" "$TUN_SPOOF_SRC" "$TUN_SPOOF_DST" "$TUN_DCPI" "$TUN_NAME" "$TUN_HEARTBEAT_SEC" "$TUN_IDLE_TIMEOUT_SEC" ;;
    esac
    ok "Config written: ${CONFIG}"

    install_service
    start_service

    echo ""
    echo -e "${GREEN}${BOLD}  Client installed successfully.${NC}"
    echo ""
    echo -e "  Service   : ${BOLD}${SERVICE_NAME}${NC}"
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
        echo -e "  Interface : ${BOLD}$([ -n "$QM_IFACE" ] && echo "$QM_IFACE" || echo "auto-detect")${NC}"
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
    echo -e "  ${CYAN}${BOLD}DaggerConnect Installer - @DaggerConnect${NC}"
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
    echo "    9)  Update Core (Binary)"
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
        9) run_action download_binary ;;
        0) echo -e "\n  ${CYAN}Bye.${NC}\n"; exit 0 ;;
        *) warn "Invalid choice: ${CHOICE}" ;;
    esac

    pause
done