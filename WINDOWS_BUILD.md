# 🪟 بناء تطبيق MyServices لـWindows

دليل بناء نسخة Windows من تطبيق Flutter الموجود.

---

## ✅ المتطلبات

| الأداة | النسخة | كيف تتأكد |
|---|---|---|
| Flutter SDK | 3.16+ | `flutter --version` |
| Visual Studio Build Tools 2022 | + workload "Desktop development with C++" | `flutter doctor` |
| Windows 10/11 | 64-bit | `winver` |

> 💡 لا حاجة لـVisual Studio IDE الكامل — Build Tools يكفي.

---

## ١. إعداد Flutter لدعم Windows (مرّة واحدة فقط)

```powershell
flutter config --enable-windows-desktop
flutter doctor
```

تأكد من ظهور:
```
[√] Visual Studio - develop Windows apps (Visual Studio Build Tools 2022)
[√] Windows Version (Installed version of Windows is version 10 or higher)
```

---

## ٢. إضافة منصة Windows للمشروع (مرّة واحدة)

```powershell
cd mobile-app
flutter create --platforms=windows .
```

هذا الأمر **يضيف** مجلد `windows/` بدون ما يلمس Dart code. يحتوي على:
- `windows/CMakeLists.txt`
- `windows/runner/` — C++ runner للتطبيق
- `windows/flutter/` — Flutter engine

> ⚠️ بعد إضافة Windows، أعد التحقّق:
> ```powershell
> flutter pub get
> ```

---

## ٣. اختبار سريع (development mode)

```powershell
flutter run -d windows
```

⏱️ أول build يأخذ ~5 دقائق (compilation كامل لـC++ engine).
مرّات لاحقة: ~30 ثانية.

النافذة تفتح. ميزات تشتغل تلقائياً:
- ✅ تسجيل دخول SAS4
- ✅ قائمة المشتركين
- ✅ التقارير المالية والتفعيلات
- ✅ WhatsApp templates
- ✅ Huawei ONT (HTTP مباشرة من اللاب لجهاز LAN)

ميزات تحتاج إعداد إضافي:
- ⚠️ Ubiquiti SNMP — يحتاج `pure_snmp` أو `snmp_client` (راجع §٥)
- ⚠️ Push notifications — متعطّلة على Windows (لكن in-app notifications تشتغل)

---

## ٤. بناء النسخة النهائية (release)

```powershell
flutter build windows --release
```

النتيجة:
```
build\windows\x64\runner\Release\
├── rad_mysvcs.exe          ← الملف القابل للتنفيذ
├── flutter_windows.dll     ← Flutter engine
├── *.dll                   ← مكتبات الـplugins
└── data/                   ← Dart bundle + assets
```

**حجم تقريبي:** 30-50 MB كاملاً.

---

## ٥. إضافة SNMP لـUbiquiti (اختياري)

التطبيق الحالي ما يستعمل SNMP بالموبايل (يستعمل HTTP للـAirOS web UI).
على Windows ممكن نضيف SNMP حقيقي بـpure Dart:

```yaml
# pubspec.yaml — أضف هذا تحت dependencies:
dependencies:
  pure_snmp: ^1.0.0
```

ثم في `lib/core/services/`:
```dart
// ubnt_snmp_service.dart
import 'package:pure_snmp/pure_snmp.dart';
import '../utils/platform_utils.dart';

Future<Map<String, dynamic>?> fetchUbntSnmp(String ip) async {
  if (!PlatformUtils.supportsLocalSnmp) return null;
  // ... pure_snmp logic
}
```

> ⏰ هذي ميزة مستقبلية — التطبيق يشتغل بدونها على Windows.

---

## ٦. إنشاء installer (.exe)

Flutter ينتج folder وليس installer. نلفّه بأحد الخيارات:

### الخيار أ: Inno Setup (موصى به — مجاني وبسيط)

١. نزّل: https://jrsoftware.org/isinfo.php
٢. أنشئ ملف `installer.iss`:
```iss
[Setup]
AppName=MyServices Desktop
AppVersion=1.0.0
DefaultDirName={autopf}\MyServices
DefaultGroupName=MyServices
OutputBaseFilename=MyServices-Setup-1.0.0
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{group}\MyServices"; Filename: "{app}\rad_mysvcs.exe"
Name: "{commondesktop}\MyServices"; Filename: "{app}\rad_mysvcs.exe"

[Run]
Filename: "{app}\rad_mysvcs.exe"; Description: "تشغيل التطبيق"; Flags: nowait postinstall skipifsilent
```

٣. ابني:
```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
```

النتيجة: `MyServices-Setup-1.0.0.exe` (~25 MB).

### الخيار ب: MSIX (للتوزيع عبر Microsoft Store)
أعقد — يحتاج certificate. نتركه لمرحلة لاحقة.

---

## 🔧 مشاكل شائعة

| المشكلة | الحل |
|---|---|
| `flutter create` يفشل | تأكد إنك بمجلد `mobile-app/` وليس parent |
| `Visual Studio is not installed` | نزّل Build Tools ↪ workload C++ desktop |
| `LINK : fatal error` | احذف `build/` و`flutter clean` ثم أعد |
| نص ينقص في النافذة | أضف خط Cairo للـassets أو استعمل خط نظام |
| الإشعارات لا تظهر | متعمّد — Windows ما يدعم FCM (راجع platform_utils.dart) |

---

## 📋 ملخّص الأوامر

```powershell
# مرّة واحدة
flutter config --enable-windows-desktop
flutter doctor

# لأول مرة بهذا المشروع
cd mobile-app
flutter create --platforms=windows .
flutter pub get

# تطوير
flutter run -d windows

# بناء نهائي
flutter build windows --release

# مع Inno Setup (لو منصّب)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
```

---

## 🎯 ما تم إعداده مسبقاً

تعديلات الكود الجاهزة (تشتغل بكل المنصات):

- ✅ `lib/main.dart` — يتجاوز Firebase/WorkManager على desktop
- ✅ `lib/core/utils/platform_utils.dart` — مفاتيح اكتشاف المنصة
- ✅ `lib/core/services/fcm_service.dart` — early return على desktop
- ✅ `lib/core/services/expiry_push_service.dart` — early return على desktop
- ✅ `lib/screens/home_screen.dart` — badge skip على desktop
- ✅ `lib/widgets/contact_picker.dart` — رسالة بديلة على desktop
