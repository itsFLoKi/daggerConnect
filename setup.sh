#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'
if [ ! -t 1 ] || [ "${TERM:-dumb}" = dumb ] || [ -n "${NO_COLOR+x}" ]; then
    RED='' GREEN='' YELLOW='' CYAN='' MAGENTA='' DIM='' BOLD='' NC=''
fi

LAUNCHER="/usr/local/bin/DaggerLauncher"
LAUNCHER_LATEST_URL="https://github.com/itsFLoKi/daggerConnect/releases/latest/download/DaggerLauncher"
CONFIG_DIR="/etc/DaggerConnect"
CONFIG=""
CONFIG_FMT=""
SERVICE_NAME=""
SERVICE_FILE=""
TRANSPORT=""
XHTTP_CDN="false"
XHTTP_CDN_HOST=""
XHTTP_CDN_PORT="443"
XHTTP_CDN_IPS=""
XHTTP_INSECURE="true"
XHTTP_ORIGIN_PORT="8443"
XHTTP_PEER_IP=""
XHTTP_PUBLIC_IP=""
XHTTP_CDN_POOL="6"
XHTTP_UP_MAX_BYTES="65536"
XHTTP_BUFFER_BYTES="32768"
XHTTP_PROBE_MS="8000"
XHTTP_SOCKET_BUF_BYTES="131072"
CHANNEL=""
VERSION=""
SERVER_PUBLIC_IP=""
SSL_MODE=""
DOMAIN=""
CERT_FILE=""
KEY_FILE=""

info()  { printf '  %s\n' "$*"; }
ok()    { printf '%b  OK%b  %s\n' "$GREEN" "$NC" "$*"; }
warn()  { printf '%b  !%b  %s\n' "$YELLOW" "$NC" "$*"; }
step()  { printf '\n%b  %s%b\n' "$BOLD" "$*" "$NC"; }

error() { printf '%b  Error:%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
hr()    { printf '\n%b  %s%b\n\n' "$BOLD" "$*" "$NC"; }

ensure_runtime_dependencies() {
    local missing=0 cmd
    for cmd in curl od cmp wc python3; do
        command -v "$cmd" >/dev/null 2>&1 || missing=1
    done
    [ "$missing" -eq 0 ] && return 0

    info "Installing launcher download and version-list dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq ca-certificates curl coreutils python3
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q ca-certificates curl coreutils python3
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q ca-certificates curl coreutils python3
    else
        error "Missing curl/coreutils/python3 and no supported package manager was found."
    fi
    for cmd in curl od cmp wc python3; do
        command -v "$cmd" >/dev/null 2>&1 || error "Required command is still missing after installation: ${cmd}"
    done
}

ask() {
    local var="$1" prompt="$2" default="$3" input
    while true; do
        if [ -n "$default" ]; then
            printf '%b  ?%b %s [%s]: ' "$CYAN" "$NC" "$prompt" "$default"
        else
            printf '%b  ?%b %s: ' "$CYAN" "$NC" "$prompt"
        fi
        if ! read -r input; then
            printf '\n' >&2
            exit 130
        fi
        [ -z "$input" ] && [ -n "$default" ] && input="$default"
        case "$prompt" in
            *'(y/n)'*)
                case "${input,,}" in
                    y|yes) input=y ;;
                    n|no) input=n ;;
                    *) warn "Enter y or n."; continue ;;
                esac ;;
            *'(yes/no)'*)
                case "${input,,}" in
                    yes) input=yes ;;
                    no) input=no ;;
                    *) warn "Enter yes or no."; continue ;;
                esac ;;
        esac
        break
    done
    printf -v "$var" '%s' "$input"
}

ask_required() {
    local var="$1" prompt="$2"
    while true; do
        ask "$var" "$prompt" ""
        [ -n "${!var}" ] && break
        warn "This field cannot be empty."
    done
}

validate_label() {
    echo "$1" | grep -qE '^[A-Za-z0-9_-]+$'
}

ask_service_name() {
    local svc_name svc_file

    while true; do
        ask LABEL "Service name" ""
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

    # The launcher reads JSON. The core still accepts existing YAML profiles.
    CONFIG_FMT="json"
    SERVICE_NAME="${LABEL}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    CONFIG="${CONFIG_DIR}/${SERVICE_NAME}.${CONFIG_FMT}"

    echo ""
    info "Service Name : ${SERVICE_NAME}"
    info "Config File  : ${CONFIG}"
}

detect_server_public_ip() {
    if [ -n "$DC_SERVER_PUBLIC_IP" ] && validate_public_ip "$DC_SERVER_PUBLIC_IP"; then
        echo "$DC_SERVER_PUBLIC_IP"
        return 0
    fi

    # Kernel route lookup only; this does not send a packet or query a website.
    local ip
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="src") {print $(i+1); exit}}')
    if validate_public_ip "$ip"; then
        echo "$ip"
        return 0
    fi

    return 1
}

validate_ip() {
    local value="$1" part
    [[ "$value" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    local -a octets
    IFS=. read -r -a octets <<< "$value"
    for part in "${octets[@]}"; do
        [[ "$part" = "0" || "$part" != 0* ]] || return 1
        (( 10#$part <= 255 )) || return 1
    done
}

validate_public_ip() {
    validate_ip "$1" || return 1
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    (( a > 0 && a < 224 && a != 10 && a != 127 )) || return 1
    (( a != 100 || b < 64 || b > 127 )) || return 1
    (( a != 169 || b != 254 )) || return 1
    (( a != 172 || b < 16 || b > 31 )) || return 1
    (( a != 192 || b != 168 )) || return 1
    (( a != 198 || (b != 18 && b != 19) )) || return 1
    (( a != 192 || b != 0 || (c != 0 && c != 2) )) || return 1
    (( a != 198 || b != 51 || c != 100 )) || return 1
    (( a != 203 || b != 0 || c != 113 )) || return 1
    return 0
}

ask_server_public_ip() {
    echo ""
    local detected
    detected=$(detect_server_public_ip)

    if [ -n "$detected" ]; then
        info "Server IP : ${detected}  (local configuration)"
        ask USE_DETECTED "Use this IP? (y/n)" "y"
        if [ "$USE_DETECTED" = "y" ] || [ "$USE_DETECTED" = "Y" ]; then
            SERVER_PUBLIC_IP="$detected"
            return
        fi
    else
        warn "No public IPv4 found in local routing. Behind NAT, enter the mapped public IP."
    fi

    while true; do
        ask SERVER_PUBLIC_IP "Enter server public IP manually" "$detected"
        if [ -z "$SERVER_PUBLIC_IP" ]; then
            warn "IP cannot be empty."
            continue
        fi
        if validate_public_ip "$SERVER_PUBLIC_IP"; then
            break
        fi
        warn "Enter a public IPv4 address, not a private, loopback or reserved address."
    done
    info "Public IP : ${SERVER_PUBLIC_IP}  (manual)"
}

ask_transport() {
    echo ""
    echo -e "  ${BOLD}Transport${NC}"
    local index=1 name
    QM_PROFILE=""
    for name in tcp ws wss http https quantum quantum+ tun xhttp xhttps dc6 quantum-gaming; do
        printf '   %2d) %s\n' "$index" "$name"
        index=$((index + 1))
    done
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
            9|xhttp)   TRANSPORT="xhttp";   break ;;
            10|xhttps) TRANSPORT="xhttps";  break ;;
            11|dc6) TRANSPORT="dc6"; break ;;
            12|quantum-gaming|quantumgaming|qgaming)
                TRANSPORT="quantum"; QM_PROFILE="gaming"
                info "Quantum Gaming is Quantum with quantum.profile=gaming. Use it on BOTH endpoints."
                break ;;
            *) warn "Please enter 1-12 or transport name." ;;
        esac
    done
}

select_transport_release() {
    CHANNEL="release"; VERSION="latest"
    if [ "${QM_PROFILE:-}" = gaming ]; then
        info "Quantum Gaming: stable v4.2.8+ or beta v4.3.1+, on BOTH endpoints."
        ask_version "$1" "v4.3.1" "v4.2.8"
        return
    fi
    case "$TRANSPORT" in
        dc6)
            info "DC6: stable v4.2.8+ or beta v4.2.9+, on BOTH endpoints."
            ask_version "$1" "v4.2.9" "v4.2.8"
            ;;
        quantum-gaming)
            info "Quantum Gaming: stable v4.2.8+ or beta v4.3.1+, on BOTH endpoints."
            ask_version "$1" "v4.3.1" "v4.2.8"
            ;;
    esac
    info "Version : ${VERSION} (${CHANNEL})"
}

version_at_least() {
    python3 -c '
import re, sys
def version(s):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", s): raise ValueError()
    return tuple(map(int, s[1:].split(".")))
try:
    sys.exit(0 if version(sys.argv[1]) >= version(sys.argv[2]) else 1)
except ValueError:
    sys.exit(1)
' "$1" "$2"
}

config_needs_new_transport_core() {
    python3 -c '
import json, re, sys
targets = (sys.argv[2],) if len(sys.argv) > 2 and sys.argv[2] else ("dc6",)
try:
    text = open(sys.argv[1], encoding="utf-8").read()
    try:
        doc = json.loads(text)
        nodes = [doc] + doc.get("paths", []) + doc.get("listeners", [])
        found = any(n.get("transport") in targets for n in nodes)
    except (ValueError, TypeError, AttributeError):
        found = re.search(r"(?m)^\s*(?:-\s*)?transport\s*:\s*[\x22\x27]?(?:" + "|".join(map(re.escape, targets)) + r")[\x22\x27]?\s*(?:#.*)?$", text) is not None
    sys.exit(0 if found else 1)
except OSError:
    sys.exit(1)
' "$1" "${2:-}"
}

validate_transport_ip() {
    # Literal addresses only. Never resolve user input or call an IP-check site.
    python3 -c '
import ipaddress, sys
try:
    value, family, side = sys.argv[1:]
    if "%" in value: raise ValueError()
    ip = ipaddress.ip_address(value)
    valid = ip.version == int(family) and not ip.is_multicast and not ip.is_loopback and not ip.is_link_local
    if ip.version == 6:
        valid = valid and ip.ipv4_mapped is None and (not ip.is_unspecified or side == "server")
    else:
        valid = valid and not ip.is_unspecified and str(ip) != "255.255.255.255"
    sys.exit(0 if valid else 1)
except ValueError:
    sys.exit(1)
' "$1" "$2" "$3"
}

local_has_transport_ip() {
    ip -j addr show 2>/dev/null | python3 -c '
import ipaddress, json, sys
try:
    wanted = ipaddress.ip_address(sys.argv[1])
    found = any(ipaddress.ip_address(a["local"]) == wanted
                for iface in json.load(sys.stdin) for a in iface.get("addr_info", []) if "local" in a)
    sys.exit(0 if found else 1)
except (ValueError, KeyError):
    sys.exit(1)
' "$1"
}

ask_dc6_address() {
    local side="$1" value default=""
    [ "$side" = "server" ] && default="::"
    info "IPv4 for licensing; IPv6 for the tunnel."
    while true; do
        if [ "$side" = "server" ]; then
            ask value "Local IPv6 to listen on (:: = all IPv6 interfaces, no port)" "$default"
        else
            ask_required value "Server IPv6 for tunnel traffic (address only, no port)"
        fi
        # Accept pasted [IPv6] too, but not [IPv6]:port or scope IDs.
        value="${value#[}"; value="${value%]}"
        if ! validate_transport_ip "$value" 6 "$side"; then
            warn "Enter an IPv6 unicast address; no IPv4, zone, link-local address or port."
            continue
        fi
        if [ "$side" = "server" ] && [ "$value" != "::" ] && ! local_has_transport_ip "$value"; then
            warn "That IPv6 is not assigned locally. Choose a local address or ::."
            continue
        fi
        DC6_IPV6="$value"
        break
    done
}

show_new_transport_summary() {
    local side="$1" port
    if [ "$side" = "server" ]; then port="$PORT"; else port="$SERVER_PORT"; fi
    case "$TRANSPORT" in
        dc6)
            info "IPv6 tunnel endpoint : [${DC6_IPV6}]:${port}"
            info "License IPv4 : ${SERVER_PUBLIC_IP:-${SERVER_IP}}"
            warn "Allow TCP on the tunnel port in the server's IPv6 firewall; both hosts need working IPv6 routing."
            ;;
    esac
    return 0
}

ask_xhttp() {
    local side="$1"
    echo ""
    echo -e "  ${BOLD}xhttp settings${NC}"
    ask XHTTP_PATH "URL path  (must match the other side)" "/api/v2"
    case "$XHTTP_PATH" in
        /*) ;;
        *) XHTTP_PATH="/$XHTTP_PATH" ;;
    esac

    if [ "$side" = "client" ]; then
        echo ""
        echo -e "  ${BOLD}Upload mode${NC}"
        printf '    1) auto\n    2) streaming\n    3) sequenced\n\n'
        while true; do
            ask XHTTP_MODE_CHOICE "Upload mode" "1"
            case "$XHTTP_MODE_CHOICE" in
                1|auto) XHTTP_MODE="auto"; break ;;
                2|stream|streaming|stream-up) XHTTP_MODE="stream-up"; break ;;
                3|packet|sequenced|packet-up) XHTTP_MODE="packet-up"; break ;;
                *) warn "Choose 1-3." ;;
            esac
        done
    else
        XHTTP_MODE="auto"
    fi
}

ask_xhttp_cdn() {
    local side="$1"
    XHTTP_CDN="false"
    XHTTP_CDN_HOST=""
    XHTTP_CDN_PORT="443"
    XHTTP_CDN_IPS=""
    XHTTP_INSECURE="true"
    XHTTP_ORIGIN_PORT="8443"
    XHTTP_PEER_IP=""
    XHTTP_PUBLIC_IP=""

    echo ""
    echo -e "  ${YELLOW}Answer the same on both sides.${NC}"
    echo ""
    ask XHTTP_CDN_CHOICE "Use Cloudflare (y/n)" "n"
    case "$XHTTP_CDN_CHOICE" in
        y|Y|yes) ;;
        *) return ;;
    esac

    XHTTP_CDN="true"
    XHTTP_INSECURE="false"

    if [ "$side" = "client" ]; then
        echo ""
        echo -e "  ${BOLD}This side is the origin${NC}"
        echo -e "  ${DIM}Cloudflare connects to THIS machine. Point your domain's DNS record${NC}"
        echo -e "  ${DIM}here, orange cloud on, and open the port below in the firewall.${NC}"
        echo ""
        ask_num_range XHTTP_ORIGIN_PORT "Origin port" 8443 1 65535

        echo ""
        local mine
        mine=$(detect_server_public_ip)
        while true; do
            ask XHTTP_PUBLIC_IP "Client IP  (blank = skip)" "$mine"
            [ -z "$XHTTP_PUBLIC_IP" ] && break
            validate_ip "$XHTTP_PUBLIC_IP" && break
            warn "That is not an IP address."
        done
        return
    fi

    ask_required XHTTP_CDN_HOST "Your Cloudflare-proxied domain  (e.g. cdn.example.com)"
    echo ""
    echo -e "  ${YELLOW}That domain's DNS record must point at the FOREIGN server,${NC}"
    echo -e "  ${YELLOW}not at this one, with the orange cloud on.${NC}"
    echo ""
    echo -e "  ${DIM}Cloudflare forwards these HTTPS ports only:${NC}"
    echo -e "  ${DIM}443, 2053, 2083, 2087, 2096, 8443${NC}"
    echo -e "  ${DIM}Use the same port the far side waits on.${NC}"
    ask_num_range XHTTP_CDN_PORT "Port" 443 1 65535
    echo ""
    echo -e "  ${BOLD}Edge IPv4 addresses (comma-separated)${NC}"
    echo ""
    while true; do
        ask_required XHTTP_CDN_IPS "Edge addresses"
        if validate_edge_ips "$XHTTP_CDN_IPS"; then
            break
        fi
    done
    XHTTP_CDN_IPS="$(normalize_edge_ips "$XHTTP_CDN_IPS")"
    ok "Edge addresses: ${XHTTP_CDN_IPS}"

    echo ""
    echo ""
    ask_num_range XHTTP_CDN_POOL "Connections" 6 1 64

    echo ""
    while true; do
        ask XHTTP_PEER_IP "Client IPv4 (blank = any)" ""
        [ -z "$XHTTP_PEER_IP" ] && break
        validate_ip "$XHTTP_PEER_IP" && break
        warn "Enter a valid IPv4 address."
    done
    [ -n "$XHTTP_PEER_IP" ] && ok "Only ${XHTTP_PEER_IP} will be accepted"
    return 0
}

validate_edge_ips() {
    local list="$1" ip bad=0 count=0
    IFS=',' read -ra _VIPS <<< "$list"
    for ip in "${_VIPS[@]}"; do
        ip="$(echo "$ip" | xargs)"
        [ -z "$ip" ] && continue
        count=$((count + 1))
        if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            warn "\"${ip}\" is not an IP address."
            bad=1
            continue
        fi
        local o
        for o in ${ip//./ }; do
            if [ "$o" -gt 255 ] 2>/dev/null; then
                warn "\"${ip}\" is not a valid IP address (${o} is above 255)."
                bad=1
                break
            fi
        done
    done
    if [ "$count" -eq 0 ]; then
        warn "Enter at least one address."
        return 1
    fi
    [ "$bad" -eq 0 ]
}

normalize_edge_ips() {
    local list="$1" out="" ip
    local -a _NIPS
    IFS=',' read -ra _NIPS <<< "$list"
    for ip in "${_NIPS[@]}"; do
        ip="$(echo "$ip" | xargs)"
        [ -z "$ip" ] && continue
        case ",${out}," in *",${ip},"*) continue ;; esac
        [ -n "$out" ] && out="${out},"
        out="${out}${ip}"
    done
    printf '%s' "$out"
}

build_edge_ips_json() {
    local ips="$1" out="" ip
    [ -z "$ips" ] && { printf ''; return; }
    IFS=',' read -ra _EIPS <<< "$ips"
    for ip in "${_EIPS[@]}"; do
        ip="$(echo "$ip" | xargs)"
        [ -z "$ip" ] && continue
        [ -n "$out" ] && out="${out}, "
        out="${out}\"${ip}\""
    done
    printf '%s' "$out"
}

build_edge_ips_yaml() {
    printf '[%s]' "$(build_edge_ips_json "$1")"
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
        error "Port 80 is busy. Free it before requesting a certificate."
    fi

    info "Obtaining SSL certificate for: ${domain}"
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "$domain" \
        --http-01-port 80; then
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

install_openssl() {
    command -v openssl &>/dev/null && return
    info "Installing openssl..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq openssl
    elif command -v yum &>/dev/null; then
        yum install -y -q openssl
    elif command -v dnf &>/dev/null; then
        dnf install -y -q openssl
    else
        error "Cannot install openssl — package manager not found. Install it manually."
    fi
}

make_self_signed_cert() {
    local domain="$1"
    local dir="/etc/daggerconnect/tls"

    install_openssl
    mkdir -p "$dir"
    CERT_FILE="${dir}/${SERVICE_NAME}.crt"
    KEY_FILE="${dir}/${SERVICE_NAME}.key"

    info "Creating a self-signed certificate for ${domain} ..."
    if ! openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
            -keyout "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/CN=${domain}" \
            -addext "subjectAltName=DNS:${domain}" >/dev/null 2>&1; then
        openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
            -keyout "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/CN=${domain}" >/dev/null 2>&1 \
            || error "openssl could not create the certificate."
    fi
    chmod 600 "$KEY_FILE"
    chmod 644 "$CERT_FILE"
    ok "Cert : ${CERT_FILE}"
    ok "Key  : ${KEY_FILE}"
    ok "Valid for 10 years. Set Cloudflare's SSL mode to \"Full\"."
}

ask_ssl_cert() {
    echo ""
    echo -e "  ${BOLD}Certificate:${NC}"
    echo "    1)  Self-signed"
    echo "    2)  Let's Encrypt"
    echo "    3)  Custom"
    echo ""
    while true; do
        ask SSL_CHOICE "Certificate" "1"
        case "$SSL_CHOICE" in
            1|self|selfsigned) SSL_MODE="self";   break ;;
            2|auto|letsencrypt) SSL_MODE="auto";  break ;;
            3|custom)          SSL_MODE="custom"; break ;;
            *) warn "Please enter 1, 2 or 3." ;;
        esac
    done

    case "$SSL_MODE" in
        self)
            echo ""
            local def_domain="${XHTTP_CDN_HOST:-daggerconnect.local}"
            ask DOMAIN "Domain name" "$def_domain"
            echo ""
            make_self_signed_cert "$DOMAIN"
            ;;
        auto)
            echo ""
            info "DNS must point here and TCP port 80 must be reachable."
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

tune_network() {
    # Runtime owns bounded tuning; do not overwrite host policy during install.
    # In particular, never run sysctl --system (which applies unrelated files).
    info "This core tunes kernel buffer/queue ceilings at tunnel startup (unless tuner is off)."
    info "Existing sysctl files, congestion control and interface queues are preserved."
}

download_latest_launcher() {
    local tmp magic size
    mkdir -p "$(dirname "$LAUNCHER")"
    tmp=$(mktemp "${LAUNCHER}.XXXXXX")

    if ! curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 2 --retry-connrefused \
        --connect-timeout 15 --max-time 180 \
        -o "$tmp" "$LAUNCHER_LATEST_URL"; then
        rm -f "$tmp"
        return 1
    fi

    size=$(wc -c < "$tmp" 2>/dev/null || echo 0)
    magic=$(LC_ALL=C od -An -tx1 -N4 "$tmp" 2>/dev/null | tr -d ' \n')
    if [ "$magic" != "7f454c46" ] || [ "$size" -lt 1048576 ]; then
        rm -f "$tmp"
        warn "Latest launcher asset is not a valid Linux ELF binary (size=${size}, magic=${magic:-unknown})."
        return 1
    fi

    chmod 0755 "$tmp"
    if [ -f "$LAUNCHER" ] && cmp -s "$tmp" "$LAUNCHER"; then
        rm -f "$tmp"
        info "DaggerLauncher is already the latest published release."
        return 0
    fi
    mv -f "$tmp" "$LAUNCHER"
    return 0
}

ensure_launcher() {
    local role="$1"
    info "Checking the latest DaggerLauncher release..."
    if download_latest_launcher; then
        ok "DaggerLauncher ready : ${LAUNCHER}"
        return 0
    fi
    if [ -x "$LAUNCHER" ]; then
        warn "Could not fetch the latest launcher; keeping the existing executable."
        return 0
    fi
    error "Failed to download DaggerLauncher -- check network/DNS, or place a Linux launcher at ${LAUNCHER}, chmod +x it, and re-run."
}

update_launcher() {
    hr "Update Launcher"
    echo ""

    step "Downloading latest DaggerLauncher from GitHub..."
    if ! download_latest_launcher; then
        error "Download failed -- check network/DNS. ${LAUNCHER} was left untouched."
    fi
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

parse_version_list() {
    python3 -c '
import json, re, sys
try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict) or data.get("ok") is False:
        raise ValueError("version service returned an error")
    channels = data.get("channels", data)
    if not isinstance(channels, dict):
        raise ValueError("invalid channels object")
    rows = []
    for channel in ("release", "beta"):
        entry = channels.get(channel, [])
        versions = entry.get("versions", []) if isinstance(entry, dict) else entry
        if not isinstance(versions, list):
            raise ValueError("invalid versions array")
        for version in versions:
            if isinstance(version, str) and re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", version):
                row = channel + "\t" + version
                if row not in rows:
                    rows.append(row)
    print("\n".join(rows))
except (ValueError, TypeError) as exc:
    print("Cannot parse version list: " + str(exc), file=sys.stderr)
    sys.exit(1)
'
}

ask_version() {
    local role="$1" required_min="${2:-}" release_min="${3:-${2:-}}" selected_min

    echo ""
    info "Fetching available versions..."

    local json rows channel version
    # Preserve stderr: an HTTP/TLS/launcher error is not an empty release list.
    if ! json=$("$LAUNCHER" --list-versions --role "$role"); then
        warn "Launcher could not retrieve versions for role=${role}; see the error above."
        ask_channel_manual "$required_min" "$release_min"
        return
    fi
    if ! rows=$(printf '%s' "$json" | parse_version_list); then
        warn "Version-list parsing failed; falling back to manual entry."
        ask_channel_manual "$required_min" "$release_min"
        return
    fi

    local labels=() chans=() vers=() ch ver
    local -a rel_list=() beta_list=()

    while IFS=$'\t' read -r channel version; do
        version="${version%$'\r'}"
        [ -n "$version" ] || continue
        selected_min="$required_min"
        [ "$channel" != release ] || selected_min="$release_min"
        if [ -n "$selected_min" ] && ! version_at_least "$version" "$selected_min"; then
            continue
        fi
        case "$channel" in
            release) rel_list+=("$version") ;;
            beta)    beta_list+=("$version") ;;
        esac
    done <<< "$rows"

    if [ "$(( ${#rel_list[@]} + ${#beta_list[@]} ))" -eq 0 ]; then
        warn "No published versions meet this selection. Check the releases directory or enter a published version manually."
        ask_channel_manual "$required_min" "$release_min"
        return
    fi

    # Newest first inside each channel.
    if [ "${#rel_list[@]}" -gt 0 ]; then
        mapfile -t rel_list < <(printf '%s\n' "${rel_list[@]}" | sort -V -r -u)
    fi
    if [ "${#beta_list[@]}" -gt 0 ]; then
        mapfile -t beta_list < <(printf '%s\n' "${beta_list[@]}" | sort -V -r -u)
    fi

    if [ -n "$required_min" ]; then
        info "Minimum: stable ${release_min}, beta ${required_min}. Pick a numbered version."
    fi

    echo ""
    echo -e "  ${BOLD}Core version${NC}"
    local i=1
    local -a sections=("release:Stable" "beta:Beta")
    local sec name list_ref
    for sec in "${sections[@]}"; do
        ch="${sec%%:*}"; name="${sec#*:}"
        if [ "$ch" = release ]; then list_ref=("${rel_list[@]}"); else list_ref=("${beta_list[@]}"); fi
        if [ -z "$required_min" ]; then
            :
        elif [ "${#list_ref[@]}" -eq 0 ]; then
            continue
        fi
        echo ""
        echo -e "  ${BOLD}${name}${NC}"
        if [ -z "$required_min" ]; then
            echo "    ${i})  latest ${name,,}   (follows new ${name,,} builds on each start)"
            chans+=("$ch"); vers+=("latest"); labels+=("latest")
            i=$((i + 1))
        fi
        for ver in "${list_ref[@]}"; do
            echo "    ${i})  ${ver}"
            chans+=("$ch"); vers+=("$ver"); labels+=("$ver")
            i=$((i + 1))
        done
    done

    echo ""

    while true; do
        ask VER_CHOICE "Pick a version" "1"

        if [[ "$VER_CHOICE" =~ ^[0-9]{1,9}$ ]] \
            && (( 10#$VER_CHOICE >= 1 && 10#$VER_CHOICE <= ${#labels[@]} )); then

            local idx=$((10#$VER_CHOICE - 1))

            CHANNEL="${chans[$idx]}"
            VERSION="${vers[$idx]}"

            break
        fi

        warn "Please enter a number between 1 and ${#labels[@]}."
    done

    info "Selected : ${VERSION}  ($([ "$CHANNEL" = release ] && echo stable || echo beta))"
}

ask_channel_manual() {
    local required_min="${1:-}" release_min="${2:-${1:-}}"
    echo ""
    echo -e "  ${BOLD}Release Channel:${NC}"
    echo "    1)  release"
    echo "    2)  beta"
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
    [ "$CHANNEL" != release ] || required_min="$release_min"

    echo ""
    if [ -n "$required_min" ]; then
        info "Enter a published version >= ${required_min}; 'latest' cannot be verified here."
    else
        info "Enter vN.N.N, or leave empty to track latest on ${CHANNEL}."
    fi
    while true; do
        ask VER_INPUT "Version${required_min:+ (minimum ${required_min})}" ""
        if [ -z "$VER_INPUT" ] && [ -z "$required_min" ]; then
            VERSION="latest"
            break
        fi
        if echo "$VER_INPUT" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            if [ -n "$required_min" ] && ! version_at_least "$VER_INPUT" "$required_min"; then
                warn "This transport requires ${required_min} or newer."
                continue
            fi
            VERSION="$VER_INPUT"
            break
        fi
        warn "Use vN.N.N${required_min:+ at or above ${required_min}}."
    done
    info "Version : ${VERSION}"
}

switch_channel() {
    hr "Update Core / Select Version"
    echo ""
    pick_service "Update core for" || return 0
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

    local svc_role="" svc_min=""
    for cfg_candidate in "${CONFIG_DIR}/${svc}.json" "${CONFIG_DIR}/${svc}.yaml"; do
        [ -f "$cfg_candidate" ] || continue
        if config_needs_new_transport_core "$cfg_candidate"; then
            svc_min="v4.2.9"
        fi
        if grep -qE '"mode"[[:space:]]*:[[:space:]]*"server"|^[[:space:]]*mode[[:space:]]*:[[:space:]]*server' "$cfg_candidate"; then
            svc_role="server"; break
        elif grep -qE '"mode"[[:space:]]*:[[:space:]]*"client"|^[[:space:]]*mode[[:space:]]*:[[:space:]]*client' "$cfg_candidate"; then
            svc_role="client"; break
        fi
    done

    if [ -n "$svc_role" ]; then
        ask_version "$svc_role" "$svc_min" "${svc_min:+v4.2.8}"
    else
        warn "Could not determine whether '${svc}' is a server or client from its config -- falling back to manual entry."
        ask_channel_manual "$svc_min" "${svc_min:+v4.2.8}"
    fi
    local new_channel="$CHANNEL" new_version="$VERSION"

    if [ "$new_channel" = "$cur_channel" ] && [ "$new_version" = "$cur_version" ]; then
        info "Same version selection: restarting will fetch and verify it again (latest will be resolved again)."
    fi
    warn "Applying this selection restarts the selected service and briefly interrupts its connections."
    local apply_core=""
    ask apply_core "Apply channel=${new_channel} version=${new_version} and restart now? (y/n)" "n"
    case "$apply_core" in
        y|Y) ;;
        *) info "Cancelled; service and version selection left unchanged."; return 0 ;;
    esac

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

    # Migrate services created by older installers.  A failing launcher/core
    # used to be restarted every five seconds, which amplified an authority
    # outage into a request storm.  Exit 78 is a permanent host/config
    # limitation and must stay stopped until the operator fixes it.
    if grep -q '^RestartSec=' "$svc_file" 2>/dev/null; then
        sed -i 's/^RestartSec=.*/RestartSec=60/' "$svc_file"
    else
        sed -i '/^Restart=/a RestartSec=60' "$svc_file"
    fi
    if grep -q '^RestartPreventExitStatus=' "$svc_file" 2>/dev/null; then
        sed -i 's/^RestartPreventExitStatus=.*/RestartPreventExitStatus=78/' "$svc_file"
    else
        sed -i '/^RestartSec=/a RestartPreventExitStatus=78' "$svc_file"
    fi
    systemctl daemon-reload

    step "Restarting ${svc} on channel=${new_channel} version=${new_version} ..."
    systemctl restart "$svc"
    sleep 2
    if systemctl is-active --quiet "$svc"; then
        ok "Service is active with channel=${new_channel} version=${new_version}."
        info "Check its startup log for 'launcher: fetched version=' and tunnel readiness; active alone does not confirm a working tunnel."
    else
        warn "Service failed to start on the new setting -- reverting. Logs:"
        journalctl -u "$svc" -n 20 --no-pager
        set_unit_env DC_CHANNEL "$cur_channel"
        set_unit_env DC_VERSION "$cur_version"
        systemctl daemon-reload
        systemctl restart "$svc"
        warn "Previous version selection restored. 'latest' or a replaced same-version artifact cannot roll back to the previous binary automatically."
    fi
}

ask_ports() {
    local default_type=tcp ptype _p parsed normalized previous duplicate
    local -a _parts
    echo ""
    info "Port mappings: 8080 or 8080=80, separated by commas. Blank to finish."
    PORTS=()
    while true; do
        ask P "Port" ""
        [ -z "$P" ] && break
        while true; do
            ask ptype "Type for '$P' - tcp or udp" "$default_type"
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
            [[ "$_p" == */* ]] || _p="${_p}/${ptype}"
            if ! parsed=$(parse_port_entry "$_p"); then
                warn "Invalid mapping: $_p. Use ports 1-65535 and tcp/udp/both."
                continue
            fi
            local protocol bind target
            IFS='|' read -r protocol bind target <<< "$parsed"
            normalized="${bind}=${target}/${protocol}"
            duplicate=false
            for previous in "${PORTS[@]}"; do
                if [ "$previous" = "$normalized" ]; then duplicate=true; break; fi
                if [[ "$previous" == "$bind="* ]] &&
                   { [[ "$previous" == */both ]] || [ "$protocol" = both ] || [[ "$previous" == */"$protocol" ]]; }; then
                    warn "Port ${bind}/${protocol} already has a mapping."
                    duplicate=true
                    break
                fi
            done
            [ "$duplicate" = true ] || PORTS+=("$normalized")
        done
    done
    if [ ${#PORTS[@]} -eq 0 ]; then
        info "No port mappings."
    fi
}

parse_port_entry() {
    local entry="$1" ptype="tcp" pbind ptarget
    if [[ "$entry" == */* ]]; then
        ptype="${entry##*/}"
        entry="${entry%/*}"
        ptype="$(echo "$ptype" | tr '[:upper:]' '[:lower:]')"
        case "$ptype" in
            tcp|udp|both) ;;
            any) ptype=both ;;
            *) return 1 ;;
        esac
    fi
    if [[ "$entry" == *=* ]]; then
        pbind="${entry%%=*}"
        ptarget="${entry#*=}"
    else
        pbind="$entry"
        ptarget="$entry"
    fi
    [[ "$pbind" =~ ^[0-9]{1,5}$ && "$ptarget" =~ ^[0-9]{1,5}$ ]] || return 1
    pbind=$((10#$pbind)); ptarget=$((10#$ptarget))
    (( pbind >= 1 && pbind <= 65535 && ptarget >= 1 && ptarget <= 65535 )) || return 1
    printf '%s|%s|%s\n' "$ptype" "$pbind" "$ptarget"
}

build_ports_json() {
    local first=1 p ptype pbind ptarget parsed
    for p in "$@"; do
        parsed=$(parse_port_entry "$p") || return 1
        IFS='|' read -r ptype pbind ptarget <<< "$parsed"
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
    local p ptype pbind ptarget parsed
    for p in "$@"; do
        parsed=$(parse_port_entry "$p") || return 1
        IFS='|' read -r ptype pbind ptarget <<< "$parsed"
        printf '      - type: "%s"
        bind: "0.0.0.0:%s"
        target: "127.0.0.1:%s"
' "$ptype" "$pbind" "$ptarget"
    done
}

SOCKS5_ENABLED="false"
SOCKS5_BIND=""

CLIENT_CONN_POOL="6"

ask_connection_pool() {
    local default_pool=6
    echo ""
    echo -e "  ${BOLD}Connection Pool:${NC}"
    echo ""
    ask_num_range CLIENT_CONN_POOL "Connections per path" "$default_pool" 1 64
}

ask_socks5() {
    echo ""
    echo -e "  ${BOLD}Standalone SOCKS5 Proxy:${NC}"
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
ADV_TUNER_MODE="auto"
ADV_TUNER_BUDGET=128
ADV_TUNER_MIN_BUFFER=262144
ADV_TUNER_MAX_BUFFER=16777216
ADV_TUNER_MIN_WINDOW=262144
ADV_TUNER_MAX_WINDOW=8388608
ADV_TUNER_QUEUE_MS=40
TUN_TUNE_PROFILE="auto"
TUN_MTU=""
TUN_SOCK_BUF=""
TUN_RX_QUEUE=""
TUN_TXQUEUELEN=""
ADV_PROFILE="auto"
ADV_TCP_KEEPALIVE="30"
ADV_CONN_TIMEOUT="30"
ADV_CLEANUP_INTERVAL="3"
ADV_TCP_READ_BUF="4194304"
ADV_TCP_WRITE_BUF="4194304"
ADV_UDP_BUF="4194304"
ADV_CHANNEL_BACKLOG="4096"
ADV_HEALTH_PROBE_SEC="10"
ADV_HEALTH_PROBE_TIMEOUT_MS="3000"
ADV_HEALTH_MAX_MISSED="4"
ADV_HANDSHAKE_TIMEOUT_SEC="30"

apply_profile() {
    local p="$1"
    ADV_PROFILE="$p"
    case "$p" in
        stable)
            ADV_TCP_READ_BUF="4194304"   ADV_TCP_WRITE_BUF="4194304"
            ADV_UDP_BUF="4194304"
            ADV_CHANNEL_BACKLOG="4096"
            ADV_TCP_KEEPALIVE="30"       ADV_CONN_TIMEOUT="30"
            ADV_CLEANUP_INTERVAL="3"
            ADV_HEALTH_PROBE_SEC="10"    ADV_HEALTH_PROBE_TIMEOUT_MS="3000"
            ADV_HEALTH_MAX_MISSED="4"    ADV_HANDSHAKE_TIMEOUT_SEC="30"
            ;;
        aggressive)
            ADV_TCP_READ_BUF="16777216"  ADV_TCP_WRITE_BUF="16777216"
            ADV_UDP_BUF="16777216"
            ADV_CHANNEL_BACKLOG="8192"
            ADV_TCP_KEEPALIVE="30"       ADV_CONN_TIMEOUT="60"
            ADV_CLEANUP_INTERVAL="5"
            ADV_HEALTH_PROBE_SEC="10"    ADV_HEALTH_PROBE_TIMEOUT_MS="3000"
            ADV_HEALTH_MAX_MISSED="4"    ADV_HANDSHAKE_TIMEOUT_SEC="30"
            ;;
        low_latency)
            ADV_TCP_READ_BUF="2097152"   ADV_TCP_WRITE_BUF="2097152"
            ADV_UDP_BUF="2097152"
            ADV_CHANNEL_BACKLOG="2048"
            ADV_TCP_KEEPALIVE="20"       ADV_CONN_TIMEOUT="20"
            ADV_CLEANUP_INTERVAL="2"
            ADV_HEALTH_PROBE_SEC="8"     ADV_HEALTH_PROBE_TIMEOUT_MS="2500"
            ADV_HEALTH_MAX_MISSED="4"    ADV_HANDSHAKE_TIMEOUT_SEC="30"
            ;;
        low_hardware)
            ADV_TCP_READ_BUF="524288"    ADV_TCP_WRITE_BUF="524288"
            ADV_UDP_BUF="524288"
            ADV_CHANNEL_BACKLOG="512"
            ADV_TCP_KEEPALIVE="30"       ADV_CONN_TIMEOUT="30"
            ADV_CLEANUP_INTERVAL="3"
            ADV_HEALTH_PROBE_SEC="15"    ADV_HEALTH_PROBE_TIMEOUT_MS="4000"
            ADV_HEALTH_MAX_MISSED="4"    ADV_HANDSHAKE_TIMEOUT_SEC="45"
            ;;
    esac
}

ask_num_range() {
    local __var="$1" prompt="$2" def="$3" lo="$4" hi="$5" val
    while true; do
        ask val "$prompt" "$def"
        case "$val" in
            ''|*[!0-9]*) warn "Enter a whole number." ; continue ;;
        esac
        if [ "${#val}" -gt 9 ]; then
            warn "Number is too large."
            continue
        fi
        val=$((10#$val))
        if [ "$val" -lt "$lo" ] || [ "$val" -gt "$hi" ]; then
            warn "Out of range — expected ${lo}..${hi}."
            continue
        fi
        printf -v "$__var" '%s' "$val"
        return
    done
}

ask_tun_encapsulation() {
    printf '\n  TUN encapsulation\n    1) tcp\n    2) udp\n    3) icmp\n    4) gre\n    5) ipip\n    6) bip\n\n'
    while true; do
        ask TUN_PROFILE_CHOICE "Profile (match both ends)" 1
        case "$TUN_PROFILE_CHOICE" in
            1|tcp) TUN_PROFILE=tcp; break ;;
            2|udp) TUN_PROFILE=udp; break ;;
            3|icmp) TUN_PROFILE=icmp; break ;;
            4|gre) TUN_PROFILE=gre; break ;;
            5|ipip) TUN_PROFILE=ipip; break ;;
            6|bip) TUN_PROFILE=bip; break ;;
            *) warn "Choose 1-6." ;;
        esac
    done
    TUN_ENCAP=ipx
    TUN_L4_PORT=""
    case "$TUN_PROFILE" in
        tcp|udp) ask_num_range TUN_L4_PORT "Service port (match both ends)" 443 1 65535 ;;
    esac
    return 0
}

# Optional "profile" line for the quantum block; empty unless Quantum Gaming.
quantum_profile_json() {
    if [ "${QM_PROFILE:-}" = gaming ]; then
        printf ',\n    "profile": "gaming"'
    fi
    return 0
}

quantum_profile_yaml() {
    if [ "${QM_PROFILE:-}" = gaming ]; then
        printf '\n  profile: gaming'
    fi
    return 0
}

ask_quantum_settings() {
    ask_num_range QM_MTU "MTU" 1350 512 9000
    while true; do
        ask QM_BLOCK "Header cipher (aes/salsa20/none; match both ends)" aes
        case "$QM_BLOCK" in
            aes|salsa20|none) break ;;
            *) warn "Choose aes, salsa20 or none." ;;
        esac
    done
}

ask_server_endpoint() {
    while true; do
        ask SERVER_ADDR "Server IPv4:port" ""
        SERVER_IP="${SERVER_ADDR%%:*}"
        SERVER_PORT="${SERVER_ADDR##*:}"
        if ! validate_ip "$SERVER_IP" || ! [[ "$SERVER_PORT" =~ ^[0-9]{1,5}$ ]] ||
           [ "$SERVER_IP" = "$SERVER_PORT" ] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
            warn "Use IPv4:port, with a port between 1 and 65535."
            continue
        fi
        if [ "$TRANSPORT" = dc6 ] && ! validate_transport_ip "$SERVER_IP" 4 client; then
            warn "Enter a unicast IPv4 address."
            continue
        fi
        SERVER_PORT=$((10#$SERVER_PORT))
        break
    done
}

ask_tun_custom() {
    ask_num_range TUN_MTU "MTU (bytes)" 1380 576 9000
    ask_num_range TUN_SOCK_BUF "Capture buffer (bytes)" 4194304 262144 67108864
    ask_num_range TUN_RX_QUEUE "Receive queue (frames)" 512 64 8192
    ask_num_range TUN_TXQUEUELEN "Transmit queue (packets)" 500 10 10000
}

ask_tun_liveness() {
    local device_default
    device_default="dc$(printf '%s' "$SERVICE_NAME" | cksum | awk '{print $1}')"
    while true; do
        ask TUN_NAME "TUN device name (unique for this profile)" "$device_default"
        [[ "$TUN_NAME" =~ ^[A-Za-z0-9_-]{1,15}$ ]] && break
        warn "Use 1-15 letters, digits, underscores or hyphens."
    done
    ask_num_range TUN_HEARTBEAT_SEC "Heartbeat interval (sec)" 10 1 60
    local min_idle=$((TUN_HEARTBEAT_SEC * 3))
    local default_idle=90
    [ "$default_idle" -lt "$min_idle" ] && default_idle=$min_idle
    ask_num_range TUN_IDLE_TIMEOUT_SEC "Peer silence before confirmation (sec)" "$default_idle" "$min_idle" 3600
}

ask_tun_profile() {
    echo ""
    echo -e "  ${BOLD}TUN Performance Profile:${NC}"
    printf '    1) auto\n    2) stable\n    3) speed\n    4) gaming\n    5) custom\n'
    echo ""
    TUN_MTU=""; TUN_SOCK_BUF=""; TUN_RX_QUEUE=""; TUN_TXQUEUELEN=""
    while true; do
        ask TUN_PROF_CHOICE "TUN profile" "1"
        case "$TUN_PROF_CHOICE" in
            1|auto)   TUN_TUNE_PROFILE="auto"; break ;;
            2|stable) TUN_TUNE_PROFILE="stable"; break ;;
            3|speed)  TUN_TUNE_PROFILE="speed"; break ;;
            4|gaming) TUN_TUNE_PROFILE="gaming"; break ;;
            5|custom) TUN_TUNE_PROFILE="custom"; ask_tun_custom; break ;;
            *) warn "Choose 1-5." ;;
        esac
    done
    warn "Match the TUN profile on both ends."
}

ask_advanced() {
    ADV_UDP_FLOW_TIMEOUT=300
    ADV_WS_READ_BUF=131072
    ADV_WS_WRITE_BUF=131072
    ADV_TUNER_BUDGET=128
    ADV_TUNER_MIN_BUFFER=262144
    ADV_TUNER_MAX_BUFFER=16777216
    ADV_TUNER_MIN_WINDOW=262144
    ADV_TUNER_MAX_WINDOW=8388608
    ADV_TUNER_QUEUE_MS=40
    echo ""
    echo -e "  ${BOLD}Tuner Mode:${NC}"
    printf '    1) auto\n    2) balanced\n    3) aggressive\n    4) low_latency\n    5) low_memory\n    6) custom\n'
    echo ""
    while true; do
        ask ADV_CHOICE "Tuner mode" "1"
        case "$ADV_CHOICE" in
            1|auto|2|stable|balanced|3|aggressive|4|low_latency|5|low_hardware|low_memory|6|custom) break ;;
            *) warn "Choose 1-6." ;;
        esac
    done
    echo ""
    case "$ADV_CHOICE" in
        1|auto)
            ADV_TUNER_MODE="auto"
            ADV_AUTO_TUNE="true"
            apply_profile "stable"
            ;;
        2|stable|balanced)
            ADV_TUNER_MODE="balanced"
            ADV_AUTO_TUNE="true"
            apply_profile "stable"
            ;;
        3|aggressive)
            ADV_TUNER_MODE="aggressive"
            ADV_AUTO_TUNE="true"
            apply_profile "aggressive"
            ;;
        4|low_latency)
            ADV_TUNER_MODE="low_latency"
            ADV_TUNER_QUEUE_MS=10
            ADV_AUTO_TUNE="true"
            apply_profile "low_latency"
            ;;
        5|low_hardware|low_memory)
            ADV_TUNER_MODE="low_memory"
            ADV_TUNER_QUEUE_MS=20
            ADV_AUTO_TUNE="true"
            apply_profile "low_hardware"
            ;;
        6|custom)
            ADV_TUNER_MODE="off"
            ADV_AUTO_TUNE="false"
            ADV_PROFILE="custom"
            echo -e "  ${BOLD}Timeouts & Intervals:${NC}"
            ask_num_range ADV_TCP_KEEPALIVE "tcp_keepalive (sec)" 30 1 3600
            ask_num_range ADV_CONN_TIMEOUT "connection_timeout (sec)" 30 1 300
            ask_num_range ADV_CLEANUP_INTERVAL "cleanup_interval (sec)" 3 1 60
            echo ""
            echo -e "  ${BOLD}Connection health${NC}"
            ask_num_range ADV_HEALTH_PROBE_SEC "health_probe_sec (sec)" 10 1 300
            ask_num_range ADV_HEALTH_PROBE_TIMEOUT_MS "health_probe_timeout_ms (ms)" 3000 300 60000
            ask_num_range ADV_HEALTH_MAX_MISSED "health_max_missed (count)" 4 2 20
            ask_num_range ADV_HANDSHAKE_TIMEOUT_SEC "handshake_timeout_sec (sec)" 30 5 300
            echo ""
            echo -e "  ${BOLD}Buffers  (bytes, e.g. 4194304 = 4MB):${NC}"
            ask_num_range ADV_TCP_READ_BUF "tcp_read_buffer (bytes)" 4194304 65536 67108864
            ask_num_range ADV_TCP_WRITE_BUF "tcp_write_buffer (bytes)" 4194304 65536 67108864
            ask_num_range ADV_UDP_BUF "udp_buffer_size (bytes)" 4194304 65536 67108864
            echo ""
            echo -e "  ${BOLD}Channel / Stream sizes:${NC}"
            ask_num_range ADV_CHANNEL_BACKLOG "channel_backlog (count)" 4096 64 16384
            ;;
        *)
            ADV_TUNER_MODE="auto"
            ADV_AUTO_TUNE="true"
            apply_profile "stable"
            ;;
    esac
    if [ "$ADV_TUNER_MODE" = "off" ]; then
        ask_num_range ADV_UDP_FLOW_TIMEOUT "UDP flow idle timeout (sec)" 300 10 86400
        if [ "$TRANSPORT" = "ws" ] || [ "$TRANSPORT" = "wss" ]; then
            ask_num_range ADV_WS_READ_BUF "WebSocket read buffer (bytes)" 131072 4096 4194304
            ask_num_range ADV_WS_WRITE_BUF "WebSocket write buffer (bytes)" 131072 4096 4194304
        fi
    fi
    if [ "$ADV_TUNER_MODE" != "off" ]; then
        local tune_limits
        ask tune_limits "Customize adaptive safety limits? (y/n)" "n"
        case "$tune_limits" in
            y|Y|yes)
                ask_num_range ADV_TUNER_BUDGET "Estimated tuning budget (MB, per process)" 128 8 1024
                ask_num_range ADV_TUNER_MIN_BUFFER "Minimum socket buffer (bytes, safety may reduce)" 262144 65536 16777216
                ask_num_range ADV_TUNER_MAX_BUFFER "Maximum socket buffer (bytes)" 16777216 "$ADV_TUNER_MIN_BUFFER" 16777216
                ask_num_range ADV_TUNER_MIN_WINDOW "Minimum DC window (bytes, safety may reduce)" 262144 262144 8388608
                ask_num_range ADV_TUNER_MAX_WINDOW "Maximum DC stream window (bytes)" 8388608 "$ADV_TUNER_MIN_WINDOW" 8388608
                ask_num_range ADV_TUNER_QUEUE_MS "Queue delay target (ms, not a guarantee)" "$ADV_TUNER_QUEUE_MS" 5 250
                ;;
        esac
        if [ "$TRANSPORT" = "tun" ]; then
            info "Live TUN buffers require TUN profile=auto and no explicit rx_queue/sock_buf."
        fi
        info "Explicit dc.window_bytes remains fixed; choose DC Auto for a live window."
    fi
    info "Tuner Profile : ${ADV_PROFILE}$([ "$ADV_AUTO_TUNE" = "true" ] && echo " (adaptive)" || echo " (fixed)")"
}

build_advanced_json() {
    printf '  "tuner": {"mode":"%s","memory_budget_mb":%s,"min_buffer_bytes":%s,"max_buffer_bytes":%s,"min_window_bytes":%s,"max_window_bytes":%s,"queue_delay_ms":%s},\n' \
        "$ADV_TUNER_MODE" "$ADV_TUNER_BUDGET" "$ADV_TUNER_MIN_BUFFER" "$ADV_TUNER_MAX_BUFFER" "$ADV_TUNER_MIN_WINDOW" "$ADV_TUNER_MAX_WINDOW" "$ADV_TUNER_QUEUE_MS"
    printf '  "advanced": {
'
    printf '    "udp_flow_timeout": %s,\n' "${ADV_UDP_FLOW_TIMEOUT:-300}"
    if [ "$ADV_TUNER_MODE" = "off" ] && { [ "$TRANSPORT" = "ws" ] || [ "$TRANSPORT" = "wss" ]; }; then
        printf '    "websocket_read_buffer": %s,\n    "websocket_write_buffer": %s,\n' "${ADV_WS_READ_BUF:-131072}" "${ADV_WS_WRITE_BUF:-131072}"
    fi
    printf '    "auto_tune": %s,
'          "$ADV_AUTO_TUNE"
    printf '    "tcp_nodelay": true,
'
    printf '    "tcp_keepalive": %s,
'      "$ADV_TCP_KEEPALIVE"
    printf '    "connection_timeout": %s,
' "$ADV_CONN_TIMEOUT"
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
    printf '    "health_probe_sec": %s,
' "$ADV_HEALTH_PROBE_SEC"
    printf '    "health_probe_timeout_ms": %s,
' "$ADV_HEALTH_PROBE_TIMEOUT_MS"
    printf '    "health_max_missed": %s,
' "$ADV_HEALTH_MAX_MISSED"
    printf '    "handshake_timeout_sec": %s
' "$ADV_HANDSHAKE_TIMEOUT_SEC"
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
    printf 'tuner:\n  mode: "%s"\n  memory_budget_mb: %s\n  min_buffer_bytes: %s\n  max_buffer_bytes: %s\n  min_window_bytes: %s\n  max_window_bytes: %s\n  queue_delay_ms: %s\n\n' \
        "$ADV_TUNER_MODE" "$ADV_TUNER_BUDGET" "$ADV_TUNER_MIN_BUFFER" "$ADV_TUNER_MAX_BUFFER" "$ADV_TUNER_MIN_WINDOW" "$ADV_TUNER_MAX_WINDOW" "$ADV_TUNER_QUEUE_MS"
    printf "advanced:
"
    printf '  udp_flow_timeout: %s\n' "${ADV_UDP_FLOW_TIMEOUT:-300}"
    if [ "$ADV_TUNER_MODE" = "off" ] && { [ "$TRANSPORT" = "ws" ] || [ "$TRANSPORT" = "wss" ]; }; then
        printf '  websocket_read_buffer: %s\n  websocket_write_buffer: %s\n' "${ADV_WS_READ_BUF:-131072}" "${ADV_WS_WRITE_BUF:-131072}"
    fi
    printf "  auto_tune: %s
"          "$ADV_AUTO_TUNE"
    printf "  tcp_nodelay: true
"
    printf "  tcp_keepalive: %s
"      "$ADV_TCP_KEEPALIVE"
    printf "  connection_timeout: %s
" "$ADV_CONN_TIMEOUT"
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
    printf "  health_probe_sec: %s
" "$ADV_HEALTH_PROBE_SEC"
    printf "  health_probe_timeout_ms: %s
" "$ADV_HEALTH_PROBE_TIMEOUT_MS"
    printf "  health_max_missed: %s
" "$ADV_HEALTH_MAX_MISSED"
    printf "  handshake_timeout_sec: %s
" "$ADV_HANDSHAKE_TIMEOUT_SEC"
}

dc_applies() {
    case "$TRANSPORT" in
        tun) return 1 ;;
        *) return 0 ;;
    esac
}

build_dc_json() {
    printf '  "profile_id": "%s",\n' "${PAIR_PROFILE_ID:-default}"
    dc_applies || return 0
    [ "$DC_PROFILE" = "auto" ] && return 0
    printf '  "dc": {
    "streams_per_carrier": %s,
    "max_carriers": %s,
    "window_bytes": %s
  },
' "$DC_STREAMS" "$DC_CARRIERS" "$DC_WINDOW"
}

build_dc_yaml() {
    printf 'profile_id: "%s"\n' "${PAIR_PROFILE_ID:-default}"
    dc_applies || return 0
    [ "$DC_PROFILE" = "auto" ] && return 0
    printf 'dc:
  streams_per_carrier: %s
  max_carriers: %s
  window_bytes: %s

' "$DC_STREAMS" "$DC_CARRIERS" "$DC_WINDOW"
}

ask_dc() {
    DC_PROFILE="auto"; DC_STREAMS=8; DC_CARRIERS=32; DC_WINDOW=1048576

    if ! dc_applies; then
        return
    fi

    echo ""
    echo -e "  ${BOLD}Connection profile${NC}"
    echo ""
    echo "    1) Balanced"
    echo "    2) Stability"
    echo "    3) Speed"
    echo "    4) Custom"
    echo ""
    while true; do
        ask DC_CHOICE "Profile" "1"
        case "$DC_CHOICE" in
            1|balanced|auto)
                DC_PROFILE="auto"
                break ;;
            2|stability|stable)
                DC_PROFILE="stable"; DC_STREAMS=4; DC_CARRIERS=16; DC_WINDOW=1048576
                break ;;
            3|speed|fast)
                DC_PROFILE="speed"; DC_STREAMS=12; DC_CARRIERS=16; DC_WINDOW=2097152
                break ;;
            4|custom)
                DC_PROFILE="custom"
                ask_num_range DC_STREAMS "Connections per carrier" 8 1 64
                ask_num_range DC_CARRIERS "Maximum carriers" 32 2 64
                while true; do
                    ask_num_range DC_WINDOW "Per-stream receive window (bytes, 0 = adaptive)" 0 0 8388608
                    [ "$DC_WINDOW" -eq 0 ] || [ "$DC_WINDOW" -ge 262144 ] && break
                    warn "Use 0 for adaptive, or 262144..8388608 for a fixed window."
                done
                break ;;
            *) warn "Please enter 1-4." ;;
        esac
    done
}

write_native_dc_config() {
    # JSON is also valid YAML, so these writers support existing YAML callers.
    # Serialize user strings, especially PSKs, instead of interpolating raw JSON.
    local role="$1" transport="$2" endpoint="$3" license_addr="$4" ipv6_addr="$5" psk="$6"
    shift 6
    local common maps socks tmp
    common="{$(build_dc_json)$(build_advanced_json)}"
    maps=$(build_ports_json "$@") || error "Invalid port mapping; config unchanged."
    maps="[$maps]"
    socks="{$(build_socks5_json)\"_end\":0}"
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR" || error "Cannot create config directory."
    fi
    tmp=$(umask 077; mktemp "${CONFIG}.XXXXXX") || error "Cannot create temporary config."
    if ! python3 -c '
import ipaddress, json, sys
role, transport, endpoint, license_addr, ipv6_addr, psk, common, maps, socks, pool = sys.argv[1:]
def address(value, family, wildcard=False):
    host, port = value.rsplit(":", 1)
    if family == 6:
        if not (host.startswith("[") and host.endswith("]")): raise ValueError("IPv6 brackets required")
        host = host[1:-1]
    ip = ipaddress.ip_address(host)
    if ("%" in host or ip.version != family or ip.is_multicast or ip.is_loopback or ip.is_link_local
        or (ip.is_unspecified and not wildcard) or (family == 6 and ip.ipv4_mapped is not None)
        or str(ip) == "255.255.255.255" or not port.isascii() or not port.isdigit() or not 1 <= int(port) <= 65535):
        raise ValueError("invalid transport endpoint")
    return int(port)
if role not in ("server", "client") or transport != "dc6" or not psk:
    raise ValueError("invalid transport configuration")
port = address(endpoint, 6 if transport == "dc6" else 4, role == "server" and transport == "dc6")
doc = json.loads(common)
doc.update(mode=role, transport=transport, psk=psk, log_level="info")
if role == "server":
    mappings = json.loads(maps)
    for m in mappings:
        for key in ("bind", "target"):
            mp = m[key].rsplit(":", 1)[-1]
            if not mp.isascii() or not mp.isdigit() or not 1 <= int(mp) <= 65535:
                raise ValueError("mapped ports must be 1..65535")
    doc["listeners"] = [dict(addr=endpoint, transport=transport, maps=mappings)]
    doc["socks5"] = json.loads(socks)["socks5"]
else:
    address(license_addr, 4)
    pool = int(pool)
    if not 1 <= pool <= 64: raise ValueError("invalid connection pool")
    path = dict(transport=transport, addr=license_addr, connection_pool=pool, retry_interval=3, dial_timeout=10)
    if transport == "dc6":
        address(ipv6_addr, 6)
        path["ipv6_addr"] = ipv6_addr
    doc["paths"] = [path]
print(json.dumps(doc, indent=2))
' "$role" "$transport" "$endpoint" "$license_addr" "$ipv6_addr" "$psk" \
        "$common" "$maps" "$socks" "${CLIENT_CONN_POOL:-2}" > "$tmp"; then
        rm -f "$tmp"
        error "Invalid transport configuration; existing config left unchanged."
    fi
    mv -f "$tmp" "$CONFIG" || error "Cannot install configuration."
}

write_server_config_dc6() {
    local port="$1" psk="$2" ipv6="$3"
    shift 3
    write_native_dc_config server dc6 "[${ipv6}]:${port}" "" "" "$psk" "$@"
}

write_client_config_dc6() {
    write_native_dc_config client dc6 "[$4]:$2" "$1:$2" "[$4]:$2" "$3"
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
' "$psk" "$port" "$ports_json"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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
' "$psk" "$port" "$ports_yaml"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$port" "$ports_json" "$ws_path"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$port" "$ports_yaml" "$ws_path"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$port" "$cert" "$key" "$ports_json" "$ws_path"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$port" "$cert" "$key" "$ports_yaml" "$ws_path"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_wss() {
    local server_ip="$1" server_port="$2" psk="$3" ws_path="$4"
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
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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


' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$ws_path"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$port" "$ports_json" "$http_domain" "$http_path"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$port" "$ports_yaml" "$http_domain" "$http_path"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_server_config_xhttp() {
    local port="$1" psk="$2" path="$3" secure="$4" cert="$5" key="$6"
    local cdn="$7" cdn_host="$8" cdn_port="$9" cdn_ips="${10}" insecure="${11}"
    local pool="${12}" peer_ip="${13}"
    shift 13
    local ports_json ports_yaml transport edge_json edge_yaml peer_json peer_yaml up_concurrency
    local cert_json cert_yaml

    ports_json=$(build_ports_json "$@")
    ports_yaml=$(build_ports_yaml "$@")
    edge_json=$(build_edge_ips_json "$cdn_ips")
    edge_yaml=$(build_edge_ips_yaml "$cdn_ips")
    peer_json=$(build_edge_ips_json "$peer_ip")
    peer_yaml=$(build_edge_ips_yaml "$peer_ip")

    transport="xhttp"
    [ "$secure" = "true" ] && transport="xhttps"
    [ -z "$pool" ] && pool=6
    up_concurrency=2
    [ "$cdn" = "true" ] && up_concurrency=8

    cert_json=""
    cert_yaml=""
    if [ "$cdn" != "true" ] && [ "$secure" = "true" ]; then
        cert_json=$(printf '\n  "cert_file": "%s",\n  "key_file": "%s",' "$cert" "$key")
        cert_yaml=$(printf '\ncert_file: "%s"\nkey_file: "%s"' "$cert" "$key")
    fi

    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {
        if [ "$cdn" = "true" ]; then
            printf '{
  "mode": "server",
  "transport": "%s",
  "psk": "%s",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "connection_pool": %s,
      "peer_ips": [%s],
      "maps": [
%s
      ]
    }
  ],
  "xhttp": {
    "path": "%s",
    "mode": "auto",
    "up_max_bytes": %s,
    "up_concurrency": %s,
    "buffer_bytes": %s,
    "separate_conns": true,
    "probe_ms": %s,
    "socket_buf_bytes": %s,
    "allow_insecure_tls": %s,
    "cdn": {
      "enabled": true,
      "host": "%s",
      "port": %s,
      "edge_ips": [%s]
    }
  },
' "$transport" "$psk" "$port" "$pool" "$peer_json" "$ports_json" \
  "$path" "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES" \
  "$insecure" "$cdn_host" "$cdn_port" "$edge_json"
        else
            printf '{
  "mode": "server",
  "transport": "%s",
  "psk": "%s",
  "log_level": "info",%s
  "listeners": [
    {
      "addr": "0.0.0.0:%s",
      "maps": [
%s
      ]
    }
  ],
  "xhttp": {
    "path": "%s",
    "mode": "auto",
    "up_max_bytes": %s,
    "up_concurrency": %s,
    "buffer_bytes": %s,
    "separate_conns": true,
    "probe_ms": %s,
    "socket_buf_bytes": %s
  },
' "$transport" "$psk" "$cert_json" "$port" "$ports_json" "$path" \
  "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES"
        fi
        build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {
        if [ "$cdn" = "true" ]; then
            printf 'mode: server
transport: %s
psk: "%s"
log_level: info
listeners:
  - addr: "0.0.0.0:%s"
    connection_pool: %s
    peer_ips: %s
    maps:
%s
xhttp:
  path: "%s"
  mode: auto
  up_max_bytes: %s
  up_concurrency: %s
  buffer_bytes: %s
  separate_conns: true
  probe_ms: %s
  socket_buf_bytes: %s
  allow_insecure_tls: %s
  cdn:
    enabled: true
    host: "%s"
    port: %s
    edge_ips: %s

' "$transport" "$psk" "$port" "$pool" "$peer_yaml" "$ports_yaml" \
  "$path" "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES" \
  "$insecure" "$cdn_host" "$cdn_port" "$edge_yaml"
        else
            printf 'mode: server
transport: %s
psk: "%s"
log_level: info%s
listeners:
  - addr: "0.0.0.0:%s"
    maps:
%s
xhttp:
  path: "%s"
  mode: auto
  up_max_bytes: %s
  up_concurrency: %s
  buffer_bytes: %s
  separate_conns: true
  probe_ms: %s
  socket_buf_bytes: %s

' "$transport" "$psk" "$cert_yaml" "$port" "$ports_yaml" "$path" \
  "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES"
        fi
        build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_xhttp() {
    local server_ip="$1" server_port="$2" psk="$3" path="$4" mode="$5" secure="$6"
    local insecure="$7" cdn="$8" cdn_host="$9" cdn_port="${10}" cdn_ips="${11}"
    local origin_port="${12}" cert="${13}" key="${14}" public_ip="${15}"
    local transport addr peer_json peer_yaml cert_json cert_yaml up_concurrency

    transport="xhttp"
    [ "$secure" = "true" ] && transport="xhttps"
    up_concurrency=2
    [ "$cdn" = "true" ] && up_concurrency=8

    addr="${server_ip}:${server_port}"
    peer_json=$(build_edge_ips_json "$(echo "$server_ip" | xargs)")
    peer_yaml=$(build_edge_ips_yaml "$(echo "$server_ip" | xargs)")

    cert_json=""
    cert_yaml=""
    if [ "$cdn" = "true" ] && [ -n "$cert" ] && [ -n "$key" ]; then
        cert_json=$(printf '\n  "cert_file": "%s",\n  "key_file": "%s",' "$cert" "$key")
        cert_yaml=$(printf '\ncert_file: "%s"\nkey_file: "%s"' "$cert" "$key")
    fi

    mkdir -p "$CONFIG_DIR"
    if [ "$CONFIG_FMT" = "json" ]; then
        {
        if [ "$cdn" = "true" ]; then
            printf '{
  "mode": "client",
  "transport": "%s",
  "psk": "%s",
  "log_level": "info",%s
  "paths": [
    {
      "addr": "%s",
      "peer_ips": [%s],
      "public_ip": "%s",
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "xhttp": {
    "path": "%s",
    "mode": "%s",
    "up_max_bytes": %s,
    "up_concurrency": %s,
    "buffer_bytes": %s,
    "separate_conns": true,
    "probe_ms": %s,
    "socket_buf_bytes": %s,
    "cdn": {
      "enabled": true,
      "origin_bind": "0.0.0.0:%s"
    }
  },
' "$transport" "$psk" "$cert_json" "$addr" "$peer_json" "$public_ip" \
  "$path" "$mode" "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES" "$origin_port"
        else
            printf '{
  "mode": "client",
  "transport": "%s",
  "psk": "%s",
  "log_level": "info",
  "paths": [
    {
      "addr": "%s",
      "connection_pool": %s,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ],
  "xhttp": {
    "path": "%s",
    "mode": "%s",
    "up_max_bytes": %s,
    "up_concurrency": %s,
    "buffer_bytes": %s,
    "separate_conns": true,
    "probe_ms": %s,
    "socket_buf_bytes": %s,
    "allow_insecure_tls": %s
  },
' "$transport" "$psk" "$addr" "$CLIENT_CONN_POOL" "$path" "$mode" \
  "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES" "$insecure"
        fi
        build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
    else
        {
        if [ "$cdn" = "true" ]; then
            printf 'mode: client
transport: %s
psk: "%s"
log_level: info%s
paths:
  - addr: "%s"
    peer_ips: %s
    public_ip: "%s"
    retry_interval: 3
    dial_timeout: 10

xhttp:
  path: "%s"
  mode: "%s"
  up_max_bytes: %s
  up_concurrency: %s
  buffer_bytes: %s
  separate_conns: true
  probe_ms: %s
  socket_buf_bytes: %s
  cdn:
    enabled: true
    origin_bind: "0.0.0.0:%s"

' "$transport" "$psk" "$cert_yaml" "$addr" "$peer_yaml" "$public_ip" \
  "$path" "$mode" "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES" "$origin_port"
        else
            printf 'mode: client
transport: %s
psk: "%s"
log_level: info
paths:
  - addr: "%s"
    connection_pool: %s
    retry_interval: 3
    dial_timeout: 10

xhttp:
  path: "%s"
  mode: "%s"
  up_max_bytes: %s
  up_concurrency: %s
  buffer_bytes: %s
  separate_conns: true
  probe_ms: %s
  socket_buf_bytes: %s
  allow_insecure_tls: %s

' "$transport" "$psk" "$addr" "$CLIENT_CONN_POOL" "$path" "$mode" \
  "$XHTTP_UP_MAX_BYTES" "$up_concurrency" "$XHTTP_BUFFER_BYTES" "$XHTTP_PROBE_MS" "$XHTTP_SOCKET_BUF_BYTES" "$insecure"
        fi
        build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$port" "$cert" "$key" "$ports_json" "$http_domain" "$http_path"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$port" "$cert" "$key" "$ports_yaml" "$http_domain" "$http_path"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

write_client_config_https() {
    local server_ip="$1" server_port="$2" psk="$3" http_domain="$4" http_path="$5"
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
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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


' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
    "block": "%s"%s
  },
' "$psk" "$port" "$ports_json" "$mtu" "$block" "$(quantum_profile_json)"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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
  block: "%s"%s

' "$psk" "$port" "$ports_yaml" "$mtu" "$block" "$(quantum_profile_yaml)"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
    "block": "%s"%s
  },
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$mtu" "$block" "$(quantum_profile_json)"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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
  block: "%s"%s

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$mtu" "$block" "$(quantum_profile_yaml)"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
    fi
}

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
' "$psk" "$port" "$ports_json"; build_socks5_json; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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
' "$psk" "$port" "$ports_yaml"; build_socks5_yaml; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path"; build_dc_json; build_advanced_json; printf '}\n'; } > "$CONFIG"
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

' "$psk" "$server_ip" "$server_port" "$CLIENT_CONN_POOL" "$http_domain" "$http_path"; build_dc_yaml; build_advanced_yaml; } > "$CONFIG"
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
            printf '    "profile": "%s",
' "$TUN_TUNE_PROFILE"
            printf '    "encrypt": true,
'
            [ -n "$TUN_MTU"        ] && printf '    "mtu": %s,
' "$TUN_MTU"
            [ -n "$TUN_RX_QUEUE"   ] && printf '    "rx_queue": %s,
' "$TUN_RX_QUEUE"
            [ -n "$TUN_TXQUEUELEN" ] && printf '    "tx_queue_len": %s,
' "$TUN_TXQUEUELEN"
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
            printf '    "sock_buf": %s
' "${TUN_SOCK_BUF:-0}"
            printf '  },
'
            build_socks5_json
            build_dc_json
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
            if [ -n "$ports_yaml" ]; then
            printf '    maps:
'
            printf '%s
'               "$ports_yaml"
            else
                printf '    maps: []\n'
            fi
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
            printf '  profile: "%s"
' "$TUN_TUNE_PROFILE"
            printf '  encrypt: true
'
            [ -n "$TUN_MTU"        ] && printf '  mtu: %s
' "$TUN_MTU"
            [ -n "$TUN_RX_QUEUE"   ] && printf '  rx_queue: %s
' "$TUN_RX_QUEUE"
            [ -n "$TUN_TXQUEUELEN" ] && printf '  tx_queue_len: %s
' "$TUN_TXQUEUELEN"
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
            printf '  sock_buf: %s

' "${TUN_SOCK_BUF:-0}"
            build_socks5_yaml
            build_dc_yaml
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
            printf '    "profile": "%s",
' "$TUN_TUNE_PROFILE"
            printf '    "encrypt": true,
'
            [ -n "$TUN_MTU"        ] && printf '    "mtu": %s,
' "$TUN_MTU"
            [ -n "$TUN_RX_QUEUE"   ] && printf '    "rx_queue": %s,
' "$TUN_RX_QUEUE"
            [ -n "$TUN_TXQUEUELEN" ] && printf '    "tx_queue_len": %s,
' "$TUN_TXQUEUELEN"
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
            printf '    "sock_buf": %s
' "${TUN_SOCK_BUF:-0}"
            printf '  },
'
            build_dc_json
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
            printf '  profile: "%s"
' "$TUN_TUNE_PROFILE"
            printf '  encrypt: true
'
            [ -n "$TUN_MTU"        ] && printf '  mtu: %s
' "$TUN_MTU"
            [ -n "$TUN_RX_QUEUE"   ] && printf '  rx_queue: %s
' "$TUN_RX_QUEUE"
            [ -n "$TUN_TXQUEUELEN" ] && printf '  tx_queue_len: %s
' "$TUN_TXQUEUELEN"
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
            printf '  sock_buf: %s

' "${TUN_SOCK_BUF:-0}"
            build_dc_yaml
            build_advanced_yaml
        } > "$CONFIG"
    fi
}

install_service() {
    # Stop before replacing the unit if generated fields are not valid JSON.
    # Do not print the document: it contains the user's PSK.
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CONFIG" >/dev/null 2>&1; then
        error "Invalid JSON configuration; service unchanged. Check quoted input values."
    fi
    local extra_env=""
    if [ -n "$SERVER_PUBLIC_IP" ]; then
        extra_env="Environment=DC_SERVER_PUBLIC_IP=${SERVER_PUBLIC_IP}"
    fi
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=DaggerConnect Tunnel (${SERVICE_NAME})
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
Environment=DC_CHANNEL=${CHANNEL:-release}
Environment=DC_VERSION=${VERSION:-latest}
${extra_env}
ExecStart=${LAUNCHER} -c ${CONFIG}
Restart=always
RestartSec=60
RestartPreventExitStatus=78
TimeoutStopSec=20
KillSignal=SIGTERM
LimitNOFILE=1048576
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

ask_pair_profile_id() {
    info "Match the profile ID on both ends; use a different ID for each tunnel."
    while true; do
        ask_required PAIR_PROFILE_ID "Pairing profile ID"
        if [[ "$PAIR_PROFILE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]; then
            break
        fi
        warn "Use 1-64 ASCII letters, digits, dots, underscores or hyphens."
    done
}

install_server() {
    hr "Install Server"
    ensure_launcher server
    check_ptrace_scope
    tune_network
    echo ""

    ask_service_name
    ask_pair_profile_id
    echo ""

    ask_server_public_ip
    echo ""

    ask_transport
    select_transport_release server
    echo ""

    if [ "$TRANSPORT" = "tun" ]; then
        PORT="8443"
    elif [ "$TRANSPORT" = "xhttp" ] || [ "$TRANSPORT" = "xhttps" ]; then
        :
    else
        ask_num_range PORT "Listen port" 8443 1 65535
        echo ""
    fi

    ask_required PSK "PSK  (must match client)"
    echo ""

    case "$TRANSPORT" in
        dc6) ask_dc6_address server ;;
        ws|wss)
            ask WS_PATH "WebSocket path" "/ws"
            echo ""
            ;;
        http|https)
            ask HTTP_DOMAIN "Fake domain  (e.g. www.google.com)" "www.google.com"
            ask HTTP_PATH   "Fake path    (e.g. /search)" "/search"
            echo ""
            ;;
        xhttp|xhttps)
            ask_xhttp server
            if [ "$TRANSPORT" = "xhttps" ]; then
                ask_xhttp_cdn server
            else
                XHTTP_CDN="false"; XHTTP_CDN_HOST=""; XHTTP_CDN_PORT="80"
                XHTTP_CDN_IPS=""; XHTTP_INSECURE="true"; XHTTP_ORIGIN_PORT="8443"
                XHTTP_PEER_IP=""; XHTTP_PUBLIC_IP=""; XHTTP_CDN_POOL="6"
            fi
            if [ "$XHTTP_CDN" = "true" ]; then
                PORT="$XHTTP_CDN_PORT"
            else
                echo ""
                ask_num_range PORT "Listen port" 8443 1 65535
            fi
            echo ""
            ;;
        quantum)
            ask_quantum_settings
            echo ""
            ;;
        tun)
            ask_tun_encapsulation
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
            ask_tun_liveness
            ask_tun_profile
            echo ""
            ask TUN_DCPI_CHOICE "Enable DCPI (IPv4/proto58) (y/n)" "n"
            [ "$TUN_DCPI_CHOICE" = "y" ] || [ "$TUN_DCPI_CHOICE" = "Y" ] && TUN_DCPI="yes" || TUN_DCPI="no"
            TUN_SPOOF_CHOICE="n"
            if [ "$TUN_DCPI" != "yes" ]; then
                ask TUN_SPOOF_CHOICE "Enable IP Spoof (y/n)" "n"
            fi
            if [ "$TUN_SPOOF_CHOICE" = "y" ] || [ "$TUN_SPOOF_CHOICE" = "Y" ]; then
                ask TUN_SPOOF_SRC "Spoof Source IP" ""
                ask TUN_SPOOF_DST "Spoof Dest IP  " ""
            else
                TUN_SPOOF_SRC="" TUN_SPOOF_DST=""
            fi
            echo ""
            ;;
    esac

    if [ "$TRANSPORT" = "wss" ] || [ "$TRANSPORT" = "https" ] ||
       { [ "$TRANSPORT" = "xhttps" ] && [ "$XHTTP_CDN" != "true" ]; }; then
        ask_ssl_cert
        echo ""
    fi

    ask_ports
    echo ""

    ask_socks5
    echo ""

    ask_dc
    ask_advanced
    echo ""

    case "$TRANSPORT" in
        dc6)     write_server_config_dc6 "$PORT" "$PSK" "$DC6_IPV6" "${PORTS[@]}" ;;
        tcp)     write_server_config_tcp     "$PORT" "$PSK" "${PORTS[@]}" ;;
        ws)      write_server_config_ws      "$PORT" "$PSK" "$WS_PATH" "${PORTS[@]}" ;;
        wss)     write_server_config_wss     "$PORT" "$PSK" "$WS_PATH" "$CERT_FILE" "$KEY_FILE" "${PORTS[@]}" ;;
        http)    write_server_config_http    "$PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" "${PORTS[@]}" ;;
        https)   write_server_config_https   "$PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" "$CERT_FILE" "$KEY_FILE" "${PORTS[@]}" ;;
        quantum) write_server_config_quantum "$PORT" "$PSK" "$QM_MTU" "$QM_BLOCK" "${PORTS[@]}" ;;
        quantum+) write_server_config_quantumplus "$PORT" "$PSK" "${PORTS[@]}" ;;
        xhttp)   write_server_config_xhttp   "$PORT" "$PSK" "$XHTTP_PATH" "false" "" "" \
                     "$XHTTP_CDN" "$XHTTP_CDN_HOST" "$XHTTP_CDN_PORT" "$XHTTP_CDN_IPS" "$XHTTP_INSECURE" \
                     "$XHTTP_CDN_POOL" "$XHTTP_PEER_IP" "${PORTS[@]}" ;;
        xhttps)  write_server_config_xhttp   "$PORT" "$PSK" "$XHTTP_PATH" "true" "$CERT_FILE" "$KEY_FILE" \
                     "$XHTTP_CDN" "$XHTTP_CDN_HOST" "$XHTTP_CDN_PORT" "$XHTTP_CDN_IPS" "$XHTTP_INSECURE" \
                     "$XHTTP_CDN_POOL" "$XHTTP_PEER_IP" "${PORTS[@]}" ;;
        tun)     write_server_config_tun     "$PORT" "$PSK" "$TUN_LOCAL_IP" "$TUN_PEER_IP" "$TUN_LOCAL_ADDR" "$TUN_REMOTE_ADDR" "$TUN_ENCAP" "$TUN_PROFILE" "$TUN_IFACE" "$TUN_SPOOF_SRC" "$TUN_SPOOF_DST" "$TUN_DCPI" "$TUN_NAME" "$TUN_HEARTBEAT_SEC" "$TUN_IDLE_TIMEOUT_SEC" "${PORTS[@]}" ;;
    esac
    chmod 0600 "$CONFIG"
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
    show_new_transport_summary server
    echo "  PSK       : saved in config"
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
        if [ "${QM_PROFILE:-}" = gaming ]; then
            echo -e "  Profile   : ${BOLD}gaming${NC}  ${DIM}(set it on both endpoints)${NC}"
        fi
    fi
    if [ "$TRANSPORT" = "quantum+" ]; then
        echo -e "  ${YELLOW}Open UDP ${PORT} AND UDP $((PORT + 10000)) (knock port) in your firewall.${NC}"
    fi
    if [ "$TRANSPORT" = "xhttp" ] || [ "$TRANSPORT" = "xhttps" ]; then
        echo -e "  URL path  : ${BOLD}${XHTTP_PATH}${NC}  ${DIM}(the other side must use the same one)${NC}"
        if [ "$XHTTP_CDN" = "true" ]; then
            echo -e "  Cloudflare: ${BOLD}on — this side dials OUT${NC}"
            echo -e "  Domain    : ${BOLD}${XHTTP_CDN_HOST}${NC}  ${DIM}(this is what decides where traffic goes)${NC}"
            echo -e "  CF port   : ${BOLD}${XHTTP_CDN_PORT}${NC}"
            echo -e "  Edge IPs  : ${BOLD}${XHTTP_CDN_IPS}${NC}  ${DIM}(tried in this order)${NC}"
            echo -e "  ${DIM}Nothing needs opening in this firewall — this side only dials out.${NC}"
            echo -e "  ${DIM}The far side must be running and reachable through Cloudflare.${NC}"
        fi
        if [ "$TRANSPORT" = "xhttps" ] && [ "$XHTTP_CDN" != "true" ]; then
            echo -e "  SSL Mode  : ${BOLD}${SSL_MODE}${NC}"
            [ "$SSL_MODE" = "auto" ] && echo -e "  Domain    : ${BOLD}${DOMAIN}${NC}"
            echo -e "  Cert      : ${BOLD}${CERT_FILE}${NC}"
        fi
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
        echo -e "  SOCKS5    : ${BOLD}${SOCKS5_BIND}${NC}"
    fi
    echo -e "  Config    : ${BOLD}${CONFIG}${NC}"
    echo ""
    echo -e "  Logs      : journalctl -u ${SERVICE_NAME} -f"
    echo ""
}

install_client() {
    SERVER_PUBLIC_IP=""
    hr "Install Client"
    ensure_launcher client
    check_ptrace_scope
    tune_network
    echo ""

    ask_service_name
    ask_pair_profile_id
    echo ""

    ask_transport
    select_transport_release client
    echo ""

    if [ "$TRANSPORT" != "tun" ] && [ "$TRANSPORT" != "xhttp" ] && [ "$TRANSPORT" != "xhttps" ]; then
        ask_connection_pool
    fi

    if [ "$TRANSPORT" = "tun" ]; then
        SERVER_PORT="8443"
    elif [ "$TRANSPORT" = "xhttp" ] || [ "$TRANSPORT" = "xhttps" ]; then
        :
    else
        [ "$TRANSPORT" = "dc6" ] && info "Enter the server's LICENSED IPv4 and tunnel port here. IPv6 is requested separately."
        ask_server_endpoint
        echo ""
    fi

    ask_required PSK "PSK  (must match server)"
    echo ""

    case "$TRANSPORT" in
        dc6) ask_dc6_address client ;;
        ws|wss)
            ask WS_PATH "WebSocket path  (must match server)" "/ws"
            echo ""
            ;;
        http|https)
            ask HTTP_DOMAIN "Fake domain  (must match server)" "www.google.com"
            ask HTTP_PATH   "Fake path    (must match server)" "/search"
            echo ""
            ;;
        xhttp|xhttps)
            ask_xhttp client
            if [ "$TRANSPORT" = "xhttps" ]; then
                ask_xhttp_cdn client
            else
                XHTTP_CDN="false"; XHTTP_CDN_HOST=""; XHTTP_CDN_PORT="80"
                XHTTP_CDN_IPS=""; XHTTP_INSECURE="true"; XHTTP_ORIGIN_PORT="8443"
                XHTTP_PEER_IP=""; XHTTP_PUBLIC_IP=""; XHTTP_CDN_POOL="6"
            fi
            if [ "$XHTTP_CDN" = "true" ]; then
                echo ""
                while true; do
                    ask_required SERVER_IP "Server IP"
                    if ! validate_ip "$SERVER_IP"; then
                        warn "That is not an IP address."
                        continue
                    fi
                    if [ -n "$XHTTP_PUBLIC_IP" ] && [ "$SERVER_IP" = "$XHTTP_PUBLIC_IP" ]; then
                        warn "That is the same as the Client IP (${XHTTP_PUBLIC_IP})."
                        warn "These are two different servers — one of the two is wrong."
                        continue
                    fi
                    break
                done
                echo ""
                ok "Client IP : ${XHTTP_PUBLIC_IP:-not stated}"
                ok "Server IP : ${SERVER_IP}"
                SERVER_PORT="$XHTTP_ORIGIN_PORT"
                CLIENT_CONN_POOL=6

                echo ""
                echo -e "  ${BOLD}Certificate for Cloudflare to connect to${NC}"
                ask_ssl_cert
            else
                echo ""
                ask_connection_pool
                ask_server_endpoint
            fi
            echo ""
            ;;
        quantum)
            ask_quantum_settings
            echo ""
            ;;
        tun)
            ask_tun_encapsulation
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
            ask_tun_liveness
            ask_tun_profile
            echo ""
            ask TUN_DCPI_CHOICE "Enable DCPI (IPv4/proto58) (y/n)" "n"
            [ "$TUN_DCPI_CHOICE" = "y" ] || [ "$TUN_DCPI_CHOICE" = "Y" ] && TUN_DCPI="yes" || TUN_DCPI="no"
            TUN_SPOOF_CHOICE="n"
            if [ "$TUN_DCPI" != "yes" ]; then
                ask TUN_SPOOF_CHOICE "Enable IP Spoof (y/n)" "n"
            fi
            if [ "$TUN_SPOOF_CHOICE" = "y" ] || [ "$TUN_SPOOF_CHOICE" = "Y" ]; then
                ask TUN_SPOOF_SRC "Spoof Source IP" ""
                ask TUN_SPOOF_DST "Spoof Dest IP  " ""
            else
                TUN_SPOOF_SRC="" TUN_SPOOF_DST=""
            fi
            echo ""
            ;;
    esac

    if [ "$TRANSPORT" = "wss" ] || [ "$TRANSPORT" = "https" ]; then
        echo ""
    fi

    ask_dc
    ask_advanced
    echo ""

    case "$TRANSPORT" in
        dc6)     write_client_config_dc6 "$SERVER_IP" "$SERVER_PORT" "$PSK" "$DC6_IPV6" ;;
        tcp)     write_client_config_tcp     "$SERVER_IP" "$SERVER_PORT" "$PSK" ;;
        ws)      write_client_config_ws      "$SERVER_IP" "$SERVER_PORT" "$PSK" "$WS_PATH" ;;
        wss)     write_client_config_wss     "$SERVER_IP" "$SERVER_PORT" "$PSK" "$WS_PATH" ;;
        http)    write_client_config_http    "$SERVER_IP" "$SERVER_PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" ;;
        https)   write_client_config_https   "$SERVER_IP" "$SERVER_PORT" "$PSK" "$HTTP_DOMAIN" "$HTTP_PATH" ;;
        quantum) write_client_config_quantum "$SERVER_IP" "$SERVER_PORT" "$PSK" "$QM_MTU" "$QM_BLOCK" ;;
        quantum+) write_client_config_quantumplus "$SERVER_IP" "$SERVER_PORT" "$PSK" ;;
        xhttp)   write_client_config_xhttp   "$SERVER_IP" "$SERVER_PORT" "$PSK" "$XHTTP_PATH" "$XHTTP_MODE" "false" \
                     "$XHTTP_INSECURE" "$XHTTP_CDN" "$XHTTP_CDN_HOST" "$XHTTP_CDN_PORT" "$XHTTP_CDN_IPS" \
                     "$XHTTP_ORIGIN_PORT" "$CERT_FILE" "$KEY_FILE" "$XHTTP_PUBLIC_IP" ;;
        xhttps)  write_client_config_xhttp   "$SERVER_IP" "$SERVER_PORT" "$PSK" "$XHTTP_PATH" "$XHTTP_MODE" "true" \
                     "$XHTTP_INSECURE" "$XHTTP_CDN" "$XHTTP_CDN_HOST" "$XHTTP_CDN_PORT" "$XHTTP_CDN_IPS" \
                     "$XHTTP_ORIGIN_PORT" "$CERT_FILE" "$KEY_FILE" "$XHTTP_PUBLIC_IP" ;;
        tun)     write_client_config_tun     "$SERVER_PORT" "$PSK" "$TUN_LOCAL_IP" "$TUN_PEER_IP" "$TUN_LOCAL_ADDR" "$TUN_REMOTE_ADDR" "$TUN_ENCAP" "$TUN_PROFILE" "$TUN_IFACE" "$TUN_SPOOF_SRC" "$TUN_SPOOF_DST" "$TUN_DCPI" "$TUN_NAME" "$TUN_HEARTBEAT_SEC" "$TUN_IDLE_TIMEOUT_SEC" ;;
    esac
    chmod 0600 "$CONFIG"
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
    if [ "$TRANSPORT" = "tun" ]; then
        echo -e "  Server    : ${BOLD}${TUN_PEER_IP}${NC}  ${DIM}(tun — no listen port)${NC}"
    else
        echo -e "  Server    : ${BOLD}${SERVER_IP}:${SERVER_PORT}${NC}"
    fi
    show_new_transport_summary client
    echo "  PSK       : saved in config"
    [ "$TRANSPORT" = "ws"  ] && echo -e "  WS Path   : ${BOLD}${WS_PATH}${NC}"
    if [ "$TRANSPORT" = "wss" ]; then
        echo -e "  WS Path   : ${BOLD}${WS_PATH}${NC}"
    fi
    if [ "$TRANSPORT" = "http" ]; then
        echo -e "  Fake Domain : ${BOLD}${HTTP_DOMAIN}${NC}"
        echo -e "  Fake Path   : ${BOLD}${HTTP_PATH}${NC}"
    fi
    if [ "$TRANSPORT" = "https" ]; then
        echo -e "  Fake Domain : ${BOLD}${HTTP_DOMAIN}${NC}"
        echo -e "  Fake Path   : ${BOLD}${HTTP_PATH}${NC}"
    fi
    if [ "$TRANSPORT" = "quantum" ]; then
        echo -e "  Interface : ${BOLD}auto-detect${NC}"
        echo -e "  MTU       : ${BOLD}${QM_MTU}${NC}"
        echo -e "  Block     : ${BOLD}${QM_BLOCK}${NC}"
        if [ "${QM_PROFILE:-}" = gaming ]; then
            echo -e "  Profile   : ${BOLD}gaming${NC}  ${DIM}(set it on both endpoints)${NC}"
        fi
    fi
    if [ "$TRANSPORT" = "xhttp" ] || [ "$TRANSPORT" = "xhttps" ]; then
        echo -e "  URL path  : ${BOLD}${XHTTP_PATH}${NC}"
        echo -e "  Upload    : ${BOLD}${XHTTP_MODE}${NC}"
        if [ "$XHTTP_CDN" = "true" ]; then
            echo -e "  Route     : ${BOLD}Cloudflare — this side is the ORIGIN${NC}"
            echo -e "  Waiting on: ${BOLD}0.0.0.0:${XHTTP_ORIGIN_PORT}${NC}"
            echo ""
            warn "Point the proxied DNS record here and allow TCP ${XHTTP_ORIGIN_PORT}."
        else
            echo -e "  Route     : ${BOLD}direct to the server${NC}"
        fi
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
    pick_service "Logs for" || return 0
    journalctl -u "$PICKED_SVC" -n 80 --no-pager
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
        if ! [[ "$IDX" =~ ^[0-9]{1,9}$ ]] || (( 10#$IDX < 1 || 10#$IDX > ${#SERVICES[@]} )); then
            warn "Invalid selection."
            return 1
        fi
        IDX=$((10#$IDX))
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
    ask_num_range IDX "$prompt" 1 1 "${#SERVICES[@]}"
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

# ---------------------------------------------------------------------------
# Tester (menu 11)
#
# Server side: this server waits for the test.  Client side: this server runs it
# against the Server.  The test itself lives in the licensed core and runs through
# the launcher; the license is checked there, never here.  This installer only
# starts the launcher and shows what the core prints, with its exit status as the
# final answer.  Both sides use the PSK of the tunnel you plan to build and the
# fixed pairing profile ID below, so there is nothing else to type or copy.
# ---------------------------------------------------------------------------
LINKTEST_PROFILE_ID="DC-TEST"
LINKTEST_TMP_CFG=""
LT_PSK=""
LT_PROFILE=""

linktest_cleanup() {
    if [ -n "$LINKTEST_TMP_CFG" ]; then
        rm -f -- "$LINKTEST_TMP_CFG"
        LINKTEST_TMP_CFG=""
    fi
}

linktest_installed_profiles() {
    # file<TAB>mode<TAB>profile_id for installed configs. Never prints a PSK.
    python3 - "$CONFIG_DIR" <<'PY'
import glob, json, os, sys
for p in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        continue
    if isinstance(d, dict) and d.get("psk") and d.get("mode") in ("server", "client"):
        print("%s\t%s\t%s" % (p, d["mode"], d.get("profile_id") or "default"))
PY
}

linktest_read_field() {
    python3 - "$1" "$2" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        v = json.load(f).get(sys.argv[2])
except (OSError, ValueError):
    v = None
print("" if v is None else v)
PY
}

linktest_pick_pairing() {
    LT_PSK=""; LT_PROFILE="$LINKTEST_PROFILE_ID"
    local files=() labels=() f m p c i
    while IFS=$'\t' read -r f m p; do
        [ -n "$f" ] || continue
        files+=("$f")
        labels+=("$(basename "$f" .json)  (${m})")
    done < <(linktest_installed_profiles)

    info "Use the PSK of the tunnel you plan to build, the same on both servers."
    if [ "${#files[@]}" -gt 0 ]; then
        echo ""
        for i in "${!labels[@]}"; do
            printf '    %d) Use the PSK of %s\n' "$((i + 1))" "${labels[$i]}"
        done
        printf '    %d) Enter a PSK manually\n' "$(( ${#labels[@]} + 1 ))"
        echo ""
        ask c "Choice" "1"
        if [[ "$c" =~ ^[0-9]{1,3}$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#files[@]}" ]; then
            f="${files[$((c - 1))]}"
            LT_PSK=$(linktest_read_field "$f" psk)
            ok "Using the PSK of ${labels[$((c - 1))]}"
            return 0
        fi
    fi
    printf '%b  ?%b PSK (typing is hidden): ' "$CYAN" "$NC"
    if ! read -r -s LT_PSK; then
        printf '\n' >&2
        exit 130
    fi
    printf '\n'
    [ -n "$LT_PSK" ] || error "The PSK cannot be empty."
}

linktest_write_config() {
    # role peer -> sets LINKTEST_TMP_CFG (0600, removed on exit)
    local role="$1" peer="${2:-}" old_umask
    old_umask=$(umask)
    umask 077
    LINKTEST_TMP_CFG=$(mktemp --suffix=.json /var/tmp/dc-linktest.XXXXXX) || { umask "$old_umask"; error "Cannot create a temporary config."; }
    umask "$old_umask"
    if ! LT_PSK="$LT_PSK" LT_PROFILE="$LT_PROFILE" LT_PEER="$peer" python3 - "$role" "$LINKTEST_TMP_CFG" <<'PY'
import json, os, sys
role, path = sys.argv[1], sys.argv[2]
psk, profile, peer = os.environ["LT_PSK"], os.environ["LT_PROFILE"], os.environ.get("LT_PEER", "")
# The core derives the real test port from the PSK; this port is a placeholder
# that only has to make the config valid for the launcher.
if role == "server":
    cfg = {"mode": "server", "psk": psk, "profile_id": profile,
           "listeners": [{"addr": "0.0.0.0:20000", "transport": "tcp", "maps": []}]}
else:
    cfg = {"mode": "client", "psk": psk, "profile_id": profile,
           "paths": [{"transport": "tcp", "addr": peer + ":20000"}]}
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f)
PY
    then
        linktest_cleanup
        error "Could not write the temporary test config."
    fi
    chmod 600 "$LINKTEST_TMP_CFG"
}

# Runs the core through the launcher; retries once with another core version when
# the fetched core does not include Link Test.
linktest_run_core() {
    local role="$1"; shift
    local log rc attempt
    log=$(mktemp /var/tmp/dc-linktest-log.XXXXXX) || error "Cannot create a temporary log."
    for attempt in 1 2; do
        : > "$log"
        env DC_CHANNEL="${CHANNEL:-release}" DC_VERSION="${VERSION:-latest}" \
            ${SERVER_PUBLIC_IP:+DC_SERVER_PUBLIC_IP="$SERVER_PUBLIC_IP"} \
            "$LAUNCHER" -c "$LINKTEST_TMP_CFG" "$@" 2> >(tee "$log" >&2)
        rc=$?
        sleep 0.3
        if [ "$rc" -ne 0 ] && grep -q "flag provided but not defined" "$log"; then
            echo ""
            warn "The core version the launcher fetched does not include Link Test."
            if [ "$attempt" -eq 1 ]; then
                info "Pick stable v4.2.8+ or beta v4.3.1+."
                ask_version "$role" "v4.3.1" "v4.2.8"
                continue
            fi
        fi
        break
    done
    rm -f -- "$log"
    return "$rc"
}

linktest_run() {
    # role peer quick
    local role="$1" peer="${2:-}" quick="${3:-}" rc args=()
    CHANNEL="${DC_CHANNEL:-release}"; VERSION="${DC_VERSION:-latest}"
    ensure_launcher "$role"
    echo ""
    linktest_pick_pairing
    SERVER_PUBLIC_IP=""
    if [ "$role" = "server" ]; then
        ask_server_public_ip
        echo ""
        info "On the other server choose Tester > Client and enter this IP: ${SERVER_PUBLIC_IP}"
        info "Allow the test ports (TCP and UDP) in this server's firewall while testing."
    fi
    trap linktest_cleanup EXIT
    trap 'linktest_cleanup; exit 130' INT TERM
    linktest_write_config "$role" "$peer"
    echo ""
    if [ "$role" = "server" ]; then
        args=(-linktest listen)
    else
        args=(-linktest probe -lt-peer "$peer")
        [ "$quick" = "quick" ] && args+=(-lt-quick)
    fi
    rc=0
    linktest_run_core "$role" "${args[@]}" || rc=$?
    linktest_cleanup
    return "$rc"
}

linktest_listen() {
    hr "Tester: Server side (waiting for the Client)"
    linktest_run server
}

linktest_probe() {
    local peer="$1" quick="${2:-}"
    hr "Tester: Client side (testing the path to ${peer})"
    linktest_run client "$peer" "$quick"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        echo ""
        info "To use the result: run Install Server and Install Client and choose the transport"
        info "under RECOMMENDED on BOTH servers (same transport and profile on each)."
    fi
    return "$rc"
}

linktest_menu() {
    hr "Tester"
    info "Find out which tunnel works best between two of YOUR servers."
    info "Run the Server side first, then the Client side on the other server."
    info "Both sides use the PSK and profile ID of the tunnel you plan to build."
    echo ""
    echo "    1) Server   (this server waits for the test; its IP is detected)"
    echo "    2) Client   (this server runs the test against the Server)"
    echo "    0) Back"
    echo ""
    local c peer mode
    ask c "Choice" ""
    case "$c" in
        1) linktest_listen ;;
        2)
            while true; do
                ask_required peer "Server public IPv4 (the server running the Server side)"
                validate_ip "$peer" && break
                warn "Enter an IPv4 address such as 203.0.113.10."
            done
            echo ""
            echo "    1) Quick test  (about 1 minute)"
            echo "    2) Full test   (about 2-3 minutes, more accurate speeds)"
            echo ""
            ask mode "Choice" "2"
            if [ "$mode" = "1" ]; then linktest_probe "$peer" quick; else linktest_probe "$peer"; fi ;;
        0|"") return 0 ;;
        *) warn "Invalid choice: ${c}" ;;
    esac
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
    echo "    4)  Service Control"
    echo "    5)  Edit Config"
    echo ""
    echo -e "  ${BOLD}Logs${NC}"
    echo "    6)  Recent Logs"
    echo "    7)  Live Logs"
    echo ""
    echo -e "  ${BOLD}Diagnose${NC}"
    echo "   11)  Tester (which tunnel works best between two servers)"
    echo ""
    echo -e "  ${BOLD}Other${NC}"
    echo "    8)  Remove"
    echo "    9)  Core Version"
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
    printf '  Press Enter to return: '
    read -r _ || exit 130
}

if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    return 0 2>/dev/null || true
fi

[ "$EUID" -ne 0 ] && { echo -e "${RED}[ERR ]${NC}  Run as root: sudo bash setup.sh"; exit 1; }
ensure_runtime_dependencies

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
        11) run_action linktest_menu ;;
        0) echo -e "\n  ${CYAN}Bye.${NC}\n"; exit 0 ;;
        *) warn "Invalid choice: ${CHOICE}" ;;
    esac

    pause
done
