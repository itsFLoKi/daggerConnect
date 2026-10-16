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

دگرکانکت هستم

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
