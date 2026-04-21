# Ubiquiti airOS — Handoff Document

## الحالة الحالية

| الميزة | الحالة |
|--------|--------|
| HG8145C ONT (optical + VoIP) | ✅ يشتغل على الجهازين (.201 و .240) |
| Ubiquiti airOS service | ✅ كود موجود — v6 + v8 support |
| Ubiquiti login | ❌ يفشل — السبب لم يُحدَّد بعد |
| Ubiquiti device screen | ✅ واجهة جاهزة تنتظر login يشتغل |

الخطوة التالية: تشخيص لماذا `UbiquitiService.login()` يرجع null على الجهاز الفعلي.

---

## ملفات المشروع

```
lib/core/services/ubiquiti_service.dart      ← login + fetchStatus (v6/v8)
lib/models/ubiquiti_info.dart                ← UbiquitiStatus, UbiquitiLoginResult
lib/screens/devices/ubiquiti_device_screen.dart  ← UI card (signal, CCQ, LAN)
lib/screens/devices/device_probe_screen.dart ← probe screen (debug logs)
lib/providers/device_provider.dart           ← auto-probe + caching
lib/models/device_config.dart                ← DeviceKind enum (ont / ubiquiti)
```

---

## Login Flow — airOS v6 (أشيع)

```
1. GET /              ← prime TCP session (sometimes sets session cookie here)
2. POST /login.cgi
   Content-Type: application/x-www-form-urlencoded
   Body: uri=&username=<user>&password=<pass>
   → Set-Cookie: AIROS_SESSIONID=<hash>  (or AIROS_* prefix)
3. Verify: GET /status.cgi  with cookie
   → JSON must contain "wireless" or "host" key
```

## Login Flow — airOS v8 (AC series)

```
1. POST /api/auth
   Content-Type: application/json
   Body: {"username":"<user>","password":"<pass>"}
   → Set-Cookie: AIROS_* OR X-Auth-Token header
2. Verify: GET /api/status  with cookie/token
```

الكود يجرّب v6 أول، وإذا فشل يجرّب v8. ولكل منهما يجرّب HTTPS أولاً ثم HTTP.

---

## أسباب الفشل المحتملة

### 1. مشكلة استخراج الـ Cookie
الدالة `_extractAirosCookie()` تبحث عن header يبدأ بـ `AIROS_` أو يحتوي `SESSION`.
لو الجهاز يرجع اسم cookie مختلف → تفشل بصمت.
**فحص:** شوف في probe screen logs شو الـ `Set-Cookie` header اللي يرجع فعلياً.

### 2. Verification يرفض الـ session
بعد login، الكود يتحقق بـ GET /status.cgi ويتأكد إن الـ JSON يحتوي `wireless` أو `host`.
لو الجهاز يرجع redirect أو HTML بدل JSON → يرفض.
**فحص:** شوف status code وبداية الـ body لـ /status.cgi في الـ logs.

### 3. Connection pooling
airOS v6 حساس لبعض الـ TCP session details — تأكد إن نفس Dio instance يُستخدم لـ GetRandCount → login (مثل HG8145C).
الكود الحالي ينشئ Dio جديد لكل base URL — هذا الصح.

### 4. Firmware غير معروف
لو الجهاز NanoStation M series قديم، قد يستخدم `/login.cgi` مع body مختلف أو cookie مختلفة.

---

## curl Commands للفحص اليدوي

```bash
# 1. فحص الـ root
curl -sk https://10.100.12.X:80/ -o /dev/null -w "%{http_code}\n"

# 2. محاولة login v6
curl -sk -c /tmp/airos.jar -X POST https://10.100.12.X:80/login.cgi \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "uri=/&username=ubnt&password=ubnt" -v 2>&1 | head -40

# 3. فحص cookie + status
curl -sk -b /tmp/airos.jar https://10.100.12.X:80/status.cgi | python3 -m json.tool | head -60

# 4. محاولة login v8 (AC series)
curl -sk -c /tmp/airos8.jar -X POST https://10.100.12.X/api/auth \
  -H "Content-Type: application/json" \
  -d '{"username":"ubnt","password":"ubnt"}' -v 2>&1 | head -40

# 5. فحص v8 status
curl -sk -b /tmp/airos8.jar https://10.100.12.X/api/status | python3 -m json.tool | head -60
```

استبدل `10.100.12.X` بالـ IP الفعلي.

---

## البيانات المطلوبة من الجهاز

```json
{
  "wireless": {
    "ccq": 94,          ← CCQ (0–100)
    "signal": -62,      ← dBm
    "noisef": -96,      ← noise floor dBm
    "txrate": 130000,   ← kbps
    "rxrate": 130000    ← kbps
  },
  "interfaces": [
    {
      "ifname": "eth0",
      "status": {
        "speed": "100Mbps-Full",  ← LAN port speed
        "plugged": true
      }
    }
  ]
}
```

---

## معايير الألوان (موجودة بالكود، للمراجعة)

| المقياس | أخضر | أصفر | أحمر |
|---------|------|------|------|
| Signal | > -65 dBm | -65 إلى -75 | < -75 |
| CCQ | ≥ 80% | 50–79% | < 50% |
| LAN speed | 1000 Mbps | 100 Mbps | < 100 Mbps |

---

## IP Resolution

الـ IP يأتي من مصدرين:
1. `DeviceConfig` المحفوظ للمشترك (من الـ backend)
2. Fallback: يُمرَّر من شاشة الـ probe يدوياً

الـ `device_provider.dart` يحسم الأولوية: إذا `DeviceKind.ubiquiti` صريح → يجرّب Ubiquiti أولاً، وإلا يبدأ بـ ONT.

---

## Timeouts

```dart
connectTimeout: Duration(seconds: 15)
receiveTimeout: Duration(seconds: 15)
```
إجمالي probe مقيّد بـ 15 ثانية (موجود بـ device_provider.dart).

---

## آخر Commits ذات صلة

```
e335826  chore(mobile): verbose Ubiquiti probe — dump root + login responses
70ef821  fix(mobile): close _probeDevice with } not }); after provider refactor
39e0dd5  feat(mobile): Ubiquiti airOS driver + probe + device screen
78fd807  feat(devices): HG8145C optical + VoIP screen  ← آخر commit شغال
```

---

## خطوات الاستمرار

1. **شغّل الـ probe screen** على الجهاز الـ Ubiquiti (فحص جهاز → اختار Ubiquiti)
2. **شارك الـ logs كاملة** — خصوصاً:
   - الـ `Set-Cookie` header على `/login.cgi`
   - الـ status code وأول 300 حرف من response `/status.cgi`
3. بناءً على النتيجة: إما fix `_extractAirosCookie()` أو أضف support لـ firmware variant جديد
4. بعد ما login يشتغل → تتحقق إن CCQ و LAN speed يظهرون صح بالـ `ubiquiti_device_screen`
