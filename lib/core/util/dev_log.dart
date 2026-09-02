import 'package:flutter/foundation.dart';

/// مستويات ضجيج سجلّ التطوير.
///
/// 🐛 سجلّ المستخدم ٢٠٢٦-٠٩-٠٢: آلافُ الأسطر من جلسات ميكروتك — كلّ
/// أمرٍ يُرسَل، وكلّ جملةٍ تعود، وكلّ حمولة SSH خاماً. وثمانون جهازاً
/// كلّ خمس عشرة ثانية تُنتج طوفاناً **يُخفي العطل الذي نبحث عنه**.
///
/// السجلّ الذي لا يُقرأ ليس سجلّاً. والمستوى يفصل «ما يجري» عمّا
/// «يستحقّ النظر».
enum LogLevel {
  /// أخطاءٌ وتحوّلاتٌ فقط — الافتراضيّ.
  quiet,

  /// + نتائج كلّ استدعاء (عدد الصفوف، الطريق المُختار).
  normal,

  /// + كلّ أمرٍ وكلّ جملةٍ وكلّ حمولة خام. للتشخيص العميق وحده.
  verbose,
}

/// سجلّ الأجهزة — يُصمت في الإصدار، ويُخفَّف في التطوير.
///
/// ⚠️ التغيير هنا لا في مواضع الطباعة: مفتاحٌ واحد بدل ستّة عشر
/// `kDebugMode` متفرّقة، فيسهل رفعُه عند التشخيص وخفضُه بعده.
class DevLog {
  DevLog._();

  /// ارفعه إلى [LogLevel.verbose] عند تشخيص جلسةٍ بعينها.
  static LogLevel level = LogLevel.quiet;

  static bool get _on => kDebugMode;

  /// خطأٌ أو تحوّل — يظهر دائماً في التطوير.
  static void warn(String Function() msg) {
    if (_on) debugPrint(msg());
  }

  /// نتيجةُ استدعاء — تظهر من `normal` فصاعداً.
  static void info(String Function() msg) {
    if (_on && level.index >= LogLevel.normal.index) debugPrint(msg());
  }

  /// تفصيلُ بروتوكول — لا يظهر إلّا في `verbose`.
  ///
  /// ⚠️ الوسيط دالّة لا نصّ: بناء السلسلة نفسه يكلّف، وفي `quiet` لا
  /// نريد أن ندفع ثمن نصٍّ لن يُطبع.
  static void trace(String Function() msg) {
    if (_on && level == LogLevel.verbose) debugPrint(msg());
  }
}
