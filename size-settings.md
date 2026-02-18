# راهنمای کامل تنظیم سایزها — DaggerConnect
## برای سناریو: vless+tcp / httpmux / سرور ایرانی

---

## ۱. منطق کلی — چرا هر مقدار مهمه؟

```
کاربر → [smux session] → [smux stream × N] → [tcp conn به xray] → اینترنت
```

هر کاربر vless:
- ۱ smux session
- معمولاً ۲-۵ stream همزمان (هر tab مرورگر = ۱-۲ stream)
- هر stream = ۱ tcp connection به xray روی loopback

---

## ۲. SMUX Settings

### `keepalive` (ثانیه)
**هدف:** تشخیص session های مرده

```
keepalive = 10s  →  timeout = keepalive × 5 = 50s
keepalive = 15s  →  timeout = 75s
keepalive = 20s  →  timeout = 100s
```

| کاربر | keepalive | توضیح |
|-------|-----------|-------|
| < 100 | 8-10s | تشخیص سریع session مرده |
| 100-300 | 10-15s | تعادل |
| 300-500 | 15-20s | فشار keepalive روی CPU کمتر |
| 500+ | 20-30s | هر keepalive = N پیام به همه session ها |

**محاسبه بار keepalive:**
```
پیام/ثانیه = تعداد_session / keepalive
500 session ÷ 10s = 50 پیام/ثانیه  ← قابل قبول
500 session ÷ 8s  = 62 پیام/ثانیه  ← کمی زیاد
```

---

### `max_recv` و `max_stream` (بایت)
**هدف:** حداکثر داده‌ای که smux می‌تونه buffer کنه

این یه **shared pool** هست، نه per-session. یعنی ۴MB برای همه session ها تقسیم میشه.

**قانون اصلی:**
```
max_recv ≥ frame_size × تعداد_stream_همزمان_در_burst
```

| سناریو | کاربر | max_recv | RAM مصرفی تقریبی |
|--------|-------|----------|------------------|
| سبک | < 100 | 2MB | ~50MB |
| متوسط | 100-300 | 4MB | ~100MB |
| سنگین | 300-500 | 6-8MB | ~150-200MB |
| خیلی سنگین | 500+ | 8-16MB | ~300MB+ |

**محدودیت RAM:**
```
اگه RAM = 2GB:
  max_recv ≤ 4MB   (smux نباید بیشتر از 10-15% RAM بگیره)

اگه RAM = 4GB:
  max_recv ≤ 8MB

اگه RAM = 8GB+:
  max_recv ≤ 16MB
```

**نکته:** `max_stream` معمولاً = `max_recv` بذار.

---

### `frame_size` (بایت)
**هدف:** سایز هر packet داخل smux

```
frame_size کوچیک = latency کمتر، overhead بیشتر
frame_size بزرگ = throughput بیشتر، latency بیشتر
```

| ترافیک | frame_size | توضیح |
|--------|-----------|-------|
| VoIP/gaming | 8192 (8KB) | latency مهمه |
| مرورگر عادی | 16384 (16KB) | تعادل |
| **vless+tcp** | **32768 (32KB)** | **بهترین برای اکثر ترافیک** |
| دانلود سنگین | 65536 (64KB) | throughput max |

**تقریباً همیشه ۳۲KB بذار.** فقط اگه ping بالاست ۱۶KB امتحان کن.

---

## ۳. Advanced Settings

### `tcp_read_buffer` و `tcp_write_buffer`
**مهم‌ترین نکته:** این buffer برای connection **از DaggerConnect به xray** هست، نه از کاربر به DaggerConnect.

```
xray روی 127.0.0.1 (loopback):
  RTT ≈ 0.1ms
  bandwidth = عملاً نامحدود

فرمول:
  بهینه = bandwidth × RTT
  loopback: هر عددی بالای 64KB اضافه‌ست
```

| نوع connection | buffer بهینه |
|----------------|-------------|
| loopback (xray) | 64KB - 256KB |
| شبکه محلی (LAN) | 512KB - 1MB |
| اینترنت (WAN) | 1MB - 4MB |

```
پس برای vless که xray روی همون سرور هست:
  tcp_read_buffer: 131072   # 128KB کافیه
  tcp_write_buffer: 131072  # 128KB کافیه
```

با ۴MB buffer روی loopback فقط RAM هدر میده!

---

### `connection_timeout` (ثانیه)
زمان انتظار برای برقراری connection اولیه

```
اگه < 15s → connection موفق نشده = مرده است
```

| شبکه | مقدار |
|------|-------|
| اینترنت ایران (معمولی) | 10-15s |
| اینترنت ایران (پرفشار/فیلترینگ) | 20-30s |
| LAN | 5s |

**توصیه: ۱۵s** — اگه ۱۵ ثانیه وصل نشد، retry کنه بهتره از منتظر موندن.

---

### `stream_timeout` (ثانیه)
زمانی که یه stream بدون فعالیت باز میمونه

```
stream مرده = goroutine leak = حافظه هدر رفته
```

| ترافیک | مقدار |
|--------|-------|
| HTTP معمولی | 30-60s |
| **vless+tcp** | **60s** |
| فایل بزرگ دانلود | 120-300s |
| WebSocket/long-poll | 300s+ |

**توصیه: ۶۰s** برای vless — اگه یه stream 60 ثانیه ساکت بود، احتمالاً مرده.

---

### `cleanup_interval` (ثانیه)
هر چند ثانیه session/stream های مرده پاک بشن

```
cleanup کم = حافظه سریع‌تر آزاد میشه ← CPU بیشتر
cleanup زیاد = حافظه دیرتر آزاد میشه ← CPU کمتر
```

| کاربر | مقدار |
|-------|-------|
| < 100 | 3s |
| 100-300 | 5s |
| 300-500 | 5-10s |
| 500+ | 10s |

---

### `udp_flow_timeout` (ثانیه)
مدت نگه‌داری UDP flow بعد از آخرین packet

```
vless+tcp → UDP استفاده خیلی کمی داره
→ timeout کوتاه = حافظه بهتر آزاد میشه
```

| ترافیک | مقدار |
|--------|-------|
| vless+tcp (شما) | 30-60s |
| vless+udp / DNS | 60-120s |
| gaming / VoIP | 120-300s |

---

### `max_connections`
حداکثر connection همزمان که سرور قبول میکنه

```
RAM مورد نیاز تقریبی:
  هر connection ≈ tcp_buffer × 2 + smux overhead
  هر connection با 128KB buffer ≈ 300-400KB RAM

فرمول:
  max_connections ≤ (RAM_قابل_استفاده) / (buffer_per_conn)
```

| RAM | tcp_buffer | max_connections |
|-----|-----------|----------------|
| 2GB | 128KB | ~500 |
| 2GB | 256KB | ~300 |
| 4GB | 256KB | ~600 |
| 4GB | 512KB | ~400 |
| 8GB | 256KB | ~1200 |

**توصیه برای ۲-۴GB RAM با ۲۵۶KB buffer:**
```
max_connections: 400-600
```

---

### `obfuscation padding`
**overhead محاسبه:**
```
overhead% = max_padding / (میانگین_packet_size + max_padding) × 100

vless packet معمولی ≈ 1000-1400 bytes
با max_padding=256: overhead ≈ 18%
با max_padding=512: overhead ≈ 37%
با max_padding=128: overhead ≈ 9%
```

با ۵۰۰ کاربر × ۱۰ Mbps = ۵ Gbps ترافیک:
```
padding=512 → ~37% overhead → ۱.۸۵ Gbps هدر میره
padding=256 → ~18% overhead → ۰.۹ Gbps هدر میره
padding=128 → ~9% overhead  → ۰.۴۵ Gbps هدر میره
```

برای سرور با bandwidth محدود padding رو کم کن.

---

## ۴. Linux Kernel — مهم‌تر از همه

```bash
cat >> /etc/sysctl.conf << 'EOF'
# شبکه
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535

# TCP buffers (kernel level)
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 87380 4194304
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304

# BBR congestion control — خیلی مهم
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# TIME_WAIT سریع‌تر آزاد بشه
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# file descriptors
fs.file-max = 1000000
EOF

sysctl -p
```

```bash
# file descriptor limit برای process
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 1000000
* hard nofile 1000000
EOF
```

**BBR چقدر فرق میکنه؟**
```
بدون BBR (cubic): با packet loss 5% → throughput افت 40-60%
با BBR:           با packet loss 5% → throughput افت 10-20%

ایران → packet loss معمولاً 2-10% داره → BBR خیلی مهمه
```

---

## ۵. جدول خلاصه — کپی مستقیم

### سرور ۲GB RAM / 200 کاربر
```yaml
smux:
  keepalive: 10
  max_recv: 2097152      # 2MB
  max_stream: 2097152
  frame_size: 32768

advanced:
  tcp_read_buffer: 131072    # 128KB
  tcp_write_buffer: 131072
  cleanup_interval: 5
  connection_timeout: 15
  stream_timeout: 60
  max_connections: 300
  udp_flow_timeout: 60
  udp_buffer_size: 524288    # 512KB

obfuscation:
  max_padding: 128
```

### سرور ۴GB RAM / 300 کاربر
```yaml
smux:
  keepalive: 12
  max_recv: 4194304      # 4MB
  max_stream: 4194304
  frame_size: 32768

advanced:
  tcp_read_buffer: 262144    # 256KB
  tcp_write_buffer: 262144
  cleanup_interval: 5
  connection_timeout: 15
  stream_timeout: 60
  max_connections: 500
  udp_flow_timeout: 60
  udp_buffer_size: 1048576   # 1MB

obfuscation:
  max_padding: 256
```

### سرور ۴GB RAM / 500 کاربر (فشار زیاد)
```yaml
smux:
  keepalive: 15
  max_recv: 4194304      # 4MB — زیادتر کمک نمیکنه
  max_stream: 4194304
  frame_size: 32768

advanced:
  tcp_read_buffer: 262144    # 256KB
  tcp_write_buffer: 262144
  cleanup_interval: 10
  connection_timeout: 15
  stream_timeout: 60
  max_connections: 600
  udp_flow_timeout: 30
  udp_buffer_size: 1048576

obfuscation:
  max_padding: 128           # overhead کمتر با فشار زیاد
```

### سرور ۸GB RAM / 1000 کاربر
```yaml
smux:
  keepalive: 20
  max_recv: 8388608      # 8MB
  max_stream: 8388608
  frame_size: 32768

advanced:
  tcp_read_buffer: 262144
  tcp_write_buffer: 262144
  cleanup_interval: 10
  connection_timeout: 15
  stream_timeout: 60
  max_connections: 1200
  udp_flow_timeout: 30
  udp_buffer_size: 1048576

obfuscation:
  max_padding: 64            # overhead خیلی کم با 1000 کاربر
```

---

## ۶. چطور بفهمیم تنظیمات درسته؟

```bash
# RAM مصرفی DaggerConnect
ps aux | grep dagger

# تعداد connection های باز
ss -s

# file descriptor های باز
ls /proc/$(pgrep dagger)/fd | wc -l

# اگه این عدد به 1000000 نزدیک شد → limits مشکل داره
cat /proc/sys/fs/file-nr
```

**علائم تنظیم اشتباه:**
- RAM بالا میره و پایین نمیاد → `cleanup_interval` رو کم کن
- CPU spike هر چند ثانیه → `keepalive` رو زیاد کن
- disconnect های تصادفی → `stream_timeout` رو زیاد کن
- connection قطع و وصل → `connection_timeout` رو زیاد کن
- throughput پایین با کاربر کم → `tcp_read/write_buffer` رو زیاد کن
- throughput پایین با کاربر زیاد → `max_padding` رو کم کن
