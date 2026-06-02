# MyServices Radius v2 — Login screen only

تطبيق v2 يُبنى **شاشة واحدة في الجلسة** بعد موافقة المستخدم على كل قطعة.

**هذه الجلسة:** شاشة الدخول (Login).

## التصميم المتفق عليه

- **الأسلوب:** Soft Pastel + Premium (مستوحى من تصاميم Dribbble الـpopular).
- **الخلفية:** كريم دافئ `#F5EFE5`.
- **الـbrand:** أخضر غابة `#2D5F47`.
- **اللوقو:** لوقو الشركة الحالي ملوّن أخضر runtime (BlendMode.srcIn).
- **Face ID/البصمة:** مدعوم عبر `local_auth`.

## التشغيل لأول مرة

على Mac:

```bash
cd mobile-app-v2
chmod +x setup.sh
./setup.sh
flutter run -d ios   # أو -d android
```

## ما هو موجود

- `lib/main.dart` — entry point، MaterialApp بـRTL Arabic.
- `lib/screens/login_screen.dart` — الشاشة الكاملة.
- `lib/theme/colors.dart` — palette محدد.
- `lib/theme/typography.dart` — Cairo via google_fonts.
- `lib/theme/spacing.dart` — مقياس 4-pt.
- `assets/images/logo.png` — لوقو الشركة (بنفسجي أصلي، يُلوّن أخضر بـcolorBlendMode).

## ما هو **غير** موجود (عمداً)

- لا تابات، لا shell، لا drawer.
- لا dashboard.
- لا backend connection (login لا يُنفّذ شيء فعلاً — placeholder حتى نوصّله بـPhase 2).
- لا dark mode (بُسّط للحد الأدنى، يُضاف لو وافقت).

## الـPhase التالي

بعد مشاهدتك لهذه الشاشة وموافقتك، نختار الشاشة التالية ونصمّمها معاً بنفس المنهج.
