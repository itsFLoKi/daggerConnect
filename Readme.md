# ⚙️ DaggerConnect

<div align="center">

[![buyLICENSE](https://img.shields.io/badge/buyLICENSE-@DaggerConnectBot-blue.svg)](https://t.me/DaggerConnectBot)
[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)](https://github.com/itsFLoKi/DaggerConnect/releases)
[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org)
[![Telegram](https://img.shields.io/badge/Telegram-@DaggerConnect-blue.svg)](https://t.me/DaggerConnect)

[ویژگی‌ها](#-ویژگیها) • [نصب](#-نصب) • [فرمت کانفیگ](#-فرمت-کانفیگ) • [ترنسپورت‌ها](#-ترنسپورتها) • [اتوتیونر](#-اتوتیونر) • [SOCKS5](#-پروکسی-socks5) • [پورت‌فورواردینگ](#-پورتفورواردینگ) • [نمونه کانفیگ](#-نمونه-کانفیگ)

</div>

---

## 🎯 معرفی

DaggerConnect یک ریورس تانل حرفه‌ایه که با هدف عبور امن و پایدار از فیلترینگ ساخته شده — با رمزنگاری واقعی روی تمام ترافیک (نه فقط obfuscation ظاهری)، تشخیص و بازیابی هوشمند از قطعی، و چندین ترنسپورت با کاربردهای متفاوت.

---

## ✨ ویژگی‌ها

- 🔐 **رمزنگاری AES-GCM** — روی تک‌تک پکت‌ها و فریم‌های تونل، در همه‌ی ترنسپورت‌ها (از جمله TUN)
- 🧩 **هسته‌ی DagMux** — مالتی‌پلکسر اختصاصی برای چند stream روی یک اتصال
- 🔁 **Reconnect هوشمند** — تشخیص دقیق قطعی و اتصال مجدد بدون دخالت دستی
- 💓 **Heartbeat قابل‌تنظیم** — تشخیص کانکشن مرده بدون false-positive روی لینک‌های ناپایدار
- 🎭 **آنتی DPI** — مخصوصاً ترنسپورت `tun` با پروفایل `bip`، ترافیک رو شبیه پروتکل‌های معمولی می‌کنه
- 🌐 **ترنسپورت TUN (لایه‌ی ۳)** — تونل سطح شبکه با IP اختصاصی point-to-point
- ⚛️ **ترنسپورت Quantum (v3)** — تونل مبتنی بر raw packet، مقاوم در برابر فیلترینگ
- 🧦 **پروکسی SOCKS5 مستقل** — سمت سرور، جدا از پورت‌فورواردینگ
- 🔀 **پورت‌فورواردینگ TCP/UDP** — با تشخیص خودکار پروتکل
- 🎛️ **اتوتیونر** — کنترل خودکار یا دستی بافرها و پارامترهای شبکه با پروفایل‌های آماده

---

## 🚀 نصب

روش پیشنهادی و رسمی نصب، از طریق اسکریپت نصب‌کننده‌ست — نیازی به ساخت دستی کانفیگ یا سرویس systemd نیست، خودش همه‌چیز رو مدیریت می‌کنه.

```bash
curl -O https://raw.githubusercontent.com/itsFLoKi/DaggerConnect/main/setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

با اجرای اسکریپت، یه منوی تعاملی باز می‌شه:

```
  Select an option:
  Install
    1)  Install Server
    2)  Install Client
  Manage
    3)  Service Status
    4)  Service Control  (restart / stop / start)
    5)  Edit Config
  Logs
    6)  View Logs        (last 80 lines)
    7)  Live Logs        (follow)
  Other
    8)  Remove
    0)  Exit
```

اسکریپت به‌ترتیب ترنسپورت، پورت، PSK (کد لایسنس)، تنظیمات هر ترنسپورت، و پروفایل تیونر رو می‌پرسه، و در پایان کانفیگ + سرویس systemd رو خودکار می‌سازه و اجرا می‌کنه.

### نصب/اجرای دستی (بدون اسکریپت)

اگه ترجیح می‌دید دستی کار کنید:

```bash
DaggerConnect --gen server   # ساخت کانفیگ نمونه‌ی سرور
DaggerConnect --gen client   # ساخت کانفیگ نمونه‌ی کلاینت

DaggerConnect -c config.json    # اجرا با کانفیگ (JSON یا YAML، فرقی نداره)
DaggerConnect -v                # نمایش نسخه
```

---

## 📄 فرمت کانفیگ

کانفیگ هم به‌صورت **JSON** هم **YAML** پشتیبانی می‌شه — هر دو دقیقاً همون فیلدها رو دارن، فقط فرمت متفاوته. اسکریپت نصب موقع ساخت کانفیگ ازتون می‌پرسه کدوم فرمت رو می‌خواید.

انتخاب بینشون کاملاً سلیقه‌ایه؛ فقط اگه دستی ادیت می‌کنید، YAML رو خواناتر و JSON رو دقیق‌تر (کمتر جای خطای indentation) پیدا می‌کنید.

---

## 🎨 ترنسپورت‌ها

| ترنسپورت | نوع | مناسب برای                                                                                                       |
|---|---|------------------------------------------------------------------------------------------------------------------|
| `tcp` | TCP ساده | سبک‌ترین حالت، شبکه‌های بدون فیلترینگ سنگین                                                                      |
| `ws` | WebSocket | شبیه‌سازی ترافیک وب معمولی                                                                                       |
| `wss` | WebSocket + TLS | مثل `ws` به‌علاوه‌ی رمزنگاری TLS در لایه‌ی انتقال                                                                |
| `http` | HTTP Mimicry | شبیه‌سازی ترافیک HTTP معمولی                                                                                     |
| `https` | HTTP Mimicry + TLS | شبیه سازی ترافیک https                                                                                           |
| `quantum` | Raw-packet (نسخه‌ی ۳) | مقاومت بالا در برابر فیلترینگ، عبور پکت خام با obfuscation                                                       |
| `tun` | تونل لایه‌ی ۳ (نسخه‌ی ۲) | یه رابط شبکه‌ی مجازی با IP اختصاصی؛ چند پروفایل (`bip`، `icmp`، `gre`، `ipip`)؛ پروفایل `bip` مقاوم در برابر DPI |

نکته: هم `quantum` هم `tun` امکانات پیشرفته‌تری هم دارن (مثل IP Spoofing، DCPI) که برای شروع لازم نیست بهشون فکر کنید — تنظیمات پیش‌فرض برای اکثر کاربردها کافیه.

---

## 🎛️ اتوتیونر

اتوتیونر بافرها، پنجره‌ها و پارامترهای timeout رو کنترل می‌کنه. یا از پروفایل‌های آماده استفاده کنید، یا دستی هر مقدار رو تنظیم کنید.

| پروفایل | مناسب برای |
|---|---|
| `auto` | تیونینگ زنده و خودکار بر اساس ترافیک واقعی (پیشنهادی) |
| `stable` | تعادل بین سرعت و پایداری |
| `aggressive` | بیشترین throughput، مصرف حافظه‌ی بیشتر |
| `low_latency` | کمترین تاخیر، بافر کوچیک‌تر |
| `low_hardware` | برای VPS با منابع محدود |
| `custom` | تنظیم دستیِ تک‌تک مقادیر |

بخش `advanced` تو کانفیگ همینا رو نگه می‌داره — از جمله `keepalive_sec` و `dead_timeout_sec` (فاصله‌ی heartbeat و آستانه‌ی تشخیص قطعی، برای همه‌ی ترنسپورت‌ها به‌جز `tun`). ترنسپورت `tun` این دو مقدار رو جدا و داخل بخش `tun` خودش داره: `heartbeat_sec` و `idle_timeout_sec`.

```yaml
advanced:
  auto_tune: true
  keepalive_sec: 5
  dead_timeout_sec: 25
  # ... بقیه‌ی پارامترهای بافر/تایم‌اوت
```

---

## 🧦 پروکسی SOCKS5

یه پروکسی SOCKS5 مستقل، فقط سمت **سرور**، کاملاً جدا از سیستم پورت‌فورواردینگ. با فعال‌کردنش، هر ترافیکی که به این پورت برسه از تونل رد می‌شه و از سمت کلاینت به مقصد واقعی وصل می‌شه.

```yaml
socks5:
  enabled: true
  bind: "127.0.0.1:6060"
```

تست کردنش (رو خودِ سرور):

```bash
curl -x socks5h://127.0.0.1:6060 https://ifconfig.me
```

> پیشنهاد: چون این پروکسی احراز هویت نداره، همیشه رو `127.0.0.1` نگهش دارید، نه `0.0.0.0`.

---

## 🔀 پورت‌فورواردینگ

هر `listener` (سمت سرور) می‌تونه چند پورت رو فوروارد کنه — با فرمت کوتاه یا کامل، و پشتیبانی خودکار از TCP و UDP:

**فرمت کوتاه** (هم TCP هم UDP رو خودکار پوشش می‌ده):
```yaml
ports:
  - "2222=22"          # bind 2222 → target 22 (روی 127.0.0.1)
  - "8080"              # bind 8080 → target 8080
```

**فرمت کامل** (وقتی نیاز به کنترل دقیق‌تر یا مقصد غیر از 127.0.0.1 دارید):
```yaml
maps:
  - type: tcp
    bind: "0.0.0.0:2222"
    target: "192.168.1.10:22"
  - type: udp
    bind: "0.0.0.0:5000"
    target: "127.0.0.1:5000"
```

اگه `type` رو ننویسید، هم TCP هم UDP خودکار روی همون بایند/مقصد فعال می‌شن.

---

## 📝 نمونه کانفیگ

یه نمونه‌ی ساده با ترنسپورت `https`، یه پورت‌فوروارد، SOCKS5 فعال، و تیونر روی `auto` — هم به YAML هم JSON:

### سرور — YAML
```yaml
mode: server
transport: https
psk: "YOUR_LICENSE_KEY"
log_level: info

listeners:
  - addr: "0.0.0.0:443"
    transport: https
    cert_file: "/etc/DaggerConnect/certs/cert.pem"
    key_file: "/etc/DaggerConnect/certs/key.pem"
    ports:
      - "2222=22"

socks5:
  enabled: true
  bind: "127.0.0.1:6060"

advanced:
  auto_tune: true
  keepalive_sec: 5
  dead_timeout_sec: 25
```

### سرور — JSON (همون کانفیگ)
```json
{
  "mode": "server",
  "transport": "https",
  "psk": "YOUR_LICENSE_KEY",
  "log_level": "info",
  "listeners": [
    {
      "addr": "0.0.0.0:443",
      "transport": "https",
      "cert_file": "/etc/DaggerConnect/certs/cert.pem",
      "key_file": "/etc/DaggerConnect/certs/key.pem",
      "ports": ["2222=22"]
    }
  ],
  "socks5": {
    "enabled": true,
    "bind": "127.0.0.1:6060"
  },
  "advanced": {
    "auto_tune": true,
    "keepalive_sec": 5,
    "dead_timeout_sec": 25
  }
}
```

### کلاینت — YAML
```yaml
mode: client
transport: https
psk: "YOUR_LICENSE_KEY"
log_level: info

paths:
  - transport: https
    addr: "IRAN_SERVER_IP:443"
    retry_interval: 3
    dial_timeout: 10

advanced:
  auto_tune: true
  keepalive_sec: 5
  dead_timeout_sec: 25
```

برای ترنسپورت‌های دیگه (`tcp`, `ws`, `wss`, `http`, `quantum`, `tun`) فقط کافیه فیلد `transport` رو (هم بالای فایل، هم داخل `listeners`/`paths`) عوض کنید — بقیه‌ی ساختار همینه. `tun` و `quantum` چندتا فیلد اختصاصی بیشتر دارن (بخش `tun`/`ipx` یا `quantum`) که اسکریپت نصب موقع انتخابشون خودکار می‌پرسه.

---

## 📞 پشتیبانی

- 📱 **Telegram Channel**: [@DaggerConnect](https://t.me/DaggerConnect)
- 🤖 **buyLICENSE**: [@DaggerConnectBot](https://t.me/DaggerConnectBot)
- 🐛 **گزارش باگ**: [GitHub Issues](https://github.com/itsFLoKi/DaggerConnect/issues)

---

<div align="center">

⭐ **اگه مفید بود یه ستاره بدید!** ⭐

Made with ❤️ by [itsFLoKi](https://github.com/itsFLoKi)

**DaggerConnect — Professional Reverse Tunnel**

</div>
