# ⚙️ DaggerConnect v1.4

<div align="center">

**ریورس تانل حرفه‌ای با DPI Bypass و Traffic Obfuscation**

[![خرید لایسنس](https://img.shields.io/badge/BUYLICENSE-@DaggerConnectBot-blue.svg)](https://t.me/DaggerConnectBot)

[ویژگی‌ها](#-ویژگیها) • [نصب سریع](#-نصب-سریع) • [آموزش](#-آموزش-گام-به-گام) • [DPI Bypass](#-dpi-bypass) • [عیب‌یابی](#-عیبیابی)

</div>

<div align="center">

[![Version](https://img.shields.io/badge/version-1.4-blue.svg)](https://github.com/itsFLoKi/DaggerConnect/releases)
[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org)
[![Telegram](https://img.shields.io/badge/Telegram-@DaggerConnect-blue.svg)](https://t.me/DaggerConnect)

</div>

---

## 🎯 معرفی

DaggerConnect یک راهکار حرفه‌ای برای ایجاد تونل معکوس با قابلیت دور زدن فیلترینگ‌های پیشرفته است. این ابزار با استفاده از تکنیک‌های مختلف DPI Bypass و Traffic Obfuscation، امکان عبور از فیلترینگ‌های عمیق بسته را فراهم می‌کند.

### ✨ چرا DaggerConnect v1.4؟

✅ **3 روش DPI Bypass** - Light, Raw Socket, هر دو  
✅ **HTTP Mimicry** - شبیه‌سازی کامل ترافیک مرورگر  
✅ **Multi-Listener** - چند پورت و پروتکل همزمان  
✅ **Load Balancing** - 4 استراتژی توزیع بار  
✅ **UDP Support** - پشتیبانی کامل UDP  
✅ **Auto-Reconnect** - اتصال مجدد هوشمند  

---

## 🆕 ویژگی‌های جدید v1.4

### 🛡️ سه روش DPI Bypass

1. **Light DPI Bypass** (بدون root)
   - SNI Splitting
   - TTL Manipulation
   - Segment Pacing
   - 📱 مناسب کاربران عادی

2. **Raw Socket (pcap-based)** (نیاز به root)
   - Packet Fragmentation
   - Desync Methods: split, disorder, fake
   - TTL Randomization
   - TCP Window Manipulation
   - 💪 قدرتمندترین روش

3. **ترکیبی** - هر دو روش همزمان
   - بالاترین سطح Bypass
   - 🔥 توصیه برای فیلترینگ شدید

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
wget https://github.com/itsFLoKi/DaggerConnect/releases/download/v1.4/DaggerConnect
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

#### مرحله 3: انتخاب DPI Bypass ⭐

```
1) Off                           → بدون DPI bypass
2) Light DPI Bypass             → SNI split (بدون root)
3) Raw Socket                   → pcap desync (نیاز root)
4) Both                         → ترکیبی (توصیه برای فیلترینگ شدید)
```

**توصیه‌ها:**
- فیلترینگ ملایم → Light DPI Bypass
- فیلترینگ متوسط → Raw Socket با desync=split
- فیلترینگ شدید → Both (Light + Raw Socket)

#### مرحله 4: تنظیمات Raw Socket (اگر انتخاب کردید)

اسکریپت به صورت خودکار تشخیص می‌دهد:
```
Interface: eth0 (تشخیص خودکار)
Local IP: 1.2.3.4 (تشخیص خودکار)
Gateway MAC: aa:bb:cc:dd:ee:ff (تشخیص خودکار)
Port: 443

Desync Method:
  1) split    → تقسیم بسته به 2 قسمت [پیش‌فرض]
  2) disorder → ارسال نامرتب قطعات
  3) fake     → ارسال بسته جعلی با TTL=1
```

#### مرحله 5: Port Mapping

```
Protocol: tcp/udp/both

مثال‌ها:
- تک پورت: 8080
- رنج: 1000/2000
- مپ کاستوم: 5000=8080
- رنج مپ: 1000/1010=2000/2010
```

#### مرحله 6: بهینه‌سازی سیستم
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

#### مرحله 5: DPI Bypass (باید با سرور یکسان باشد)

```
اگر سرور Light DPI دارد → Light DPI
اگر سرور Raw Socket دارد → Raw Socket (با همان تنظیمات)
اگر سرور هر دو دارد → Both
```

کلاینت آماده است! 🎉

---

## 🛡️ DPI Bypass - راهنمای کامل

### روش 1: Light DPI Bypass

**بدون نیاز به Root | کم‌مصرف | مناسب 70% موارد**

```yaml
light_dpi_bypass:
  enabled: true
  sni_split: true           # تقسیم ClientHello
  ttl_manipulation: false   # تغییر TTL بسته اول
  segment_size: 1200        # اندازه segment
  pacing_delay_ms: 2        # تاخیر بین segment ها
  jitter_range_ms: 1        # جیتر تصادفی
```

**چگونه کار می‌کند:**
1. ClientHello را به دو قسمت تقسیم می‌کند
2. قسمت اول (حاوی SNI) را جدا ارسال می‌کند
3. با تاخیر کوچک، قسمت دوم را ارسال می‌کند

**مزایا:**
- ✅ بدون نیاز به دسترسی root
- ✅ مصرف CPU کم
- ✅ سازگار با همه سیستم‌ها

**معایب:**
- ❌ برای DPI های پیشرفته کافی نیست

---

### روش 2: Raw Socket (pcap-based)

**نیاز به Root | قدرتمند | بهترین نتیجه**

```yaml
raw_socket:
  enabled: true
  interface: "eth0"                    # اینترفیس شبکه
  local_ip: "1.2.3.4"                 # IP سرور
  local_port: 443                      # پورت
  gateway_mac: "aa:bb:cc:dd:ee:ff"    # MAC gateway
  
  # Desync Method
  desync_method: "split"               # split/disorder/fake
  
  # Performance
  batch_size: 32
  buffer_size: 2097152                 # 2MB
  coalesce_ms: 1
  max_packet_size: 1400
  
  # TTL Manipulation
  randomize_ttl: true
  min_ttl: 64
  max_ttl: 128
  
  # Fragmentation
  fragment_first_packet: true
  fragment_size: 40
  
  # Advanced
  fake_payload: false
  tcp_window_scale: 7
  ip_options_padding: false
```

#### 🔧 Desync Methods

**1. Split (پیش‌فرض - توصیه می‌شود)**
```yaml
desync_method: "split"
```
- بسته را به 2 قطعه تقسیم می‌کند
- قطعه اول کوچک (40-60 بایت)
- تاخیر 1-3ms بین قطعات
- ✅ بهترین نتیجه برای اکثر موارد

**2. Disorder (مناسب DPI های زمان‌بندی)**
```yaml
desync_method: "disorder"
```
- قطعه دوم را قبل از اول ارسال می‌کند
- DPI منتظر قطعه اول می‌ماند
- سرور مقصد بسته را reassemble می‌کند
- ✅ برای DPI های stateful

**3. Fake (مناسب DPI های عمیق)**
```yaml
desync_method: "fake"
fake_payload: true
```
- یک بسته جعلی با TTL=1 ارسال می‌کند
- DPI بسته جعلی را می‌بیند و تحلیل می‌کند
- بسته جعلی قبل از مقصد expire می‌شود
- بسته واقعی بدون مشکل به مقصد می‌رسد
- ✅ قدرتمندترین روش

#### 🎯 تشخیص Gateway MAC

```bash
# روش خودکار (در اسکریپت)
ip route | grep default | awk '{print $3}'
ip neigh show

# روش دستی
ip route
# default via 192.168.1.1 dev eth0

ip neigh show 192.168.1.1
# 192.168.1.1 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE
```

#### ⚡ Performance Tuning

```yaml
# سرعت بالا
batch_size: 32
buffer_size: 2097152      # 2MB
coalesce_ms: 1

# کم‌مصرف
batch_size: 16
buffer_size: 1048576      # 1MB
coalesce_ms: 5
```

---

### روش 3: ترکیبی (Light + Raw)

**بهترین نتیجه برای فیلترینگ شدید**

```yaml
# فعال کردن هر دو
light_dpi_bypass:
  enabled: true
  sni_split: true
  
raw_socket:
  enabled: true
  desync_method: "split"
```

**مزایا:**
- ✅ دو لایه محافظت
- ✅ عبور از DPI های ترکیبی
- ✅ Fallback اگر یکی fail شد

**معایب:**
- ❌ مصرف CPU بیشتر
- ❌ پیچیدگی بیشتر

---

## 🎨 پروتکل‌ها و Transports

### انتخاب Transport مناسب

| Transport | Port | امنیت | DPI Bypass | سرعت | کاربرد               |
|-----------|------|-------|------------|------|----------------------|
| **httpsmux** | 443 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **با TLS**           |
| **httpmux** | 80 | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |  توصیه میشود |
| **wssmux** | 443 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | WebSocket + TLS      |
| **wsmux** | 80 | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | WebSocket            |
| **kcpmux** | UDP | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | سرعت بالا            |
| **tcpmux** | Any | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ | ساده و سریع          |

### HTTP Mimicry Configuration

```yaml
http_mimic:
  fake_domain: "www.google.com"
  fake_path: "/search"
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  chunked_encoding: true
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

# Gaming (بهینه برای بازی)
profile: "gaming"
# کمترین تاخیر + سرعت خوب
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
- توجه کنید در این بخش حتما پورت کانفیگاتون در سرور هاتون برای اینکه اختلال نیفته تو بار زیاد ، متفاوت بزنید همچنین میتونید ترنسپورت ثابت یا متغیر مثل مثال پایین بزنید 

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

### مثال 1: V2Ray با DPI Bypass کامل

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

# DPI Bypass: هر دو روش
light_dpi_bypass:
  enabled: true
  sni_split: true

raw_socket:
  enabled: true
  interface: "eth0"
  local_ip: "1.2.3.4"
  local_port: 443
  gateway_mac: "aa:bb:cc:dd:ee:ff"
  desync_method: "split"

# Obfuscation
obfuscation:
  enabled: true
  min_padding: 32
  max_padding: 1024
```

#### Client (خارج)
```yaml
mode: "client"
psk: "License-@DAGGERCONNECBOT"
profile: "aggressive"

paths:
  - transport: "httpmux"
    addr: "1.2.3.4:443"
    connection_pool: 3
    retry_interval: 3

# DPI Bypass: همان تنظیمات سرور
light_dpi_bypass:
  enabled: true
  sni_split: true

raw_socket:
  enabled: true
  interface: "eth0"
  local_ip: "5.6.7.8"
  local_port: 0
  gateway_mac: "ff:ee:dd:cc:bb:aa"
  desync_method: "split"

obfuscation:
  enabled: true
  min_padding: 32
  max_padding: 1024
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
profile: "gaming"

maps:
  # Minecraft
  - type: tcp
    bind: "0.0.0.0:25565"
    target: "127.0.0.1:25565"
  - type: udp
    bind: "0.0.0.0:25565"
    target: "127.0.0.1:25565"

# DPI Bypass: خاموش (برای کمترین تاخیر)
light_dpi_bypass:
  enabled: false

raw_socket:
  enabled: false

obfuscation:
  enabled: false
```

---

## 🛠️ عیب‌یابی

### ❌ Raw Socket کار نمی‌کند

```bash
# 1. چک کردن دسترسی root
sudo -v

# 2. نصب libpcap
sudo apt install libpcap-dev

# 3. چک کردن interface
ip link show

# 4. چک کردن gateway MAC
ip route | grep default
ip neigh show

# 5. Ping gateway برای populate کردن ARP
ping -c 1 YOUR_GATEWAY_IP

# 6. چک کردن مجدد MAC
ip neigh show YOUR_GATEWAY_IP

# 7. اگر MAC نمایش نمی‌دهد
sudo arp-scan --interface=eth0 --localnet
```

### ❌ Gateway MAC پیدا نمی‌شود

```bash
# روش 1: ARP Scan
sudo apt install arp-scan
sudo arp-scan -I eth0 --localnet

# روش 2: nmap
sudo nmap -sn YOUR_GATEWAY_IP

# روش 3: دستی در کانفیگ
# وارد کردن MAC به صورت دستی:
gateway_mac: "aa:bb:cc:dd:ee:ff"
```

### ❌ DPI Bypass کار نمی‌کند

```bash
# تست 1: Light DPI فقط
light_dpi_bypass:
  enabled: true
raw_socket:
  enabled: false

# تست 2: Raw Socket فقط
light_dpi_bypass:
  enabled: false
raw_socket:
  enabled: true
  desync_method: "split"

# تست 3: تغییر desync method
desync_method: "disorder"  # یا "fake"

# تست 4: ترکیبی
light_dpi_bypass:
  enabled: true
raw_socket:
  enabled: true
  desync_method: "fake"
  fake_payload: true
```

### ❌ سرعت کم است

```bash
# 1. غیرفعال کردن Obfuscation
obfuscation:
  enabled: false

# 2. افزایش Connection Pool
connection_pool: 6

# 3. تغییر Profile
profile: "aggressive"

# 4. استفاده از KCP
transport: "kcpmux"

# 5. افزایش Buffers
advanced:
  tcp_read_buffer: 8388608
  tcp_write_buffer: 8388608
  udp_buffer_size: 4194304
```

### ❌ تاخیر زیاد است

```bash
# 1. تغییر Profile
profile: "latency"  # یا "gaming"

# 2. غیرفعال کردن DPI Bypass
light_dpi_bypass:
  enabled: false
raw_socket:
  enabled: false

# 3. کاهش Connection Pool
connection_pool: 2

# 4. استفاده از KCP
transport: "kcpmux"
profile: "gaming"
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

# لاگ‌های DPI
journalctl -u DaggerConnect-server | grep -i "dpi\|raw\|light"
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

# Disable auto-start
sudo systemctl disable DaggerConnect-server
sudo systemctl disable DaggerConnect-client
```

---

## 📊 بنچمارک

### DPI Bypass Overhead

| روش | CPU | تاخیر اضافی | موفقیت |
|-----|-----|------------|---------|
| **بدون DPI** | 0% | 0ms | - |
| **Light DPI** | +2% | +3ms | 70% |
| **Raw Socket (split)** | +5% | +5ms | 90% |
| **Raw Socket (fake)** | +8% | +7ms | 95% |
| **ترکیبی** | +10% | +10ms | 99% |

### Transport Performance

| Transport | تاخیر | سرعت | CPU | DPI |
|-----------|-------|------|-----|-----|
| **tcpmux** | 15ms | 850 Mbps | 8% | ⭐⭐ |
| **kcpmux** | 12ms | 920 Mbps | 15% | ⭐⭐⭐ |
| **httpsmux** | 25ms | 700 Mbps | 15% | ⭐⭐⭐⭐⭐ |

---

### SSL Certificate

```bash
# Self-signed (اسکریپت انجام می‌دهد)
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout key.pem -out cert.pem -days 365 \
  -subj "/CN=www.google.com"

# یا استفاده از Let's Encrypt
certbot certonly --standalone -d yourdomain.com
```

### Firewall

```bash
# فقط IP مشخص
sudo ufw allow from 5.6.7.8 to any port 443

# Rate limiting
sudo ufw limit 443/tcp

# Port Knocking (پیشرفته)
# پورت واقعی را مخفی نگه دارید
```

---

## 📞 پشتیبانی

- 📱 **Telegram**: [@DaggerConnect](https://t.me/DaggerConnect)
- 🐛 **Issues**: [GitHub Issues](https://github.com/itsFLoKi/DaggerConnect/issues)
- 📧 **Email**: [Support](https://t.me/DDDDDTRIPLE)

---

## 📝 Changelog v1.4

- ✨ Light DPI Bypass (SNI Split)
- ✨ Raw Socket Transport (pcap-based)
- ✨ 3 Desync Methods (split, disorder, fake)
- ✨ Multi-Listener Support
- ✨ Load Balancing (4 strategies)
- ✨ License Manager + Anti-Tampering
- ⚡ بهبود Performance
- 🐛 رفع باگ‌های v1.3

---

<div align="center">

⭐ **اگه مفید بود یه ستاره بدید!** ⭐

Made with ❤️ by [itsFLoKi](https://github.com/itsFLoKi)

**v1.4 - DPI Bypass پیشرفته**

</div>
