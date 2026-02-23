# 🗡️ DaggerMux — راهنمای کامل

> **Raw TCP/KCP via pcap | DPI Bypass | Zero Kernel TCP Stack**

DaggerMux یک transport لایه‌ی سفارشی در DaggerConnect است که به‌جای استفاده از TCP استک کرنل، پکت‌های TCP را مستقیماً از طریق **libpcap** تزریق و دریافت می‌کند. این تکنیک باعث می‌شود ترافیک از دید سیستم‌های DPI (Deep Packet Inspection) شبیه به TCP معمولی به نظر برسد، اما در واقع payload داخل آن KCP/AES است.

---

## 📐 معماری کلی

```
[ App ] → KCP (روی DaggerMuxRawConn) → pcap inject → [ شبکه ]
                                                            ↓
[ App ] ← KCP (روی DaggerMuxRawConn) ← pcap capture ← [ شبکه ]
```

### چرا DaggerMux؟

| ویژگی | TCP معمولی | DaggerMux |
|-------|-----------|-----------|
| TCP handshake | کرنل انجام می‌دهد | **جعلی — pcap inject** |
| RST پاسخ | کرنل می‌فرستد | **Drop شده با iptables** |
| DPI fingerprint | TCP stack OS | **دلخواه — flag کاملاً کنترل‌پذیر** |
| FEC | ندارد | **دارد (DataShard/ParityShard)** |
| Encryption | نیاز به TLS | **AES داخلی روی KCP** |
| نیاز به root | خیر | **بله (pcap + raw socket)** |

---

## ⚙️ تنظیمات کامل

### ساختار YAML

```yaml
daggermux:
  # ── شبکه ──────────────────────────────────────────────────────
  interface:    ""          # نام interface (خالی = auto-detect)
  local_ip:     ""          # IP لوکال (خالی = auto-detect)
  router_mac:   ""          # MAC gateway — فقط در client (خالی = ARP auto)

  # ── KCP / FEC ──────────────────────────────────────────────────
  mtu:          1350        # حداکثر اندازه پکت (bytes)
  snd_wnd:      1024        # پنجره ارسال KCP (تعداد پکت)
  rcv_wnd:      1024        # پنجره دریافت KCP (تعداد پکت)
  data_shard:   10          # تعداد data shardهای FEC
  parity_shard: 1           # تعداد parity shardهای FEC
  sock_buf:     4194304     # بافر pcap (bytes) — 4MB پیش‌فرض

  # ── TCP Flags ──────────────────────────────────────────────────
  local_flags:              # flag پکت‌های ارسالی از این سمت
    - "PA"                  # PSH+ACK (معمول‌ترین)
    - "A"                   # ACK خالی
  remote_flags:             # flag مورد انتظار از طرف مقابل
    - "PA"
    - "A"
```

---

## 🎛️ راهنمای تنظیم پارامترها

### ۱. MTU

```
MTU = حداکثر اندازه payload هر پکت TCP جعلی
```

| شرایط | مقدار توصیه‌شده |
|-------|----------------|
| اینترنت عادی | `1350` |
| VPN روی VPN (double tunnel) | `1280` |
| شبکه با جیتر بالا | `1200` |
| LAN/DC | `1400` |

> ⚠️ اگر MTU خیلی بزرگ باشد، pcap پکت‌ها را drop می‌کند.
> اگر خیلی کوچک باشد، overhead بالا می‌رود.

**فرمول بهینه:**
```
MTU_dagger = MTU_شبکه - 40 (IP+TCP header) - 8 (daggerFrame header)
```

---

### ۲. پنجره KCP (snd_wnd / rcv_wnd)

این مقدار تعداد پکت‌هایی است که بدون دریافت ACK می‌توانند در راه باشند.

```
Throughput ≈ (snd_wnd × MTU) / RTT
```

**مثال:**
```
snd_wnd=1024, MTU=1350, RTT=80ms
→ ~13.5 MB/s theoretical max
```

| کاربرد | snd_wnd | rcv_wnd |
|--------|---------|---------|
| یک کاربر / low latency | `512` | `512` |
| چند کاربر همزمان | `1024` | `1024` |
| پرسرعت (فیبر) | `2048` | `2048` |
| شبکه با تأخیر بالا (>200ms) | `2048` | `2048` |

---

### ۳. FEC — Forward Error Correction

FEC خطاهای شبکه را بدون retransmit جبران می‌کند — اما **مستقیماً bandwidth مصرف می‌کند.**

```
ضریب مصرف bandwidth = (data_shard + parity_shard) / data_shard
overhead واقعی      = parity_shard / data_shard × 100%
```

| data_shard | parity_shard | ضریب مصرف | overhead | جبران packet loss |
|------------|--------------|-----------|----------|-------------------|
| 20 | 1 | **1.05x** | 5% | تا 5% |
| 10 | 1 | **1.10x** | 10% | تا 10% |
| 10 | 2 | **1.20x** | 20% | تا 20% |
| 10 | 3 | **1.30x** | 30% | تا 30% |
| 5  | 3 | **1.60x** | 60% | تا 60% |

> **مثال عملی:** اگر سرور شما 100 Mbps دارد و `data_shard=10, parity_shard=2`:
> مصرف واقعی = 100 × 1.20x = **120 Mbps** — یعنی ۲۰ Mbps اضافه می‌سوزد.

**توصیه بر اساس کیفیت شبکه:**

```yaml
# شبکه باکیفیت (packet loss < 1%):
data_shard: 20
parity_shard: 1     # ضریب: 1.05x ← کمترین هدررفت

# شبکه متوسط (packet loss 1-5%):
data_shard: 10
parity_shard: 1     # ضریب: 1.10x ← پیش‌فرض بهینه

# شبکه ضعیف (packet loss 5-15%):
data_shard: 10
parity_shard: 2     # ضریب: 1.20x

# شبکه خیلی بد (> 15% loss):
data_shard: 10
parity_shard: 3     # ضریب: 1.30x
```

> 💡 **قانون طلایی:** با `parity=1` شروع کنید. فقط اگر در `ping` یا `mtr` به سرور drop مداوم دیدید بالا ببرید.

---

### ⛔ Obfuscation — باید خاموش باشد

```yaml
obfuscation:
  enabled: false   # ← اجباری برای DaggerMux
```

> **چرا؟**

DaggerMux خودش payload را داخل TCP frame جعلی می‌گذارد. لایه obfuscation روی **هر پکت** padding اضافه می‌کند:

```
بدون obfuscation:  Data → daggerEncodeFrame → KCP → pcap
با obfuscation:    Data → padding اضافه → re-framing → daggerEncodeFrame → KCP → pcap
                                 ↑
                          این لایه اضافی روی DaggerMux بی‌معنی و مضر است
```

**اثر روشن بودن obfuscation روی DaggerMux:**

| مشکل | توضیح |
|------|-------|
| **ضریب مصرف +1.5x تا +3x** | هر پکت 16–512 byte padding اضافه می‌گیرد |
| **MTU violation** | پکت‌ها از MTU تعریف‌شده بزرگ‌تر می‌شوند → fragmentation یا drop |
| **Latency بالاتر** | دو لایه framing به‌جای یک لایه |
| **CPU بیشتر** | دو بار serialize/deserialize |

**مثال عددی:**
```
MTU=1350, obfuscation min_padding=16, max_padding=512

بدترین حالت: 1350 + 512 = 1862 bytes per packet
→ pcap drop می‌کند (از MTU شبکه بزرگ‌تر است)
→ اتصال ناپایدار یا کاملاً قطع
```

**DPI bypass روی DaggerMux چطور کار می‌کند؟**
از طریق **TCP flag manipulation** و **connID** — نه padding. بنابراین obfuscation هیچ مزیتی اضافه نمی‌کند و فقط آسیب می‌زند.

```yaml
# ✅ تنظیم صحیح برای DaggerMux
obfuscation:
  enabled: false

# ❌ هرگز این‌طور تنظیم نکنید
obfuscation:
  enabled: true   # با DaggerMux ترکیب نکنید
```

---

### ۴. TCP Flags

DaggerMux می‌تواند هر ترکیبی از TCP flag تولید کند تا ترافیک شبیه جریان‌های واقعی شود.

| Flag | معنی | کاربرد |
|------|------|--------|
| `PA` | PSH+ACK | **رایج‌ترین** — شبیه HTTP data |
| `A` | ACK | شبیه TCP ack خالی |
| `S` | SYN | فقط برای handshake |
| `FA` | FIN+ACK | شبیه close |
| `SA` | SYN+ACK | شبیه handshake پاسخ |

**پروفایل‌های توصیه‌شده:**

```yaml
# پروفایل HTTP — شبیه‌ترین به ترافیک وب معمولی
local_flags:
  - "PA"
  - "A"
  - "PA"
remote_flags:
  - "PA"
  - "A"

# پروفایل Stealth — تنوع بیشتر
local_flags:
  - "PA"
  - "A"
  - "PA"
  - "FA"
remote_flags:
  - "SA"
  - "PA"
  - "A"

# پروفایل Minimal — ساده‌ترین
local_flags:
  - "PA"
remote_flags:
  - "PA"
```

> ⚠️ از `S` (SYN) به تنهایی در `local_flags` استفاده نکنید — کرنل RST می‌فرستد مگر اینکه iptables rules اعمال شده باشند.

---

### ۵. sock_buf (بافر pcap)

```yaml
sock_buf: 4194304   # 4MB پیش‌فرض
```

| ترافیک | sock_buf |
|--------|----------|
| < 10MB/s | `4194304` (4MB) |
| 10–50MB/s | `8388608` (8MB) |
| > 50MB/s | `16777216` (16MB) |

> اگر در لاگ `pcap: packet buffer overflow` دیدید، این مقدار را دوبرابر کنید.

---

## 🚨 iptables — اجباری

بدون این rule‌ها، کرنل لینوکس برای هر پکت ورودی یک **RST** می‌فرستد و اتصال خراب می‌شود:

```bash
# روی سرور — PORT را با پورت واقعی خود جایگزین کنید
PORT=2020

# جلوگیری از tracking کرنل
iptables -t raw    -A PREROUTING -p tcp --dport $PORT -j NOTRACK
iptables -t raw    -A OUTPUT     -p tcp --sport $PORT -j NOTRACK

# Drop کردن RST خودکار کرنل
iptables -t mangle -A OUTPUT     -p tcp --sport $PORT --tcp-flags RST RST -j DROP
```

**ذخیره دائمی:**
```bash
iptables-save > /etc/iptables/rules.v4
```

**بررسی اعمال شدن:**
```bash
iptables -t raw    -L PREROUTING -n | grep $PORT
iptables -t mangle -L OUTPUT    -n | grep $PORT
```

---

## 🔍 Auto-detection

DaggerMux سعی می‌کند اطلاعات شبکه را خودکار پیدا کند:

| پارامتر | روش auto-detect |
|---------|----------------|
| `interface` | بر اساس `local_ip` و routing table |
| `local_ip` | `dial udp 8.8.8.8:80` → local addr |
| `router_mac` | `/proc/net/route` → gateway IP → `/proc/net/arp` |

**مشکل رایج با ARP:**
```
daggermux: auto-detect gateway MAC: ARP entry not found for 192.168.1.1
hint: run: ping -c1 192.168.1.1 first
```

**راه‌حل:**
```bash
ping -c3 $(ip route | grep default | awk '{print $3}')
# یا
router_mac: "aa:bb:cc:dd:ee:ff"   # در config ست کنید
```

---

## 📋 نمونه Config کامل

### سرور (ایران)

```yaml
mode: "server"
psk: "your-strong-psk-here"
profile: "latency"
verbose: false
heartbeat: 2

listeners:
  - addr: "0.0.0.0:2020"
    transport: "daggermux"
    maps:
      - type: tcp
        bind: "0.0.0.0:8080"
        target: "127.0.0.1:8080"
      - type: udp
        bind: "0.0.0.0:5353"
        target: "127.0.0.1:5353"

daggermux:
  mtu: 1350
  snd_wnd: 1024
  rcv_wnd: 1024
  data_shard: 10
  parity_shard: 1
  sock_buf: 4194304
  local_flags:
    - "PA"
    - "A"
  remote_flags:
    - "PA"
    - "A"
```

### کلاینت (خارج)

```yaml
mode: "client"
psk: "your-strong-psk-here"
profile: "latency"
verbose: false
heartbeat: 2

paths:
  - transport: "daggermux"
    addr: "IRAN_SERVER_IP:2020"
    connection_pool: 2
    aggressive_pool: true
    retry_interval: 2
    dial_timeout: 10

daggermux:
  local_ip: ""          # auto
  interface: ""         # auto
  router_mac: ""        # auto (یا MAC gateway خود را ست کنید)
  mtu: 1350
  snd_wnd: 1024
  rcv_wnd: 1024
  data_shard: 10
  parity_shard: 1
  sock_buf: 4194304
  local_flags:
    - "PA"
    - "A"
  remote_flags:
    - "PA"
    - "A"
```

---

## 🚀 پروفایل‌های بهینه‌سازی

### 🎮 Gaming / Low Latency

```yaml
daggermux:
  mtu: 1200
  snd_wnd: 512
  rcv_wnd: 512
  data_shard: 10
  parity_shard: 1      # ضریب bandwidth: 1.10x
  local_flags: ["PA", "A"]
  remote_flags: ["PA", "A"]

obfuscation:
  enabled: false       # ⛔ اجباری
```
```yaml
kcp:
  nodelay: 1
  interval: 5
  resend: 2
  nc: 1
  sndwnd: 512
  rcvwnd: 512
```

---

### 📥 High Throughput (دانلود/آپلود سنگین)

```yaml
daggermux:
  mtu: 1350
  snd_wnd: 2048
  rcv_wnd: 2048
  data_shard: 20
  parity_shard: 1      # ضریب bandwidth: 1.05x ← کمترین overhead ممکن
  sock_buf: 8388608
  local_flags: ["PA"]
  remote_flags: ["PA"]

obfuscation:
  enabled: false       # ⛔ اجباری
```
```yaml
kcp:
  nodelay: 1
  interval: 10
  resend: 2
  nc: 1
  sndwnd: 2048
  rcvwnd: 2048
```

---

### 🛡️ Maximum Stealth (DPI سخت‌گیر)

```yaml
daggermux:
  mtu: 1300
  snd_wnd: 1024
  rcv_wnd: 1024
  data_shard: 10
  parity_shard: 1      # ضریب: 1.10x
  local_flags:
    - "PA"
    - "A"
    - "PA"
    - "PA"
    - "A"
  remote_flags:
    - "PA"
    - "A"
    - "PA"

obfuscation:
  enabled: false       # ⛔ اجباری — با DaggerMux روشن نکنید
```

---

### 🌐 شبکه پرنوسان (packet loss بالا)

```yaml
daggermux:
  mtu: 1280
  snd_wnd: 2048
  rcv_wnd: 2048
  data_shard: 10
  parity_shard: 2      # ضریب bandwidth: 1.20x — برای جبران drop
  sock_buf: 8388608
  local_flags: ["PA", "A"]
  remote_flags: ["PA", "A"]

obfuscation:
  enabled: false       # ⛔ اجباری
```
```yaml
kcp:
  nodelay: 1
  interval: 15
  resend: 3
  nc: 1
  sndwnd: 2048
  rcvwnd: 2048
```

---

## 🧪 تشخیص مشکل

### تست اتصال اولیه

```bash
# از سمت کلاینت — بررسی دسترسی به پورت
timeout 5 bash -c "cat < /dev/tcp/IRAN_IP/2020" && echo "Port reachable"

# بررسی آیا pcap ترافیک می‌بیند
tcpdump -i eth0 -nn "tcp port 2020" -c 20
```

### لاگ‌های مهم

| لاگ | معنی | اقدام |
|-----|------|-------|
| `✅ [daggermux] Dial connID=...` | اتصال موفق | — |
| `⚠️ [daggermux] idle timeout` | 15 ثانیه بدون پکت | MTU یا NAT مشکل دارد |
| `⚠️ [daggermux] Write error — triggering reconnect` | اتصال قطع شد | auto-reconnect فعال است |
| `pcap activate eth0: permission denied` | نیاز به root | `sudo` اجرا کنید |
| `ARP entry not found` | gateway MAC پیدا نشد | `ping` بزنید یا `router_mac` ست کنید |
| `kcp cipher: ...` | خطای رمزنگاری | PSK را بررسی کنید |

### بررسی iptables

```bash
# اطمینان از rule‌های NOTRACK
iptables -t raw -L -n -v | grep 2020

# اطمینان از Drop RST
iptables -t mangle -L -n -v | grep RST

# مشاهده live ترافیک pcap
tcpdump -i any -nn -X "tcp port 2020" 2>/dev/null | head -100
```

### CPU / Memory

```bash
# مصرف منابع DaggerConnect
pidstat -p $(pgrep DaggerConnect) 1

# مشاهده pcap buffer drops
cat /proc/net/dev | grep eth0
netstat -s | grep "receive buffer"
```

---

## ⚠️ محدودیت‌ها و نکات مهم

```
┌─────────────────────────────────────────────────────┐
│  ❗ نیاز به root / CAP_NET_RAW                       │
│  ❗ فقط IPv4 پشتیبانی می‌شود                          │
│  ❗ iptables rules اجباری است روی سرور               │
│  ❗ روی NAT دوگانه (CGN) ممکن است مشکل داشته باشد   │
│  ❗ libpcap باید نصب باشد (apt install libpcap-dev)  │
│  ❗ هر listener/path یک pcap handle جداگانه باز می‌کند│
└─────────────────────────────────────────────────────┘
```

### NAT و محیط‌های cloud

روی برخی VPSها (مخصوصاً OpenVZ/LXC) دسترسی به pcap محدود است:

```bash
# بررسی دسترسی pcap
python3 -c "import ctypes; print(ctypes.cdll.LoadLibrary('libpcap.so'))"

# بررسی capabilities
getcap $(which DaggerConnect) 2>/dev/null || echo "No caps set"

# اگر root نیستید، capability بدهید
setcap cap_net_raw,cap_net_admin+eip /usr/local/bin/DaggerConnect
```

---

## 🔄 مقایسه DaggerMux با سایر Transport‌ها

```
┌──────────────┬──────┬──────┬────────┬────────┬────────────┐
│  Transport   │ DPI  │Speed │Latency │ Setup  │   Root     │
├──────────────┼──────┼──────┼────────┼────────┼────────────┤
│ httpsmux     │ ★★★★ │ ★★★★ │  ★★★   │  Easy  │   No       │
│ httpmux      │ ★★★  │ ★★★★ │  ★★★   │  Easy  │   No       │
│ wssmux       │ ★★★★ │ ★★★  │  ★★★   │  Easy  │   No       │
│ kcpmux       │  ★   │ ★★★★★│  ★★★★★ │  Easy  │   No       │
│ rawmux       │ ★★   │ ★★★★★│  ★★★★★ │  Med   │   No       │
│ daggermux    │ ★★★★★│ ★★★★ │  ★★★★  │  Hard  │   YES      │
└──────────────┴──────┴──────┴────────┴────────┴────────────┘

★ = کم    ★★★★★ = عالی
```

**انتخاب transport:**
- 🔵 **httpsmux** → انتخاب پیش‌فرض برای اکثر کاربران
- 🔴 **daggermux** → وقتی همه روش‌های دیگر فیلتر شده‌اند

---

## 📊 تنظیم بر اساس سناریو واقعی

### سناریو ۱: سرور ایران ← → سرور اروپا (RTT ~120ms)

```yaml
daggermux:
  mtu: 1350
  snd_wnd: 1024
  rcv_wnd: 1024
  data_shard: 10
  parity_shard: 1
kcp:
  nodelay: 1
  interval: 10
  resend: 2
  nc: 1
  sndwnd: 1024
  rcvwnd: 1024
```

### سناریو ۲: فیلترینگ سنگین، packet loss بالا (RTT ~200ms)

```yaml
daggermux:
  mtu: 1280
  snd_wnd: 2048
  rcv_wnd: 2048
  data_shard: 10
  parity_shard: 2
  sock_buf: 8388608
kcp:
  nodelay: 1
  interval: 15
  resend: 3
  nc: 1
  sndwnd: 2048
  rcvwnd: 2048
```

### سناریو ۳: یوزر gaming، تأخیر کم مهم‌تر از throughput

```yaml
daggermux:
  mtu: 1200
  snd_wnd: 512
  rcv_wnd: 512
  data_shard: 10
  parity_shard: 1
kcp:
  nodelay: 1
  interval: 5
  resend: 2
  nc: 1
  sndwnd: 512
  rcvwnd: 512
profile: "gaming"
```

---

*DaggerConnect — DaggerMux Transport Reference*
