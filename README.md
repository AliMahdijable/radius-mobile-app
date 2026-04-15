# MyServices Radius - Flutter App

تطبيق إدارة مشتركي الإنترنت مع تكامل واتساب

## المتطلبات

- Flutter SDK >= 3.2.0
- Dart SDK >= 3.2.0
- Android Studio / Xcode

## التشغيل

### 1. إنشاء ملفات المنصة

```bash
cd rad_app
flutter create . --org com.mysvcs --project-name rad_mysvcs
```

### 2. تثبيت الحزم

```bash
flutter pub get
```

### 3. تشغيل التطبيق

```bash
# Android
flutter run

# iOS
flutter run -d ios

# بناء APK
flutter build apk --release

# بناء iOS
flutter build ios --release
```

## هيكل المشروع

```
lib/
├── main.dart                    # نقطة الدخول
├── app.dart                     # إعداد التطبيق (MaterialApp)
├── core/
│   ├── constants/               # ثوابت API والتطبيق
│   ├── network/                 # Dio clients + interceptors
│   ├── router/                  # GoRouter navigation
│   ├── services/                # Storage, Socket, Encryption
│   ├── theme/                   # Material 3 themes
│   └── utils/                   # Helper functions
├── models/                      # Data models
├── providers/                   # Riverpod state management
├── screens/                     # UI screens
│   ├── dashboard_screen.dart
│   ├── home_screen.dart
│   ├── login_screen.dart
│   ├── schedules_screen.dart
│   ├── settings_screen.dart
│   ├── templates_screen.dart
│   ├── subscribers/
│   └── whatsapp/
└── widgets/                     # Reusable widgets
```

## الخوادم

| الخادم | URL | الاستخدام |
|--------|-----|-----------|
| Backend | `https://rad.mysvcs.net` | واتساب، إعدادات، جدولة |
| SAS4 API | `https://reseller-supernet.net/admin/api/index.php/api` | إدارة المشتركين |

## التقنيات

- **Flutter** - إطار عمل متعدد المنصات
- **Riverpod** - إدارة الحالة
- **Dio** - HTTP client
- **Socket.IO** - أحداث الوقت الفعلي
- **GoRouter** - التنقل
- **Material 3** - واجهة مستخدم عصرية
- **Google Fonts (Cairo)** - خط عربي
