# ⚙️ DaggerConnect

<div align="center">

**ریورس تانل حرفه‌ای با Traffic Obfuscation و بایپس پیشرفته DPI**

[![buyLICENSE](https://img.shields.io/badge/buyLICENSE-@DaggerConnectBot-blue.svg)](https://t.me/DaggerConnectBot)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/itsFLoKi/DaggerConnect/releases)
[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org)
[![Telegram](https://img.shields.io/badge/Telegram-@DaggerConnect-blue.svg)](https://t.me/DaggerConnect)

[ویژگی‌ها](#-ویژگیها) • [نصب سریع](#-نصب-سریع) • [Transports](#-پروتکلها-و-transports) • [کانفیگ کامل](#-کانفیگ-کامل) • [عیب‌یابی](#-عیبیابی)

</div>

---

## 🎯 معرفی

نیازی به معرفی نیست 😁

---

## ✨ ویژگی‌ها

- 🎭 **HTTP/HTTPS Mimicry** — شبیه‌سازی کامل ترافیک مرورگر Chrome/Firefox
- 📡 **Multi-Listener** — چند پورت و پروتکل همزمان روی سرور
- 🛣️ **Multi-Path** — اتصال کلاینت به چندین سرور با Connection Pool مجزا
- 🥷 **QuantumMux** — TCP خام از طریق pcap با FEC
- 🔮 **TunMux** — تونل L2/L3 با ۷ پروفایل (tcp/udp/icmp/gre/ipip/ipx/bip)
- 🔀 **Traffic Obfuscation** — padding تصادفی + jitter delay
- 📦 **UDP Support** — فوروارد کامل UDP
- 🔁 **Auto-Reconnect** — اتصال مجدد هوشمند با exponential backoff
- ⚡ **KCP Transport** — پروتکل UDP-based برای کمترین تاخیر
- 🔗 **smux Multiplexing** — چند stream روی یک اتصال
- 🔐 **AES-GCM Encryption** — رمزنگاری end-to-end با PSK
- 🎚️ **AdaptiveTuner** — تنظیم خودکار KCP/smux/buffers بر اساس بار شبکه
- 💓 **Heartbeat** — تشخیص قطعی و بستن session مرده

---

## 🚀 نصب سریع

### نصب با اسکریپت (توصیه می‌شود)

```bash
curl -O https://raw.githubusercontent.com/itsFLoKi/DaggerConnect/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

اسکریپت یک منوی کامل برای نصب سرور/کلاینت، انتخاب transport، کانفیگ port mappings، و مدیریت سرویس‌های systemd ارائه می‌دهد.

### نصب دستی

```bash
# دانلود باینری
wget https://github.com/itsFLoKi/DaggerConnect/releases/download/LASTVERSION/DaggerConnect
chmod +x DaggerConnect
sudo mv DaggerConnect /usr/local/bin/

# ساخت کانفیگ پیش‌فرض (JSON یا YAML)
DaggerConnect -gen server.json     # → DaggerConnect-server.json
DaggerConnect -gen client.json     # → DaggerConnect-client.json
```

### گزینه‌های CLI

```
DaggerConnect -c config.json       # اجرا با کانفیگ JSON یا YAML
DaggerConnect -gen server.json     # ساخت کانفیگ سرور JSON
DaggerConnect -gen client.json     # ساخت کانفیگ کلاینت JSON
DaggerConnect -gen server          # ساخت کانفیگ YAML (پسوند پیش‌فرض)
DaggerConnect -v                   # نمایش نسخه
```

---

## 📚 آموزش گام به گام

### 🖥️ راه‌اندازی سرور (سرور ایران / مقصد)

سرور باید روی ماشینی باشد که **کلاینت‌ها به آن وصل می‌شوند** (معمولاً سرور ایران).

#### مرحله ۱ — ساخت کانفیگ

```bash
DaggerConnect -gen server.json
```

#### مرحله ۲ — ویرایش کانفیگ

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "log_level": "info",
  "heartbeat": 8,
  "cert_file": "cert.pem",
  "key_file": "key.pem",
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "httpsmux",
      "cert_file": "cert.pem",
      "key_file": "key.pem",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:2222",
          "target": "127.0.0.1:22"
        }
      ]
    }
  ]
}
```

#### مرحله ۳ — اجرا

```bash
sudo DaggerConnect -c DaggerConnect-server.json
```

---

### 💻 راه‌اندازی کلاینت (سرور خارج / مبدا)

کلاینت روی ماشینی اجرا می‌شود که **سرویس اصلی روی آن است** (معمولاً سرور خارج).

#### مرحله ۱ — ساخت کانفیگ

```bash
DaggerConnect -gen client.json
```

#### مرحله ۲ — ویرایش کانفیگ

```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "license_token": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "log_level": "info",
  "heartbeat": 8,
  "paths": [
    {
      "transport": "httpsmux",
      "addr": "IRAN_SERVER_IP:443",
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ]
}
```

#### مرحله ۳ — اجرا

```bash
sudo DaggerConnect -c DaggerConnect-client.json
```

---

## 🎨 پروتکل‌ها و Transports

| Transport     | پورت | امنیت  | سرعت  | سطح بایپس DPI | کاربرد |
|---------------|------|--------|-------|---------------|--------|
| `httpsmux`    | 443  | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐  | ⭐⭐⭐⭐         | HTTPS + TLS |
| `httpmux`     | 80   | ⭐⭐⭐   | ⭐⭐⭐⭐  | ⭐⭐⭐          | HTTP میمیکری |
| `wssmux`      | 443  | ⭐⭐⭐⭐⭐ | ⭐⭐⭐   | ⭐⭐⭐⭐         | WebSocket + TLS |
| `wsmux`       | 80   | ⭐⭐⭐   | ⭐⭐⭐   | ⭐⭐⭐          | WebSocket |
| `kcpmux`      | UDP  | ⭐⭐⭐   | ⭐⭐⭐⭐⭐ | ⭐⭐           | سرعت بالا / gaming |
| `tcpmux`      | Any  | ⭐⭐⭐   | ⭐⭐⭐⭐  | ⭐⭐           | ساده و سریع |
| `rawmux`      | Any  | ⭐⭐⭐   | ⭐⭐⭐⭐⭐ | ⭐⭐⭐          | Raw KCP/UDP — کمترین overhead |
| `quantummux`  | TCP  | ⭐⭐⭐⭐  | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐        | **Raw TCP via pcap + KCP + FEC — توصیه می‌شود** |
| `tunmux`      | Any  | ⭐⭐⭐⭐  | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐        | تونل L2/L3 با ۷ پروفایل + proto58 |

> **نکته:** `quantummux` و `tunmux` نیاز به `root + libpcap` دارند و برای پروفایل tcp قوانین `iptables NOTRACK` لازم است (اسکریپت setup خودکار اعمال می‌کند).

---

## 🎮 پروفایل‌های عملکرد

پروفایل مقادیر پیش‌فرض KCP و smux را تنظیم می‌کند. AdaptiveTuner در runtime بر اساس بار شبکه این مقادیر را تنظیم مجدد می‌کند.

| Profile         | کاربرد                  | KCP Interval | KCP SndWnd | smux Keepalive |
|-----------------|-------------------------|--------------|------------|----------------|
| `balanced`      | پیش‌فرض — تعادل سرعت/CPU | 5ms          | 512        | 8s             |
| `aggressive`    | بیشترین پهنای باند        | 3ms          | 1024       | 5s             |
| `latency`       | کمترین تاخیر             | 3ms          | 512        | 3s             |
| `gaming`        | gaming / VoIP            | 3ms          | 1024       | 2s             |
| `cpu-efficient` | مصرف CPU کم              | 20ms         | 256        | 10s            |

```json
{
  "profile": "balanced"
}
```

---

می‌توانید از کلاینت به چند سرور همزمان وصل شوید. هر path یک connection pool مستقل دارد و در صورت قطع، به‌صورت مستقل reconnect می‌کند.

```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "license_token": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "log_level": "info",
  "paths": [
    {
      "transport": "httpsmux",
      "addr": "server1.example.com:443",
      "connection_pool": 3,
      "aggressive_pool": true,
      "retry_interval": 3,
      "dial_timeout": 10
    },
    {
      "transport": "httpmux",
      "addr": "server2.example.com:80",
      "connection_pool": 2,
      "retry_interval": 5,
      "dial_timeout": 10
    },
    {
      "transport": "kcpmux",
      "addr": "server3.example.com:4000",
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    },
    {
      "transport": "httpsmux",
      "addr": "server4.example.com:443",
      "psk": "DIFFERENT_LICENSE_KEY",
      "connection_pool": 2,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ]
}
```

**نکات:**
- `connection_pool` تعداد اتصال موازی به هر سرور (توصیه: 2-4)
- `aggressive_pool: true` همه‌ی اتصال‌های pool را فوری ایجاد می‌کند (به جای lazy)
- اگر یک path قطع شود، path های دیگر **تحت تأثیر قرار نمی‌گیرند**
- `psk` در path اختیاری است — اگر نباشد از PSK global استفاده می‌شود

---

## 🥷 QuantumMux — Raw TCP via pcap

`quantummux` بسته‌های TCP خام را مستقیماً از طریق `libpcap` ارسال/دریافت می‌کند — kernel stack دور زده می‌شود. این یعنی:

- **DPI bypass در سطح L4** — هیچ kernel handshake ای رخ نمی‌دهد
- **FEC داخلی** — تحمل بالای از دست رفتن بسته
- **Natural Send mode** — TCP options واقعی (MSS, WindowScale, SACK, Timestamps) برای fingerprinting

### کانفیگ کامل QuantumMux

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "listeners": [
    {
      "addr": "0.0.0.0:5000",
      "transport": "quantummux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:8080",
          "target": "127.0.0.1:8080"
        }
      ]
    }
  ],
  "quantummux": {
    "interface": "eth0",
    "local_ip": "203.0.113.1",
    "data_shard": 10,
    "parity_shard": 1,
    "mtu": 1280,
    "ttl_base": 64,
    "ttl_jitter": 8,
    "tcp_window": 65535,
    "tcp_flags": "PA",
    "ack_step_min": 64,
    "ack_step_max": 512,
    "idle_timeout": 60,
    "use_pcap": true,
    "natural_send": true,
    "icmpv6_mode": false,
    "spoof_src_ip": "",
    "spoof_src_mac": "",
    "client_spoof_ip": "",
    "client_real_ip": ""
  }
}
```

### نیازمندی‌های iptables

برای جلوگیری از `RST` خودکار kernel:

```bash
# سرور (پورت 5000)
iptables -t raw    -A PREROUTING -p tcp --dport 5000 -j NOTRACK
iptables -t raw    -A OUTPUT     -p tcp --sport 5000 -j NOTRACK
iptables -t mangle -A OUTPUT     -p tcp --sport 5000 --tcp-flags RST RST -j DROP
```

اسکریپت `setup.sh` این قوانین را خودکار اعمال و در `/etc/iptables/rules.v4` ذخیره می‌کند.

---

## 🔮 TunMux — تونل L2/L3 با ۷ پروفایل

`tunmux` انعطاف‌پذیرترین ترنسپورت است. می‌توانید بسته‌ها را در **۷ پروتکل متفاوت** کپسوله کنید — بسته به اینکه چه چیزی در شبکه‌ی شما اجازه عبور دارد.

### پروفایل‌های موجود

| پروفایل | پروتکل IP | کاربرد |
|---------|-----------|--------|
| `tcp`   | proto 6 (TCP)        | بایپس عمومی DPI (نیاز به iptables) |
| `udp`   | proto 17 (UDP)       | سریع و ساده |
| `icmp`  | proto 1 (ICMPv4)     | بایپس extreme — تونل از طریق `ping` |
| `gre`   | proto 47 (GRE)       | شبیه VPN ساده، در شبکه‌های سازمانی مرسوم |
| `ipip`  | proto 4 (IP-in-IP)   | کپسوله‌سازی IPv4 درون IPv4 |
| `ipx`   | EtherType 0x8137     | IPX روی Ethernet (legacy — کمتر فیلتر می‌شود) |
| `bip`   | proto 253 (reserved) | پروتکل آزمایشی — بایپس بسیار بالا |

### کانفیگ کامل TunMux

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "listeners": [
    {
      "addr": "0.0.0.0:6000",
      "transport": "tunmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:8080",
          "target": "127.0.0.1:8080"
        }
      ]
    }
  ],
  "tunmux": {
    "profile": "tcp",
    "interface": "",
    "local_ip": "",
    "mtu": 1400,
    "ttl_base": 64,
    "ttl_jitter": 8,
    "tcp_window": 65535,
    "tcp_flags": "PA",
    "sock_buf": 16777216,
    "idle_timeout": 120,
    "spoof_src_ip": "",
    "client_spoof_ip": "",
    "client_real_ip": "",
    "server_spoof_ip": "",
    "sni_spoof": "www.cloudflare.com",
    "proto58": false,
    "proto58_src_ipv6": "",
    "proto58_dst_ipv6": ""
  }
}
```

### کلاینت TunMux

```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "paths": [
    {
      "transport": "tunmux",
      "addr": "IRAN_IP:6000",
      "connection_pool": 2,
      "retry_interval": 2,
      "dial_timeout": 8
    }
  ],
  "tunmux": {
    "profile": "tcp",
    "router_mac": "",
    "sni_spoof": "www.cloudflare.com"
  }
}
```

> **توجه:** برای profile=tcp، قوانین iptables مشابه quantummux لازم است. برای پروفایل‌های دیگر (udp/icmp/gre/ipip/ipx/bip) نیازی به iptables نیست چون portless هستند یا UDP استفاده می‌کنند.

---

## 🔧 کانفیگ کامل

### کانفیگ کامل سرور

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "log_level": "info",
  "cert_file": "cert.pem",
  "key_file": "key.pem",
  "heartbeat": 8,
  "smux": {
    "version": 2,
    "keepalive": 8,
    "max_recv": 8388608,
    "max_stream": 4194304,
    "frame_size": 32768
  },
  "kcp": {
    "nodelay": 1,
    "interval": 5,
    "resend": 2,
    "nc": 1,
    "sndwnd": 512,
    "rcvwnd": 512,
    "mtu": 1400
  },
  "rawmux": {
    "handshake_timeout": 10,
    "keepalive": 15,
    "read_buffer": 4194304,
    "write_buffer": 4194304,
    "use_pcap": false
  },
  "advanced": {
    "tcp_nodelay": true,
    "tcp_keepalive": 1,
    "tcp_read_buffer": 4194304,
    "tcp_write_buffer": 4194304,
    "websocket_read_buffer": 262144,
    "websocket_write_buffer": 262144,
    "websocket_compression": false,
    "cleanup_interval": 3,
    "session_timeout": 30,
    "connection_timeout": 60,
    "stream_timeout": 120,
    "max_connections": 2000,
    "max_udp_flows": 1000,
    "udp_flow_timeout": 300,
    "udp_buffer_size": 4194304,
    "channel_backlog": 4096,
    "stream_chan_buf": 512,
    "restart_interval": 0
  },
  "obfuscation": {
    "enabled": false,
    "min_padding": 16,
    "max_padding": 512,
    "min_delay_ms": 0,
    "max_delay_ms": 0,
    "burst_chance": 0.15
  },
  "http_mimic": {
    "fake_domain": "www.google.com",
    "fake_path": "/search",
    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "chunked_encoding": false,
    "session_cookie": true,
    "custom_headers": [
      "Accept-Language: en-US,en;q=0.9",
      "Accept-Encoding: gzip, deflate, br"
    ]
  },
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "httpsmux",
      "cert_file": "cert.pem",
      "key_file": "key.pem",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:2222",
          "target": "127.0.0.1:22"
        },
        {
          "type": "udp",
          "bind": "0.0.0.0:53",
          "target": "127.0.0.1:53"
        }
      ]
    }
  ]
}
```

### کانفیگ کامل کلاینت

```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "license_token": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "log_level": "info",
  "heartbeat": 8,
  "smux": {
    "version": 2,
    "keepalive": 8,
    "max_recv": 8388608,
    "max_stream": 4194304,
    "frame_size": 32768
  },
  "kcp": {
    "nodelay": 1,
    "interval": 5,
    "resend": 2,
    "nc": 1,
    "sndwnd": 512,
    "rcvwnd": 512,
    "mtu": 1400
  },
  "advanced": {
    "tcp_nodelay": true,
    "tcp_keepalive": 1,
    "tcp_read_buffer": 4194304,
    "tcp_write_buffer": 4194304,
    "connection_timeout": 60,
    "stream_timeout": 120,
    "max_udp_flows": 1000,
    "udp_flow_timeout": 300,
    "udp_buffer_size": 4194304,
    "channel_backlog": 4096,
    "stream_chan_buf": 512
  },
  "obfuscation": {
    "enabled": false,
    "min_padding": 16,
    "max_padding": 512,
    "burst_chance": 0.15
  },
  "http_mimic": {
    "fake_domain": "www.google.com",
    "fake_path": "/search",
    "session_cookie": true
  },
  "paths": [
    {
      "transport": "httpsmux",
      "addr": "IRAN_SERVER_IP:443",
      "connection_pool": 2,
      "aggressive_pool": true,
      "retry_interval": 3,
      "dial_timeout": 10
    }
  ]
}
```

---

## 🎭 HTTP Mimicry

تنظیمات HTTP Mimicry می‌تواند per-listener باشد یا از مقدار global استفاده کند.

```json
{
  "http_mimic": {
    "fake_domain": "www.google.com",
    "fake_path": "/search",
    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "session_cookie": true,
    "chunked_encoding": false,
    "custom_headers": [
      "Accept-Language: en-US,en;q=0.9",
      "Cache-Control: no-cache"
    ]
  },
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "httpsmux",
      "http_mimic": {
        "fake_domain": "api.github.com",
        "fake_path": "/repos",
        "session_cookie": false
      }
    }
  ]
}
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
```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "aggressive",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "httpsmux",
      "cert_file": "cert.pem",
      "key_file": "key.pem",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:8443",
          "target": "127.0.0.1:443"
        }
      ]
    }
  ],
  "obfuscation": {
    "enabled": true,
    "min_padding": 16,
    "max_padding": 256
  }
}
```

#### سرور خارج (کلاینت)
```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "license_token": "FROM_LICENSE_SERVER",
  "profile": "aggressive",
  "paths": [
    {
      "transport": "httpsmux",
      "addr": "IRAN_IP:443",
      "connection_pool": 3,
      "aggressive_pool": true,
      "retry_interval": 3
    }
  ],
  "obfuscation": {
    "enabled": true,
    "min_padding": 16,
    "max_padding": 256
  }
}
```

کاربر به `IRAN_IP:8443` وصل می‌شود ← تانل ← به `127.0.0.1:443` روی سرور خارج می‌رسد.

---

### مثال ۲ — چند پروتکل همزمان (Multi-Listener)

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "httpsmux",
      "cert_file": "cert.pem",
      "key_file": "key.pem",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:10443",
          "target": "127.0.0.1:10443"
        }
      ]
    },
    {
      "addr": "0.0.0.0:80",
      "transport": "httpmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:10080",
          "target": "127.0.0.1:10080"
        }
      ]
    },
    {
      "addr": "0.0.0.0:4000",
      "transport": "kcpmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:10000",
          "target": "127.0.0.1:10000"
        },
        {
          "type": "udp",
          "bind": "0.0.0.0:10000",
          "target": "127.0.0.1:10000"
        }
      ]
    },
    {
      "addr": "0.0.0.0:5000",
      "transport": "quantummux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:11000",
          "target": "127.0.0.1:11000"
        }
      ]
    },
    {
      "addr": "0.0.0.0:6000",
      "transport": "tunmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:12000",
          "target": "127.0.0.1:12000"
        }
      ]
    }
  ]
}
```

---

### مثال ۳ — Gaming Server (Low Latency)

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "gaming",
  "heartbeat": 3,
  "listeners": [
    {
      "addr": "0.0.0.0:4000",
      "transport": "kcpmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:25565",
          "target": "127.0.0.1:25565"
        },
        {
          "type": "udp",
          "bind": "0.0.0.0:25565",
          "target": "127.0.0.1:25565"
        }
      ]
    }
  ],
  "obfuscation": {
    "enabled": false
  }
}
```

---

### مثال ۴ — SSH Tunneling

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "httpsmux",
      "cert_file": "cert.pem",
      "key_file": "key.pem",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:2222",
          "target": "127.0.0.1:22"
        }
      ]
    }
  ]
}
```

```bash
# اتصال SSH از کاربر
ssh -p 2222 user@IRAN_SERVER_IP
```

---

### مثال ۵ — QuantumMux با بایپس پیشرفته

#### سرور ایران
```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "aggressive",
  "listeners": [
    {
      "addr": "0.0.0.0:5000",
      "transport": "quantummux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:8080",
          "target": "127.0.0.1:8080"
        }
      ]
    }
  ],
  "quantummux": {
    "data_shard": 10,
    "parity_shard": 3,
    "natural_send": true,
    "use_pcap": true
  }
}
```

#### سرور خارج (کلاینت)
```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "license_token": "FROM_LICENSE_SERVER",
  "profile": "aggressive",
  "paths": [
    {
      "transport": "quantummux",
      "addr": "IRAN_IP:5000",
      "connection_pool": 4,
      "aggressive_pool": true,
      "retry_interval": 2
    }
  ],
  "quantummux": {
    "data_shard": 10,
    "parity_shard": 3,
    "natural_send": true
  }
}
```

> **توجه:** `quantummux` نیاز به `root + libpcap + iptables NOTRACK` دارد.

---

### مثال ۶ — TunMux با ICMP (بایپس extreme)

برای شرایطی که حتی UDP/TCP فیلتر شده — تونل از طریق `ping`.

#### سرور ایران
```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "listeners": [
    {
      "addr": "0.0.0.0:6000",
      "transport": "tunmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:8080",
          "target": "127.0.0.1:8080"
        }
      ]
    }
  ],
  "tunmux": {
    "profile": "icmp",
    "mtu": 1280
  }
}
```

#### کلاینت
```json
{
  "mode": "client",
  "psk": "YOUR_LICENSE_KEY",
  "license_token": "FROM_LICENSE_SERVER",
  "profile": "balanced",
  "paths": [
    {
      "transport": "tunmux",
      "addr": "IRAN_IP:6000",
      "connection_pool": 1,
      "retry_interval": 2
    }
  ],
  "tunmux": {
    "profile": "icmp",
    "mtu": 1280
  }
}
```

---

### مثال ۷ — TunMux با proto58 (حداکثر stealth)

`proto58` بسته‌ها را درون IPv6 ESP-like کپسوله می‌کند — برای بایپس DPI های بسیار سختگیر.

```json
{
  "mode": "server",
  "psk": "YOUR_LICENSE_KEY",
  "server_secret": "FROM_LICENSE_SERVER",
  "listeners": [
    {
      "addr": "0.0.0.0:6000",
      "transport": "tunmux",
      "maps": [
        {
          "type": "tcp",
          "bind": "0.0.0.0:8080",
          "target": "127.0.0.1:8080"
        }
      ]
    }
  ],
  "tunmux": {
    "profile": "tcp",
    "proto58": true,
    "sni_spoof": "www.cloudflare.com",
    "mtu": 1280
  }
}
```

---

## 📊 بنچمارک

### مقایسه Transports

| Transport     | تاخیر  | سرعت        | CPU  | توضیح |
|---------------|--------|-------------|------|-------|
| `tcpmux`      | ~15ms  | 850 Mbps    | 8%   | ساده |
| `rawmux`      | ~10ms  | 980 Mbps    | 6%   | کمترین overhead |
| `kcpmux`      | ~12ms  | 920 Mbps    | 15%  | بهترین سرعت UDP |
| `httpmux`     | ~20ms  | 750 Mbps    | 12%  | توصیه عمومی |
| `httpsmux`    | ~25ms  | 700 Mbps    | 15%  | امن‌ترین |
| `quantummux`  | ~8ms   | 1100+ Mbps  | 18%  | با FEC، بایپس DPI کامل |
| `tunmux`      | ~10ms  | 1000+ Mbps  | 14%  | انعطاف‌پذیر، ۷ پروفایل |

### Obfuscation Overhead

| تنظیم Padding | CPU | Overhead | کاربرد |
|--------------|-----|---------|--------|
| 16-128 byte  | +1% | ~9%     | سرور پرفشار |
| 16-256 byte  | +2% | ~18%    | پیش‌فرض |
| 16-512 byte  | +4% | ~37%    | فیلترینگ شدید |

---

## ⚙️ مدیریت سرویس (systemd)

اسکریپت setup سرویس‌ها را با نام‌گذاری `DaggerConnect-{NAME}` ایجاد می‌کند (می‌توانید چندین instance داشته باشید).

```bash
# شروع
sudo systemctl start DaggerConnect-server
sudo systemctl start DaggerConnect-client

# توقف
sudo systemctl stop DaggerConnect-server
sudo systemctl stop DaggerConnect-client

# ری‌استارت
sudo systemctl restart DaggerConnect-server

# وضعیت
sudo systemctl status DaggerConnect-server

# فعال در بوت
sudo systemctl enable DaggerConnect-server
```

### نمونه فایل systemd

```ini
[Unit]
Description=DaggerConnect Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/DaggerConnect
ExecStart=/usr/local/bin/DaggerConnect -c /etc/DaggerConnect/server.json
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
LimitNOFILE=1048576

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
sudo ufw allow 5000/tcp   # برای rawmux / quantummux
sudo ufw allow 6000/tcp   # برای tunmux

# محدود کردن به IP مشخص (امنیت بیشتر)
sudo ufw allow from CLIENT_IP to any port 443

# Rate limiting
sudo ufw limit 443/tcp
```

### iptables برای quantummux / tunmux (profile=tcp)

```bash
PORT=5000   # پورت listener
iptables -t raw    -A PREROUTING -p tcp --dport $PORT -j NOTRACK
iptables -t raw    -A OUTPUT     -p tcp --sport $PORT -j NOTRACK
iptables -t mangle -A OUTPUT     -p tcp --sport $PORT --tcp-flags RST RST -j DROP

# ذخیره دائمی
iptables-save > /etc/iptables/rules.v4
```

---

## 🛠️ عیب‌یابی

### ❌ خطای License

```
ERROR [LICENSE-VALIDATION-FAILED]
```

- PSK و `server_secret` / `license_token` را با مقدار دریافتی از `@DaggerConnectBot` چک کنید
- اتصال اینترنت سرور را بررسی کنید
- اگر 3 بار متوالی شکست بخورد، 5 دقیقه rate-limit فعال می‌شود

---

### ❌ خطای QuantumMux/TunMux

```
ERROR pcap activate ...: Operation not permitted
```

- باینری را با `sudo` اجرا کنید (`libpcap` به CAP_NET_RAW نیاز دارد)
- بررسی کنید `libpcap` نصب باشد: `apt install libpcap0.8`

```
ERROR connection reset / RST received
```

- قوانین `iptables NOTRACK` را اعمال کنید (به بخش فایروال مراجعه کنید)
- اسکریپت `setup.sh` این قوانین را خودکار اعمال می‌کند

---

### ❌ سرعت کم

```json
{
  "obfuscation": {
    "enabled": false
  },
  "paths": [
    {
      "connection_pool": 4,
      "aggressive_pool": true
    }
  ],
  "profile": "aggressive",
  "transport": "rawmux"
}
```

---

### ❌ تاخیر زیاد

```json
{
  "profile": "latency",
  "transport": "kcpmux",
  "kcp": {
    "nodelay": 1,
    "interval": 3,
    "resend": 2,
    "nc": 1
  },
  "heartbeat": 3,
  "obfuscation": {
    "enabled": false
  }
}
```

---

### ❌ قطع و وصل مکرر

```json
{
  "advanced": {
    "connection_timeout": 30,
    "stream_timeout": 120,
    "session_timeout": 60
  },
  "smux": {
    "keepalive": 15
  },
  "tunmux": {
    "idle_timeout": 180
  },
  "paths": [
    {
      "retry_interval": 5,
      "dial_timeout": 15
    }
  ]
}
```

---

### 📋 مشاهده لاگ‌ها

```bash
# لاگ زنده سرور
journalctl -u DaggerConnect-server -f

# لاگ زنده کلاینت
journalctl -u DaggerConnect-client -f

# فقط خطاها
journalctl -u DaggerConnect-server | grep -i "error"

# آخرین 100 خط
journalctl -u DaggerConnect-server -n 100

# سطح لاگ پیشرفته (در کانفیگ)
log_level: "debug"   # debug | info | warn | error
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

**DaggerConnect v2.0.0 — Professional Reverse Tunnel**

</div>
