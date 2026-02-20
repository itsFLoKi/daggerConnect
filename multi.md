# ⚙️ DaggerConnect — نمونه کانفیگ‌های Multi-Listener و Multi-Path

> کانفیگ‌های آماده برای تمام حالت‌ها — با TUN و بدون TUN

---

## 📑 فهرست

- [Multi-Listener Server — بدون TUN](#-multi-listener-server--بدون-tun)
- [Multi-Listener Server — با TUN](#-multi-listener-server--با-tun)
- [Multi-Path Client — بدون TUN](#-multi-path-client--بدون-tun)
- [Multi-Path Client — با TUN](#-multi-path-client--با-tun)
- [ترکیب کامل — Multi-Listener + Multi-Path + TUN](#-ترکیب-کامل--multi-listener--multi-path--tun)
- [نکات مهم](#-نکات-مهم)

---

## 📡 Multi-Listener Server — بدون TUN

چند listener با پروتکل و پورت متفاوت روی یک سرور.

```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false
heartbeat: 10

cert_file: "/etc/DaggerConnect/certs/cert.pem"
key_file: "/etc/DaggerConnect/certs/key.pem"

listeners:

  # ── Listener 0 — HTTPS روی پورت 443
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "/etc/DaggerConnect/certs/cert.pem"
    key_file: "/etc/DaggerConnect/certs/key.pem"
    maps:
      - { type: tcp, bind: "0.0.0.0:8443", target: "127.0.0.1:8443" }
      - { type: tcp, bind: "0.0.0.0:2222", target: "127.0.0.1:22"   }

  # ── Listener 1 — HTTP روی پورت 80
  - addr: "0.0.0.0:80"
    transport: "httpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:8080", target: "127.0.0.1:8080" }
      - { type: udp, bind: "0.0.0.0:5353", target: "127.0.0.1:5353" }

  # ── Listener 2 — KCP (UDP) روی پورت 4000
  - addr: "0.0.0.0:4000"
    transport: "kcpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:25565", target: "127.0.0.1:25565" }
      - { type: udp, bind: "0.0.0.0:25565", target: "127.0.0.1:25565" }

  # ── Listener 3 — WebSocket Secure روی پورت 8443
  - addr: "0.0.0.0:8443"
    transport: "wssmux"
    cert_file: "/etc/DaggerConnect/certs/cert.pem"
    key_file: "/etc/DaggerConnect/certs/key.pem"
    maps:
      - { type: tcp, bind: "0.0.0.0:9000", target: "127.0.0.1:9000" }

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768

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
  cleanup_interval: 3
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
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
```

---

## 🌐 Multi-Listener Server — با TUN

هر listener یک TUN interface **مجزا و ایزوله** دارد.

```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false
heartbeat: 10

cert_file: "/etc/DaggerConnect/certs/cert.pem"
key_file: "/etc/DaggerConnect/certs/key.pem"

listeners:

  # ── Listener 0 — HTTPS + TUN
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "/etc/DaggerConnect/certs/cert.pem"
    key_file: "/etc/DaggerConnect/certs/key.pem"
    maps:
      - { type: tcp, bind: "0.0.0.0:8443", target: "127.0.0.1:8443" }
    tun:
      enabled: true
      name: "dagger0"        # نام interface — باید unique باشد
      local_ip: "10.0.0.1"  # IP این سرور در تانل
      peer_ip: "10.0.0.2"   # IP کلاینت متناظر
      mtu: 1400

  # ── Listener 1 — HTTP + TUN (IP range متفاوت!)
  - addr: "0.0.0.0:80"
    transport: "httpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:8080", target: "127.0.0.1:8080" }
    tun:
      enabled: true
      name: "dagger1"        # نام متفاوت
      local_ip: "10.0.1.1"  # IP range متفاوت — تداخل نداشته باشد
      peer_ip: "10.0.1.2"
      mtu: 1400

  # ── Listener 2 — KCP + TUN
  - addr: "0.0.0.0:4000"
    transport: "kcpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:9000", target: "127.0.0.1:9000" }
      - { type: udp, bind: "0.0.0.0:9000", target: "127.0.0.1:9000" }
    tun:
      enabled: true
      name: "dagger2"
      local_ip: "10.0.2.1"
      peer_ip: "10.0.2.2"
      mtu: 1400

  # ── Listener 3 — بدون TUN (TUN اختیاری است)
  - addr: "0.0.0.0:8080"
    transport: "wsmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:7000", target: "127.0.0.1:7000" }

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768

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
  cleanup_interval: 3
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
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
```

---

## 🛣️ Multi-Path Client — بدون TUN

اتصال به چند سرور همزمان، هر path با connection pool مستقل.

```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false
heartbeat: 10

paths:

  # ── Path 0 — سرور اصلی با HTTPS
  - transport: "httpsmux"
    addr: "iran1.example.com:443"
    connection_pool: 3
    aggressive_pool: false
    retry_interval: 3
    dial_timeout: 10
    # psk نداره = از psk global استفاده می‌کنه

  # ── Path 1 — سرور بکاپ با HTTP
  - transport: "httpmux"
    addr: "iran2.example.com:80"
    connection_pool: 2
    aggressive_pool: false
    retry_interval: 5
    dial_timeout: 10

  # ── Path 2 — سرور دیگر با PSK متفاوت
  - transport: "httpsmux"
    addr: "iran3.example.com:443"
    psk: "DIFFERENT_LICENSE_KEY"   # PSK مخصوص این سرور
    connection_pool: 2
    aggressive_pool: false
    retry_interval: 3
    dial_timeout: 10

  # ── Path 3 — KCP برای شرایط اضطراری
  - transport: "kcpmux"
    addr: "iran4.example.com:4000"
    connection_pool: 2
    aggressive_pool: true
    retry_interval: 3
    dial_timeout: 10

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768

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
  cleanup_interval: 3
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
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
```

---

## 🌐 Multi-Path Client — با TUN

هر path می‌تواند TUN interface **مجزا** داشته باشد.

```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false
heartbeat: 10

paths:

  # ── Path 0 — HTTPS + TUN
  # باید با Listener 0 سرور (local_ip: 10.0.0.1) match باشد
  - transport: "httpsmux"
    addr: "iran1.example.com:443"
    connection_pool: 3
    aggressive_pool: false
    retry_interval: 3
    dial_timeout: 10
    tun:
      enabled: true
      name: "dagger0"        # نام interface — باید unique باشد
      local_ip: "10.0.0.2"  # IP کلاینت (peer_ip سرور)
      peer_ip: "10.0.0.1"   # IP سرور (local_ip سرور)
      mtu: 1400

  # ── Path 1 — HTTP + TUN (IP range متفاوت)
  # باید با Listener 1 سرور (local_ip: 10.0.1.1) match باشد
  - transport: "httpmux"
    addr: "iran2.example.com:80"
    connection_pool: 2
    aggressive_pool: false
    retry_interval: 5
    dial_timeout: 10
    tun:
      enabled: true
      name: "dagger1"        # نام متفاوت
      local_ip: "10.0.1.2"  # باید با peer_ip سرور یکی باشد
      peer_ip: "10.0.1.1"   # باید با local_ip سرور یکی باشد
      mtu: 1400

  # ── Path 2 — KCP + TUN
  - transport: "kcpmux"
    addr: "iran3.example.com:4000"
    connection_pool: 2
    aggressive_pool: true
    retry_interval: 3
    dial_timeout: 10
    tun:
      enabled: true
      name: "dagger2"
      local_ip: "10.0.2.2"
      peer_ip: "10.0.2.1"
      mtu: 1400

  # ── Path 3 — بدون TUN
  - transport: "httpsmux"
    addr: "iran4.example.com:443"
    psk: "DIFFERENT_LICENSE_KEY"
    connection_pool: 2
    aggressive_pool: false
    retry_interval: 3
    dial_timeout: 10

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768

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
  cleanup_interval: 3
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
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
```

---

## 🔗 ترکیب کامل — Multi-Listener + Multi-Path + TUN

جدول تطابق IP های TUN بین سرور و کلاینت:

| Listener/Path | Transport | پورت | TUN Server | TUN Client |
|:---:|-----------|------|-----------|-----------|
| #0 | httpsmux | 443 | `10.0.0.1/32` | `10.0.0.2/32` |
| #1 | httpmux | 80 | `10.0.1.1/32` | `10.0.1.2/32` |
| #2 | kcpmux | 4000 | `10.0.2.1/32` | `10.0.2.2/32` |
| #3 | wsmux | 8080 | — (بدون TUN) | — (بدون TUN) |

### server.yaml

```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false
heartbeat: 10

cert_file: "/etc/DaggerConnect/certs/cert.pem"
key_file: "/etc/DaggerConnect/certs/key.pem"

listeners:

  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "/etc/DaggerConnect/certs/cert.pem"
    key_file: "/etc/DaggerConnect/certs/key.pem"
    maps:
      - { type: tcp, bind: "0.0.0.0:8443", target: "127.0.0.1:8443" }
    tun:
      enabled: true
      name: "dagger0"
      local_ip: "10.0.0.1"
      peer_ip: "10.0.0.2"
      mtu: 1400

  - addr: "0.0.0.0:80"
    transport: "httpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:8080", target: "127.0.0.1:8080" }
      - { type: udp, bind: "0.0.0.0:5353", target: "127.0.0.1:5353" }
    tun:
      enabled: true
      name: "dagger1"
      local_ip: "10.0.1.1"
      peer_ip: "10.0.1.2"
      mtu: 1400

  - addr: "0.0.0.0:4000"
    transport: "kcpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:25565", target: "127.0.0.1:25565" }
      - { type: udp, bind: "0.0.0.0:25565", target: "127.0.0.1:25565" }
    tun:
      enabled: true
      name: "dagger2"
      local_ip: "10.0.2.1"
      peer_ip: "10.0.2.2"
      mtu: 1400

  - addr: "0.0.0.0:8080"
    transport: "wsmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:9000", target: "127.0.0.1:9000" }

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768

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
  cleanup_interval: 3
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
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
```

### client.yaml

```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false
heartbeat: 10

paths:

  - transport: "httpsmux"
    addr: "IRAN_SERVER_IP:443"
    connection_pool: 3
    aggressive_pool: false
    retry_interval: 3
    dial_timeout: 10
    tun:
      enabled: true
      name: "dagger0"
      local_ip: "10.0.0.2"
      peer_ip: "10.0.0.1"
      mtu: 1400

  - transport: "httpmux"
    addr: "IRAN_SERVER_IP:80"
    connection_pool: 2
    aggressive_pool: false
    retry_interval: 3
    dial_timeout: 10
    tun:
      enabled: true
      name: "dagger1"
      local_ip: "10.0.1.2"
      peer_ip: "10.0.1.1"
      mtu: 1400

  - transport: "kcpmux"
    addr: "IRAN_SERVER_IP:4000"
    connection_pool: 2
    aggressive_pool: true
    retry_interval: 3
    dial_timeout: 10
    tun:
      enabled: true
      name: "dagger2"
      local_ip: "10.0.2.2"
      peer_ip: "10.0.2.1"
      mtu: 1400

  - transport: "wsmux"
    addr: "IRAN_SERVER_IP:8080"
    connection_pool: 2
    aggressive_pool: false
    retry_interval: 5
    dial_timeout: 10

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608
  max_stream: 8388608
  frame_size: 32768

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
  cleanup_interval: 3
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
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
```

---

## ⚠️ نکات مهم

### قوانین TUN

| قانون | توضیح |
|-------|-------|
| **IP های `/32` استفاده می‌شود** | هر TUN فقط یک IP point-to-point دارد |
| **نام interface باید unique باشد** | `dagger0`، `dagger1`، `dagger2` — تکراری نباشد |
| **IP range هر TUN باید متفاوت باشد** | `10.0.0.x`، `10.0.1.x`، `10.0.2.x` — تداخل نداشته باشد |
| **local_ip سرور = peer_ip کلاینت** | و برعکس — باید دقیقاً match باشند |
| **نیاز به دسترسی root** | TUN interface بدون `sudo` کار نمی‌کند |

### قوانین Multi-Listener

| قانون | توضیح |
|-------|-------|
| **پورت bind باید unique باشد** | دو listener نمی‌توانند یک پورت bind داشته باشند |
| **هر listener session مجزا دارد** | قطعی یک listener روی بقیه تأثیر ندارد |
| **cert فقط برای httpsmux و wssmux لازم است** | برای httpmux، wsmux، kcpmux لازم نیست |

### قوانین Multi-Path

| قانون | توضیح |
|-------|-------|
| **psk در path اختیاری است** | اگر نباشد از global psk استفاده می‌شود |
| **هر path reconnect مستقل دارد** | قطعی یک path بقیه را متوقف نمی‌کند |
| **connection_pool توصیه: 2-4** | بیشتر از 4 معمولاً مفید نیست |
| **aggressive_pool** | برای اتصال‌های ناپایدار مناسب‌تر است |