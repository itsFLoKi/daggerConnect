# ⚙️ DaggerConnect 

<div align="center">

**ریورس تانل حرفه‌ای با Traffic Obfuscation**

[![buyLICENSE](https://img.shields.io/badge/buyLICENSE-@DaggerConnectBot-blue.svg)](https://t.me/DaggerConnectBot)
[![Version](https://img.shields.io/badge/version-1.3.3-blue.svg)](https://github.com/itsFLoKi/DaggerConnect/releases)
[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org)
[![Telegram](https://img.shields.io/badge/Telegram-@DaggerConnect-blue.svg)](https://t.me/DaggerConnect)

[ویژگی‌ها](#-ویژگیها) • [نصب سریع](#-نصب-سریع) • [آموزش](#-آموزش-گام-به-گام) • [کانفیگ](#-کانفیگ-کامل) • [عیب‌یابی](#-عیبیابی)

</div>

---

## 🎯 معرفی

ریورس تانل قدرتمند
---

## ✨ ویژگی‌ها

- 🎭 **HTTP/HTTPS Mimicry** — شبیه‌سازی کامل ترافیک مرورگر Chrome/Firefox
- 📡 **Multi-Listener** — چند پورت و پروتکل همزمان روی سرور
- 🛣️ **Multi-Path** — اتصال کلاینت به چندین سرور با Connection Pool مجزا
- 🔀 **Traffic Obfuscation** — padding تصادفی + jitter delay
- 📦 **UDP Support** — فوروارد کامل UDP
- 🌐 **TUN Interface** — تانل سطح شبکه (layer 3)
- 🔁 **Auto-Reconnect** — اتصال مجدد هوشمند با exponential backoff
- ⚡ **KCP Transport** — پروتکل UDP-based برای کمترین تاخیر
- 🔗 **smux Multiplexing** — چند stream روی یک اتصال
- 🔐 **AES-GCM Encryption** — رمزنگاری end-to-end با PSK
- 💓 **Heartbeat** — تشخیص قطعی و بستن session مرده

---

## 🚀 نصب سریع

### نصب با اسکریپت (توصیه می‌شود)

```bash
curl -O https://raw.githubusercontent.com/itsFLoKi/DaggerConnect/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

### نصب دستی

```bash
# دانلود باینری
wget https://github.com/itsFLoKi/DaggerConnect/releases/download/LASTVERSION/DaggerConnect
chmod +x DaggerConnect
sudo mv DaggerConnect /usr/local/bin/

# ساخت کانفیگ پیش‌فرض
DaggerConnect --gen server   # → DaggerConnect-server.yaml
DaggerConnect --gen client   # → DaggerConnect-client.yaml

# ایجاد دایرکتوری
sudo mkdir -p /etc/DaggerConnect
```

### گزینه‌های CLI

```
DaggerConnect -c config.yaml     # اجرا با کانفیگ
DaggerConnect --gen server       # ساخت کانفیگ سرور
DaggerConnect --gen client       # ساخت کانفیگ کلاینت
DaggerConnect -v                 # نمایش نسخه
```

---

## 📚 آموزش گام به گام

### 🖥️ راه‌اندازی سرور (سرور ایران / مقصد)

سرور باید روی ماشینی باشد که **کلاینت‌ها به آن وصل می‌شوند** (معمولاً سرور ایران).

#### مرحله ۱ — ساخت کانفیگ

```bash
DaggerConnect --gen server
# فایل DaggerConnect-server.yaml ساخته می‌شود
```

#### مرحله ۲ — ویرایش کانفیگ

```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"          # کد لایسنس از @DaggerConnectBot
profile: "balanced"
verbose: false

listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "cert.pem"
    key_file: "key.pem"
    maps:
      - type: tcp
        bind: "0.0.0.0:2222"
        target: "127.0.0.1:22"
```

#### مرحله ۳ — اجرا

```bash
sudo DaggerConnect -c DaggerConnect-server.yaml
```

---

### 💻 راه‌اندازی کلاینت (سرور خارج / مبدا)

کلاینت روی ماشینی اجرا می‌شود که **سرویس اصلی روی آن است** (معمولاً سرور خارج).

#### مرحله ۱ — ساخت کانفیگ

```bash
DaggerConnect --gen client
```

#### مرحله ۲ — ویرایش کانفیگ

```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"          # همان PSK سرور
profile: "balanced"
verbose: false

paths:
  - transport: "httpsmux"
    addr: "IRAN_SERVER_IP:443"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10
```

#### مرحله ۳ — اجرا

```bash
sudo DaggerConnect -c DaggerConnect-client.yaml
```

---

## 🎨 پروتکل‌ها و Transports

| Transport | پورت | امنیت | سرعت | کاربرد |
|-----------|------|-------|------|--------|
| `httpsmux` | 443 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **HTTPS + TLS — توصیه می‌شود** |
| `httpmux` | 80 | ⭐⭐⭐ | ⭐⭐⭐⭐ | HTTP میمیکری |
| `wssmux` | 443 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | WebSocket + TLS |
| `wsmux` | 80 | ⭐⭐⭐ | ⭐⭐⭐ | WebSocket |
| `kcpmux` | UDP | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | سرعت بالا / gaming |
| `tcpmux` | Any | ⭐⭐⭐ | ⭐⭐⭐⭐ | ساده و سریع |
| `rawmux` | Any | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Raw TCP — کمترین overhead |

---

## 🎮 پروفایل‌های عملکرد

پروفایل مقادیر پیش‌فرض KCP و smux را تنظیم می‌کند. اگر مقادیر را دستی تنظیم کنید، پروفایل نادیده گرفته می‌شود.

| Profile | کاربرد | KCP Interval | smux Keepalive |
|---------|--------|-------------|----------------|
| `balanced` | پیش‌فرض — تعادل سرعت/CPU | 10ms | 8s |
| `aggressive` | بیشترین پهنای باند | 8ms | 5s |
| `latency` | کمترین تاخیر | 8ms | 3s |
| `cpu-efficient` | مصرف CPU کم | 20ms | 10s |
| `gaming` | gaming / VoIP | 5ms | 2s |

```yaml
profile: "balanced"   # balanced | aggressive | latency | cpu-efficient | gaming
```

---

## 📡 Multi-Listener (سرور)

می‌توانید چند listener با پورت، پروتکل و TLS متفاوت روی یک سرور داشته باشید.

> **توجه:** برای جلوگیری از تداخل، حتماً هر listener پورت متفاوت داشته باشد.

```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"

listeners:
  # Listener 1 — HTTPS روی پورت 443
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "/etc/DaggerConnect/certs/cert.pem"
    key_file: "/etc/DaggerConnect/certs/key.pem"
    maps:
      - type: tcp
        bind: "0.0.0.0:8664"
        target: "127.0.0.1:8664"

  # Listener 2 — HTTP روی پورت 80
  - addr: "0.0.0.0:80"
    transport: "httpmux"
    maps:
      - type: tcp
        bind: "0.0.0.0:5456"
        target: "127.0.0.1:5456"
      - type: udp
        bind: "0.0.0.0:5456"
        target: "127.0.0.1:5456"

  # Listener 3 — KCP روی پورت 4000
  - addr: "0.0.0.0:4000"
    transport: "kcpmux"
    maps:
      - type: tcp
        bind: "0.0.0.0:6000"
        target: "127.0.0.1:6000"

  # Listener 4 — WebSocket روی پورت 8080
  - addr: "0.0.0.0:8080"
    transport: "wsmux"
    maps:
      - type: tcp
        bind: "0.0.0.0:7000"
        target: "127.0.0.1:7000"

  # Listener 5 — Raw TCP روی پورت 5000
  - addr: "0.0.0.0:5000"
    transport: "rawmux"
    maps:
      - type: tcp
        bind: "0.0.0.0:9000"
        target: "127.0.0.1:9000"
```

**نکات:**
- هر listener سشن منیجر و UDP منیجر **کاملاً مجزا** دارد
- `cert_file` و `key_file` فقط برای transport های `httpsmux` و `wssmux` لازم است
- اگر `cert_file` در listener خالی باشد، از مقدار global استفاده می‌شود

---

## 🛣️ Multi-Path (کلاینت)

می‌توانید از کلاینت به چند سرور همزمان وصل شوید. هر path یک connection pool مستقل دارد و در صورت قطع، به‌صورت مستقل reconnect می‌کند.

```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"

paths:
  # Path 1 — سرور اصلی با HTTPS
  - transport: "httpsmux"
    addr: "server1.example.com:443"
    connection_pool: 3        # تعداد اتصال موازی
    retry_interval: 3         # ثانیه بین هر تلاش مجدد
    dial_timeout: 10          # timeout اتصال (ثانیه)

  # Path 2 — سرور بکاپ با HTTP
  - transport: "httpmux"
    addr: "server2.example.com:80"
    connection_pool: 2
    retry_interval: 5
    dial_timeout: 10

  # Path 3 — سرور بکاپ با KCP (UDP)
  - transport: "kcpmux"
    addr: "server3.example.com:4000"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

  # Path 4 — PSK متفاوت برای سرور دیگر
  - transport: "httpsmux"
    addr: "server4.example.com:443"
    psk: "DIFFERENT_LICENSE_KEY"   # PSK مخصوص این سرور
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

  # Path 5 — Raw TCP با کمترین overhead
  - transport: "rawmux"
    addr: "server5.example.com:5000"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10
```

**نکات:**
- `connection_pool` تعداد اتصال موازی به هر سرور را تعیین می‌کند (توصیه: 2-4)
- اگر یک path قطع شود، path های دیگر **تحت تأثیر قرار نمی‌گیرند**
- `psk` در path اختیاری است — اگر نباشد از PSK global استفاده می‌شود
- Reconnect از backoff نمایی استفاده می‌کند (max: 60 ثانیه)

---

## 🔧 کانفیگ کامل

### کانفیگ کامل سرور

```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false

# برای transport های TLS
cert_file: "cert.pem"
key_file: "key.pem"

heartbeat: 10          # فاصله heartbeat به ثانیه

smux:
  version: 2
  keepalive: 8
  max_recv: 8388608    # 8MB
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

rawmux:
  handshake_timeout: 10
  keepalive: 15
  read_buffer: 4194304
  write_buffer: 4194304
  use_pcap: true

advanced:
  tcp_nodelay: true
  tcp_keepalive: 15
  tcp_read_buffer: 16777216
  tcp_write_buffer: 16777216
  cleanup_interval: 3
  session_timeout: 30
  connection_timeout: 60
  stream_timeout: 120
  max_connections: 2000
  max_udp_flows: 1000
  udp_flow_timeout: 300
  udp_buffer_size: 4194304

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 512
  min_delay_ms: 5
  max_delay_ms: 50
  burst_chance: 0.15    # احتمال ارسال بدون delay

http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  chunked_encoding: false
  session_cookie: true
  custom_headers: []

listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "cert.pem"
    key_file: "key.pem"
    maps:
      - type: tcp
        bind: "0.0.0.0:2222"
        target: "127.0.0.1:22"
      - type: udp
        bind: "0.0.0.0:53"
        target: "127.0.0.1:53"
```

### کانفیگ کامل کلاینت

```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"
verbose: false

heartbeat: 10

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

rawmux:
  handshake_timeout: 10
  keepalive: 15
  read_buffer: 4194304
  write_buffer: 4194304
  use_pcap: true

advanced:
  tcp_nodelay: true
  tcp_keepalive: 15
  tcp_read_buffer: 16777216
  tcp_write_buffer: 16777216
  connection_timeout: 60
  stream_timeout: 120
  max_udp_flows: 1000
  udp_flow_timeout: 300
  udp_buffer_size: 4194304

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 512
  min_delay_ms: 5
  max_delay_ms: 50
  burst_chance: 0.15

http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true

paths:
  - transport: "httpsmux"
    addr: "IRAN_SERVER_IP:443"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10
```

---

## 🌐 TUN Interface (Layer 3 Tunnel)

DaggerConnect از TUN interface پشتیبانی می‌کند که امکان تانل سطح شبکه را فراهم می‌کند.

### سرور با TUN

```yaml
listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "cert.pem"
    key_file: "key.pem"
    tun:
      enabled: true
      name: "dagger0"       # نام interface (اختیاری)
      local_ip: "10.0.0.1"  # IP سرور در تانل
      peer_ip: "10.0.0.2"   # IP کلاینت در تانل
      mtu: 1400
```

### کلاینت با TUN

```yaml
paths:
  - transport: "httpsmux"
    addr: "IRAN_SERVER_IP:443"
    connection_pool: 2
    tun:
      enabled: true
      name: "dagger0"
      local_ip: "10.0.0.2"  # IP کلاینت در تانل
      peer_ip: "10.0.0.1"   # IP سرور در تانل
      mtu: 1400
```

> **توجه:** اجرای TUN نیاز به دسترسی root دارد.

---

## 🎭 HTTP Mimicry

تنظیمات HTTP Mimicry می‌تواند per-listener باشد یا از مقدار global استفاده کند.

```yaml
# تنظیم global (برای همه listeners)
http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  session_cookie: true
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Cache-Control: no-cache"

# تنظیم per-listener (override global)
listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    http_mimic:
      fake_domain: "api.github.com"
      fake_path: "/repos"
      session_cookie: false
```

**دامنه‌های پیشنهادی:**

| دامنه | کاربرد |
|-------|--------|
| `www.google.com` | پرترافیک‌ترین — مناسب اکثر موارد |
| `www.cloudflare.com` | CDN / API |
| `api.github.com` | Developer traffic |
| `www.microsoft.com` | Enterprise |

---

## 🔧 مثال‌های کاربردی

### مثال ۱ — V2Ray با Obfuscation

#### سرور ایران
```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "aggressive"
verbose: false

listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "cert.pem"
    key_file: "key.pem"
    maps:
      - type: tcp
        bind: "0.0.0.0:8443"
        target: "127.0.0.1:443"

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 256
```

#### سرور خارج (کلاینت)
```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "aggressive"

paths:
  - transport: "httpsmux"
    addr: "IRAN_IP:443"
    connection_pool: 3
    retry_interval: 3

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 256
```

کاربر به `IRAN_IP:8443` وصل می‌شود ← تانل ← به `127.0.0.1:443` روی سرور خارج می‌رسد.

---

### مثال ۲ — چند پروتکل همزمان (Multi-Listener)

```yaml
# server.yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"

listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "cert.pem"
    key_file: "key.pem"
    maps:
      - { type: tcp, bind: "0.0.0.0:10443", target: "127.0.0.1:10443" }

  - addr: "0.0.0.0:80"
    transport: "httpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:10080", target: "127.0.0.1:10080" }

  - addr: "0.0.0.0:4000"
    transport: "kcpmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:10000", target: "127.0.0.1:10000" }
      - { type: udp, bind: "0.0.0.0:10000", target: "127.0.0.1:10000" }

  - addr: "0.0.0.0:5000"
    transport: "rawmux"
    maps:
      - { type: tcp, bind: "0.0.0.0:11000", target: "127.0.0.1:11000" }
```

---

### مثال ۳ — چند سرور با Multi-Path

```yaml
# client.yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"

paths:
  # سرور اصلی
  - transport: "httpsmux"
    addr: "iran1.example.com:443"
    connection_pool: 3
    retry_interval: 3
    dial_timeout: 10

  # سرور بکاپ
  - transport: "httpmux"
    addr: "iran2.example.com:80"
    connection_pool: 2
    retry_interval: 5
    dial_timeout: 10

  # بکاپ KCP برای شرایط اضطراری
  - transport: "kcpmux"
    addr: "iran3.example.com:4000"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10

  # بکاپ Raw TCP با کمترین overhead
  - transport: "rawmux"
    addr: "iran4.example.com:5000"
    connection_pool: 2
    retry_interval: 3
    dial_timeout: 10
```

---

### مثال ۴ — Gaming Server (Low Latency)

```yaml
# server.yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "gaming"

listeners:
  - addr: "0.0.0.0:4000"
    transport: "kcpmux"
    maps:
      - type: tcp
        bind: "0.0.0.0:25565"
        target: "127.0.0.1:25565"
      - type: udp
        bind: "0.0.0.0:25565"
        target: "127.0.0.1:25565"

obfuscation:
  enabled: false    # غیرفعال برای کمترین overhead
```

---

### مثال ۵ — SSH Tunneling

```yaml
# server.yaml — ایران
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "balanced"

listeners:
  - addr: "0.0.0.0:443"
    transport: "httpsmux"
    cert_file: "cert.pem"
    key_file: "key.pem"
    maps:
      - type: tcp
        bind: "0.0.0.0:2222"
        target: "127.0.0.1:22"
```

```bash
# اتصال SSH از کاربر
ssh -p 2222 user@IRAN_SERVER_IP
```

---

### مثال ۶ — rawmux با حداکثر throughput

#### سرور ایران
```yaml
mode: "server"
psk: "YOUR_LICENSE_KEY"
profile: "aggressive"
verbose: false

listeners:
  - addr: "0.0.0.0:5000"
    transport: "rawmux"
    maps:
      - type: tcp
        bind: "0.0.0.0:8080"
        target: "127.0.0.1:8080"

rawmux:
  handshake_timeout: 10
  keepalive: 15
  read_buffer: 4194304
  write_buffer: 4194304
  use_pcap: true

obfuscation:
  enabled: false    # غیرفعال برای کمترین overhead
```

#### سرور خارج (کلاینت)
```yaml
mode: "client"
psk: "YOUR_LICENSE_KEY"
profile: "aggressive"

paths:
  - transport: "rawmux"
    addr: "IRAN_IP:5000"
    connection_pool: 4
    retry_interval: 2
    dial_timeout: 10

rawmux:
  handshake_timeout: 10
  keepalive: 15
  read_buffer: 4194304
  write_buffer: 4194304
  use_pcap: true
```

> **توجه:** `rawmux` هیچ HTTP mimicry ای ندارد — برای شبکه‌های بدون DPI یا زمانی که سرعت خالص مهم‌تر از obfuscation است مناسب است.

---

## 📊 بنچمارک

### مقایسه Transports

| Transport | تاخیر | سرعت | CPU | توضیح |
|-----------|-------|------|-----|-------|
| `tcpmux` | ~15ms | 850 Mbps | 8% | ساده |
| `rawmux` | ~10ms | 980 Mbps | 6% | کمترین overhead |
| `kcpmux` | ~12ms | 920 Mbps | 15% | بهترین سرعت UDP |
| `httpmux` | ~20ms | 750 Mbps | 12% | توصیه عمومی |
| `httpsmux` | ~25ms | 700 Mbps | 15% | امن‌ترین |

### Obfuscation Overhead

| تنظیم Padding | CPU | Overhead | کاربرد |
|--------------|-----|---------|--------|
| 16-128 byte | +1% | ~9% | سرور پرفشار |
| 16-256 byte | +2% | ~18% | پیش‌فرض |
| 16-512 byte | +4% | ~37% | فیلترینگ شدید |

---

## ⚙️ مدیریت سرویس (systemd)

```bash
# شروع
sudo systemctl start DaggerConnect-server
sudo systemctl start DaggerConnect-client

# توقف
sudo systemctl stop DaggerConnect-server
sudo systemctl stop DaggerConnect-client

# ری‌استارت
sudo systemctl restart DaggerConnect-server
sudo systemctl restart DaggerConnect-client

# وضعیت
sudo systemctl status DaggerConnect-server

# فعال در بوت
sudo systemctl enable DaggerConnect-server
sudo systemctl enable DaggerConnect-client
```

### نمونه فایل systemd

```ini
[Unit]
Description=DaggerConnect Server
After=network.target

[Service]
ExecStart=/usr/local/bin/DaggerConnect -c /etc/DaggerConnect/server.yaml
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
```

---

## 🔐 SSL Certificate

```bash
# Self-signed (برای تست یا بدون دامنه)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout key.pem -out cert.pem -days 365 \
  -subj "/CN=www.google.com"

# با دامنه واقعی (Let's Encrypt)
certbot certonly --standalone -d yourdomain.com
```

---

## 🛡️ فایروال

```bash
# باز کردن پورت سرور
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw allow 4000/udp   # برای kcpmux
sudo ufw allow 5000/tcp   # برای rawmux

# محدود کردن به IP مشخص (امنیت بیشتر)
sudo ufw allow from CLIENT_IP to any port 443

# Rate limiting
sudo ufw limit 443/tcp
```

---

## 🛠️ عیب‌یابی

### ❌ خطای License

```
ERROR [LICENSE-VALIDATION-FAILED]
```

- PSK را با کد دریافتی از `@DaggerConnectBot` چک کنید
- اتصال اینترنت سرور را بررسی کنید
- اگر 3 بار متوالی شکست بخورد، 5 دقیقه rate-limit فعال می‌شود

---

### ❌ سرعت کم

```yaml
# 1. غیرفعال کردن Obfuscation
obfuscation:
  enabled: false

# 2. افزایش Connection Pool
connection_pool: 4

# 3. Profile تهاجمی‌تر
profile: "aggressive"

# 4. برای سرعت ماکزیمم از rawmux یا KCP استفاده کنید
transport: "rawmux"   # کمترین overhead
# یا
transport: "kcpmux"   # بهترین سرعت UDP
```

---

### ❌ تاخیر زیاد

```yaml
# 1. پروفایل کم‌تاخیر
profile: "latency"

# 2. KCP با تنظیمات دستی
transport: "kcpmux"
kcp:
  nodelay: 1
  interval: 5
  resend: 2
  nc: 1

# 3. غیرفعال کردن Obfuscation delay
obfuscation:
  enabled: false
```

---

### ❌ قطع و وصل مکرر

```yaml
# 1. افزایش timeout ها
advanced:
  connection_timeout: 30
  stream_timeout: 120

# 2. تنظیم smux keepalive
smux:
  keepalive: 15

# 3. تنظیم rawmux keepalive (اگر از rawmux استفاده می‌کنید)
rawmux:
  keepalive: 15
  handshake_timeout: 10

# 4. افزایش retry interval
paths:
  - retry_interval: 5
```

---

### 📋 مشاهده لاگ‌ها

```bash
# لاگ زنده سرور
journalctl -u DaggerConnect-server -f

# لاگ زنده کلاینت
journalctl -u DaggerConnect-client -f

# فقط خطاها
journalctl -u DaggerConnect-server | grep -i "error\|❌"

# آخرین 100 خط
journalctl -u DaggerConnect-server -n 100

# لاگ verbose (در کانفیگ)
verbose: true
```

---



## 📞 پشتیبانی

- 📱 **Telegram Channel**: [@DaggerConnect](https://t.me/DaggerConnect)
- 🤖 **buyLICENSE**: [@DaggerConnectBot](https://t.me/DaggerConnectBot)
- 🐛 **گزارش باگ**: [GitHub Issues](https://github.com/itsFLoKi/DaggerConnect/issues)

---

<div align="center">

⭐ **اگه مفید بود یه ستاره بدید!** ⭐

Made with ❤️ by [itsFLoKi](https://github.com/itsFLoKi)

**DaggerConnect  — Professional Reverse Tunnel**

</div>
