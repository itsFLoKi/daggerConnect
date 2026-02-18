# ⚙️ DaggerConnect v1.4

<div align="center">

**ریورس تانل حرفه‌ای با Traffic Obfuscation**

[![خرید لایسنس](https://img.shields.io/badge/BUYLICENSE-@DaggerConnectBot-blue.svg)](https://t.me/DaggerConnectBot)

[ویژگی‌ها](#-ویژگیها) • [نصب سریع](#-نصب-سریع) • [آموزش](#-آموزش-گام-به-گام) • [عیب‌یابی](#-عیبیابی)

</div>

<div align="center">

[![Version](https://img.shields.io/badge/version-1.4-blue.svg)](https://github.com/itsFLoKi/DaggerConnect/releases)
[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org)
[![Telegram](https://img.shields.io/badge/Telegram-@DaggerConnect-blue.svg)](https://t.me/DaggerConnect)

</div>

---

## 🎯 معرفی

DaggerConnect یک راهکار حرفه‌ای برای ایجاد تونل معکوس با قابلیت دور زدن فیلترینگ‌های پیشرفته است. این ابزار با استفاده از HTTP Mimicry و Traffic Obfuscation، امکان عبور از فیلترینگ‌های عمیق بسته را فراهم می‌کند.

### ✨ چرا DaggerConnect v1.4؟

✅ **HTTP Mimicry** - شبیه‌سازی کامل ترافیک مرورگر  
✅ **Multi-Listener** - چند پورت و پروتکل همزمان  
✅ **Load Balancing** - 4 استراتژی توزیع بار  
✅ **UDP Support** - پشتیبانی کامل UDP  
✅ **Auto-Reconnect** - اتصال مجدد هوشمند

---

## 🆕 ویژگی‌های جدید v1.4

### 🎭 HTTP/HTTPS Mimicry پیشرفته

- شبیه‌سازی کامل Chrome/Firefox
- Host Header Spoofing
- Cookie & Session Management
- Chunked Transfer Encoding
- Custom Headers

### 🔀 Multi-Listener

- چند پورت همزمان روی سرور
- پروتکل‌های مختلف (TCP, KCP, HTTP, HTTPS, WS, WSS)
- SSL/TLS جداگانه برای هر listener

### ⚖️ Load Balancing هوشمند

- **Round Robin** - توزیع یکنواخت
- **Least Loaded** - انتخاب کم‌بارترین
- **Failover** - بر اساس اولویت
- **Weighted Random** - بر اساس وزن

### 🔐 امنیت پیشرفته

- License Manager با Anti-Tampering
- Binary Integrity Check
- Challenge-Response Authentication
- Session Management

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
# دانلود
wget https://github.com/itsFLoKi/DaggerConnect/releases/download/LASTVERSION/DaggerConnect
chmod +x DaggerConnect
sudo mv DaggerConnect /usr/local/bin/

# ایجاد دایرکتوری
sudo mkdir -p /etc/DaggerConnect
```

---

## 📚 آموزش گام به گام

### 🖥️ نصب سرور (ایران)

#### مرحله 1: اجرای اسکریپت
```bash
sudo ./setup.sh
# انتخاب: 1) Install Server
```

#### مرحله 2: تنظیمات پایه
```
پورت: 443
PSK: کد لایسنس که از ربات گرفته اید
Transport: HTTPmux (توصیه می‌شود)
Profile: balanced یا aggressive
```

#### مرحله 3: Port Mapping

```
Protocol: tcp/udp/both

مثال‌ها:
- تک پورت: 8080
- رنج: 1000/2000
- مپ کاستوم: 5000=8080
- رنج مپ: 1000/1010=2000/2010
```

#### مرحله 4: بهینه‌سازی سیستم
```
Optimize system? [Y/n]: Y
```

سرور آماده است! 🎉

---

### 💻 نصب کلاینت (سرور خارج)

#### مرحله 1: اجرای اسکریپت
```bash
sudo ./setup.sh
# انتخاب: 2) Install Client
```

#### مرحله 2: تنظیمات پایه
```
PSK: همان PSK سرور
Profile: همان profile سرور
```

#### مرحله 3: تنظیم Server Paths

```
Server #1:
  Transport: HTTPmux
  Address: 1.2.3.4:443
  Connection Pool: 3
  Retry Interval: 3
  Dial Timeout: 10
  Weight: 1
  Priority: 0

Add more? [y/N]: n
```

#### مرحله 4: Load Balancer (اگر چند سرور دارید)

```
Strategy:
  1) round_robin      → توزیع یکنواخت [پیش‌فرض]
  2) least_loaded     → انتخاب کم‌بارترین
  3) failover         → بر اساس priority
  4) weighted_random  → بر اساس weight
```

کلاینت آماده است! 🎉

---

## 🎨 پروتکل‌ها و Transports

### انتخاب Transport مناسب

| Transport | Port | امنیت | سرعت | کاربرد |
|-----------|------|-------|------|--------|
| **httpsmux** | 443 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **با TLS** |
| **httpmux** | 80 | ⭐⭐⭐ | ⭐⭐⭐⭐ | توصیه میشود |
| **wssmux** | 443 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | WebSocket + TLS |
| **wsmux** | 80 | ⭐⭐⭐ | ⭐⭐⭐ | WebSocket |
| **kcpmux** | UDP | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | سرعت بالا |
| **tcpmux** | Any | ⭐⭐⭐ | ⭐⭐⭐⭐ | ساده و سریع |

### HTTP Mimicry Configuration

```yaml
http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  chunked_encoding: false
  session_cookie: true
  custom_headers:
    - "Accept-Language: en-US,en;q=0.9"
    - "Accept-Encoding: gzip, deflate, br"
```

**دامنه‌های پیشنهادی:**
- `www.google.com` - پرترافیک‌ترین
- `www.cloudflare.com` - CDN/API
- `api.github.com` - Developer
- `www.microsoft.com` - Enterprise

---

## 🎮 پروفایل‌های عملکرد

```yaml
# Balanced (پیش‌فرض)
profile: "balanced"
# تعادل بین سرعت، CPU، و تاخیر

# Aggressive (سرعت بالا)
profile: "aggressive"
# بیشترین پهنای باند، CPU بیشتر

# Latency (کمترین تاخیر)
profile: "latency"
# مناسب Gaming، VoIP
```

---

## 📊 Load Balancing

### چهار استراتژی

**1. Round Robin (پیش‌فرض)**
```yaml
load_balancer:
  strategy: "round_robin"
```
- توزیع یکنواخت بین سرورها
- ✅ ساده و کارآمد

**2. Least Loaded**
```yaml
load_balancer:
  strategy: "least_loaded"
```
- انتخاب سرور با کمترین بار
- ✅ بهینه برای بار متغیر

**3. Failover**
```yaml
load_balancer:
  strategy: "failover"
  
paths:
  - addr: "server1:443"
    priority: 0    # اولویت بالا
  - addr: "server2:443"
    priority: 1    # backup
```
- استفاده از سرور اصلی
- در صورت خرابی → backup
- ✅ بهترین برای High Availability

**4. Weighted Random**
```yaml
load_balancer:
  strategy: "weighted_random"
  
paths:
  - addr: "server1:443"
    weight: 3    # 60% ترافیک
  - addr: "server2:443"
    weight: 2    # 40% ترافیک
```
- توزیع بر اساس وزن
- ✅ مناسب سرورهای نامتجانس

### Health Monitoring

```yaml
load_balancer:
  health_check_sec: 10      # هر 10 ثانیه چک
  max_failures: 3           # 3 خطا → unhealthy
  recovery_time_sec: 30     # 30 ثانیه برای recovery
  failover_delay_ms: 500    # تاخیر switchover
```

---

## 💾 Multi-Listener (Server)

توجه کنید در این بخش حتما پورت کانفیگاتون در سرور هاتون برای اینکه اختلال نیفته تو بار زیاد، متفاوت بزنید. همچنین میتونید ترنسپورت ثابت یا متغیر مثل مثال پایین بزنید:

```yaml
# server.yaml
mode: "server"

listeners:
   #Server 1 Kharej
   - addr: "0.0.0.0:443"
     transport: "httpsmux"
     cert_file: "/etc/DaggerConnect/certs/cert.pem"
     key_file: "/etc/DaggerConnect/certs/key.pem"
     maps:
        - type: tcp
          bind: "0.0.0.0:8664"
          target: "127.0.0.1:8664"
   #Server 2 Kharej
   - addr: "0.0.0.0:4000"
     transport: "httpmux"
     maps:
        - type: tcp
          bind: "0.0.0.0:5456"
          target: "127.0.0.1:5456"
   #Server 3 Kharej
   - addr: "0.0.0.0:8080"
     transport: "kcpmux"
     maps:
        - type: tcp
          bind: "0.0.0.0:6000"
          target: "127.0.0.1:6000"
```

**مزایا:**
- ✅ چند پروتکل همزمان
- ✅ SSL/TLS جداگانه
- ✅ Port های مختلف

---

## 🔧 مثال‌های کاربردی

### مثال 1: V2Ray با Obfuscation

#### Server (ایران)
```yaml
mode: "server"
listen: "0.0.0.0:443"
transport: "httpmux"
psk: "License-@DAGGERCONNECBOT"
profile: "aggressive"
verbose: false

maps:
  - type: tcp
    bind: "0.0.0.0:8443"
    target: "127.0.0.1:443"

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 256
```

#### Client (خارج)
```yaml
mode: "client"
psk: "License-@DAGGERCONNECBOT"
profile: "aggressive"
verbose: false

paths:
  - transport: "httpmux"
    addr: "1.2.3.4:443"
    connection_pool: 2
    retry_interval: 3

obfuscation:
  enabled: true
  min_padding: 16
  max_padding: 256
```

```bash
# V2Ray Config (خارج)
"inbounds": [{
  "port": 443,
  "listen": "127.0.0.1",
  "protocol": "vmess"
}]

# کاربر متصل می‌شود به:
1.2.3.4:8443
```

---

### مثال 2: Multi-Server با Failover

```yaml
# client.yaml
mode: "client"
psk: "License-@DAGGERCONNECBOT"

paths:
  # Primary
  - transport: "httpmux"
    addr: "server1.com:443"
    connection_pool: 3
    weight: 3
    priority: 0
  
  # Backup 1
  - transport: "httpmux"
    addr: "server2.com:443"
    connection_pool: 2
    weight: 2
    priority: 1
  
  # Backup 2 (KCP fallback)
  - transport: "kcpmux"
    addr: "server3.com:4000"
    connection_pool: 2
    weight: 1
    priority: 2

load_balancer:
  strategy: "failover"
  max_failures: 3
  recovery_time_sec: 60
```

---

### مثال 3: Gaming Server (Low Latency)

```yaml
# server.yaml
mode: "server"
listen: "0.0.0.0:4000"
transport: "kcpmux"
psk: "License-@DAGGERCONNECBOT"
profile: "latency"

maps:
  # Minecraft
  - type: tcp
    bind: "0.0.0.0:25565"
    target: "127.0.0.1:25565"
  - type: udp
    bind: "0.0.0.0:25565"
    target: "127.0.0.1:25565"

obfuscation:
  enabled: false
```

---

## 🛠️ عیب‌یابی

### ❌ سرعت کم است

```bash
# 1. غیرفعال کردن Obfuscation
obfuscation:
  enabled: false

# 2. افزایش Connection Pool
connection_pool: 3

# 3. تغییر Profile
profile: "aggressive"

# 4. استفاده از KCP
transport: "kcpmux"
```

### ❌ تاخیر زیاد است

```bash
# 1. تغییر Profile
profile: "latency"

# 2. کاهش Connection Pool
connection_pool: 2

# 3. استفاده از KCP
transport: "kcpmux"
```

### ❌ قطع و وصل مکرر

```bash
# 1. افزایش connection_timeout
advanced:
  connection_timeout: 15
  stream_timeout: 60

# 2. تنظیم smux keepalive
smux:
  keepalive: 15

# 3. چک کردن لاگ
journalctl -u DaggerConnect-server -f
```

### 📋 لاگ‌ها

```bash
# Server logs
journalctl -u DaggerConnect-server -f

# Client logs
journalctl -u DaggerConnect-client -f

# فقط خطاها
journalctl -u DaggerConnect-server | grep -i error

# آخرین 100 خط
journalctl -u DaggerConnect-server -n 100
```

---

## ⚙️ مدیریت سرویس

```bash
# Start
sudo systemctl start DaggerConnect-server
sudo systemctl start DaggerConnect-client

# Stop
sudo systemctl stop DaggerConnect-server
sudo systemctl stop DaggerConnect-client

# Restart
sudo systemctl restart DaggerConnect-server
sudo systemctl restart DaggerConnect-client

# Status
sudo systemctl status DaggerConnect-server
sudo systemctl status DaggerConnect-client

# Enable auto-start
sudo systemctl enable DaggerConnect-server
sudo systemctl enable DaggerConnect-client
```

---

## 📊 بنچمارک

### Transport Performance

| Transport | تاخیر | سرعت | CPU | مناسب |
|-----------|-------|------|-----|-------|
| **tcpmux** | 15ms | 850 Mbps | 8% | ساده |
| **kcpmux** | 12ms | 920 Mbps | 15% | gaming |
| **httpmux** | 20ms | 750 Mbps | 12% | **توصیه** |
| **httpsmux** | 25ms | 700 Mbps | 15% | امن‌ترین |

### Obfuscation Overhead

| padding | CPU | overhead | کاربرد |
|---------|-----|---------|--------|
| 16-128 | +1% | ~9% | سرور پرفشار |
| 16-256 | +2% | ~18% | **پیش‌فرض** |
| 16-512 | +4% | ~37% | فیلترینگ شدید |

---

### SSL Certificate

```bash
# Self-signed (اسکریپت انجام می‌دهد)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout key.pem -out cert.pem -days 365 \
  -subj "/CN=www.google.com"
```

### Firewall

```bash
# فقط IP مشخص
sudo ufw allow from 5.6.7.8 to any port 443

# Rate limiting
sudo ufw limit 443/tcp
```

---

## 📞 پشتیبانی

- 📱 **Telegram**: [@DaggerConnect](https://t.me/DaggerConnect)
- 🐛 **Issues**: [GitHub Issues](https://github.com/itsFLoKi/DaggerConnect/issues)
- 📧 **Email**: [Support](https://t.me/DDDDDTRIPLE)

---

## 📝 Changelog v1.4

- ✨ HTTP/HTTPS Mimicry پیشرفته
- ✨ Multi-Listener Support
- ✨ Load Balancing (4 strategies)
- ✨ License Manager + Anti-Tampering
- ⚡ بهبود Performance و پایداری
- 🐛 رفع باگ‌های v1.3

---

<div align="center">

⭐ **اگه مفید بود یه ستاره بدید!** ⭐

Made with ❤️ by [itsFLoKi](https://github.com/itsFLoKi)

**v1.4 - Professional Reverse Tunnel**

</div>
